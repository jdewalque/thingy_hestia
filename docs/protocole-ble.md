# Protocole entre l'application et le bijou

Ce document décrit le dialogue entre l'application mobile et le firmware du
bijou. Les deux côtés doivent rester d'accord avec lui :

- application : `app/lib/jewel/protocol.dart` et `app/lib/jewel/ble_jewel.dart` ;
- firmware : `firmware/src/link.c` et `firmware/src/config_json.c`.

## Chemin des messages sur le Thingy:91 X

Le Thingy:91 X contient deux puces. Le nRF9151 (réseau mobile, GPS) exécute le
firmware Hestia mais ne fait pas de Bluetooth. Le Bluetooth est assuré par le
nRF5340, qui garde son firmware d'origine (« connectivity bridge ») : celui-ci
relaie tel quel tout ce qui passe entre le Bluetooth et la liaison série UART0
du nRF9151.

```
Application  ⇄  Bluetooth (service Nordic UART)  ⇄  nRF5340  ⇄  UART0  ⇄  nRF9151 (Hestia)
```

Le relais Bluetooth est désactivé à la sortie d'usine : il faut l'activer une
fois (voir le README).

La même liaison série est aussi visible sur le premier port série USB du
Thingy:91 X (115 200 bauds) : on peut y taper les requêtes ci-dessous à la main
pour essayer le firmware sans téléphone.

## Service GATT

C'est le service « Nordic UART » (NUS), annoncé par le nRF5340.

| Rôle | UUID | Propriétés |
|---|---|---|
| Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | |
| RX (application → bijou) | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` | write |
| TX (bijou → application) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` | notify |

La liaison n'est ni chiffrée ni authentifiée : toute personne à portée
Bluetooth peut lire et modifier les réglages. Acceptable pour un prototype, à
traiter avant tout usage réel.

## Messages

Chaque message est un objet JSON en UTF-8 terminé par un saut de ligne (`\n`).
Un message peut arriver en plusieurs morceaux : le destinataire accumule les
octets jusqu'au `\n`. Les lignes qui ne sont pas un message valide sont
ignorées des deux côtés.

L'application envoie des requêtes numérotées ; le bijou répond avec le même
`id`.

```
→ {"id":1,"cmd":"get_status"}
← {"id":1,"ok":true,"status":{"battery":82,"lte":"connected"}}
```

En cas d'échec : `{"id":1,"ok":false,"error":"<code>"}`.

| Commande | Arguments | Réponse | Délai max. |
|---|---|---|---|
| `get_status` | – | `status` : `battery` (0–100, absent si inconnu), `lte` (`connected`, `searching` ou `off`) | 10 s |
| `get_config` | – | `config` (voir ci-dessous) | 10 s |
| `set_config` | `config` | – | 10 s |
| `test_alert` | – | `ok` dès que l'alerte de test est partie par au moins une voie (nRF Cloud ou SMS) | 180 s |

Une seule requête est traitée à la fois : l'application attend la réponse
avant d'envoyer la suivante.

### Codes d'erreur

| Code | Signification |
|---|---|
| `no_network` | Pas de réseau mobile. |
| `no_contact` | Aucun contact enregistré dans le bijou. |
| `send_failed` | L'alerte n'est partie ni vers nRF Cloud ni par SMS. |
| `busy` | Une alerte est déjà en cours. |
| `bad_config` | Réglages mal formés ou numéro de téléphone invalide. |
| `storage` | Enregistrement en mémoire impossible. |
| `unknown_cmd` | Commande inconnue. |

L'application affiche un message précis pour les quatre premiers et un message
générique pour les autres.

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
- Les numéros sont au format international, sans séparateurs : `+` suivi de 8
  à 15 chiffres. L'application convertit les numéros nationaux d'après le pays
  du téléphone (FR, BE, CH, LU) ; le bijou refuse tout autre format, car le
  modem ne sait envoyer un SMS qu'à un numéro international.
- `set_config` remplace tous les réglages. Le bijou les conserve en mémoire
  flash. Les textes trop longs sont tronqués.

## Alerte de test

`test_alert` suit le même chemin qu'une vraie alerte (localisation rapide,
message à nRF Cloud, puis SMS à tous les contacts), avec trois différences : le
message nRF Cloud porte le type `test`, le SMS commence par
`[TEST - pas d'urgence]`, et le bijou ne tente pas le GPS ensuite.

Le bijou attend le réseau mobile jusqu'à 2 minutes avant de répondre
`no_network` : après un allumage, il lui faut couramment plus d'une minute pour
le trouver.
