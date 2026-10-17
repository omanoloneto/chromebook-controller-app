'use strict';

// Quem recebe o push, o que vai nele (o mesmo vetor que o app decifra) e a
// limpeza dos tokens mortos, com banco e FCM de mentira.

const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const { avisar, dadosDoPush, destinatarios, TRAVA_EXPIRA_MS, ENVELOPE_MAX } = require('../recado');

const VETOR = require(path.join(__dirname, '../../../test/fixtures/push-v1.json'));
const AGORA = VETOR.agoraMs;

function banco(dados) {
  const apagados = [];
  return {
    apagados,
    ler: async (caminho) => (caminho in dados ? dados[caminho] : null),
    apagar: async (caminho) => { apagados.push(caminho); },
  };
}

test('o que vai no push é o vetor que o app decifra', () => {
  for (const { dados } of VETOR.recados) {
    const meta = { pub: dados.p, label: dados.l, uid: 'anonimo-do-pc', v: 4 };
    assert.deepEqual(dadosDoPush({ deviceId: dados.d, pushId: dados.k, env: dados.e, meta }), dados);
  }
});

test('envelope grande, vazio ou sem chave do PC não vai', () => {
  const meta = { pub: VETOR.recados[0].dados.p, label: 'Unidade 1' };
  assert.equal(dadosDoPush({ deviceId: 'pc', pushId: 'k', env: 'x'.repeat(ENVELOPE_MAX + 1), meta }), null);
  assert.equal(dadosDoPush({ deviceId: 'pc', pushId: 'k', env: '', meta }), null);
  assert.equal(dadosDoPush({ deviceId: 'pc', pushId: 'k', env: { env: 'x' }, meta }), null);
  assert.equal(dadosDoPush({ deviceId: 'pc', pushId: 'k', env: 'x', meta: { label: 'sem pub' } }), null);
  assert.equal(dadosDoPush({ deviceId: 'pc', pushId: 'k', env: 'x', meta: null }), null);
  const comprido = dadosDoPush({ deviceId: 'pc', pushId: 'k', env: 'x', meta: { ...meta, label: 'U'.repeat(200) } });
  assert.equal(comprido.l.length, 64);
});

test('sem escola vai para o professor vinculado; na escola, só para quem tem a aula', () => {
  assert.deepEqual(destinatarios({ teacherUid: 'ana', schoolUid: null, aula: null, agoraMs: AGORA }), ['ana']);
  assert.deepEqual(destinatarios({ teacherUid: 'ana', schoolUid: 'fundador', aula: null, agoraMs: AGORA }), ['ana']);
  const escola = { teacherUid: 'fundador', schoolUid: 'fundador', agoraMs: AGORA };
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: AGORA - 60000 } }), ['bia']);
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: AGORA - TRAVA_EXPIRA_MS - 1 } }), [],
    'reserva vencida: PC livre, sem notificação');
  assert.deepEqual(destinatarios({ ...escola, aula: null }), []);
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: '', ts: AGORA } }), []);
  assert.deepEqual(destinatarios({ teacherUid: null, schoolUid: null, aula: null, agoraMs: AGORA }), [],
    'PC sem vínculo');
});

test('manda para todos os celulares do professor e apaga o token morto', async () => {
  const { dados } = VETOR.recados[0];
  const fb = banco({
    [`devices/${dados.d}/bind/teacherUid`]: 'ana',
    [`devices/${dados.d}/meta`]: { pub: dados.p, label: dados.l },
    'fcm/ana': { k1: { t: 'token-celular', ts: 1 }, k2: { t: 'token-velho', ts: 1 }, k3: { ts: 1 } },
  });
  const enviados = [];
  const enviar = async (mensagem) => {
    enviados.push(mensagem);
    return {
      successCount: 1,
      responses: [{ success: true }, { success: false, error: { code: 'messaging/registration-token-not-registered' } }],
    };
  };
  const total = await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...fb, enviar, agoraMs: AGORA });
  assert.equal(total, 1);
  assert.equal(enviados.length, 1);
  assert.deepEqual(enviados[0].tokens, ['token-celular', 'token-velho']);
  assert.deepEqual(enviados[0].data, dados);
  assert.equal(enviados[0].android.priority, 'high');
  assert.deepEqual(fb.apagados, ['fcm/ana/k2']);
});

test('falha passageira do FCM não apaga token', async () => {
  const { dados } = VETOR.recados[0];
  const fb = banco({
    [`devices/${dados.d}/bind/teacherUid`]: 'ana',
    [`devices/${dados.d}/meta`]: { pub: dados.p, label: dados.l },
    'fcm/ana': { k1: { t: 'token-celular', ts: 1 } },
  });
  const enviar = async () => ({ successCount: 0, responses: [{ success: false, error: { code: 'messaging/internal-error' } }] });
  assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...fb, enviar, agoraMs: AGORA }), 0);
  assert.deepEqual(fb.apagados, []);
});

test('sem destinatário ou sem celular não chama o FCM', async () => {
  const { dados } = VETOR.recados[0];
  const enviar = async () => assert.fail('não devia mandar');
  const semVinculo = banco({ [`devices/${dados.d}/meta`]: { pub: dados.p } });
  assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...semVinculo, enviar, agoraMs: AGORA }), 0);
  const semCelular = banco({
    [`devices/${dados.d}/bind/teacherUid`]: 'ana',
    [`devices/${dados.d}/meta`]: { pub: dados.p },
  });
  assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...semCelular, enviar, agoraMs: AGORA }), 0);
  const escolaLivre = banco({
    [`devices/${dados.d}/bind/teacherUid`]: 'fundador',
    [`devices/${dados.d}/meta`]: { pub: dados.p },
    'school/meta/schoolUid': 'fundador',
    'fcm/fundador': { k1: { t: 'token', ts: 1 } },
  });
  assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...escolaLivre, enviar, agoraMs: AGORA }), 0);
});
