# Serveur d'alertes

Petit serveur (un Worker Cloudflare) qui transforme les alertes du bijou en
SMS :

```
Bijou → nRF Cloud → ce serveur → Twilio → SMS aux contacts
```

nRF Cloud lui pousse chaque message du bijou. Pour une alerte `HESTIA_ALERT`,
il envoie à chaque contact le message, un lien vers la carte et la marge
d'erreur. Il ne stocke rien : les numéros des contacts arrivent dans l'alerte.

## Mise en service

Il faut [Node.js](https://nodejs.org) 20 ou plus récent. Toutes les commandes
se lancent depuis le dossier `server/`.

### 1. Déployer le serveur

```bash
npm install
```

```bash
npx wrangler login
```

```bash
npx wrangler deploy
```

La dernière commande affiche l'adresse du serveur, de la forme
`https://hestia-alertes.<votre-compte>.workers.dev`. Notez-la.

### 2. Préparer Twilio

Dans la console Twilio :

1. Obtenir un numéro de téléphone capable d'envoyer des SMS (le compte d'essai
   en offre un).
2. Avec un compte d'essai, ajouter chaque numéro destinataire dans
   « Verified Caller IDs » : Twilio refuse les autres.
3. Dans « Messaging » → « Settings » → « Geo permissions », autoriser les pays
   des destinataires (Belgique, France…).
4. Relever l'« Account SID » et l'« Auth Token » sur la page d'accueil.

### 3. Choisir deux mots de passe pour nRF Cloud

Ils prouvent au serveur qu'une requête vient bien de nRF Cloud. Générez-en
deux et gardez-les sous la main pour les étapes 4 et 6 :

```bash
openssl rand -hex 24
```

```bash
openssl rand -hex 32
```

Le premier sera le **jeton**, le second le **secret**.

### 4. Enregistrer les réglages sur le serveur

Chaque commande demande la valeur, qui n'apparaît nulle part dans le dépôt :

```bash
npx wrangler secret put TWILIO_ACCOUNT_SID
```

```bash
npx wrangler secret put TWILIO_AUTH_TOKEN
```

```bash
npx wrangler secret put TWILIO_FROM
```

```bash
npx wrangler secret put NRFCLOUD_WEBHOOK_TOKEN
```

```bash
npx wrangler secret put NRFCLOUD_WEBHOOK_SECRET
```

| Réglage | Valeur |
|---|---|
| `TWILIO_ACCOUNT_SID` | « Account SID » de Twilio (commence par `AC`). |
| `TWILIO_AUTH_TOKEN` | « Auth Token » de Twilio. |
| `TWILIO_FROM` | Le numéro Twilio expéditeur, au format `+1…`, ou l'identifiant d'un « Messaging Service » (commence par `MG`). |
| `NRFCLOUD_WEBHOOK_TOKEN` | Le jeton de l'étape 3. |
| `NRFCLOUD_WEBHOOK_SECRET` | Le secret de l'étape 3. |

### 5. Essayer sans le bijou

Ce script envoie au serveur une fausse alerte de test, comme le ferait
nRF Cloud. Remplacez l'adresse et le numéro (un numéro vérifié chez Twilio) :

```bash
scripts/essai.sh https://hestia-alertes.<votre-compte>.workers.dev +32470123456
```

Il demande le jeton puis le secret de l'étape 3 ; ce que vous collez ne
s'affiche pas. Pour ne pas avoir à les ressaisir, vous pouvez les écrire dans
un fichier `server/.env`, qui n'est jamais envoyé dans le dépôt :

```
NRFCLOUD_WEBHOOK_TOKEN=<jeton>
NRFCLOUD_WEBHOOK_SECRET=<secret>
```

Résultat attendu :
`{"alertes":1,"sms_envoyes":1,"notifications_envoyees":0,"envois_echoues":0}`,
et le SMS arrive. En cas d'échec, les journaux (voir plus bas) donnent la raison fournie
par Twilio.

### 6. Demander à nRF Cloud de pousser les messages

Il faut créer une « destination » du service de routage des messages
(Message Routing Service) de nRF Cloud, avec :

