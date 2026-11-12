#include <math.h>

#include "alert_json.h"

static const char *kind_name(enum alert_kind kind)
{
	return kind == ALERT_KIND_TEST ? "test" : "real";
}

/* Arrondit à 5 décimales (environ 1 m) : inutile d'envoyer 15 chiffres. */
static double round5(double value)
{
	return round(value * 100000.0) / 100000.0;
}

cJSON *alert_json_build(enum alert_kind kind, const struct hestia_config *cfg,
			const struct text_position *position, int battery, int64_t ts_ms)
{
	cJSON *msg = cJSON_CreateObject();
	cJSON *data;

	if (msg == NULL || cJSON_AddStringToObject(msg, "appId", ALERT_APP_ID) == NULL ||
	    cJSON_AddStringToObject(msg, "messageType", "DATA") == NULL ||
	    (ts_ms > 0 && cJSON_AddNumberToObject(msg, "ts", (double)ts_ms) == NULL)) {
		goto fail;
	}

	data = cJSON_AddObjectToObject(msg, "data");
	if (data == NULL || cJSON_AddStringToObject(data, "type", kind_name(kind)) == NULL ||
	    cJSON_AddStringToObject(data, "name", cfg->name) == NULL ||
	    cJSON_AddStringToObject(data, "message", cfg->message) == NULL ||
	    (battery >= 0 && cJSON_AddNumberToObject(data, "battery", battery) == NULL)) {
		goto fail;
	}

	if (position != NULL) {
		cJSON *pos = cJSON_AddObjectToObject(data, "position");

		if (pos == NULL ||
		    cJSON_AddNumberToObject(pos, "lat", round5(position->latitude)) == NULL ||
		    cJSON_AddNumberToObject(pos, "lon", round5(position->longitude)) == NULL ||
		    cJSON_AddNumberToObject(pos, "accuracy",
					    round((double)position->accuracy)) == NULL) {
			goto fail;
		}
	}
	return msg;

fail:
	cJSON_Delete(msg);
	return NULL;
}
