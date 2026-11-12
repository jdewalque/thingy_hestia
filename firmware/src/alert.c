#include <errno.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <cJSON.h>
#include <cJSON_os.h>
#include <date_time.h>
#include <modem/location.h>
#include <modem/sms.h>
#include <net/nrf_cloud_coap.h>
#include <nrf_modem_at.h>

#include "alert.h"
#include "alert_json.h"
#include "battery.h"
#include "config.h"
#include "link.h"
#include "net.h"
#include "text.h"
#include "ui.h"

LOG_MODULE_REGISTER(alert, LOG_LEVEL_INF);

/* Attente maximale du réseau mobile avant d'abandonner une alerte. Après un
 * allumage, le bijou met couramment plus d'une minute à trouver le réseau.
 */
#define NETWORK_WAIT K_SECONDS(120)
/* Localisation rapide (Wi-Fi puis antennes) : elle ne doit pas retarder le SMS. */
#define FAST_METHOD_TIMEOUT_MS (15 * MSEC_PER_SEC)
#define FAST_TOTAL_TIMEOUT_MS  (30 * MSEC_PER_SEC)
/* GPS : lent, tenté seulement après l'envoi du premier SMS. */
#define GNSS_TIMEOUT_MS (120 * MSEC_PER_SEC)
/* Au-delà de cette marge, la position rapide est jugée trop vague. */
#define PRECISE_ENOUGH_M 100.0f

struct alert_request {
	bool test;
	int reply_id;
};

K_MSGQ_DEFINE(requests, sizeof(struct alert_request), 1, 4);

static atomic_t busy;
static K_SEM_DEFINE(location_done, 0, 1);
static struct text_position last_position;
static bool last_position_valid;
static bool last_position_cloud_error;

/* Tampons de travail : trop gros pour la pile, et une seule alerte à la fois. */
static struct hestia_config cfg;
static char sms_utf8[TEXT_SMS_LEN];
static char sms_latin9[TEXT_SMS_LEN];

static void location_handler(const struct location_event_data *event)
{
	switch (event->id) {
	case LOCATION_EVT_LOCATION:
		last_position.latitude = event->location.latitude;
		last_position.longitude = event->location.longitude;
		last_position.accuracy = event->location.accuracy;
		last_position_valid = true;
		LOG_INF("Position obtenue par %s (marge %d m)",
			location_method_str(event->method), (int)event->location.accuracy);
		break;
	case LOCATION_EVT_TIMEOUT:
		LOG_WRN("Localisation : délai dépassé");
		break;
	case LOCATION_EVT_ERROR:
		LOG_WRN("Localisation : échec");
		last_position_cloud_error = true;
		break;
	case LOCATION_EVT_RESULT_UNKNOWN:
		break;
	default:
		/* Événements intermédiaires (démarrage, changement de méthode…). */
		return;
	}
	k_sem_give(&location_done);
}

/* Lance une demande de position et attend le résultat. Retourne true si une position est obtenue. */
static bool locate(const struct location_config *config, int32_t wait_ms)
{
	int err;

	last_position_valid = false;
	last_position_cloud_error = false;
	k_sem_reset(&location_done);

	err = location_request(config);
	if (err) {
		LOG_ERR("location_request: %d", err);
		return false;
	}
	if (k_sem_take(&location_done, K_MSEC(wait_ms)) != 0) {
		LOG_WRN("Localisation sans réponse, annulation");
		(void)location_request_cancel();
	}
	return last_position_valid;
}

static bool locate_fast(void)
{
	struct location_config config;
	enum location_method methods[] = {LOCATION_METHOD_WIFI, LOCATION_METHOD_CELLULAR};

	/* Le Wi-Fi et les antennes passent par nRF Cloud. Sans lui, la demande
	 * échouera et le SMS partira sans position.
	 */
	(void)net_cloud_ensure();

	location_config_defaults_set(&config, ARRAY_SIZE(methods), methods);
	config.methods[0].wifi.timeout = FAST_METHOD_TIMEOUT_MS;
	config.methods[1].cellular.timeout = FAST_METHOD_TIMEOUT_MS;
	config.timeout = FAST_TOTAL_TIMEOUT_MS;

	if (locate(&config, FAST_TOTAL_TIMEOUT_MS + 5 * MSEC_PER_SEC)) {
		return true;
	}
	if (last_position_cloud_error) {
		net_cloud_invalidate();
	}
	return false;
}

static bool locate_gnss(void)
{
	struct location_config config;
	enum location_method methods[] = {LOCATION_METHOD_GNSS};

	location_config_defaults_set(&config, ARRAY_SIZE(methods), methods);
	config.methods[0].gnss.timeout = GNSS_TIMEOUT_MS;
	config.timeout = GNSS_TIMEOUT_MS + 10 * MSEC_PER_SEC;

	return locate(&config, GNSS_TIMEOUT_MS + 15 * MSEC_PER_SEC);
}

/* Code « délai réseau dépassé » du modem (+CMS ERROR: 332). */
#define CMS_NETWORK_TIMEOUT 332

/*
 * Envoie le texte de sms_utf8 à tous les contacts, directement par le modem.
 * Retourne le nombre de SMS partis.
 *
 * Tous les réseaux n'acheminent pas les SMS (en NB-IoT notamment) : c'est
 * pourquoi l'alerte part aussi vers nRF Cloud, voir send_to_cloud().
 */
