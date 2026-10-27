'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { getMessaging } = require('firebase-admin/messaging');
const logger = require('firebase-functions/logger');
const { onValueCreated } = require('firebase-functions/v2/database');
const { avisar } = require('./recado');

initializeApp();

// Recado novo de aluno no up/ de um PC: push para o celular do professor,
// mesmo com o app fechado. Sem retentativa: recado atrasado não toca.
exports.avisarRecado = onValueCreated(
  {
    ref: '/devices/{deviceId}/up/{pushId}',
    instance: 'controle-de-aula-f53bd-default-rtdb',
    region: 'us-central1',
    memory: '256MiB',
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  (event) => {
    const db = getDatabase();
    return avisar(
      { deviceId: event.params.deviceId, pushId: event.params.pushId, env: event.data.val() },
      {
        ler: async (caminho) => (await db.ref(caminho).get()).val(),
        enviar: (mensagem) => getMessaging().sendEachForMulticast(mensagem),
        apagar: (caminho) => db.ref(caminho).remove(),
        agoraMs: Date.now(),
        // Sem uid, token nem texto: o functions:log mostra só por que saiu.
        registrar: (motivo, celulares) => logger.info('avisarRecado', { motivo, celulares }),
      },
    );
  },
);
