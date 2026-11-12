# Firmware du bijou (Thingy:91 X)

Firmware du nRF9151 du Thingy:91 X, pour le nRF Connect SDK **v3.4.1**.

Un appui maintenu sur le bouton localise le bijou et envoie un SMS avec un lien
vers la carte à chaque contact d'urgence. Les contacts, le nom et le message
viennent de l'application mobile, par Bluetooth.

## Ce que fait le bijou

### Alerte

1. Maintenir le bouton 1,5 seconde (le voyant passe au bleu fixe dès l'appui,
   puis au rouge clignotant quand l'alerte part).
2. Le bijou cherche sa position par Wi-Fi et antennes mobiles (30 secondes au
   plus). Il n'attend pas le GPS, pour ne pas retarder l'alerte.
3. Il envoie le SMS à tous les contacts, avec la position et sa marge d'erreur,
   ou « Position inconnue pour le moment ».
4. Si la position est absente ou vague (plus de 100 m), il essaie ensuite le
   GPS pendant 2 minutes et envoie un second SMS s'il obtient mieux.

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
convertit en coordonnées et les renvoie au bijou. Le Thingy doit donc être
enregistré sur votre compte nRF Cloud (c'est déjà le cas s'il y apparaissait
avec le firmware d'origine : les identifiants restent dans le modem). Le bijou
ne se connecte jamais à un réseau Wi-Fi, il ne fait que les écouter.

## Mise en route

### 1. Activer le Bluetooth du Thingy:91 X (une seule fois)

Le Bluetooth est assuré par la seconde puce du Thingy (nRF5340), qui garde son
firmware d'origine. Il est désactivé à la sortie d'usine.

1. Brancher le Thingy:91 X en USB : un lecteur apparaît sur l'ordinateur.
2. Ouvrir le fichier `Config.txt` de ce lecteur et mettre `BLE_ENABLED=1`.
3. Enregistrer, éjecter le lecteur, puis éteindre et rallumer le Thingy.

### 2. Compiler

Depuis un terminal du nRF Connect SDK v3.4.1 (ou avec l'extension nRF Connect
de VS Code, en choisissant la carte `thingy91x/nrf9151/ns`) :

```bash
west build -p -b thingy91x/nrf9151/ns firmware
```

### 3. Flasher par USB

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
firmware/tests/run.sh ~/ncs/v3.4.1
```

## Organisation du code

| Fichier | Rôle |
|---|---|
| `src/main.c` | Démarrage. |
| `src/ui.c` | Bouton et voyant. |
| `src/alert.c` | Déroulement d'une alerte : localisation puis SMS. |
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
- **SMS envoyés par le modem** : il faut une carte SIM qui autorise les SMS sur
  le réseau LTE-M. L'envoi est isolé dans `send_to_all()` (`src/alert.c`) pour
  pouvoir le remplacer par un appel à un serveur.
- **Caractères des SMS** : alphabet latin uniquement ; les émojis et autres
  alphabets deviennent « ? ».
