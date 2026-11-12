/*
 * Tests sur PC de la logique indépendante du matériel : lecture des réglages
 * reçus de l'application et rédaction des SMS. Voir run.sh.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "alert_json.h"
#include "config.h"
#include "text.h"

static void check_str(const char *what, const char *got, const char *expected)
{
	if (strcmp(got, expected) != 0) {
		fprintf(stderr, "ÉCHEC %s\n  obtenu  : [%s]\n  attendu : [%s]\n", what, got, expected);
		assert(0);
	}
}

static int parse(const char *json, struct hestia_config *cfg)
{
	cJSON *obj = cJSON_Parse(json);
	int err = config_from_json(obj, cfg);

	cJSON_Delete(obj);
	return err;
}

static void test_config_roundtrip(void)
{
	/* Exactement ce que l'application envoie (voir docs/protocole-ble.md). */
	const char *json = "{\"name\":\"Marie Dupont\","
			   "\"message\":\"Marie a besoin d'aide.\","
			   "\"contacts\":[{\"name\":\"Paul \\\"Popol\\\" Martin\","
			   "\"phone\":\"+32470123456\"},"
			   "{\"name\":\"Zoé\",\"phone\":\"+33612345678\"}]}";
	struct hestia_config cfg;
	cJSON *back;
	char *text;

	assert(parse(json, &cfg) == 0);
	check_str("nom", cfg.name, "Marie Dupont");
	assert(cfg.contact_count == 2);
	check_str("contact 1", cfg.contacts[0].name, "Paul \"Popol\" Martin");
	check_str("téléphone 1", cfg.contacts[0].phone, "+32470123456");
	check_str("contact 2", cfg.contacts[1].name, "Zoé");

	back = config_to_json(&cfg);
	text = cJSON_PrintUnformatted(back);
	check_str("aller-retour", text, json);
	cJSON_free(text);
	cJSON_Delete(back);
}

static void test_config_rejects(void)
{
	struct hestia_config cfg;

	assert(parse("[]", &cfg) != 0);
	assert(parse("{\"name\":12}", &cfg) != 0);
	assert(parse("{\"contacts\":[{\"name\":\"A\",\"phone\":\"12345\"}]}", &cfg) != 0);
	assert(parse("{\"contacts\":[{\"name\":\"A\",\"phone\":\"+32 470 12 34 56\"}]}", &cfg) != 0);
	assert(parse("{\"contacts\":[{\"name\":\"A\"}]}", &cfg) != 0);
	/* Numéro national : refusé, un SMS ne partirait pas. */
	assert(parse("{\"contacts\":[{\"name\":\"A\",\"phone\":\"0470123456\"}]}", &cfg) != 0);
	assert(parse("{\"contacts\":[{\"phone\":\"+32470123456\"},{\"phone\":\"+32470123456\"},"
		     "{\"phone\":\"+32470123456\"},{\"phone\":\"+32470123456\"},"
		     "{\"phone\":\"+32470123456\"},{\"phone\":\"+32470123456\"}]}", &cfg) != 0);
	/* Réglages vides : acceptés (bijou remis à zéro). */
	assert(parse("{}", &cfg) == 0 && cfg.contact_count == 0);
}

static void test_utf8_truncation(void)
{
	char small[6];

	/* « é » occupe deux octets : il ne doit pas être coupé en deux. */
	text_copy_utf8(small, sizeof(small), "abcdé");
	check_str("troncature", small, "abcd");
	text_copy_utf8(small, sizeof(small), "abé");
	check_str("sans troncature", small, "abé");
}

static void test_latin9(void)
{
	char out[64];

	text_utf8_to_latin9(out, sizeof(out), "Zoé à l’hôpital… 5 € “ok” 🙂");
	check_str("latin9", out, "Zo\xE9 \xE0 l'h\xF4pital... 5 \xA4 \"ok\" ?");

	/* Séquence UTF-8 invalide : remplacée, sans débordement. */
	text_utf8_to_latin9(out, sizeof(out), "a\xC3");
	check_str("invalide", out, "a?");

	text_utf8_to_latin9(out, 4, "abcdef");
	check_str("limite", out, "abc");
}