- l'adresse du serveur (étape 1) ;
- le jeton et le secret (étape 3).

Dans le portail nRF Cloud, cela se trouve dans la rubrique « Message Routing ».
On peut aussi le faire par l'API, avec un jeton d'organisation
(« Organization Auth Token ») et les noms de l'organisation et du projet tels
qu'ils apparaissent dans l'adresse du portail :

```bash
curl -X POST "https://api.nrfcloud.com/v1/organizations/<organisation>/projects/<projet>/destinations" \
  -H "Authorization: Bearer <jeton d'organisation>" \
  -H "content-type: application/json" \
  --data '{"name":"hestia-alertes","isEnabled":true,"config":{"type":"http","url":"https://hestia-alertes.<votre-compte>.workers.dev","verifySsl":true,"token":"<jeton>","secret":"<secret>"},"filter":{"categories":["device_messages"]}}'
```

nRF Cloud vérifie aussitôt la destination ; le serveur répond tout seul à
cette vérification. Si nRF Cloud réclame malgré tout un code à 6 chiffres, il
figure dans les journaux du serveur (« Vérification nRF Cloud reçue »).

### 7. Essayer avec le bijou

Flasher le firmware à jour (il ajoute les numéros des contacts à l'alerte),
puis lancer une alerte de test depuis l'application ou le port série. Le SMS
doit arriver quelques secondes après « Alerte reçue par nRF Cloud ».

## Essayer sans fournisseur de SMS : notifications ntfy

Tant que Twilio n'est pas prêt (vérification du compte, achat d'un numéro), le
serveur peut envoyer l'alerte en notification sur un téléphone, par le service
gratuit [ntfy](https://ntfy.sh), sans compte ni vérification. Les deux voies
peuvent fonctionner en même temps.

1. Installer l'application **ntfy** sur le téléphone (App Store ou Google Play).
2. Choisir un nom de « sujet » difficile à deviner, par exemple
   `hestia-` suivi du résultat de :

   ```bash
   openssl rand -hex 8
   ```

   Toute personne qui connaît ce nom peut lire les alertes : il joue le rôle
   de mot de passe.
3. Dans l'application : « + » → saisir ce nom de sujet → s'abonner.
4. L'enregistrer sur le serveur :

   ```bash
   npx wrangler secret put NTFY_TOPIC
   ```

5. Relancer `scripts/essai.sh` : la notification arrive sur le téléphone, et
   la toucher ouvre la carte.

Ce n'est pas un remplacement des SMS : seuls les téléphones abonnés au sujet
sont prévenus, pas les contacts choisis dans l'application. Pour arrêter,
supprimer le réglage avec `npx wrangler secret delete NTFY_TOPIC`.

## Journaux

En direct, pendant un essai :

```bash
npx wrangler tail
```

Ils sont aussi conservés dans le tableau de bord Cloudflare (Workers →
`hestia-alertes` → Logs). Les numéros de téléphone y sont masqués.

## Tests

```bash
npm test
```

## Comportement à connaître

- **Authentification** : le serveur refuse toute requête sans le bon jeton
  (`x-api-key`) et, si un secret est configuré, sans la bonne signature
  (`x-nrfcloud-signature`). Il refuse tout s'il lui manque le jeton, ou s'il
  n'a ni les trois réglages Twilio ni un sujet ntfy.
- **Nouvelle livraison** : si rien ne part (ni SMS ni notification), le serveur répond en erreur et
  nRF Cloud relivre l'alerte plus tard. Après un envoi partiel, il ne demande
  pas de nouvelle livraison, pour ne pas envoyer l'alerte en double à ceux qui
  l'ont reçue.
- **Double SMS possible** : le bijou tente toujours ses propres SMS. Le jour où
  sa carte SIM les achemine, les contacts recevront l'alerte deux fois (bijou
  et serveur) ; il faudra alors désactiver l'une des deux voies.
- **Compte d'essai Twilio** : envoi limité aux numéros vérifiés, avec une
  mention d'essai en tête du SMS.
