// Envoi d'un SMS, ou d'un message WhatsApp, par l'API de Twilio.

/**
 * @returns {Promise<{ok: boolean, detail: string}>}
 */
export async function sendSms(env, to, body, fetchImpl = fetch) {
  // TWILIO_FROM est un numéro ou un nom d'expéditeur, l'identifiant d'un
  // « Messaging Service » (il commence par MG), ou un expéditeur WhatsApp
  // (« whatsapp:+14155238886 »). Dans ce dernier cas, le message part par
  // WhatsApp : le destinataire doit porter le même préfixe.
  const whatsapp = env.TWILIO_FROM.startsWith('whatsapp:');
  const params = new URLSearchParams({ To: whatsapp ? `whatsapp:${to}` : to, Body: body });
  if (env.TWILIO_FROM.startsWith('MG')) {
    params.set('MessagingServiceSid', env.TWILIO_FROM);
  } else {
    params.set('From', env.TWILIO_FROM);
  }

  let response;
  try {
    response = await fetchImpl(
      `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`,
      {
        method: 'POST',
        headers: {
          authorization: `Basic ${btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`)}`,
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
      },
    );
  } catch (error) {
    return { ok: false, detail: `Twilio injoignable : ${error.message}` };
  }

  if (response.ok) return { ok: true, detail: 'envoyé' };

  // Twilio explique le refus : {"code": 21608, "message": "…"}.
  let detail = `HTTP ${response.status}`;
  try {
    const error = await response.json();
    detail = `Twilio ${error.code ?? response.status} : ${error.message ?? ''}`;
  } catch {
    // Réponse illisible : on garde le code HTTP.
  }
  return { ok: false, detail };
}
