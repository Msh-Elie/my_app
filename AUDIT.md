# Audit SwitchMoney — 08/07/2026

État des lieux du projet après finalisation. Trois sections :
ce qui a été **corrigé/ajouté**, ce qui reste **acceptable en sandbox mais à
traiter avant production**, et les **limites connues**.

## 1. Problèmes trouvés et corrigés

### Sécurité

| Problème | Gravité | Correction |
|---|---|---|
| Jeton PawaPay **codé en dur** dans `server.js` (visible dans git) | Critique | Retiré du code ; le serveur exige `PAWA_TOKEN` dans `.env` et refuse de démarrer sans. |
| Aucune authentification : n'importe qui joignant le serveur pouvait initier dépôts/payouts avec le compte PawaPay du projet | Critique | Auth complète : comptes (PIN haché **scrypt + sel**), jetons JWT signés HMAC-SHA256, middleware `requireAuth` sur toutes les routes qui bougent de l'argent. |
| `/api/simulate-callback` ouvert : quiconque pouvait forcer une transaction en `COMPLETED` et déclencher de vrais payouts | Haute | Désactivé par défaut, activable via `ENABLE_SIMULATE=true` (sandbox). |
| Signature HMAC des callbacks définie mais **jamais vérifiée** | Haute | Vérification opt-in (`VERIFY_CALLBACK_SIGNATURE=true`). Voir §2. |
| `verifySignature` : `crypto.timingSafeEqual` levait une exception si les longueurs différaient (crash possible du handler) | Moyenne | Comparaison de longueur préalable. |
| Historique global : tous les clients voyaient toutes les transactions | Haute | `/api/history`, `/api/tx/:id`, `/api/transfer-status/:id` filtrés par utilisateur connecté. |

### Fonctionnalités manquantes ou cassées

| Problème | Correction |
|---|---|
| Page Connexion vide, Profil « Jean Dupont » en dur, aucune session | Écrans connexion + inscription, garde d'authentification au démarrage, profil réel éditable (nom/e-mail), déconnexion avec confirmation. |
| Lookup du bénéficiaire jamais déclenché (`_scheduleRecipientLookup` non branché) — le badge « Nom vérifié » ne pouvait jamais apparaître | Branché sur la saisie du numéro de réception (debounce 500 ms) ; nom affiché sous le champ et dans la confirmation. |
| Statut de transfert **menti** : « validé » affiché dès que le backend acceptait la requête HTTP, sans attendre PawaPay | Statut réel (`ACCEPTED` → « en cours ») + double polling : le backend interroge PawaPay jusqu'au statut final et déclenche alors les payouts ; l'app interroge `/api/transfer-status/:id` et met à jour l'écran de résultat + l'historique. |
| Payouts dépendants d'un callback public (ngrok) impossible en local | Polling serveur : les payouts partent dès que le dépôt est `COMPLETED`, sans tunnel. Callback conservé en complément. |
| Transactions **en mémoire** (Map) : tout était perdu au redémarrage du serveur | Persistance SQLite (`backend/switchmoney.db`, WAL) via `db.js` — même interface, zéro perte. |
| Historique : fausses transactions de démo (USDT/DERIV) affichées quand le backend était injoignable | Supprimées ; fallback = historique local du téléphone, sinon état vide. |
| Échecs affichés comme « En cours » dans l'historique | Statut « Échec » distinct (rouge) + filtre dédié ; propagé du backend (`FAILED/REJECTED/CANCELLED`) jusqu'à l'UI. |
| URL backend figée sur une URL ngrok morte | URL configurable dans l'app (écran de connexion et Paramètres → « Serveur backend », avec test de connexion), surchargée par `--dart-define=BACKEND_BASE`. Défaut : `http://10.0.2.2:3002` (émulateur). |
| Paramètres factices (notifications, biométrie, langue non persistés ; « Sauvegarder mes données » sans effet) | Préférences persistées localement ; entrée morte supprimée ; lien réel vers l'aide ; ajout de la config serveur. Le commutateur de thème (sans effet réel, l'UI étant conçue sombre) a été retiré. |
| `/api/test-pawapay` testait `GET /health`, endpoint inexistant chez PawaPay (renvoyait toujours `connected: false`) | Teste `GET /active-conf` → `connected: true` vérifié en sandbox. |
| Conflit de ports avec un autre projet local (PolyFact occupe 3000/3001 sur cette machine) | Backend → **3002**, lookup → **3003** ; le service lookup charge désormais `.env` (il ignorait `RECIPIENT_LOOKUP_PORT`). |
| `better-sqlite3` compilé pour une ancienne version de Node (crash au démarrage) | `npm rebuild better-sqlite3` (Node 24). |
| `pubspec.yaml` tronqué (dépendances effacées) découvert en cours de session | Restauré intégralement. |

