#ifndef HESTIA_BATTERY_H_
#define HESTIA_BATTERY_H_

/*
 * Niveau de batterie en pourcentage (0 à 100), estimé à partir de la tension.
 * Retourne une valeur négative si la mesure est impossible.
 */
int battery_percent(void);

#endif /* HESTIA_BATTERY_H_ */
