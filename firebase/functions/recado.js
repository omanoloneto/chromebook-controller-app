'use strict';

// Push de um item novo do up/ (chat, pedido de liberação, mão levantada): quem
// recebe, o que vai e quais tokens o FCM recusou. Sem Firebase aqui dentro —
// index.js entrega o banco e o envio, e os testes rodam sem rede.

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

/** Sem escola, o professor vinculado; na escola, só quem tem a reserva viva
 * do PC — PC livre aparece a todo membro no app, sem notificação. */
function destinatarios({ teacherUid, schoolUid, aula, agoraMs }) {
  if (typeof teacherUid !== 'string' || !teacherUid) return [];
  if (typeof schoolUid !== 'string' || teacherUid !== schoolUid) return [teacherUid];
  if (!aula || typeof aula.uid !== 'string' || !aula.uid || typeof aula.ts !== 'number') return [];
  return agoraMs - aula.ts > TRAVA_EXPIRA_MS ? [] : [aula.uid];
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
 * `apagar(caminho)`. Devolve quantos celulares receberam. */
async function avisar({ deviceId, pushId, env }, { ler, enviar, apagar, agoraMs }) {
  const [teacherUid, meta, schoolUid, aula] = await Promise.all([
    ler(`devices/${deviceId}/bind/teacherUid`),
    ler(`devices/${deviceId}/meta`),
    ler('school/meta/schoolUid'),
    ler(`school/aulas/${deviceId}`),
  ]);
  const uids = destinatarios({ teacherUid, schoolUid, aula, agoraMs });
  const data = dadosDoPush({ deviceId, pushId, env, meta });
  if (!uids.length || !data) return 0;
  const alvos = [];
  for (const uid of uids) {
    for (const [chave, item] of Object.entries((await ler(`fcm/${uid}`)) || {})) {
      if (item && typeof item.t === 'string' && item.t) alvos.push({ uid, chave, token: item.t });
    }
  }
  if (!alvos.length) return 0;
  const resposta = await enviar(mensagem(alvos, data));
  await Promise.all(tokensMortos(alvos, resposta).map(apagar));
  return resposta.successCount;
}

module.exports = { avisar, dadosDoPush, destinatarios, tokensMortos, TRAVA_EXPIRA_MS, ENVELOPE_MAX };
