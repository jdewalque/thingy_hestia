// Envoi d'une notification par ntfy.sh : un service gratuit, sans compte, qui
// pousse un message vers l'application ntfy des téléphones abonnés à un
// « sujet ». Sert à essayer la chaîne d'alerte sans fournisseur de SMS.

/**
 * @returns {Promise<{ok: boolean, detail: string}>}
 */
export async function sendNotification(env, alert, text, fetchImpl = fetch) {
  // Les en-têtes HTTP n'acceptent pas les accents : titre en ASCII.
  const headers = {
    'content-type': 'text/plain; charset=utf-8',
    title: alert.test ? 'Hestia - alerte de test' : 'Hestia - ALERTE',
    priority: alert.test ? 'default' : 'urgent',
    tags: alert.test ? 'test_tube' : 'rotating_light',
  };
  // Toucher la notification ouvre la carte.
  if (alert.position) {
    headers.click =
      `https://maps.google.com/?q=${alert.position.lat.toFixed(5)},${alert.position.lon.toFixed(5)}`;
  }

  let response;
  try {
    response = await fetchImpl(`https://ntfy.sh/${encodeURIComponent(env.NTFY_TOPIC)}`, {
      method: 'POST',
      headers,
      body: text,
    });
  } catch (error) {
    return { ok: false, detail: `ntfy injoignable : ${error.message}` };
  }
  return response.ok
    ? { ok: true, detail: 'envoyée' }
    : { ok: false, detail: `ntfy HTTP ${response.status}` };
}
