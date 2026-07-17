# SwitchMoney

Application mobile Flutter de transfert d'argent inter-opérateurs (mobile money)
pour l'Afrique de l'Ouest et Centrale, adossée à l'**API PawaPay sandbox v2**.

Un transfert = un **dépôt** chez l'expéditeur (ex: MTN Bénin) suivi d'un
**payout** vers le destinataire (ex: Moov Bénin), avec frais prélevés
automatiquement selon une grille tarifaire.

## Architecture

```
┌────────────────────┐        ┌──────────────────────────────┐
│  App Flutter       │  HTTP  │  Backend Express (port 3002) │
│  (Android/iOS)     │───────▶│  backend/server.js           │
│  - Auth (PIN)      │  JWT   │  - /api/auth/* (comptes)     │
│  - Transfert 5 ét. │        │  - /api/transfer             │
│  - Historique      │        │  - /api/transfer-status/:id  │
└────────────────────┘        │  - /api/history (par user)   │
                              │  - SQLite: switchmoney.db    │
                              └────────┬─────────────┬───────┘
                                       │             │
                     ┌─────────────────▼──┐   ┌──────▼────────────────┐
                     │ PawaPay sandbox v2 │   │ Lookup service (3003) │
                     │ deposits / payouts │   │ recipients.db (noms   │
                     │ predict-provider   │   │ des bénéficiaires)    │
                     └────────────────────┘   └───────────────────────┘
```

## Démarrage rapide (sandbox)

### 1. Backend

```bash
cd backend
npm install          # première fois seulement
npm start            # backend principal sur http://localhost:3002
npm run start:lookup # (autre terminal) service lookup sur http://localhost:3003
```

Ou double-cliquez `start_services.bat` (Windows) qui lance les deux.

> Le fichier `backend/.env` est déjà configuré avec un jeton sandbox PawaPay.
> Pour repartir de zéro : copiez `backend/.env.example` vers `backend/.env`
> et renseignez `PAWA_TOKEN` (dashboard PawaPay sandbox) et `AUTH_SECRET`.
>
> ⚠️ Ports : 3000 et 3001 sont utilisés par un autre projet local (PolyFact) ;
> SwitchMoney utilise donc **3002** (backend) et **3003** (lookup).

### 2. App Flutter

```bash
flutter pub get
flutter run                          # émulateur Android : fonctionne tel quel
```

**Sur téléphone physique** (même Wi-Fi que le PC) :

1. Installez l'APK (`flutter build apk --release`, fichier dans
   `build/app/outputs/flutter-apk/app-release.apk`) ou `flutter run` avec le
   téléphone branché.
2. Sur l'écran de connexion, touchez **« Serveur backend »** (en bas) et
   saisissez l'adresse du PC, ex : `http://192.168.51.24:3002`
   (retrouvez votre IP avec `ipconfig`, champ « Adresse IPv4 » du Wi-Fi).
