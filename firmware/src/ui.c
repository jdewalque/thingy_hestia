#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "alert.h"
#include "ui.h"

LOG_MODULE_REGISTER(ui, LOG_LEVEL_INF);

#define RESULT_DISPLAY_MS 5000

static const struct gpio_dt_spec led_red = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec led_green = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec led_blue = GPIO_DT_SPEC_GET(DT_ALIAS(led2), gpios);
static const struct gpio_dt_spec button = GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios);

static struct gpio_callback button_cb;
static K_MUTEX_DEFINE(lock);
static enum ui_state state = UI_IDLE;
static bool blink_on;
static bool network_connected;

static void led_work_fn(struct k_work *work);
static void hold_work_fn(struct k_work *work);
static void button_work_fn(struct k_work *work);

static K_WORK_DELAYABLE_DEFINE(led_work, led_work_fn);
static K_WORK_DELAYABLE_DEFINE(hold_work, hold_work_fn);
static K_WORK_DEFINE(button_work, button_work_fn);

static void leds(bool red, bool green, bool blue)
{
	gpio_pin_set_dt(&led_red, red);
	gpio_pin_set_dt(&led_green, green);
	gpio_pin_set_dt(&led_blue, blue);
}

/* État de repos : éteint si le réseau est là, sinon recherche. */
static enum ui_state rest_state(void)
{
	return network_connected ? UI_IDLE : UI_SEARCHING;
}

/* Applique l'état courant au voyant et programme la suite. À appeler verrou pris. */
static void apply(void)
{
	k_work_cancel_delayable(&led_work);

	switch (state) {
	case UI_IDLE:
		leds(false, false, false);
		break;
	case UI_SEARCHING:
		blink_on = !blink_on;
		leds(false, false, blink_on);
		k_work_schedule(&led_work, blink_on ? K_MSEC(100) : K_MSEC(1900));
		break;
	case UI_HOLDING:
		leds(false, false, true);
		break;
	case UI_ALERTING:
		blink_on = !blink_on;
		leds(blink_on, false, false);
		k_work_schedule(&led_work, K_MSEC(250));
		break;
	case UI_SUCCESS:
		leds(false, true, false);
		k_work_schedule(&led_work, K_MSEC(RESULT_DISPLAY_MS));
		break;
	case UI_FAILURE:
		leds(true, false, false);
		k_work_schedule(&led_work, K_MSEC(RESULT_DISPLAY_MS));
		break;
	}
}

static void led_work_fn(struct k_work *work)
{
	k_mutex_lock(&lock, K_FOREVER);
	if (state == UI_SUCCESS || state == UI_FAILURE) {
		state = rest_state();
		blink_on = false;
	}
	apply();
	k_mutex_unlock(&lock);
}

void ui_set(enum ui_state new_state)
{
	k_mutex_lock(&lock, K_FOREVER);
	state = new_state == UI_IDLE ? rest_state() : new_state;
	blink_on = false;
	apply();
	k_mutex_unlock(&lock);
}

void ui_network_changed(bool connected)
{
	k_mutex_lock(&lock, K_FOREVER);
	network_connected = connected;
	/* Ne remplace pas l'affichage d'un appui ou d'une alerte en cours. */
	if (state == UI_IDLE || state == UI_SEARCHING) {
		state = connected ? UI_SUCCESS : UI_SEARCHING;
		blink_on = false;
		apply();
	}
	k_mutex_unlock(&lock);
}

static void hold_work_fn(struct k_work *work)
{
	if (gpio_pin_get_dt(&button) <= 0) {
		return;
	}
	LOG_INF("Bouton maintenu : alerte");
	/* Si une alerte est déjà en cours, son affichage reste en place. */
	(void)alert_trigger(false, ALERT_NO_REPLY);
}

static void button_work_fn(struct k_work *work)
{
	bool pressed = gpio_pin_get_dt(&button) > 0;

	k_mutex_lock(&lock, K_FOREVER);
	if (pressed) {
		k_work_reschedule(&hold_work, K_MSEC(UI_HOLD_MS));
		if (state == UI_IDLE || state == UI_SEARCHING) {
			state = UI_HOLDING;
			apply();
		}
	} else {
		k_work_cancel_delayable(&hold_work);
		if (state == UI_HOLDING) {
			state = rest_state();
			blink_on = false;
			apply();
		}
	}
	k_mutex_unlock(&lock);
}

static void button_isr(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	k_work_submit(&button_work);
}

int ui_init(void)
{
	int err;

	if (!gpio_is_ready_dt(&led_red) || !gpio_is_ready_dt(&button)) {
		return -ENODEV;
	}

	err = gpio_pin_configure_dt(&led_red, GPIO_OUTPUT_INACTIVE);
	err = err ?: gpio_pin_configure_dt(&led_green, GPIO_OUTPUT_INACTIVE);
	err = err ?: gpio_pin_configure_dt(&led_blue, GPIO_OUTPUT_INACTIVE);
	err = err ?: gpio_pin_configure_dt(&button, GPIO_INPUT);
	err = err ?: gpio_pin_interrupt_configure_dt(&button, GPIO_INT_EDGE_BOTH);
	if (err) {
		LOG_ERR("Configuration du bouton ou du voyant impossible : %d", err);
		return err;
	}

	gpio_init_callback(&button_cb, button_isr, BIT(button.pin));
	gpio_add_callback(button.port, &button_cb);

	ui_set(UI_SEARCHING);
	return 0;
}
