/* Bouton d'urgence et voyant du bijou. */
#ifndef HESTIA_UI_H_
#define HESTIA_UI_H_

#include <stdbool.h>

/* Durée d'appui nécessaire pour déclencher une alerte (évite les appuis accidentels). */
#define UI_HOLD_MS 1500

enum ui_state {
	/* Voyant éteint : fonctionnement normal. */
	UI_IDLE,
	/* Bleu clignotant lent : recherche du réseau mobile. */
	UI_SEARCHING,
	/* Bleu fixe : bouton enfoncé, l'alerte part si l'appui est maintenu. */
	UI_HOLDING,
	/* Rouge clignotant : alerte en cours d'envoi. */
	UI_ALERTING,
	/* Vert fixe quelques secondes : alerte envoyée (ou réseau trouvé). */
	UI_SUCCESS,
	/* Rouge fixe quelques secondes : l'alerte n'a pas pu partir. */
	UI_FAILURE,
};

int ui_init(void);

void ui_set(enum ui_state state);

/* Appelé quand le bijou trouve ou perd le réseau mobile. */
void ui_network_changed(bool connected);

#endif /* HESTIA_UI_H_ */
