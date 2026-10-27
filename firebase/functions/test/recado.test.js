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

test('na escola vai para quem tem a reserva viva; sem ela, para o dono do vínculo', () => {
  assert.deepEqual(destinatarios({ teacherUid: 'ana', schoolUid: null, aula: null, agoraMs: AGORA }), ['ana'],
    'fora da escola: o professor vinculado');
  assert.deepEqual(destinatarios({ teacherUid: 'ana', schoolUid: 'fundador', aula: { uid: 'bia', ts: AGORA }, agoraMs: AGORA }), ['ana'],
    'PC vinculado a uma conta fora da escola: essa conta, mesmo com reserva');
  const escola = { teacherUid: 'fundador', schoolUid: 'fundador', agoraMs: AGORA };
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: AGORA - 60000 } }), ['bia'],
    'aula viva da Bia: só a Bia');
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: AGORA - TRAVA_EXPIRA_MS } }), ['bia'],
    'reserva no limite exato de 15 min ainda vale');
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: AGORA - TRAVA_EXPIRA_MS - 1 } }), ['fundador'],
    'reserva vencida: PC livre, o fundador atende');
  assert.deepEqual(destinatarios({ ...escola, aula: null }), ['fundador'], 'PC sem aula: o fundador');
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: '', ts: AGORA } }), ['fundador']);
  assert.deepEqual(destinatarios({ ...escola, aula: { ts: AGORA } }), ['fundador'],
    'nó só com ts (sem dono): PC livre');
  assert.deepEqual(destinatarios({ ...escola, aula: { uid: 'bia', ts: String(AGORA) } }), ['fundador']);
  assert.deepEqual(destinatarios({ teacherUid: null, schoolUid: null, aula: null, agoraMs: AGORA }), [],
    'PC sem vínculo');
  assert.deepEqual(destinatarios({ teacherUid: '', schoolUid: 'fundador', aula: { uid: 'bia', ts: AGORA }, agoraMs: AGORA }), []);
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
  const aulaDaBiaSemCelular = banco({
    [`devices/${dados.d}/bind/teacherUid`]: 'fundador',
    [`devices/${dados.d}/meta`]: { pub: dados.p },
    'school/meta/schoolUid': 'fundador',
    [`school/aulas/${dados.d}`]: { uid: 'bia', ts: AGORA - 60000, env: 'cifrado' },
    'fcm/fundador': { k1: { t: 'token', ts: 1 } },
  });
  assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...aulaDaBiaSemCelular, enviar, agoraMs: AGORA }), 0,
    'aula viva de outra professora não toca o fundador');
});

test('escola: PC livre ou com a reserva vencida toca o celular do fundador', async () => {
  const { dados } = VETOR.recados[0];
  for (const aula of [null, { uid: 'bia', ts: AGORA - TRAVA_EXPIRA_MS - 1, env: 'cifrado' }]) {
    const fb = banco({
      [`devices/${dados.d}/bind/teacherUid`]: 'fundador',
      [`devices/${dados.d}/meta`]: { pub: dados.p, label: dados.l },
      'school/meta/schoolUid': 'fundador',
      [`school/aulas/${dados.d}`]: aula,
      'fcm/fundador': { k1: { t: 'token-fundador', ts: 1 } },
      'fcm/bia': { k1: { t: 'token-bia', ts: 1 } },
    });
    const enviados = [];
    const enviar = async (m) => { enviados.push(m); return { successCount: 1, responses: [{ success: true }] }; };
    assert.equal(await avisar({ deviceId: dados.d, pushId: dados.k, env: dados.e }, { ...fb, enviar, agoraMs: AGORA }), 1);
    assert.deepEqual(enviados.map((m) => m.tokens), [['token-fundador']]);
    assert.deepEqual(enviados[0].data, dados);
  }
});

test('cada saída registra só o motivo e quantos celulares receberam', async () => {
  const { dados } = VETOR.recados[0];
  const recado = { deviceId: dados.d, pushId: dados.k, env: dados.e };
  const vinculado = {
    [`devices/${dados.d}/bind/teacherUid`]: 'ana',
    [`devices/${dados.d}/meta`]: { pub: dados.p, label: dados.l },
  };
  const casos = [
    ['sem_destinatario', banco({ [`devices/${dados.d}/meta`]: { pub: dados.p } })],
    ['sem_dados', banco({ ...vinculado, [`devices/${dados.d}/meta`]: { label: 'sem pub' } })],
    ['sem_celular', banco(vinculado)],
    ['enviado', banco({ ...vinculado, 'fcm/ana': { k1: { t: 'token-celular', ts: 1 }, k2: { t: 'token-tablet', ts: 1 } } })],
  ];
  const enviar = async (m) => ({ successCount: m.tokens.length, responses: m.tokens.map(() => ({ success: true })) });
  for (const [motivo, fb] of casos) {
    const log = [];
    const total = await avisar(recado, { ...fb, enviar, agoraMs: AGORA, registrar: (...args) => log.push(args) });
    const celulares = motivo === 'enviado' ? 2 : 0;
    assert.equal(total, celulares);
    assert.deepEqual(log, [[motivo, celulares]], `uma linha de log, sem uid, token nem texto (${motivo})`);
  }
});
