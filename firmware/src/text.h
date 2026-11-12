/* Préparation des textes : troncature UTF-8 et rédaction des SMS. */
#ifndef HESTIA_TEXT_H_
#define HESTIA_TEXT_H_

#include <stdbool.h>
#include <stddef.h>

#include "config.h"

/* Taille maximale d'un SMS rédigé par le bijou, zéro final compris. */
#define TEXT_SMS_LEN 640

/* Position obtenue par le bijou. */
struct text_position {
	double latitude;
	double longitude;
	/* Marge d'erreur en mètres. */
	float accuracy;
};

/*
 * Copie une chaîne UTF-8 en la tronquant si besoin, sans jamais couper un
 * caractère en deux.
 */
void text_copy_utf8(char *dst, size_t dst_len, const char *src);

/*
 * Convertit de l'UTF-8 vers l'ISO-8859-15, seul jeu de caractères accepté par
 * la bibliothèque SMS. Les caractères sans équivalent deviennent « ? ».
 * Retourne la longueur écrite (hors zéro final).
 */
size_t text_utf8_to_latin9(char *dst, size_t dst_len, const char *src);

/*
 * Rédige le SMS d'alerte en UTF-8.
 * @p position vaut NULL si le bijou n'a pas pu se localiser.
 */
void text_alert_sms(char *dst, size_t dst_len, const struct hestia_config *cfg,
		    const struct text_position *position, bool test);

#endif /* HESTIA_TEXT_H_ */
