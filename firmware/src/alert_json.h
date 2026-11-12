/* Message d'alerte envoyé à nRF Cloud. */
#ifndef HESTIA_ALERT_JSON_H_
#define HESTIA_ALERT_JSON_H_

#include <stdint.h>

#include <cJSON.h>

#include "config.h"
#include "text.h"

/* Identifiant des messages Hestia dans nRF Cloud. */
#define ALERT_APP_ID "HESTIA_ALERT"

enum alert_kind {
	/* Appui sur le bouton du bijou. */
	ALERT_KIND_REAL,
	/* Essai lancé depuis l'application. */
	ALERT_KIND_TEST,
};

/*
 * Construit le message au format des messages d'appareil de nRF Cloud :
 *
 *   {"appId":"HESTIA_ALERT","messageType":"DATA","ts":1700000000000,
 *    "data":{"type":"real","name":"…","message":"…","battery":82,
 *            "contacts":["+32470123456"],
 *            "position":{"lat":50.84673,"lon":4.35247,"accuracy":21}}}
 *
 * @p position vaut NULL si le bijou n'a pas pu se localiser, @p battery est
 * négatif si le niveau est inconnu et @p ts_ms vaut 0 si l'heure est inconnue :
 * le champ correspondant est alors absent.
 *
 * Retourne NULL s'il n'y a plus de mémoire. L'appelant libère l'objet.
 */
cJSON *alert_json_build(enum alert_kind kind, const struct hestia_config *cfg,
			const struct text_position *position, int battery, int64_t ts_ms);

#endif /* HESTIA_ALERT_JSON_H_ */
