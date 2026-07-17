# 🚀 SwitchMoney - Démarrage rapide du lookup de bénéficiaires

Tu viens de créer un microservice de lookup complet! Voici comment le faire fonctionner.

## Installation (une seule fois)

```bash
cd backend
npm install
```

Tous les dépendances sont déjà dans le `package.json` (express, cors, dotenv).

## Démarrage des services

### Option 1: Automatique (Windows)
Double-clique sur `start_services.bat` - ça ouvre deux terminaux automatiquement.

### Option 2: Automatique (Mac/Linux)
```bash
chmod +x start_services.sh
./start_services.sh
```

### Option 3: Manuel (tous les OS)

**Terminal 1 - Service de lookup (port 3003):**
```bash
cd backend
node recipient_lookup_service.js
```

**Terminal 2 - Backend principal (port 3002):**
```bash
cd backend
node server.js
```

## Vérifier que ça marche

### Test 1: Health check
```bash
curl http://localhost:3003/health
```

Expected output:
```json
{
  "status": "ok",
  "service": "recipient-lookup",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Test 2: Lookup un bénéficiaire
```bash
curl -X POST http://localhost:3003/lookup \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Expected output:
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

### Test 3: Via le backend (full workflow)
```bash
curl -X POST http://localhost:3002/api/resolve-recipient \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Expected output:
```json
{
  "resolved": true,
  "source": "external",
  "displayName": "Alain Dossou",
  "reason": "lookup_success"
}
```

### Test 4: Lancer l'app Flutter et tester

1. Ouvre une app Flutter (Android, iOS, Web ou Windows)
2. Rentre un numéro existant: `22951469075` (Benin, MTN)
3. Attends 500ms
4. Le nom devrait s'afficher automatiquement: **"Alain Dossou"**
5. Le badge devient vert: **"Nom vérifié"**

## Aller plus loin

### Ajouter des bénéficiaires
```bash
curl -X POST http://localhost:3003/recipients \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22950000000",
    "name": "Mon Test",
    "provider": "MTN BJ"
  }'
```

### Lister tous les bénéficiaires
```bash
curl http://localhost:3003/recipients
```

### Supprimer un bénéficiaire
```bash
curl -X DELETE http://localhost:3003/recipients/22950000000
```

### Lookup plusieurs bénéficiaires
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

## Architecture

```
┌─────────────────┐
│  Flutter App    │
└────────┬────────┘
         │ valid phone number
         ▼
┌─────────────────────────────┐
│  Backend Server (port 3002) │
│  POST /api/resolve-recipient│
└────────┬────────────────────┘
         │ call lookup service
         ▼
┌──────────────────────────────┐
│ Lookup Service (port 3003)   │
│ POST /lookup                 │
│ (Mock DB → Bénéficiaire)     │
└────────┬─────────────────────┘
         │ return {name, resolved}
         ▼
┌─────────────────────────────┐
│  Backend - Format Response  │
│  {source, displayName, ...} │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────┐
│  Flutter App    │
│  Display name + │
│  Badge "✓"      │
└─────────────────┘
```

## Fichiers

- **`backend/recipient_lookup_service.js`** - Microservice standalone (port 3003)
- **`backend/LOOKUP_SETUP.md`** - Guide détaillé complet
- **`RECIPIENT_LOOKUP_API_SPEC.md`** - Spec API pour ton microservice
- **`start_services.bat`** - Starter Windows (double-clik)
- **`start_services.sh`** - Starter Mac/Linux (chmod +x first)
- **`backend/.env`** - Configuration (RECIPIENT_LOOKUP_URL déjà set)

## Prochaines étapes

1. ✅ Tests locaux avec le microservice mock
2. ⏭️ Remplacer la DB mock par une vraie base de données (PostgreSQL, MongoDB, etc)
3. ⏭️ Connecter à tes sources de bénéficiaires réelles (API PawaPay, provider KYC, etc)
4. ⏭️ Ajouter authentification/sécurité
5. ⏭️ Déployer en production (Heroku, Railway, AWS, etc)

## Dépannage

### "Cannot find module 'express'"
```bash
cd backend && npm install
```

### "Port 3003 already in use"
Autre app utilise le port 3003. Options:
- Ferme l'autre app
- Change `RECIPIENT_LOOKUP_PORT` dans `.env`

### "Lookup returns resolved: false"
- C'est normal! Le numéro n'existe pas dans la DB mock
- Teste avec `22951469075` (Alain Dossou)
- Ou ajoute ton propre bénéficiaire via POST /recipients

### "App Flutter doesn't show name"
- Vérifie que le `RECIPIENT_LOOKUP_URL` en `.env` est correct
- Teste directement le curl /lookup endpoint
- Vérifie les logs du terminal du lookup service

## Support

Voir les fichiers:
- `backend/LOOKUP_SETUP.md` - Guide complet et exemples
- `RECIPIENT_LOOKUP_API_SPEC.md` - Spec API détaillée
- `backend/recipient_lookup_service.js` - Source du microservice
