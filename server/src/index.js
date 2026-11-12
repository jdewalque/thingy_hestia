// Serveur d'alertes Hestia (Cloudflare Worker).
//
// nRF Cloud lui pousse les messages du bijou (« Message Routing Service »).
// Pour chaque alerte HESTIA_ALERT, il envoie un SMS à chaque contact (Twilio)
// et, si un sujet ntfy est configuré, une notification sur les téléphones
// abonnés à ce sujet.

import { composeSms, extractAlerts } from './alert.js';
import { sendNotification } from './ntfy.js';
import { sendSms } from './twilio.js';

const TWILIO = ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_FROM'];
const TEAM_HEADER = 'x-nrfcloud-team-id';
const encoder = new TextEncoder();

async function sha256(value) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
}

/** Compare deux secrets sans révéler, par le temps de réponse, où ils diffèrent. */
async function sameSecret(a, b) {
  const [x, y] = await Promise.all([sha256(a ?? ''), sha256(b ?? '')]);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

async function hmacHex(secret, body) {
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(body)));
  return [...signature].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Masque un numéro dans les journaux : +32470123456 → +3247•••3456. */
function mask(phone) {
  return `${phone.slice(0, 5)}•••${phone.slice(-4)}`;
}

export async function handleRequest(request, env, fetchImpl = fetch) {
  // nRF Cloud valide automatiquement la destination si chaque réponse lui
  // renvoie l'identifiant d'équipe qu'il a mis dans sa requête.
  const headers = { 'content-type': 'application/json; charset=utf-8' };
  const teamId = request.headers.get(TEAM_HEADER);
  if (teamId) headers[TEAM_HEADER] = teamId;
  const reply = (status, payload) => new Response(JSON.stringify(payload), { status, headers });

  if (request.method !== 'POST') {
    return reply(200, { service: 'Hestia', etat: 'en service' });
  }

  const rawBody = await request.text();
  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return reply(400, { erreur: 'JSON invalide' });
  }

  // Demande de vérification de la destination : elle ne contient aucune
  // donnée d'appareil et arrive avant toute livraison.
  if (body?.type === 'system.verification') {
    const pin = body.messages?.[0]?.verificationToken;
    console.log(`Vérification nRF Cloud reçue (code ${pin ?? 'absent'})`);
    return reply(200, { ok: true });
  }

  // Il faut le jeton de nRF Cloud et au moins une voie d'envoi complète.
  const useSms = TWILIO.every((name) => env[name]);
  const useNotification = Boolean(env.NTFY_TOPIC);
  if (!env.NRFCLOUD_WEBHOOK_TOKEN || (!useSms && !useNotification)) {
    console.error('Configuration incomplète : jeton nRF Cloud, ou Twilio et ntfy absents');
    return reply(500, { erreur: 'configuration incomplète' });
  }

  if (!(await sameSecret(request.headers.get('x-api-key'), env.NRFCLOUD_WEBHOOK_TOKEN))) {
    console.warn('Requête refusée : jeton x-api-key incorrect');
    return reply(401, { erreur: 'jeton incorrect' });
  }
  if (env.NRFCLOUD_WEBHOOK_SECRET) {
    const expected = await hmacHex(env.NRFCLOUD_WEBHOOK_SECRET, rawBody);
    const received = (request.headers.get('x-nrfcloud-signature') ?? '').toLowerCase();
    if (!(await sameSecret(received, expected))) {
      console.warn('Requête refusée : signature incorrecte');
      return reply(401, { erreur: 'signature incorrecte' });
    }
  }

  const alerts = extractAlerts(body);
  let sent = 0;
  let notified = 0;
  let failed = 0;

  for (const alert of alerts) {
    const sms = composeSms(alert);
    console.log(
      `Alerte ${alert.test ? 'de test' : 'RÉELLE'} du bijou ${alert.deviceId} : ` +
        `${alert.contacts.length} contact(s)`,
    );
    const [results, notification] = await Promise.all([
      Promise.all(
        (useSms ? alert.contacts : []).map((phone) => sendSms(env, phone, sms, fetchImpl)),
      ),
      useNotification ? sendNotification(env, alert, sms, fetchImpl) : null,
    ]);
    results.forEach((result, i) => {
      console.log(`SMS à ${mask(alert.contacts[i])} : ${result.detail}`);
      if (result.ok) sent++;
      else failed++;
    });
    if (notification) {
      console.log(`Notification ntfy : ${notification.detail}`);
      if (notification.ok) notified++;
      else failed++;
    }
  }

  // Une réponse en erreur demande à nRF Cloud de relivrer plus tard. On ne le
  // fait que si rien n'est parti : relivrer après un envoi partiel ferait
  // recevoir l'alerte en double à ceux qui l'ont déjà eue.
  const status = failed > 0 && sent + notified === 0 ? 502 : 200;
  return reply(status, {
    alertes: alerts.length,
    sms_envoyes: sent,
    notifications_envoyees: notified,
    envois_echoues: failed,
  });
}

export default {
  fetch: (request, env) => handleRequest(request, env),
};
