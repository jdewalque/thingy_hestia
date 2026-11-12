#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/settings/settings.h>

#include "config.h"

LOG_MODULE_REGISTER(config, LOG_LEVEL_INF);

/* Le suffixe change si la structure enregistrée change de forme. */
#define SETTINGS_TREE "hestia"
#define SETTINGS_KEY  "cfg1"

static struct hestia_config current;
static K_MUTEX_DEFINE(lock);

static int settings_set_cb(const char *key, size_t len, settings_read_cb read_cb, void *cb_arg)
{
	struct hestia_config loaded;

	if (strcmp(key, SETTINGS_KEY) != 0) {
		return -ENOENT;
	}
	if (len != sizeof(loaded)) {
		LOG_WRN("Réglages enregistrés illisibles (taille %zu), ignorés", len);
		return 0;
	}
	if (read_cb(cb_arg, &loaded, sizeof(loaded)) != sizeof(loaded)) {
		return -EIO;
	}
	if (loaded.contact_count > CFG_MAX_CONTACTS) {
		return 0;
	}

	k_mutex_lock(&lock, K_FOREVER);
	current = loaded;
	k_mutex_unlock(&lock);
	return 0;
}

SETTINGS_STATIC_HANDLER_DEFINE(hestia, SETTINGS_TREE, NULL, settings_set_cb, NULL, NULL);

int config_init(void)
{
	int err = settings_subsys_init();

	if (err) {
		LOG_ERR("settings_subsys_init: %d", err);
		return err;
	}
	err = settings_load_subtree(SETTINGS_TREE);
	if (err) {
		LOG_ERR("settings_load_subtree: %d", err);
		return err;
	}
	LOG_INF("Réglages chargés : %u contact(s)", current.contact_count);
	return 0;
}

void config_get(struct hestia_config *out)
{
	k_mutex_lock(&lock, K_FOREVER);
	*out = current;
	k_mutex_unlock(&lock);
}

int config_set(const struct hestia_config *cfg)
{
	int err;

	k_mutex_lock(&lock, K_FOREVER);
	current = *cfg;
	err = settings_save_one(SETTINGS_TREE "/" SETTINGS_KEY, &current, sizeof(current));
	k_mutex_unlock(&lock);

	if (err) {
		LOG_ERR("Enregistrement des réglages impossible : %d", err);
	}
	return err;
}
