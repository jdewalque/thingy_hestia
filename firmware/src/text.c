#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "text.h"

void text_copy_utf8(char *dst, size_t dst_len, const char *src)
{
	size_t len = strlen(src);

	if (len >= dst_len) {
		len = dst_len - 1;
		/* Recule jusqu'au début d'un caractère (les octets 10xxxxxx sont
		 * des octets de suite).
		 */
		while (len > 0 && ((unsigned char)src[len] & 0xC0) == 0x80) {
			len--;
		}
	}
	memcpy(dst, src, len);
	dst[len] = '\0';
}

/* Lit un caractère UTF-8 et avance @p src. Retourne U+FFFD si la séquence est invalide. */
static uint32_t utf8_next(const char **src)
{
	const unsigned char *s = (const unsigned char *)*src;
	uint32_t cp;
	int extra;

	if (s[0] < 0x80) {
		cp = s[0];
		extra = 0;
	} else if ((s[0] & 0xE0) == 0xC0) {
		cp = s[0] & 0x1F;
		extra = 1;
	} else if ((s[0] & 0xF0) == 0xE0) {
		cp = s[0] & 0x0F;
		extra = 2;
	} else if ((s[0] & 0xF8) == 0xF0) {
		cp = s[0] & 0x07;
		extra = 3;
	} else {
		*src += 1;
		return 0xFFFD;
	}

	for (int i = 1; i <= extra; i++) {
		if ((s[i] & 0xC0) != 0x80) {
			*src += i;
			return 0xFFFD;
		}
		cp = (cp << 6) | (s[i] & 0x3F);
	}
	*src += extra + 1;
	return cp;
}

/* Équivalent ISO-8859-15 d'un caractère, ou NULL s'il doit être ignoré. */
static const char *latin9_of(uint32_t cp, char single[2])
{
	single[1] = '\0';

	if (cp < 0x80) {
		single[0] = (char)cp;
		return single;
	}

	switch (cp) {
	/* Caractères dont le code diffère entre Unicode et ISO-8859-15. */
	case 0x20AC: single[0] = (char)0xA4; return single; /* € */
	case 0x0160: single[0] = (char)0xA6; return single; /* Š */
	case 0x0161: single[0] = (char)0xA8; return single; /* š */
	case 0x017D: single[0] = (char)0xB4; return single; /* Ž */
	case 0x017E: single[0] = (char)0xB8; return single; /* ž */
	case 0x0152: single[0] = (char)0xBC; return single; /* Œ */
	case 0x0153: single[0] = (char)0xBD; return single; /* œ */
	case 0x0178: single[0] = (char)0xBE; return single; /* Ÿ */
	/* Ponctuation « intelligente » que les claviers de téléphone insèrent. */
	case 0x2018:
	case 0x2019: return "'";
	case 0x201C:
	case 0x201D: return "\"";
	case 0x2013:
	case 0x2014: return "-";
	case 0x2026: return "...";
	case 0x00A0:
	case 0x202F: return " ";
	/* Sélecteurs de variante et liant des émojis : rien à afficher. */
	case 0x200D:
	case 0xFE0F: return NULL;
	/* Ces positions portent un autre caractère en ISO-8859-15. */
	case 0xA4: case 0xA6: case 0xA8: case 0xB4: case 0xB8:
	case 0xBC: case 0xBD: case 0xBE: return "?";
	default:
		break;
	}

	if (cp >= 0xA1 && cp <= 0xFF) {
		single[0] = (char)cp;
		return single;
	}
	return "?";
}

size_t text_utf8_to_latin9(char *dst, size_t dst_len, const char *src)
{
	size_t len = 0;

	while (*src != '\0') {
		char single[2];
		const char *out = latin9_of(utf8_next(&src), single);
		size_t out_len = out ? strlen(out) : 0;

		if (len + out_len >= dst_len) {
			break;
		}
		memcpy(dst + len, out, out_len);
		len += out_len;
	}
	dst[len] = '\0';
	return len;
}

/*
 * Écrit « 50.84673,4.35247 ». Passe par des entiers pour ne pas dépendre de
 * l'affichage des nombres à virgule de la bibliothèque C.
 */
static int format_coordinates(char *dst, size_t dst_len, const struct text_position *pos)
{
	long lat = (long)(pos->latitude * 100000.0 + (pos->latitude < 0 ? -0.5 : 0.5));
	long lon = (long)(pos->longitude * 100000.0 + (pos->longitude < 0 ? -0.5 : 0.5));

	return snprintf(dst, dst_len, "%s%ld.%05ld,%s%ld.%05ld",
			lat < 0 ? "-" : "", labs(lat) / 100000, labs(lat) % 100000,
			lon < 0 ? "-" : "", labs(lon) / 100000, labs(lon) % 100000);
}

static void append_position(char *dst, size_t dst_len, const struct text_position *pos)
{
	size_t len = strlen(dst);
	char coordinates[32];
	long accuracy = (long)(pos->accuracy + 0.5f);

	format_coordinates(coordinates, sizeof(coordinates), pos);

	if (accuracy >= 1000) {
		snprintf(dst + len, dst_len - len,
			 "\nPosition (à environ %ld km près) : https://maps.google.com/?q=%s",
			 (accuracy + 500) / 1000, coordinates);
	} else {
		snprintf(dst + len, dst_len - len,
			 "\nPosition (à environ %ld m près) : https://maps.google.com/?q=%s",
			 accuracy < 1 ? 1 : accuracy, coordinates);
	}
}

static const char *wearer_name(const struct hestia_config *cfg)
{
	return cfg->name[0] != '\0' ? cfg->name : "Le porteur du bijou";
}

void text_alert_sms(char *dst, size_t dst_len, const struct hestia_config *cfg,
		    const struct text_position *position, bool test)
{
	const char *prefix = test ? "[TEST - pas d'urgence] " : "";

	if (cfg->message[0] != '\0') {
		snprintf(dst, dst_len, "%s%s", prefix, cfg->message);
	} else {
		snprintf(dst, dst_len, "%s%s a appuyé sur son bouton d'urgence et a besoin d'aide.",
			 prefix, wearer_name(cfg));
	}

	if (position != NULL) {
		append_position(dst, dst_len, position);
	} else {
		size_t len = strlen(dst);

		snprintf(dst + len, dst_len - len, "\nPosition inconnue pour le moment.");
	}
}
