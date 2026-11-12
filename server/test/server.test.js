import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { test } from 'node:test';

import { composeSms, parseAlert } from '../src/alert.js';
import { handleRequest } from '../src/index.js';

const env = {
  NRFCLOUD_WEBHOOK_TOKEN: 'jeton-de-test',
  NRFCLOUD_WEBHOOK_SECRET: 'secret-de-test',
  TWILIO_ACCOUNT_SID: 'ACtest',
  TWILIO_AUTH_TOKEN: 'twilio-token',
  TWILIO_FROM: '+15005550006',
};

const alertData = {
  type: 'real',
  name: 'Marie Dupont',
  message: "Marie Dupont a besoin d'aide.",
  battery: 82,
  contacts: ['+32470123456', '+33612345678'],
  position: { lat: 50.84673, lon: 4.35247, accuracy: 21 },
};

/** Une livraison telle que nRF Cloud l'envoie. */
function delivery(data = alertData, appId = 'HESTIA_ALERT') {
  return {
    type: 'device.messages',
    timestamp: '2026-11-12T10:00:00Z',
    messages: [
      {
        teamId: 'equipe',
        deviceId: 'nrf-351234567890123',
        messageId: 'a1b2',
        receivedAt: '2026-11-12T10:00:00Z',
        topic: 'prod/equipe/m/d/nrf-351234567890123/d2c',
        message: { appId, messageType: 'DATA', ts: 1794477600000, data },
      },
    ],
  };
}

function post(body, { token = env.NRFCLOUD_WEBHOOK_TOKEN, secret = env.NRFCLOUD_WEBHOOK_SECRET } = {}) {
  const raw = typeof body === 'string' ? body : JSON.stringify(body);
  const headers = { 'content-type': 'application/json', 'x-nrfcloud-team-id': 'equipe' };
  if (token) headers['x-api-key'] = token;
  if (secret) {
    headers['x-nrfcloud-signature'] = createHmac('sha256', secret).update(raw).digest('hex');
  }
  return new Request('https://hestia.example/', { method: 'POST', headers, body: raw });
}

/** Faux Twilio : note les SMS demandés et répond selon `outcome(to)`. */
function fakeTwilio(outcome = () => true) {
  const sms = [];
  const fetchImpl = async (url, init) => {
    const params = new URLSearchParams(init.body);
    sms.push({ url, auth: init.headers.authorization, ...Object.fromEntries(params) });
    return outcome(params.get('To'))
      ? new Response(JSON.stringify({ sid: 'SM1' }), { status: 201 })
      : new Response(JSON.stringify({ code: 21608, message: 'unverified' }), { status: 400 });
  };
  return { sms, fetchImpl };
}

test('envoie un SMS à chaque contact', async () => {
  const twilio = fakeTwilio();
  const response = await handleRequest(post(delivery()), env, twilio.fetchImpl);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { alertes: 1, sms_envoyes: 2, sms_echoues: 0 });
  assert.equal(response.headers.get('x-nrfcloud-team-id'), 'equipe');

  assert.deepEqual(twilio.sms.map((s) => s.To), ['+32470123456', '+33612345678']);
  const [first] = twilio.sms;
  assert.equal(first.url, 'https://api.twilio.com/2010-04-01/Accounts/ACtest/Messages.json');
  assert.equal(first.auth, `Basic ${btoa('ACtest:twilio-token')}`);
  assert.equal(first.From, '+15005550006');
  assert.equal(
    first.Body,
    "Marie Dupont a besoin d'aide.\n" +
      'Position (à environ 21 m près) : https://maps.google.com/?q=50.84673,4.35247',
  );
});

