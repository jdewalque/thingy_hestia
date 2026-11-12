#!/bin/sh
# Envoie au serveur une fausse alerte de test, comme le ferait nRF Cloud,
# pour verifier la chaine serveur -> Twilio -> SMS sans le bijou.
#
# Usage, depuis le dossier server/ :
#   scripts/essai.sh https://hestia-alertes.<compte>.workers.dev +32470123456
#
# Le script demande le jeton et le secret (ceux enregistres sur le serveur).
# Pour ne pas les retaper, on peut les mettre dans le fichier server/.env,
# qui n'est jamais envoye dans le depot :
#   NRFCLOUD_WEBHOOK_TOKEN=...
#   NRFCLOUD_WEBHOOK_SECRET=...
#
# Ecrit sans accents ni apostrophes dans le code : le shell de macOS
# (bash 3.2) les interprete mal a certains endroits.
set -eu

if [ $# -ne 2 ]; then
	echo "Usage : scripts/essai.sh <adresse du serveur> <numero au format +32...>" >&2
	exit 1
fi
URL="$1"
PHONE="$2"

ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
	. "$ENV_FILE"
fi

# Demande une valeur sans afficher ce qui est tape.
ask() {
	printf '%s : ' "$1" >&2
	stty -echo 2>/dev/null || true
	read -r ANSWER
	stty echo 2>/dev/null || true
	printf '\n' >&2
}

if [ -z "${NRFCLOUD_WEBHOOK_TOKEN:-}" ]; then
	ask "Jeton (NRFCLOUD_WEBHOOK_TOKEN)"
	NRFCLOUD_WEBHOOK_TOKEN="$ANSWER"
fi
if [ -z "${NRFCLOUD_WEBHOOK_SECRET:-}" ]; then
	ask "Secret (NRFCLOUD_WEBHOOK_SECRET)"
	NRFCLOUD_WEBHOOK_SECRET="$ANSWER"
fi

NOW="$(date +%s)"
BODY="$(printf '{"type":"device.messages","messages":[{"teamId":"essai","deviceId":"essai","messageId":"essai-%s","message":{"appId":"HESTIA_ALERT","messageType":"DATA","data":{"type":"test","name":"Essai","message":"Essai du serveur Hestia.","contacts":["%s"],"position":{"lat":50.84673,"lon":4.35247,"accuracy":20}}}}]}' "$NOW" "$PHONE")"
SIGNATURE="$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$NRFCLOUD_WEBHOOK_SECRET" -r | cut -d' ' -f1)"

curl -sS -w '\n[HTTP %{http_code}]\n' \
	-H "content-type: application/json" \
	-H "x-api-key: $NRFCLOUD_WEBHOOK_TOKEN" \
	-H "x-nrfcloud-signature: $SIGNATURE" \
	--data-binary "$BODY" "$URL"
