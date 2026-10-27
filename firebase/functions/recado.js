'use strict';

// Push de um item novo do up/ (chat, pedido de liberação, mão levantada): quem
// recebe, o que vai e quais tokens o FCM recusou. Sem Firebase aqui dentro —
// index.js entrega o banco, o envio e o log, e os testes rodam sem rede.

// Mesmo prazo de kTravaExpira (lib/src/cloud/aula_locks.dart).
const TRAVA_EXPIRA_MS = 15 * 60 * 1000;
// O FCM aceita 4096 bytes de dados no total; o maior recado do protocolo
// (chat de 500 emojis) dá ~2700 caracteres de envelope.
const ENVELOPE_MAX = 3200;
const DOIS_HORAS_MS = 2 * 60 * 60 * 1000;
const TOKEN_MORTO = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** Na escola, quem tem a reserva viva do PC; sem ela (PC livre ou reserva
 * vencida) e fora da escola, o dono do vínculo — na escola, o fundador. */
function destinatarios({ teacherUid, schoolUid, aula, agoraMs }) {
  if (typeof teacherUid !== 'string' || !teacherUid) return [];
  const viva = teacherUid === schoolUid && !!aula && typeof aula.uid === 'string' && !!aula.uid &&
    typeof aula.ts === 'number' && agoraMs - aula.ts <= TRAVA_EXPIRA_MS;
  return [viva ? aula.uid : teacherUid];
}

/** O envelope vai como chegou: só o celular do professor decifra
 * (lib/src/service/push_service.dart, vetor test/fixtures/push-v1.json). */
function dadosDoPush({ deviceId, pushId, env, meta }) {
  if (typeof env !== 'string' || !env || env.length > ENVELOPE_MAX) return null;
  const pub = meta && meta.pub;
  if (typeof pub !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(pub)) return null;
  const label = meta && typeof meta.label === 'string' ? meta.label.slice(0, 64) : '';
  return { t: 'up', d: deviceId, k: pushId, e: env, p: pub, l: label };
}

function mensagem(alvos, data) {
  return {
    tokens: alvos.map((alvo) => alvo.token),
    data,
    // Alta prioridade: o Android acorda o app fechado para decifrar.
    android: { priority: 'high', ttl: DOIS_HORAS_MS },
  };
}

/** Caminhos em /fcm dos tokens que o FCM disse não existirem mais. */
function tokensMortos(alvos, resposta) {
  return resposta.responses.flatMap((item, i) =>
    !item.success && TOKEN_MORTO.has(item.error && item.error.code) ? [`fcm/${alvos[i].uid}/${alvos[i].chave}`] : []);
}

/** `ler(caminho)` → valor ou null; `enviar(mensagem)` → BatchResponse;
 * `apagar(caminho)`; `registrar(motivo, celulares)` → log de cada saída, só
 * com o motivo e a contagem. Devolve quantos celulares receberam. */
async function avisar({ deviceId, pushId, env }, { ler, enviar, apagar, agoraMs, registrar = () => {} }) {
  const [teacherUid, meta, schoolUid, aula] = await Promise.all([
    ler(`devices/${deviceId}/bind/teacherUid`),
    ler(`devices/${deviceId}/meta`),
    ler('school/meta/schoolUid'),
    ler(`school/aulas/${deviceId}`),
  ]);
  const uids = destinatarios({ teacherUid, schoolUid, aula, agoraMs });
  if (!uids.length) return saida(registrar, 'sem_destinatario', 0);
  const data = dadosDoPush({ deviceId, pushId, env, meta });
  if (!data) return saida(registrar, 'sem_dados', 0);
  const alvos = [];
  for (const uid of uids) {
    for (const [chave, item] of Object.entries((await ler(`fcm/${uid}`)) || {})) {
      if (item && typeof item.t === 'string' && item.t) alvos.push({ uid, chave, token: item.t });
    }
  }
  if (!alvos.length) return saida(registrar, 'sem_celular', 0);
  const resposta = await enviar(mensagem(alvos, data));
  await Promise.all(tokensMortos(alvos, resposta).map(apagar));
  return saida(registrar, 'enviado', resposta.successCount);
}

function saida(registrar, motivo, celulares) {
  registrar(motivo, celulares);
  return celulares;
}

module.exports = { avisar, dadosDoPush, destinatarios, tokensMortos, TRAVA_EXPIRA_MS, ENVELOPE_MAX };