test('accepte les données en texte JSON ou en base64', async () => {
  for (const data of [
    JSON.stringify(alertData),
    Buffer.from(JSON.stringify(alertData), 'utf8').toString('base64'),
  ]) {
    const twilio = fakeTwilio();
    const response = await handleRequest(post(delivery(data)), env, twilio.fetchImpl);
    assert.equal((await response.json()).sms_envoyes, 2);
    assert.match(twilio.sms[0].Body, /^Marie Dupont a besoin d'aide\./);
  }
});

test('ignore les autres messages du bijou', async () => {
  const twilio = fakeTwilio();
  const response = await handleRequest(post(delivery(alertData, 'TEMP')), env, twilio.fetchImpl);
  assert.equal(response.status, 200);
  assert.equal(twilio.sms.length, 0);
});

test('refuse un jeton ou une signature incorrects', async () => {
  const twilio = fakeTwilio();
  for (const options of [{ token: 'mauvais' }, { token: null }, { secret: 'mauvais' }, { secret: null }]) {
    const response = await handleRequest(post(delivery(), options), env, twilio.fetchImpl);
    assert.equal(response.status, 401);
  }
  assert.equal(twilio.sms.length, 0);
});

test('la signature est facultative si aucun secret n\'est configuré', async () => {
  const twilio = fakeTwilio();
  const noSecret = { ...env, NRFCLOUD_WEBHOOK_SECRET: undefined };
  const response = await handleRequest(post(delivery(), { secret: null }), noSecret, twilio.fetchImpl);
  assert.equal(response.status, 200);
  assert.equal(twilio.sms.length, 2);
});

test('refuse de fonctionner sans configuration complète', async () => {
  const twilio = fakeTwilio();
  const response = await handleRequest(
    post(delivery()), { ...env, NRFCLOUD_WEBHOOK_TOKEN: '' }, twilio.fetchImpl,
  );
  assert.equal(response.status, 500);
  assert.equal(twilio.sms.length, 0);
});

test('répond à la vérification de nRF Cloud sans authentification', async () => {
  const body = { type: 'system.verification', messages: [{ verificationToken: '123456' }] };
  const response = await handleRequest(post(body, { token: null, secret: null }), {});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('x-nrfcloud-team-id'), 'equipe');
});

test('demande une nouvelle livraison seulement si aucun SMS n\'est parti', async () => {
  const none = fakeTwilio(() => false);
  assert.equal((await handleRequest(post(delivery()), env, none.fetchImpl)).status, 502);

  // Envoi partiel : pas de nouvelle livraison, pour éviter les doublons.
  const partial = fakeTwilio((to) => to === '+32470123456');
  const response = await handleRequest(post(delivery()), env, partial.fetchImpl);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { alertes: 1, sms_envoyes: 1, sms_echoues: 1 });
});

test('utilise un Messaging Service si TWILIO_FROM en désigne un', async () => {
  const twilio = fakeTwilio();
  await handleRequest(post(delivery()), { ...env, TWILIO_FROM: 'MG123' }, twilio.fetchImpl);
  assert.equal(twilio.sms[0].MessagingServiceSid, 'MG123');
  assert.equal(twilio.sms[0].From, undefined);
});

test('rejette le JSON invalide et répond aux autres méthodes', async () => {
  assert.equal((await handleRequest(post('pas du json'), env)).status, 400);
  const get = await handleRequest(new Request('https://hestia.example/'), env);
  assert.equal(get.status, 200);
});

test('nettoie les contacts', () => {
  const alert = parseAlert({
    ...alertData,
    contacts: ['+32470123456', '+32470123456', '0470123456', 42, '+1', '+33612345678'],
  });
  assert.deepEqual(alert.contacts, ['+32470123456', '+33612345678']);
  assert.equal(parseAlert({ type: 'real' }), null);
  assert.equal(parseAlert('pas du json'), null);
});

test('rédige les SMS', () => {
  const base = parseAlert(alertData);
  assert.equal(
    composeSms({ ...base, test: true }),
    "[TEST - pas d'urgence] Marie Dupont a besoin d'aide.\n" +
      'Position (à environ 21 m près) : https://maps.google.com/?q=50.84673,4.35247',
  );
  assert.equal(
    composeSms({ ...base, message: '', position: null }),
    "Marie Dupont a appuyé sur son bouton d'urgence et a besoin d'aide.\n" +
      'Position inconnue pour le moment.',
  );
  assert.match(
    composeSms({ ...base, position: { lat: -33.86882, lon: -0.5, accuracy: 2400 } }),
    /à environ 2 km près\) : https:\/\/maps\.google\.com\/\?q=-33\.86882,-0\.50000$/,
  );
});
