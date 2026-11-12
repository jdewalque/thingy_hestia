/* Réseau mobile (LTE) et connexion à nRF Cloud. */
#ifndef HESTIA_NET_H_
#define HESTIA_NET_H_

#include <stdbool.h>

#include <zephyr/kernel.h>

enum net_lte_state {
	NET_LTE_OFF,
	NET_LTE_SEARCHING,
	NET_LTE_CONNECTED,
};

/* Démarre le modem et lance la recherche du réseau, sans attendre. */
int net_init(void);

enum net_lte_state net_lte_state(void);

/* Attend que le bijou soit inscrit sur le réseau. Retourne false si le délai expire. */
bool net_wait_connected(k_timeout_t timeout);

/*
 * Ouvre la session nRF Cloud si elle ne l'est pas déjà. Nécessaire avant une
 * localisation par Wi-Fi ou par antennes.
 */
int net_cloud_ensure(void);

/* Signale que la session nRF Cloud semble rompue : elle sera rouverte au prochain besoin. */
void net_cloud_invalidate(void);

#endif /* HESTIA_NET_H_ */