### Tests (avant : 1 test widget ; après : 28 tests, tous verts)

- **Backend** (`npm test`, 9 tests) : grille de frais, mapping providers,
  sanitisation metadata, normalisation de statuts, robustesse HMAC,
  persistance SQLite (aller-retour + filtrage par utilisateur).
- **Auth** : aller-retour de jeton, rejet des jetons falsifiés/expirés/malformés.
- **Flutter** (`flutter test`, 19 tests) : validations de numéros existantes +
  écran de connexion sans session, ouverture directe du flux avec session,
  rendu des roues d'opérateurs. `flutter analyze` : 0 problème.

### Vérification bout-en-bout effectuée (sandbox réel)

Inscription → connexion → lookup bénéficiaire (nom résolu depuis la base) →
predict-provider PawaPay (`MTN_MOMO_BEN`, match) → transfert 1 500 XOF
MTN BJ → MOOV BJ : dépôt `ACCEPTED` puis `COMPLETED` en ~4 s, **2 payouts
créés automatiquement** (1 400 XOF au destinataire + 100 XOF de frais au
`FEE_RECIPIENT`), historique par utilisateur correct. APK release compilé.

## 2. À traiter avant toute mise en production

1. **`backend/.env` est versionné avec un jeton sandbox.** Acceptable en
   sandbox, mais ajoutez `backend/.env` au `.gitignore` et révoquez/régénérez
   le jeton avant tout passage en production ou tout dépôt public.
2. **HTTPS obligatoire.** Aujourd'hui tout passe en HTTP local (le PIN et le
   jeton transitent en clair sur le Wi-Fi). Derrière un vrai domaine : TLS
   terminé par un reverse proxy (Caddy/Nginx) ou un PaaS.
3. **Vérification des callbacks.** PawaPay signe ses callbacks en production ;
   implémentez la vérification selon leur schéma réel (clé publique) plutôt
   que le HMAC partagé actuel, puis activez-la.
4. **Limitation de débit** sur `/api/auth/login` (anti force-brute du PIN) et
   verrouillage après N échecs.
5. **`node_modules` est versionné** dans git (‑50 000 fichiers) : ajoutez-le au
   `.gitignore`, le `package-lock.json` suffit.
6. **Réconciliation des payouts** : si un payout échoue après un dépôt réussi,
   il n'y a pas de reprise automatique (l'état est en base, mais aucun retry).
   Prévoir une tâche de reprise + alerte.
7. **Idempotence côté app** : le `depositId` est généré par l'app à chaque
   tentative d'envoi ; en cas de retry après timeout le même id est réutilisé
   (bien), mais un double-tap sur « Confirmer » régénère un id (risque de
   double dépôt). Débounce du bouton conseillé.
8. La grille de frais est dupliquée entre l'app (affichage) et le serveur
   (référence). Le serveur fait foi ; exposer un endpoint `/api/fees` serait
   plus propre.

## 3. Limites connues (choix assumés en sandbox)

- **Devise unique par transfert** : les payouts sont émis en XOF dans
  `createPayoutForTransfer` ; les transferts transfrontaliers avec conversion
  (ex. GHS → XOF) ne sont pas gérés (pas de taux de change).
- Le **service lookup** est une base de démonstration (24 bénéficiaires
  fictifs, dont `2290151469075` → « MENSAH Elie Exaucé ») ; en production il
  serait remplacé par les API KYC des opérateurs.
- **Thème sombre uniquement** : l'UI est conçue en dark ; le sélecteur de
  thème a été retiré plutôt que de livrer un mode clair à moitié stylé.
- La **langue** (Français/Anglais) est persistée mais l'app n'est pas
  internationalisée (textes en français).
- Le **toggle biométrie** est persisté mais n'active pas encore de
  vérification biométrique réelle (nécessiterait `local_auth`).
- Les préfixes opérateurs (`operatorPrefixRules`) sont indicatifs et peuvent
  dériver de la réalité des plans de numérotation ; `predict-provider`
  (PawaPay) reste la source de vérité avant l'envoi.