3. « Enregistrer et tester » doit afficher ✅.
4. Le pare-feu Windows doit autoriser Node.js sur le réseau privé
   (une popup s'affiche au premier lancement du backend — cliquez Autoriser).

Vous pouvez aussi figer l'URL à la compilation :
`flutter run --dart-define=BACKEND_BASE=http://192.168.51.24:3002`

### 3. Parcours de test

1. **Créer un compte** (nom + numéro avec indicatif + PIN 4-8 chiffres).
2. Onglet **Transfert** : choisir opérateurs source/destination (roues).
3. Saisir les numéros. Pour le destinataire, essayez `0151469075`
   (MTN BJ) : le nom **« MENSAH Elie Exaucé »** s'affiche via le lookup
   et le badge « Nom vérifié » apparaît à la confirmation.
4. Saisir le montant (frais et net affichés), confirmer.
5. L'écran de résultat passe de « Operation en cours » à
   « Operation validee » dès que PawaPay sandbox confirme (quelques secondes).
6. Onglet **Historique** : la transaction apparaît avec son statut réel
   (filtres Tout / Valide / En cours / Échec).

### Tests automatisés

```bash
cd backend && npm test    # tests unitaires backend (node --test)
flutter test              # tests Flutter (validation numéros + widgets)
flutter analyze           # analyse statique
```

## Configuration backend (`backend/.env`)

| Variable | Rôle |
|---|---|
| `PAWA_TOKEN` | Jeton API PawaPay (**obligatoire**, le serveur refuse de démarrer sans) |
| `PAWA_BASE` | `https://api.sandbox.pawapay.io/v2` (sandbox) |
| `PORT` | Port du backend (défaut 3002) |
| `AUTH_SECRET` | Secret de signature des jetons de session (**à changer en production**) |
| `FEE_RECIPIENT` | MSISDN qui reçoit les frais prélevés (défaut : numéro du développeur) |
| `PAWAPAY_RECEIVER` | Optionnel : second payout (part PawaPay), montant = frais |
| `PAWAPAY_PROVIDER` | Optionnel : provider du payout PawaPay |
| `RECIPIENT_LOOKUP_URL` | URL du service lookup (défaut `http://localhost:3003/lookup`) |
| `ENABLE_SIMULATE` | `true` pour activer `/api/simulate-callback` (sandbox uniquement) |
| `VERIFY_CALLBACK_SIGNATURE` | `true` pour exiger la signature HMAC sur `/pawapay/callback` |
| `CALLBACK_URL` / `CALLBACK_SECRET` | Callback public (ngrok) — optionnel, le polling serveur suffit en local |

## Fonctionnement du suivi de statut

Les callbacks PawaPay ne peuvent pas joindre une machine locale sans tunnel
public. Le backend fait donc du **polling actif** : après chaque dépôt il
interroge PawaPay toutes les 4 s (max ~100 s) et déclenche les payouts dès
que le dépôt passe à `COMPLETED`. L'app interroge de son côté
`GET /api/transfer-status/:id` pour mettre à jour l'écran de résultat et
l'historique. Le callback `/pawapay/callback` reste fonctionnel si vous
configurez ngrok (`CALLBACK_URL`).

## API du backend (résumé)

| Méthode | Route | Auth | Rôle |
|---|---|---|---|
| POST | `/api/auth/register` | — | Créer un compte (name, phone, pin) → jeton |
| POST | `/api/auth/login` | — | Connexion (phone, pin) → jeton |
| GET | `/api/auth/me` | ✅ | Profil courant |
| PUT | `/api/auth/profile` | ✅ | Modifier nom / e-mail |
| PUT | `/api/auth/pin` | ✅ | Changer de PIN |
| POST | `/api/transfer` | ✅ | Dépôt + payouts automatiques (transfert complet) |
| GET | `/api/transfer-status/:id` | ✅ | Statut consolidé d'un transfert (polling client) |
| GET | `/api/history` | ✅ | Historique des transferts de l'utilisateur |
| GET | `/api/tx/:id` | ✅ | Détail brut d'une transaction (debug) |
| POST | `/api/predict-provider` | — | Prédiction opérateur d'un numéro (PawaPay) |
| POST | `/api/resolve-recipient` | — | Nom du bénéficiaire (service lookup) |
| POST | `/pawapay/callback` | HMAC opt. | Callback PawaPay |
| GET | `/api/test-pawapay` | — | Sanity-check connexion PawaPay |

Voir aussi : [AUDIT.md](AUDIT.md) (état des lieux complet, sécurité, limites
connues), [QUICKSTART.md](QUICKSTART.md) (service lookup),
[RECIPIENT_LOOKUP_API_SPEC.md](RECIPIENT_LOOKUP_API_SPEC.md).

## Déploiement du backend sur Render (accès depuis n'importe quel réseau)

Le service de lookup est fusionné dans `server.js` (voir
`backend/recipient_lookup.js`) : un seul service à déployer.

1. **Poussez le repo sur GitHub** (déjà fait si vous avez cloné depuis
   `Msh-Elie/my_app`). `backend/.env` et `backend/node_modules/` sont
   volontairement exclus du dépôt (voir `.gitignore`) — Render installe les
   dépendances lui-même et les secrets se configurent dans son dashboard.
2. Sur [render.com](https://render.com), **New → Blueprint**, connectez le
   repo GitHub : `render.yaml` (à la racine) préconfigure le service
   (`switchmoney-backend`, dossier `backend/`, `npm install` puis
   `node server.js`, health check `/healthz`).
3. Render vous demandera de saisir les variables marquées `sync: false` :
   copiez-les depuis votre `backend/.env` local — au minimum `PAWA_TOKEN`,
   `AUTH_SECRET`, `CALLBACK_SECRET`, `FEE_RECIPIENT`.
4. Déployez. Render fournit une URL publique du type
   `https://switchmoney-backend.onrender.com` — copiez-la.
5. Dans l'app, ouvrez **Paramètres → Serveur backend** (ou l'écran de
   connexion) et collez cette URL. Testez : « Enregistrer et tester ».

**Plan gratuit — ce qu'il faut savoir** : le service se met en veille après
15 min d'inactivité ; le réveil sur la requête suivante prend jusqu'à ~50s
(l'app a des délais adaptés à ça et affiche un message si c'est long), et
**sans disque payant, les comptes/l'historique repartent à zéro à chaque
réveil** (la base SQLite vit sur un disque éphémère). Pour un service
toujours actif et des données persistantes : plan payant *Starter* (~7$/mois)
+ un [disque persistant Render](https://render.com/docs/disks) (~1-2$/mois),
puis pointez `SWITCHMONEY_DB` et `RECIPIENTS_DB` vers le point de montage du
disque (ex: `/var/data/switchmoney.db`) dans les variables d'environnement.