static void test_sms(void)
{
	struct hestia_config cfg = {.name = "Marie", .message = "Marie a besoin d'aide."};
	struct text_position brussels = {50.846734, 4.352468, 34.6f};
	struct text_position south_west = {-33.86882, -0.5, 2400.0f};
	char sms[TEXT_SMS_LEN];

	text_alert_sms(sms, sizeof(sms), &cfg, &brussels, false);
	check_str("alerte", sms,
		  "Marie a besoin d'aide.\n"
		  "Position (à environ 35 m près) : https://maps.google.com/?q=50.84673,4.35247");

	text_alert_sms(sms, sizeof(sms), &cfg, &south_west, true);
	check_str("test", sms,
		  "[TEST - pas d'urgence] Marie a besoin d'aide.\n"
		  "Position (à environ 2 km près) : https://maps.google.com/?q=-33.86882,-0.50000");

	text_alert_sms(sms, sizeof(sms), &cfg, NULL, false);
	check_str("sans position", sms,
		  "Marie a besoin d'aide.\nPosition inconnue pour le moment.");

	cfg.message[0] = '\0';
	text_alert_sms(sms, sizeof(sms), &cfg, NULL, false);
	check_str("message par défaut", sms,
		  "Marie a appuyé sur son bouton d'urgence et a besoin d'aide.\n"
		  "Position inconnue pour le moment.");

	/* Le message le plus long possible tient dans le tampon avec la position. */
	memset(cfg.message, 'x', sizeof(cfg.message) - 1);
	cfg.message[sizeof(cfg.message) - 1] = '\0';
	text_alert_sms(sms, sizeof(sms), &cfg, &brussels, true);
	assert(strstr(sms, "q=50.84673,4.35247") != NULL);
}

static void check_cloud(const char *what, cJSON *msg, const char *expected)
{
	char *text = cJSON_PrintUnformatted(msg);

	check_str(what, text, expected);
	cJSON_free(text);
	cJSON_Delete(msg);
}

static void test_cloud_message(void)
{
	struct hestia_config cfg = {
		.name = "Marie",
		.message = "Marie a besoin d'aide.",
		.contact_count = 2,
		.contacts = {{.name = "Paul", .phone = "+32470123456"},
			     {.name = "Zoé", .phone = "+33612345678"}},
	};
	struct text_position brussels = {50.846734, 4.352468, 20.6f};
	struct hestia_config longest;
	cJSON *msg;
	char *text;

	check_cloud("alerte réelle",
		    alert_json_build(ALERT_KIND_REAL, &cfg, &brussels, 82, 1700000000000),
		    "{\"appId\":\"HESTIA_ALERT\",\"messageType\":\"DATA\",\"ts\":1700000000000,"
		    "\"data\":{\"type\":\"real\",\"name\":\"Marie\","
		    "\"message\":\"Marie a besoin d'aide.\",\"battery\":82,"
		    "\"contacts\":[\"+32470123456\",\"+33612345678\"],"
		    "\"position\":{\"lat\":50.84673,\"lon\":4.35247,\"accuracy\":21}}}");

	/* Sans position, sans batterie et sans heure : les champs sont absents. */
	check_cloud("test sans position", alert_json_build(ALERT_KIND_TEST, &cfg, NULL, -1, 0),
		    "{\"appId\":\"HESTIA_ALERT\",\"messageType\":\"DATA\","
		    "\"data\":{\"type\":\"test\",\"name\":\"Marie\","
		    "\"message\":\"Marie a besoin d'aide.\","
		    "\"contacts\":[\"+32470123456\",\"+33612345678\"]}}");

	/* Le message le plus gros possible doit tenir dans un seul paquet CoAP
	 * (CONFIG_COAP_CLIENT_BLOCK_SIZE=1024).
	 */
	memset(&longest, 0, sizeof(longest));
	memset(longest.name, 'n', sizeof(longest.name) - 1);
	memset(longest.message, 'm', sizeof(longest.message) - 1);
	longest.contact_count = CFG_MAX_CONTACTS;
	for (int i = 0; i < CFG_MAX_CONTACTS; i++) {
		strcpy(longest.contacts[i].phone, "+123456789012345");
	}
	msg = alert_json_build(ALERT_KIND_REAL, &longest, &brussels, 100, 1700000000000);
	text = cJSON_PrintUnformatted(msg);
	assert(strlen(text) < 1024);
	cJSON_free(text);
	cJSON_Delete(msg);
}

int main(void)
{
	test_cloud_message();
	test_config_roundtrip();
	test_config_rejects();
	test_utf8_truncation();
	test_latin9();
	test_sms();
	printf("Tous les tests passent.\n");
	return 0;
}
