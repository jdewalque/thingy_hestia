# Protocole Bluetooth entre l'application et le bijou

Ce document décrit ce que l'application attend du bijou. Le firmware du
Thingy:91 X devra l'implémenter. Côté application, tout se trouve dans
`app/lib/jewel/protocol.dart` et `app/lib/jewel/ble_jewel.dart`.

## Service GATT

Le bijou est le périphérique ; il annonce l'UUID du service dans ses trames
d'advertising (l'application filtre sa recherche dessus).

| Rôle | UUID | Propriétés |
|---|---|---|
| Service | `8e7a0001-5c1f-4b6e-9d2a-48e57149a0c1` | |
| RX (application → bijou) | `8e7a0002-5c1f-4b6e-9d2a-48e57149a0c1` | write (ou write without response) |
| TX (bijou → application) | `8e7a0003-5c1f-4b6e-9d2a-48e57149a0c1` | notify |

## Messages

Chaque message est un objet JSON en UTF-8 terminé par un saut de ligne (`\n`).
Un message peut être découpé en plusieurs écritures ou notifications de
`MTU - 3` octets : le destinataire accumule les octets jusqu'au `\n`.

L'application envoie des requêtes numérotées ; le bijou répond avec le même
`id`.

```
→ {"id":1,"cmd":"get_status"}
← {"id":1,"ok":true,"status":{"battery":82,"lte":"connected"}}
```

En cas d'échec : `{"id":1,"ok":false,"error":"<code>"}`.

| Commande | Arguments | Réponse | Délai max. |
|---|---|---|---|
| `get_status` | – | `status` : `battery` (0–100, ou absent si inconnu), `lte` (`connected`, `searching` ou `off`) | 10 s |
| `get_config` | – | `config` (voir ci-dessous) | 10 s |
| `set_config` | `config` | – | 10 s |
| `test_alert` | – | `ok` une fois l'alerte de test acceptée par le serveur | 90 s |

Codes d'erreur compris par l'application : `no_network` (pas de réseau mobile,
affiché tel quel à l'utilisateur) ; tout autre code donne un message d'erreur
générique.

## Réglages (`config`)

```json
{
  "name": "Marie Dupont",
  "message": "Marie Dupont a appuyé sur son bouton d'urgence et a besoin d'aide.",
  "contacts": [
    {"name": "Paul Martin", "phone": "+32470123456"}
  ]
}
```

- 5 contacts au maximum, message de 120 caractères au maximum.
- Les numéros sont sans séparateurs, au format international quand
  l'application a pu le déterminer (pays FR, BE, CH, LU), sinon tels que saisis.
- `set_config` remplace tous les réglages. Le bijou les conserve en mémoire
  non volatile.

## Répartition des rôles

Le téléphone ne parle qu'au bijou, en Bluetooth. C'est le bijou qui transmet
les réglages et les alertes au serveur par LTE, et le serveur qui envoie les
SMS. L'application n'a donc besoin ni de compte ni d'accès Internet, et une
alerte part même si le téléphone est éteint ou loin.

`test_alert` suit le même chemin qu'une vraie alerte (bijou → LTE → serveur →
SMS), avec un texte indiquant qu'il s'agit d'un test.
