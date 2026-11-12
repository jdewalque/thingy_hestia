// Lecture des alertes Hestia reçues de nRF Cloud et rédaction des SMS.
// Le format du message est décrit dans firmware/README.md ; le texte des SMS
// reprend celui que le bijou rédige lui-même (firmware/src/text.c).

export const APP_ID = 'HESTIA_ALERT';
export const MAX_CONTACTS = 5;

const PHONE = /^\+\d{8,15}$/;

/**
 * nRF Cloud livre le champ « data » tel quel (objet), ou sous forme de texte
 * JSON, parfois encodé en base64, selon la façon dont l'appareil l'a envoyé.
 */
function decodeData(data) {
  if (data && typeof data === 'object') return data;
  if (typeof data !== 'string') return null;
  const fromBase64 = (s) =>
    new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));
  for (const decode of [(s) => s, fromBase64]) {
    try {
      const parsed = JSON.parse(decode(data));
      if (parsed && typeof parsed === 'object') return parsed;
    } catch {
      // Essai suivant.
    }
  }
  return null;
}

function text(value, maxLength) {
  return typeof value === 'string' ? value.slice(0, maxLength) : '';
}

/** Retourne l'alerte nettoyée, ou null si les données ne sont pas exploitables. */
export function parseAlert(rawData) {
  const data = decodeData(rawData);
  if (!data || !Array.isArray(data.contacts)) return null;

  const contacts = [...new Set(data.contacts)]
    .filter((phone) => typeof phone === 'string' && PHONE.test(phone))
    .slice(0, MAX_CONTACTS);

  const p = data.position;
  const position =
    p && Number.isFinite(p.lat) && Number.isFinite(p.lon) &&
    Math.abs(p.lat) <= 90 && Math.abs(p.lon) <= 180
      ? { lat: p.lat, lon: p.lon, accuracy: Number.isFinite(p.accuracy) ? p.accuracy : null }
      : null;

  return {
    test: data.type === 'test',
    name: text(data.name, 64),
    message: text(data.message, 400),
    contacts,
    position,
  };
}

/**
 * Extrait les alertes Hestia d'une livraison de nRF Cloud. Les autres
 * messages de l'appareil (localisation, état…) sont ignorés.
 */
export function extractAlerts(body) {
  const alerts = [];
  for (const item of Array.isArray(body?.messages) ? body.messages : []) {
    const message = item?.message;
    if (!message || message.appId !== APP_ID) continue;
    const alert = parseAlert(message.data);
    if (alert) alerts.push({ ...alert, deviceId: String(item.deviceId ?? '') });
  }
  return alerts;
}

function positionLine(position) {
  if (!position) return 'Position inconnue pour le moment.';
  const link = `https://maps.google.com/?q=${position.lat.toFixed(5)},${position.lon.toFixed(5)}`;
  if (position.accuracy === null) return `Position : ${link}`;
  const margin =
    position.accuracy >= 1000
      ? `${Math.round(position.accuracy / 1000)} km`
      : `${Math.max(1, Math.round(position.accuracy))} m`;
  return `Position (à environ ${margin} près) : ${link}`;
}

export function composeSms(alert) {
  const prefix = alert.test ? "[TEST - pas d'urgence] " : '';
  const who = alert.name || 'Le porteur du bijou';
  const message =
    alert.message || `${who} a appuyé sur son bouton d'urgence et a besoin d'aide.`;
  return `${prefix}${message}\n${positionLine(alert.position)}`;
}
