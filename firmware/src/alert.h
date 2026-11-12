/* Déroulement d'une alerte : localisation puis envoi des SMS. */
#ifndef HESTIA_ALERT_H_
#define HESTIA_ALERT_H_

#include <stdbool.h>

/* Valeur de @p reply_id quand personne n'attend de réponse (appui sur le bouton). */
#define ALERT_NO_REPLY (-1)

int alert_init(void);

/*
 * Lance une alerte. Avec @p test, les SMS indiquent qu'il s'agit d'un essai et
 * le résultat est renvoyé à l'application en réponse à la requête @p reply_id.
 * Retourne -EBUSY si une alerte est déjà en cours.
 */
int alert_trigger(bool test, int reply_id);

#endif /* HESTIA_ALERT_H_ */
