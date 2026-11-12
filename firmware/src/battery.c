#include <errno.h>

#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>

#include "battery.h"

LOG_MODULE_REGISTER(battery, LOG_LEVEL_INF);

static const struct device *const charger = DEVICE_DT_GET(DT_NODELABEL(npm1300_charger));

/*
 * Courbe de décharge typique d'une batterie lithium-polymère (tension à vide).
 * C'est une estimation : la tension baisse quand le modem émet et monte
 * pendant la charge. Suffisant pour prévenir qu'il faut recharger.
 */
static const struct {
	int millivolts;
	int percent;
} curve[] = {
	{4150, 100}, {4050, 90}, {3970, 80}, {3900, 70}, {3840, 60}, {3790, 50},
	{3750, 40},  {3710, 30}, {3660, 20}, {3580, 10}, {3450, 5},  {3300, 0},
};

int battery_percent(void)
{
	struct sensor_value value;
	int millivolts;
	int err;

	if (!device_is_ready(charger)) {
		return -ENODEV;
	}

	err = sensor_sample_fetch(charger);
	if (!err) {
		err = sensor_channel_get(charger, SENSOR_CHAN_GAUGE_VOLTAGE, &value);
	}
	if (err) {
		LOG_WRN("Lecture de la batterie impossible : %d", err);
		return err;
	}

	millivolts = value.val1 * 1000 + value.val2 / 1000;

	if (millivolts >= curve[0].millivolts) {
		return 100;
	}
	for (size_t i = 1; i < ARRAY_SIZE(curve); i++) {
		if (millivolts >= curve[i].millivolts) {
			/* Interpolation entre les deux points voisins. */
			int span_mv = curve[i - 1].millivolts - curve[i].millivolts;
			int span_pct = curve[i - 1].percent - curve[i].percent;

			return curve[i].percent +
			       (millivolts - curve[i].millivolts) * span_pct / span_mv;
		}
	}
	return 0;
}
