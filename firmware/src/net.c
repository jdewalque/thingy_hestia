#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <modem/lte_lc.h>
#include <modem/nrf_modem_lib.h>
#include <net/nrf_cloud_coap.h>

#include "net.h"
#include "ui.h"

LOG_MODULE_REGISTER(net, LOG_LEVEL_INF);

static atomic_t lte_state = ATOMIC_INIT(NET_LTE_OFF);
static K_SEM_DEFINE(connected_sem, 0, 1);
static K_MUTEX_DEFINE(cloud_lock);
static bool cloud_ready;

static void lte_handler(const struct lte_lc_evt *const evt)
{
	enum net_lte_state state;

	if (evt->type == LTE_LC_EVT_LTE_MODE_UPDATE) {
		LOG_INF("Type de réseau : %s",
			evt->lte_mode == LTE_LC_LTE_MODE_LTEM ? "LTE-M" :
			evt->lte_mode == LTE_LC_LTE_MODE_NBIOT ? "NB-IoT" : "aucun");
		return;
	}

	if (evt->type != LTE_LC_EVT_NW_REG_STATUS) {
		return;
	}

	switch (evt->nw_reg_status) {
	case LTE_LC_NW_REG_REGISTERED_HOME:
	case LTE_LC_NW_REG_REGISTERED_ROAMING:
		state = NET_LTE_CONNECTED;
		break;
	case LTE_LC_NW_REG_SEARCHING:
		state = NET_LTE_SEARCHING;
		break;
	default:
		state = NET_LTE_OFF;
		break;
	}

	if (atomic_set(&lte_state, state) == state) {
		return;
	}

	if (state == NET_LTE_CONNECTED) {
		LOG_INF("Réseau mobile : connecté");
		k_sem_give(&connected_sem);
	} else {
		LOG_INF("Réseau mobile : %s", state == NET_LTE_SEARCHING ? "recherche" : "absent");
		k_sem_reset(&connected_sem);
	}
	ui_network_changed(state == NET_LTE_CONNECTED);
}

int net_init(void)
{
	int err = nrf_modem_lib_init();

	if (err) {
		LOG_ERR("nrf_modem_lib_init: %d", err);
		return err;
	}

	err = nrf_cloud_coap_init();
	if (err) {
		LOG_ERR("nrf_cloud_coap_init: %d", err);
		return err;
	}

	/* NB-IoT ne transmet pas les SMS chez tous les opérateurs (Proximus :
	 * +CMS ERROR: 332). LTE-M seul, GPS gardé pour la localisation.
	 */
	err = lte_lc_system_mode_set(LTE_LC_SYSTEM_MODE_LTEM_GPS,
				     LTE_LC_SYSTEM_MODE_PREFER_AUTO);
	if (err) {
		LOG_ERR("lte_lc_system_mode_set: %d", err);
	}

	atomic_set(&lte_state, NET_LTE_SEARCHING);
	err = lte_lc_connect_async(lte_handler);
	if (err) {
		LOG_ERR("lte_lc_connect_async: %d", err);
	}
	return err;
}

enum net_lte_state net_lte_state(void)
{
	return (enum net_lte_state)atomic_get(&lte_state);
}

bool net_wait_connected(k_timeout_t timeout)
{
	if (net_lte_state() == NET_LTE_CONNECTED) {
		return true;
	}
	if (k_sem_take(&connected_sem, timeout) != 0) {
		return false;
	}
	/* Rend le jeton pour les autres tâches qui attendent le réseau. */
	k_sem_give(&connected_sem);
	return true;
}

int net_cloud_ensure(void)
{
	int err = 0;

	k_mutex_lock(&cloud_lock, K_FOREVER);
	if (!cloud_ready) {
		err = nrf_cloud_coap_connect(NULL);
		if (err) {
			LOG_ERR("Connexion à nRF Cloud impossible : %d", err);
		} else {
			LOG_INF("Connecté à nRF Cloud");
			cloud_ready = true;
		}
	}
	k_mutex_unlock(&cloud_lock);
	return err;
}

void net_cloud_invalidate(void)
{
	k_mutex_lock(&cloud_lock, K_FOREVER);
	if (cloud_ready) {
		(void)nrf_cloud_coap_disconnect();
		cloud_ready = false;
	}
	k_mutex_unlock(&cloud_lock);
}
