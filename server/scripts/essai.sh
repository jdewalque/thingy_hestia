#!/bin/sh
# Envoie au serveur une fausse alerte de test, comme le ferait nRF Cloud,
# pour vérifier la chaîne serveur -> Twilio -> SMS sans le bijou.
#
# Usage :
#   NRFCLOUD_WEBHOOK_TOKEN=... NRFCLOUD_WEBHOOK_SECRET=... \
#     scripts/essai.sh https://hestia-alertes.<compte>.workers.dev +32470123456
#
# Les deux variables doivent avoir les mêmes valeurs que sur le serveur.
# Laissez NRFCLOUD_WEBHOOK_SECRET vide si vous n'en avez pas configuré.
set -eu

URL="${1:?Indiquez l'adresse du serveur}"
PHONE="${2:?Indiquez le numéro qui doit recevoir le SMS, au format +32...}"
: "${NRFCLOUD_WEBHOOK_TOKEN:?Définissez NRFCLOUD_WEBHOOK_TOKEN}"

BODY=$(cat <<JSON
{"type":"device.messages","messages":[{"teamId":"essai","deviceId":"essai","messageId":"essai-$(date +%s)","message":{"appId":"HESTIA_ALERT","messageType":"DATA","data":{"type":"test","name":"Essai","message":"Essai du serveur Hestia.","contacts":["$PHONE"],"position":{"lat":50.84673,"lon":4.35247,"accuracy":20}}}}]}
JSON
)

set -- -H "content-type: application/json" -H "x-api-key: $NRFCLOUD_WEBHOOK_TOKEN"
if [ -n "${NRFCLOUD_WEBHOOK_SECRET:-}" ]; then
	SIGNATURE=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$NRFCLOUD_WEBHOOK_SECRET" -r | cut -d' ' -f1)
	set -- "$@" -H "x-nrfcloud-signature: $SIGNATURE"
fi

curl -sS -w '\n[HTTP %{http_code}]\n' "$@" --data-binary "$BODY" "$URL"