static int send_sms_to_all(void)
{
	int sent = 0;

	text_utf8_to_latin9(sms_latin9, sizeof(sms_latin9), sms_utf8);

	for (int i = 0; i < cfg.contact_count; i++) {
		int err = sms_send_text(cfg.contacts[i].phone, sms_latin9);

		if (err == 0) {
			LOG_INF("SMS au contact %d : envoyé", i + 1);
			sent++;
			continue;
		}
		LOG_ERR("SMS au contact %d : échec (%d)", i + 1, err);

		/* Chaque essai sans réponse du réseau dure une trentaine de
		 * secondes et les suivants échoueraient de la même façon.
		 */
		if (err > 0 && nrf_modem_at_err_type(err) == NRF_MODEM_AT_CMS_ERROR &&
		    nrf_modem_at_err(err) == CMS_NETWORK_TIMEOUT) {
			LOG_WRN("Le réseau n'achemine pas les SMS : abandon des suivants");
			break;
		}
	}
	return sent;
}

/* Envoie l'alerte à nRF Cloud. Retourne 0 si nRF Cloud l'a bien reçue. */
static int send_to_cloud(enum alert_kind kind, const struct text_position *position)
{
	int64_t now_ms = 0;
	cJSON *msg;
	char *text;
	int err;

	err = net_cloud_ensure();
	if (err) {
		return err;
	}

	(void)date_time_now(&now_ms);
	msg = alert_json_build(kind, &cfg, position, battery_percent(), now_ms);
	text = msg ? cJSON_PrintUnformatted(msg) : NULL;
	cJSON_Delete(msg);
	if (text == NULL) {
		LOG_ERR("Mémoire insuffisante pour le message nRF Cloud");
		return -ENOMEM;
	}

	/* Message « confirmable » : nRF Cloud en accuse réception. */
	err = nrf_cloud_coap_json_message_send(text, false, true);
	cJSON_FreeString(text);

	if (err) {
		LOG_ERR("Envoi à nRF Cloud : échec (%d)", err);
		/* La session est peut-être rompue : elle sera rouverte la prochaine fois. */
		net_cloud_invalidate();
	} else {
		LOG_INF("Alerte reçue par nRF Cloud");
	}
	return err;
}

/* Répond à l'application, une seule fois par alerte. */
static void reply_once(struct alert_request *request, const char *error)
{
	if (request->reply_id != ALERT_NO_REPLY) {
		link_reply(request->reply_id, error);
		request->reply_id = ALERT_NO_REPLY;
	}
}

/*
 * Retourne NULL si l'alerte est partie par au moins une voie (nRF Cloud ou
 * SMS), sinon le code d'erreur du protocole.
 */
static const char *run_alert(struct alert_request *request)
{
	const struct text_position *position;
	bool cloud_ok;
	int sent;

	config_get(&cfg);
	if (cfg.contact_count == 0) {
		LOG_WRN("Alerte impossible : aucun contact enregistré");
		return "no_contact";
	}
	if (!net_wait_connected(NETWORK_WAIT)) {
		LOG_WRN("Alerte impossible : pas de réseau mobile");
		return "no_network";
	}

	position = locate_fast() ? &last_position : NULL;

	/* nRF Cloud d'abord : c'est rapide. Dès qu'il a reçu l'alerte, elle est
	 * considérée comme partie, sans attendre les SMS, qui peuvent mettre
	 * longtemps à échouer.
	 */
	cloud_ok = send_to_cloud(request->test ? ALERT_KIND_TEST : ALERT_KIND_REAL, position) == 0;
	if (cloud_ok) {
		reply_once(request, NULL);
		ui_set(UI_SUCCESS);
	}

	text_alert_sms(sms_utf8, sizeof(sms_utf8), &cfg, position, request->test);
	sent = send_sms_to_all();
	if (!cloud_ok && sent == 0) {
		return "send_failed";
	}

	/* Un essai s'arrête là : inutile de solliciter le GPS, qui ne capte
	 * presque jamais en intérieur.
	 */
	if (request->test) {
		return NULL;
	}

	if (position == NULL || position->accuracy > PRECISE_ENOUGH_M) {
		LOG_INF("Position vague ou absente : essai par GPS");
		if (locate_gnss()) {
			(void)send_to_cloud(ALERT_KIND_POSITION_UPDATE, &last_position);
			text_followup_sms(sms_utf8, sizeof(sms_utf8), &cfg, &last_position);
			(void)send_sms_to_all();
		}
	}
	return NULL;
}

static void alert_thread(void *p1, void *p2, void *p3)
{
	struct alert_request request;

	while (true) {
		const char *error;

		k_msgq_get(&requests, &request, K_FOREVER);
		LOG_INF("Alerte %s", request.test ? "de test" : "RÉELLE");
		ui_set(UI_ALERTING);

		error = run_alert(&request);

		ui_set(error == NULL ? UI_SUCCESS : UI_FAILURE);
		reply_once(&request, error);
		atomic_clear(&busy);
	}
}

K_THREAD_DEFINE(alert_tid, 4096, alert_thread, NULL, NULL, NULL, K_PRIO_PREEMPT(7), 0, 0);

int alert_trigger(bool test, int reply_id)
{
	struct alert_request request = {.test = test, .reply_id = reply_id};

	if (!atomic_cas(&busy, 0, 1)) {
		return -EBUSY;
	}
	return k_msgq_put(&requests, &request, K_NO_WAIT);
}

/* Le bijou ne traite pas les SMS reçus, mais le modem refuse d'en envoyer
 * (+CMS ERROR: 301) tant qu'aucun client SMS n'est inscrit.
 */
static void sms_handler(struct sms_data *const data, void *context)
{
	ARG_UNUSED(data);
	ARG_UNUSED(context);
}

int alert_init(void)
{
	int err = sms_register_listener(sms_handler, NULL);

	if (err < 0) {
		LOG_ERR("sms_register_listener: %d", err);
		return err;
	}

	err = location_init(location_handler);
	if (err) {
		LOG_ERR("location_init: %d", err);
	}
	return err;
}
