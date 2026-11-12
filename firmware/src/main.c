/*
 * Hestia — firmware du bijou d'urgence (prototype sur Thingy:91 X, nRF9151).
 *
 * Un appui maintenu sur le bouton localise le bijou (Wi-Fi, antennes, puis GPS)
 * et envoie un SMS avec la position aux contacts choisis dans l'application.
 */
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "alert.h"
#include "config.h"
#include "link.h"
#include "net.h"
#include "ui.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

int main(void)
{
	LOG_INF("Hestia démarre");

	/* Chaque module signale lui-même ses erreurs. On continue malgré un
	 * échec pour garder un maximum de fonctions : par exemple, les réglages
	 * restent modifiables même si le modem ne démarre pas.
	 */
	(void)ui_init();
	(void)config_init();
	(void)link_init();

	if (net_init() == 0) {
		(void)alert_init();
	}

	/* Ouvre la session nRF Cloud dès que le réseau est là, pour que la
	 * première alerte n'ait pas à le faire.
	 */
	if (net_wait_connected(K_FOREVER)) {
		(void)net_cloud_ensure();
	}
	return 0;
}
