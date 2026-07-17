# Configuration du service de lookup de bénéficiaires

## Étape 1: Installer les dépendances

Le microservice utilise `express` et `cors`. Vérifie que ton `backend/package.json` les inclut:

```bash
cd backend
npm install
```

Si `cors` n'est pas encore installé:
```bash
npm install cors
```

## Étape 2: Configurer l'URL du lookup

Crée un fichier `.env` à la racine du projet (au même level que `package.json`):

```env
# Lookup service configuration
RECIPIENT_LOOKUP_URL=http://localhost:3003/lookup
RECIPIENT_LOOKUP_TOKEN=dummy-token-dev
RECIPIENT_LOOKUP_PORT=3001
```

**Important**: Le token n'est pas utilisé dans le microservice mock, mais il est envoyé par le backend. En production, remplace-le.

## Étape 3: Démarrer les deux services

### Terminal 1 - Service de lookup (port 3003)
```bash
cd backend
node recipient_lookup_service.js
```

Output:
```
🔍 Recipient Lookup Service running on http://localhost:3003
   POST http://localhost:3003/lookup - Lookup recipient
   GET  http://localhost:3003/health - Health check
   GET  http://localhost:3003/recipients - List all recipients
```

### Terminal 2 - Backend principal (port 3002)
```bash
cd backend
node server.js
```

Output:
```
🚀 Server running on port 3002
```

## Étape 4: Tester le lookup

### Test 1: Health check du service de lookup
```bash
curl http://localhost:3003/health
```

### Test 2: Lookup un bénéficiaire existant
```bash
curl -X POST http://localhost:3003/lookup \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Response:
```json
{
  "resolved": true,
  "name": "Alain Dossou",
  "phoneNumber": "22951469075",
  "provider": "MTN BJ",
  "displayName": "Alain Dossou",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Test 3: Lookup un bénéficiaire inexistant
```bash
curl -X POST http://localhost:3003/lookup \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "11111111111",
    "provider": "UNKNOWN"
  }'
```

Response:
```json
{
  "resolved": false,
  "phoneNumber": "11111111111",
  "provider": "UNKNOWN",
  "reason": "not_found",
  "message": "No recipient found for 11111111111",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Test 4: Tester via le backend (full workflow)
```bash
curl -X POST http://localhost:3002/api/resolve-recipient \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Response (du backend, qui appelle le lookup service):
```json
{
  "resolved": true,
  "source": "external",
  "displayName": "Alain Dossou",
  "reason": "lookup_success"
}
```

## Endpoints du service de lookup

### POST /lookup
Lookup un bénéficiaire unique.

```bash
curl -X POST http://localhost:3003/lookup \
  -H "Content-Type: application/json" \
  -d '{ "phoneNumber": "22951469075", "provider": "MTN BJ" }'
```

### POST /lookup/batch
Lookup plusieurs bénéficiaires à la fois.

```bash
curl -X POST http://localhost:3003/lookup/batch \
  -H "Content-Type: application/json" \
  -d '{
    "recipients": [
      { "phoneNumber": "22951469075", "provider": "MTN BJ" },
      { "phoneNumber": "2348123456789", "provider": "MTN NG" }
    ]
  }'
```

### GET /recipients
Lister tous les bénéficiaires disparibles (DEBUG seulement).

```bash
curl http://localhost:3003/recipients
```

### POST /recipients
Ajouter manuellement un bénéficiaire (TEST/ADMIN).

```bash
curl -X POST http://localhost:3003/recipients \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22950000000",
    "name": "Test User",
    "provider": "MTN BJ"
  }'
```

### DELETE /recipients/:phoneNumber
Supprimer un bénéficiaire (TEST/ADMIN).

```bash
curl -X DELETE http://localhost:3003/recipients/22950000000
```

## Bénéficiaires pré-chargés

Le service démarre avec ces bénéficiaires pour tester:

**Benin (BJ)**
- `22951469075` → Alain Dossou (MTN BJ)
- `22964502183` → Carole Azanmedi (MOOV BJ)
- `22966135792` → Ibrahim Sahi (CELTIS BJ)

**Nigeria (NG)**
- `2348123456789` → Chioma Obi (MTN NG)
- `2349012345678` → Tunde Olawale (GLO NG)
- ... et 2 autres

**Senegal (SN)**
- `221701234567` → Fatou Ndiaye (ORANGE SN)
- `221764123456` → Moussa Sarr (SONATEL SN)
- ... et plus

**Ghana, Mali, South Africa, Kenya, Morocco, Côte d'Ivoire**
- 2-3 bénéficiaires chacun pour tester

Voir `GET /recipients` pour la liste complète.

## Déploiement en production

### Option 1: Microservice sur serveur séparé
1. Deploy `recipient_lookup_service.js` sur un serveur (Heroku, Railway, Render, etc)
2. Remplace la DB mock par une vraie base de données (PostgreSQL, MongoDB)
3. Remplace `RECIPIENT_LOOKUP_TOKEN` par un vrai secret
4. Configure `RECIPIENT_LOOKUP_URL` dans ton backend .env production
5. Le backend appellera automatiquement ton service

### Option 2: Intégrer dans le backend existant
Tu peux aussi ajouter le lookup directement dans `backend/server.js` et retirer le microservice séparé. C'est plus simple si tu n'as qu'un seul serveur.

### Option 3: Database externalisée
Au lieu d'une DB mock en mémoire, utilise:
- **PostgreSQL** avec une table `recipients(phone, name, provider)`
- **MongoDB** avec une collection de bénéficiaires
- **Firebase Firestore** pour du serverless
- **DynamoDB** si tu es sur AWS

Exemple PostgreSQL:
```javascript
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

app.post('/lookup', async (req, res) => {
  const { phoneNumber } = req.body;
  const result = await pool.query(
    'SELECT name FROM recipients WHERE phone = $1',
    [phoneNumber]
  );
  
  if (result.rows.length > 0) {
    return res.json({
      resolved: true,
      name: result.rows[0].name,
      phoneNumber,
      displayName: result.rows[0].name
    });
  }
  
  return res.json({ resolved: false, phoneNumber });
});
```

## Dépannage

### "Cannot POST /lookup"
- Vérifie que le service est en train de tourner (`node recipient_lookup_service.js`)
- Vérifie que tu appelles `http://localhost:3003/lookup`, pas un autre port

### "No response from lookup service"
- Le service peut être arrêté, redémarre-le
- Vérifie la configuration `RECIPIENT_LOOKUP_URL` dans ton `.env`
- Teste `curl http://localhost:3003/health`

### "lookup_not_configured" dans la réponse
- `RECIPIENT_LOOKUP_URL` n'est pas défini dans `.env`
- Ou il y a une typo dans l'URL
- Le backend utilise automatiquement un nom dérivé comme fallback (pas de problème)

### Les noms ne s'affichent pas dans l'app
- Vérifie que le lookup a `"resolved": true` en réponse
- Teste manuellement avec `curl` d'abord
- Vérifie les logs du backend et du lookup service

## Prochaines étapes

1. ✅ Démarrage local avec microservice mock
2. ✅ Test des endpoints via curl
3. ✅ Vérifier que ça fonctionne dans l'app Flutter
4. ⚠️ Remplacer la DB mock par une vraie base de données
5. ⚠️ Connecter à tes sources réelles de données de bénéficiaires (API bancaire, DB existante, etc)
6. ⚠️ Ajouter de la sécurité (token validation, rate limiting, HTTPS)
7. ⚠️ Déployer en production
