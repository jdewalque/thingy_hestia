/* Conversion des réglages depuis / vers le JSON du protocole. */
#include <ctype.h>
#include <errno.h>
#include <string.h>

#include "config.h"
#include "text.h"

static bool phone_is_valid(const char *phone)
{
	size_t digits = 0;

	/* La bibliothèque SMS n'accepte que le format international. */
	if (*phone != '+') {
		return false;
	}
	phone++;
	for (; *phone != '\0'; phone++, digits++) {
		if (!isdigit((unsigned char)*phone)) {
			return false;
		}
	}
	return digits >= 8 && digits <= 15;
}

/* Copie le champ texte @p key ; une clé absente donne une chaîne vide. */
static int copy_string(const cJSON *obj, const char *key, char *dst, size_t dst_len)
{
	const cJSON *item = cJSON_GetObjectItemCaseSensitive(obj, key);

	if (item == NULL) {
		dst[0] = '\0';
		return 0;
	}
	if (!cJSON_IsString(item)) {
		return -EINVAL;
	}
	text_copy_utf8(dst, dst_len, item->valuestring);
	return 0;
}

int config_from_json(const cJSON *obj, struct hestia_config *out)
{
	const cJSON *contacts;
	const cJSON *item;

	memset(out, 0, sizeof(*out));

	if (!cJSON_IsObject(obj) ||
	    copy_string(obj, "name", out->name, sizeof(out->name)) ||
	    copy_string(obj, "message", out->message, sizeof(out->message))) {
		return -EINVAL;
	}

	contacts = cJSON_GetObjectItemCaseSensitive(obj, "contacts");
	if (contacts == NULL) {
		return 0;
	}
	if (!cJSON_IsArray(contacts) || cJSON_GetArraySize(contacts) > CFG_MAX_CONTACTS) {
		return -EINVAL;
	}

	cJSON_ArrayForEach(item, contacts) {
		struct hestia_contact *contact = &out->contacts[out->contact_count];
		const cJSON *phone = cJSON_GetObjectItemCaseSensitive(item, "phone");

		if (!cJSON_IsObject(item) || !cJSON_IsString(phone) ||
		    strlen(phone->valuestring) >= sizeof(contact->phone) ||
		    !phone_is_valid(phone->valuestring) ||
		    copy_string(item, "name", contact->name, sizeof(contact->name))) {
			return -EINVAL;
		}
		strcpy(contact->phone, phone->valuestring);
		out->contact_count++;
	}
	return 0;
}

cJSON *config_to_json(const struct hestia_config *cfg)
{
	cJSON *obj = cJSON_CreateObject();
	cJSON *contacts;

	if (obj == NULL ||
	    cJSON_AddStringToObject(obj, "name", cfg->name) == NULL ||
	    cJSON_AddStringToObject(obj, "message", cfg->message) == NULL) {
		goto fail;
	}
	contacts = cJSON_AddArrayToObject(obj, "contacts");
	if (contacts == NULL) {
		goto fail;
	}

	for (int i = 0; i < cfg->contact_count; i++) {
		cJSON *item = cJSON_CreateObject();

		if (item == NULL) {
			goto fail;
		}
		cJSON_AddItemToArray(contacts, item);
		if (cJSON_AddStringToObject(item, "name", cfg->contacts[i].name) == NULL ||
		    cJSON_AddStringToObject(item, "phone", cfg->contacts[i].phone) == NULL) {
			goto fail;
		}
	}
	return obj;

fail:
	cJSON_Delete(obj);
	return NULL;
}
