/*
 * Réglages du bijou : nom du porteur, message d'alerte et contacts d'urgence.
 * Ils arrivent de l'application (voir docs/protocole-ble.md) et sont conservés
 * en mémoire flash.
 */
#ifndef HESTIA_CONFIG_H_
#define HESTIA_CONFIG_H_

#include <stdint.h>

#include <cJSON.h>

#define CFG_MAX_CONTACTS 5
/* Tailles en octets, zéro final compris. Les textes sont en UTF-8. */
#define CFG_NAME_LEN	 64
#define CFG_MESSAGE_LEN	 400
#define CFG_PHONE_LEN	 21

struct hestia_contact {
	char name[CFG_NAME_LEN];
	char phone[CFG_PHONE_LEN];
};

struct hestia_config {
	char name[CFG_NAME_LEN];
	char message[CFG_MESSAGE_LEN];
	uint8_t contact_count;
	struct hestia_contact contacts[CFG_MAX_CONTACTS];
};

/* Charge les réglages enregistrés. À appeler une fois au démarrage. */
int config_init(void);

/* Copie les réglages actuels dans @p out. */
void config_get(struct hestia_config *out);

/* Remplace les réglages et les enregistre en mémoire flash. */
int config_set(const struct hestia_config *cfg);

/*
 * Conversion depuis / vers l'objet JSON « config » du protocole.
 * config_from_json() retourne -EINVAL si l'objet est mal formé ou si un numéro
 * de téléphone est invalide ; les textes trop longs sont tronqués.
 */
int config_from_json(const cJSON *obj, struct hestia_config *out);
cJSON *config_to_json(const struct hestia_config *cfg);

#endif /* HESTIA_CONFIG_H_ */
