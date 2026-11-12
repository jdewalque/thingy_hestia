# Firmware du bijou (Thingy:91 X)

Firmware du nRF9151 du Thingy:91 X, pour le nRF Connect SDK **v3.4.x** (compilé
avec les versions 3.4.1 et 3.4.2).

Un appui maintenu sur le bouton localise le bijou, puis envoie l'alerte à
nRF Cloud et, par SMS, à chaque contact d'urgence. Les contacts, le nom et le
message viennent de l'application mobile, par Bluetooth.

## Ce que fait le bijou

### Alerte

1. Maintenir le bouton 1,5 seconde (le voyant passe au bleu fixe dès l'appui,
   puis au rouge clignotant quand l'alerte part).
2. Le bijou cherche sa position par Wi-Fi et antennes mobiles (30 secondes au
   plus). Le GPS n'est pas utilisé.
3. Il envoie l'alerte par deux voies :
   - **nRF Cloud** d'abord (voir « Message envoyé à nRF Cloud ») ;
   - **SMS direct** à chaque contact ensuite, avec la position et sa marge
     d'erreur, ou « Position inconnue pour le moment ».

   L'alerte est réussie dès qu'une des deux voies fonctionne. Le voyant passe
   au vert dès que nRF Cloud a reçu l'alerte, sans attendre les SMS.
Si le réseau n'achemine pas les SMS (le modem répond `+CMS ERROR: 332` après
une trentaine de secondes), le bijou n'essaie pas les contacts suivants. C'est
le cas observé en NB-IoT chez Proximus.

### Message envoyé à nRF Cloud

Un message d'appareil au format JSON, avec l'identifiant `HESTIA_ALERT` :

```json
{
  "appId": "HESTIA_ALERT",
  "messageType": "DATA",
  "ts": 1700000000000,
  "data": {
    "type": "real",
    "name": "Marie Dupont",
    "message": "Marie Dupont a appuyé sur son bouton d'urgence et a besoin d'aide.",
    "battery": 82,
    "contacts": ["+32470123456"],
    "position": {"lat": 50.84673, "lon": 4.35247, "accuracy": 21}
  }
}
```

- `type` : `real` (bouton) ou `test` (essai depuis l'application).
- `position` est absent si le bijou n'a pas pu se localiser ; `accuracy` est la
  marge d'erreur en mètres.
- `battery` (en %) et `ts` (millisecondes depuis 1970) sont absents s'ils sont
  inconnus.
- `contacts` : les numéros des contacts d'urgence, sans leurs noms. Le
  serveur d'alertes (`server/`) s'en sert pour envoyer les SMS.

nRF Cloud pousse ce message au serveur d'alertes, qui envoie les SMS : voir
`server/README.md`.

### Voyant

| Voyant | Signification |
|---|---|
| Éteint | Tout va bien, bijou prêt. |
| Bleu, bref éclat toutes les 2 s | Recherche du réseau mobile. |
| Vert fixe 5 s | Réseau trouvé, ou alerte envoyée. |
| Bleu fixe | Bouton enfoncé. |
| Rouge clignotant | Alerte en cours d'envoi. |
| Rouge fixe 5 s | L'alerte n'a pas pu partir. |

### Localisation

Le Wi-Fi ne donne qu'une liste de bornes visibles ; c'est nRF Cloud qui la
convertit en coordonnées et les renvoie au bijou. Le bijou ne se connecte
jamais à un réseau Wi-Fi, il ne fait que les écouter.

Le Thingy doit être rattaché à votre compte nRF Cloud. Sinon, la connexion
échoue avec `nrf_cloud_coap_connect` → -111 dans les journaux. Pour le
rattacher : remettre le firmware d'origine avec l'application Quick Start de
nRF Connect for Desktop, y lire le jeton d'attestation, l'utiliser pour ajouter
l'appareil au compte, puis reflasher Hestia. Les identifiants restent dans le
modem.

## Mise en route

### 1. Activer le Bluetooth du Thingy:91 X (une seule fois)

Le Bluetooth est assuré par la seconde puce du Thingy (nRF5340), qui garde son
firmware d'origine. Il est désactivé à la sortie d'usine.

1. Brancher le Thingy:91 X en USB : un lecteur apparaît sur l'ordinateur.
2. Ouvrir le fichier `Config.txt` de ce lecteur et mettre `BLE_ENABLED=1`.
3. Enregistrer, éjecter le lecteur, puis éteindre et rallumer le Thingy.

### 2. Compiler

Depuis un terminal du nRF Connect SDK (ou avec l'extension nRF Connect de
VS Code) :

```bash
west build -p -b thingy91x/nrf9151/ns firmware
```

La carte doit être `thingy91x/nrf9151/ns`. VS Code propose parfois
`nrf9151dk/nrf9151/ns` : la compilation échoue alors sur `npm1300_charger`.

### 3. Flasher par USB

Avec l'application Programmer de nRF Connect for Desktop : allumer le Thingy en
maintenant son bouton (mode MCUboot), puis écrire `build/dfu_application.zip`.
Ou en ligne de commande :

```bash
west thingy91x-dfu
```

```bash
west thingy91x-reset
```

Avec une sonde de débogage branchée sur le Thingy (interrupteur SWD sur
« nRF91 »), `west flash` fonctionne aussi.

### 4. Vérifier

- **Journaux** : second port série USB du Thingy, à 1 000 000 bauds.
- **Dialogue avec l'application** : premier port série USB, à 115 200 bauds.
  On peut y taper une requête à la main, suivie d'Entrée :

  ```
  {"id":1,"cmd":"get_status"}
  ```

  Le bijou répond par exemple
  `{"id":1,"ok":true,"status":{"battery":82,"lte":"connected"}}`.
  Toutes les commandes sont décrites dans `docs/protocole-ble.md`.

## Tests

La logique indépendante du matériel (lecture des réglages, rédaction des SMS)
se teste sur PC :

```bash
firmware/tests/run.sh ~/ncs/v3.4.2
```

## Organisation du code

| Fichier | Rôle |
|---|---|
| `src/main.c` | Démarrage. |
| `src/ui.c` | Bouton et voyant. |
| `src/alert.c` | Déroulement d'une alerte : localisation, nRF Cloud, SMS. |
| `src/alert_json.c` | Message d'alerte envoyé à nRF Cloud. |
| `src/net.c` | Réseau mobile et session nRF Cloud. |
| `src/link.c` | Dialogue avec l'application (lignes JSON sur UART0). |
| `src/config.c`, `src/config_json.c` | Réglages : stockage en flash et JSON. |
| `src/text.c` | Rédaction des SMS, conversion des caractères. |
| `src/battery.c` | Niveau de batterie. |

## Limites connues du prototype

- **Bluetooth non sécurisé** : toute personne à portée peut lire et modifier
  les réglages.
- **Batterie estimée** d'après la tension : approximative, surtout pendant la
  charge ou quand le modem émet.
- **Consommation non optimisée** : la liaison série avec le nRF5340 reste
  active en permanence.
- **Les numéros des contacts transitent par nRF Cloud**, dans chaque alerte.
- **SMS directs** : ils demandent une carte SIM et un réseau qui acheminent les
  SMS. Avec la SIM Proximus essayée, le bijou n'est accepté qu'en NB-IoT, où
  les SMS ne passent pas.
- **Caractères des SMS** : alphabet latin uniquement ; les émojis et autres
  alphabets deviennent « ? ».
