/*
 * Dialogue avec l'application mobile (voir docs/protocole-ble.md).
 *
 * Le nRF9151 ne fait pas de Bluetooth lui-même : il échange des lignes JSON sur
 * UART0 avec le nRF5340 du Thingy:91 X, dont le firmware d'origine
 * (« connectivity bridge ») les relaie en Bluetooth.
 */
#ifndef HESTIA_LINK_H_
#define HESTIA_LINK_H_

int link_init(void);

/*
 * Répond à la requête @p id : succès si @p error vaut NULL, sinon échec avec
 * ce code d'erreur.
 */
void link_reply(int id, const char *error);

#endif /* HESTIA_LINK_H_ */
