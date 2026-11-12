#include <string.h>

#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <cJSON.h>
#include <cJSON_os.h>

#include "alert.h"
#include "battery.h"
#include "config.h"
#include "link.h"
#include "net.h"

LOG_MODULE_REGISTER(link, LOG_LEVEL_INF);

/* Une requête « set_config » complète (5 contacts, message long) tient largement. */
#define LINE_MAX 2048

static const struct device *const uart = DEVICE_DT_GET(DT_NODELABEL(uart0));

/* Ligne en cours de réception (routine d'interruption). */
static char rx_buf[LINE_MAX];
static size_t rx_len;
static bool rx_overflow;

/* Ligne complète en attente de traitement. */
static char line[LINE_MAX];
static atomic_t line_pending;
static K_SEM_DEFINE(line_ready, 0, 1);

static K_MUTEX_DEFINE(tx_lock);

static void uart_isr(const struct device *dev, void *user_data)
{
	uint8_t byte;

	if (!uart_irq_update(dev) || !uart_irq_rx_ready(dev)) {
		return;
	}

	while (uart_fifo_read(dev, &byte, 1) == 1) {
		if (byte != '\n' && byte != '\r') {
			if (rx_len < sizeof(rx_buf) - 1) {
				rx_buf[rx_len++] = byte;
			} else {
				rx_overflow = true;
			}
			continue;
		}

		/* Fin de ligne. Une ligne trop longue, ou qui arrive alors que la
		 * précédente n'est pas traitée, est perdue : l'application
		 * constatera l'absence de réponse et réessaiera.
		 */
		if (rx_len > 0 && !rx_overflow && atomic_cas(&line_pending, 0, 1)) {
			memcpy(line, rx_buf, rx_len);
			line[rx_len] = '\0';
			k_sem_give(&line_ready);
		}
		rx_len = 0;
		rx_overflow = false;
	}
}

/* Envoie l'objet sur une ligne puis le libère. */
static void send_json(cJSON *obj)
{
	char *text = obj ? cJSON_PrintUnformatted(obj) : NULL;

	cJSON_Delete(obj);
	if (text == NULL) {
		LOG_ERR("Mémoire insuffisante pour répondre");
		return;
	}

	k_mutex_lock(&tx_lock, K_FOREVER);
	for (const char *p = text; *p != '\0'; p++) {
		uart_poll_out(uart, *p);
	}
	uart_poll_out(uart, '\n');
	k_mutex_unlock(&tx_lock);

	cJSON_FreeString(text);
}

static cJSON *new_reply(int id, const char *error)
{
	cJSON *reply = cJSON_CreateObject();

	if (reply == NULL) {
		return NULL;
	}
	cJSON_AddNumberToObject(reply, "id", id);
	cJSON_AddBoolToObject(reply, "ok", error == NULL);
	if (error != NULL) {
		cJSON_AddStringToObject(reply, "error", error);
	}
	return reply;
}

void link_reply(int id, const char *error)
{
	send_json(new_reply(id, error));
}

static void handle_get_status(int id)
{
	cJSON *reply = new_reply(id, NULL);
	cJSON *status = cJSON_AddObjectToObject(reply, "status");
	int battery = battery_percent();

	if (status != NULL) {
		if (battery >= 0) {
			cJSON_AddNumberToObject(status, "battery", battery);
		}
		switch (net_lte_state()) {
		case NET_LTE_CONNECTED:
			cJSON_AddStringToObject(status, "lte", "connected");
			break;
		case NET_LTE_SEARCHING:
			cJSON_AddStringToObject(status, "lte", "searching");
			break;
		default:
			cJSON_AddStringToObject(status, "lte", "off");
			break;
		}
	}
	send_json(reply);
}

static void handle_get_config(int id)
{
	/* static : trop gros pour la pile, et un seul traitement à la fois. */
	static struct hestia_config cfg;
	cJSON *reply = new_reply(id, NULL);
	cJSON *config;

	config_get(&cfg);
	config = config_to_json(&cfg);
	if (reply == NULL || config == NULL) {
		cJSON_Delete(reply);
		cJSON_Delete(config);
		link_reply(id, "internal");
		return;
	}
	cJSON_AddItemToObject(reply, "config", config);
	send_json(reply);
}

static void handle_set_config(int id, const cJSON *request)
{
	static struct hestia_config cfg;

	if (config_from_json(cJSON_GetObjectItemCaseSensitive(request, "config"), &cfg) != 0) {
		link_reply(id, "bad_config");
		return;
	}
	if (config_set(&cfg) != 0) {
		link_reply(id, "storage");
		return;
	}
	LOG_INF("Nouveaux réglages : %u contact(s)", cfg.contact_count);
	link_reply(id, NULL);
}

static void handle_line(const char *text)
{
	cJSON *request = cJSON_Parse(text);
	const cJSON *id_item = cJSON_GetObjectItemCaseSensitive(request, "id");
	const cJSON *cmd_item = cJSON_GetObjectItemCaseSensitive(request, "cmd");
	const char *cmd;
	int id;

	/* Tout ce qui n'est pas une requête est ignoré en silence : le lien
	 * série peut transporter autre chose (messages de démarrage, essais au
	 * clavier depuis un PC…).
	 */
	if (!cJSON_IsNumber(id_item) || !cJSON_IsString(cmd_item)) {
		cJSON_Delete(request);
		return;
	}
	id = id_item->valueint;
	cmd = cmd_item->valuestring;
	LOG_INF("Requête %d : %s", id, cmd);

	if (strcmp(cmd, "get_status") == 0) {
		handle_get_status(id);
	} else if (strcmp(cmd, "get_config") == 0) {
		handle_get_config(id);
	} else if (strcmp(cmd, "set_config") == 0) {
		handle_set_config(id, request);
	} else if (strcmp(cmd, "test_alert") == 0) {
		/* La réponse part quand l'alerte de test est terminée. */
		if (alert_trigger(true, id) != 0) {
			link_reply(id, "busy");
		}
	} else {
		link_reply(id, "unknown_cmd");
	}
	cJSON_Delete(request);
}

static void link_thread(void *p1, void *p2, void *p3)
{
	while (true) {
		k_sem_take(&line_ready, K_FOREVER);
		handle_line(line);
		atomic_clear(&line_pending);
	}
}

K_THREAD_DEFINE(link_tid, 4096, link_thread, NULL, NULL, NULL, K_PRIO_PREEMPT(8), 0, 0);

int link_init(void)
{
	int err;

	if (!device_is_ready(uart)) {
		LOG_ERR("UART0 indisponible");
		return -ENODEV;
	}

	cJSON_Init();

	err = uart_irq_callback_user_data_set(uart, uart_isr, NULL);
	if (err) {
		LOG_ERR("uart_irq_callback_user_data_set: %d", err);
		return err;
	}
	uart_irq_rx_enable(uart);
	return 0;
}
