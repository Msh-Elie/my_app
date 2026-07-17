# 🚀 SwitchMoney - Lookup Réel avec SQLite

**Version: Vraie base de données SQLite (pas de mock en mémoire)**

Tu as maintenant un microservice qui utilise une **vraie base de données persistante** - pas une simulation!

## Architecture

```
Flutter App
    ↓ (valid phone)
Backend (port 3000)
    ↓ POST /api/resolve-recipient
Lookup Service (port 3001)
    ↓ query
SQLite Database (recipients.db)
    ↓ return record
Lookup Response
    ↓
Flutter App Update (show name + badge)
```

## Installation (une seule fois)

```bash
cd backend
npm install
```

Les dépendances `sqlite3` et `better-sqlite3` sont déjà installées.

## Démarrage

### Option 1: Automatique (Windows)
```bash
start_services.bat
```

### Option 2: Automatique (Mac/Linux)
```bash
chmod +x start_services.sh
./start_services.sh
```

### Option 3: Manuel

**Terminal 1:**
```bash
cd backend
node recipient_lookup_service_db.js
```

Output attendu:
```
🔍 Recipient Lookup Service (SQLite) running on http://localhost:3001
📊 Database: C:\...\backend\recipients.db

📡 Available endpoints:
   POST   http://localhost:3001/lookup - Lookup recipient
   ...
```

**Terminal 2:**
```bash
cd backend
node server.js
```

## Tests

### Test 1: Health check (vérifie la DB)
```bash
curl http://localhost:3001/health
```

Réponse:
```json
{
  "status": "ok",
  "service": "recipient-lookup-db",
  "database": "sqlite",
  "recipients_count": 23,
  "db_file": "C:\\...\\backend\\recipients.db",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Test 2: Lookup un bénéficiaire existant
```bash
curl -X POST http://localhost:3001/lookup \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "22951469075", "provider": "MTN BJ"}'
```

Réponse:
```json
{
  "resolved": true,
  "name": "Alain Dossou",
  "phoneNumber": "22951469075",
  "provider": "MTN BJ",
  "displayName": "Alain Dossou",
  "countryCode": "BJ",
  "source": "database",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Test 3: Lookup un bénéficiaire inexistant
```bash
curl -X POST http://localhost:3001/lookup \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "11111111111", "provider": "UNKNOWN"}'
```

Réponse (graceful fallback):
```json
{
  "resolved": false,
  "phoneNumber": "11111111111",
  "provider": "UNKNOWN",
  "reason": "not_found",
  "message": "No recipient found in database for 11111111111",
  "source": "database",
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

## Gestion des bénéficiaires

### Lister tous les bénéficiaires
```bash
curl http://localhost:3001/recipients
```

### Lister par pays
```bash
# Benin
curl http://localhost:3001/recipients/country/BJ

# Nigeria
curl http://localhost:3001/recipients/country/NG
```

### Lister par opérateur
```bash
# MTN Benin
curl http://localhost:3001/recipients/provider/MTN%20BJ

# Orange Senegal
curl http://localhost:3001/recipients/provider/ORANGE%20SN
```

### Ajouter un bénéficiaire
```bash
curl -X POST http://localhost:3001/recipients \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22950000123",
    "name": "Jean Dupont",
    "provider": "MTN BJ",
    "countryCode": "BJ"
  }'
```

### Mettre à jour un bénéficiaire
```bash
curl -X PUT http://localhost:3001/recipients/22951469075 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Alain D. Dossou",
    "provider": "MTN BJ",
    "countryCode": "BJ"
  }'
```

### Supprimer un bénéficiaire
```bash
curl -X DELETE http://localhost:3001/recipients/22950000123
```

## Statistiques

### Voir les stats de la DB
```bash
curl http://localhost:3001/stats
```

Réponse:
```json
{
  "recipients": 23,
  "total_lookups": 45,
  "resolved_lookups": 42,
  "countries": 8,
  "providers": 15,
  "db_file": "C:\\...\\backend\\recipients.db",
  "db_size": 12288,
  "timestamp": "2026-03-16T10:30:00.000Z"
}
```

### Historique des lookups
```bash
curl http://localhost:3001/history
curl http://localhost:3001/history?limit=50
```

## Bénéficiaires pré-chargés

**23 bénéficiaires** dans 10 pays:

| Pays | Opérateur | Téléphone | Nom |
|------|-----------|-----------|-----|
| BJ | MTN | 22951469075 | Alain Dossou |
| BJ | MOOV | 22964502183 | Carole Azanmedi |
| BJ | CELTIS | 22966135792 | Ibrahim Sahi |
| NG | MTN | 2348123456789 | Chioma Obi |
| NG | GLO | 2349012345678 | Tunde Olawale |
| NG | AIRTEL | 2347030000000 | Amarachi Eze |
| NG | 9MOBILE | 2348093000000 | Seun Adebayo |
| SN | ORANGE | 221701234567 | Fatou Ndiaye |
| SN | SONATEL | 221764123456 | Moussa Sarr |
| SN | FREE | 221757654321 | Aissatou Diallo |
| GH | MTN | 233242123456 | Kwame Asante |
| GH | VODAFONE | 233501234567 | Ama Mensah |
| GH | AIRTEL | 233551234567 | Kofi Appiah |
| ML | ORANGE | 223765432109 | Daouda Toure |
| ML | SOTELMA | 223698123456 | Fatoumata Ba |
| ZA | MTN | 27721234567 | Mandla Nkosi |
| ZA | VODACOM | 27741234567 | Thandi Mkhize |
| KE | SAFARICOM | 254701234567 | David Kipchoge |
| KE | AIRTEL | 254702345678 | Zainab Hassan |
| MA | MAROC TELECOM | 212612345678 | Ahmed Ben Youssef |
| MA | ORANGE | 212661234567 | Leila El Mouhssine |
| CI | MTN | 22501234567 | Kofi Mensah |
| CI | ORANGE | 22507123456 | Yolande Kouassi |

## Base de données

### Fichier
```
backend/recipients.db
```

C'est un fichier SQLite standard. Tu peux l'inspecter avec:
```bash
# Installer DB Browser for SQLite
# Ou utiliser VSCode extension "SQLite"
```

### Schéma
```sql
-- Table recipients
CREATE TABLE recipients (
  id INTEGER PRIMARY KEY,
  phone_number TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  provider TEXT NOT NULL,
  country_code TEXT NOT NULL,
  created_at DATETIME,
  updated_at DATETIME
);

-- Table lookup_history
CREATE TABLE lookup_history (
  id INTEGER PRIMARY KEY,
  phone_number TEXT NOT NULL,
  provider TEXT,
  resolved INTEGER (0 ou 1),
  name TEXT,
  timestamp DATETIME
);
```

## Avantages (vraie DB au lieu de mock)

✅ **Persistant** - Les données restent entre les redémarrages  
✅ **Transactionnel** - ACID guarantees  
✅ **Indexé** - Recherches rapides par téléphone/provider  
✅ **Auditée** - Historique complet des lookups  
✅ **Scalable** - Facile d'importer des milliers de bénéficiaires  
✅ **Vrai** - Pas une simulation en mémoire  
✅ **Zéro dépendance externe** - Pas besoin de PostgreSQL/MongoDB  
✅ **File-based** - Sauvegarde simple, backup facile  

## Prochaines étapes

### 1. Ajouter tes vraies données
```bash
curl -X POST http://localhost:3001/recipients \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22950010000",
    "name": "Ton Bénéficiaire",
    "provider": "MTN BJ",
    "countryCode": "BJ"
  }'
```

### 2. Importer en batch
```javascript
// bulk_import.js
import Database from 'better-sqlite3';

const db = new Database('backend/recipients.db');
const stmt = db.prepare('INSERT INTO recipients (phone_number, name, provider, country_code) VALUES (?, ?, ?, ?)');

const data = [
  ['22950010000', 'Person 1', 'MTN BJ', 'BJ'],
  ['22950020000', 'Person 2', 'MTN BJ', 'BJ'],
  // ... 1000 de lignes
];

const transaction = db.transaction(() => {
  for (const row of data) stmt.run(...row);
});

transaction();
```

### 3. Connecter à une vraie source
- API bancaire (PawaPay, Flutterwave, etc)
- CSV/Excel import
- Webhook de synchronisation

### 4. Ajouter authentification
```javascript
// Valider token avant lookup
app.use((req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token || token !== process.env.LOOKUP_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
});
```

### 5. Déployer en production
- **Planet Scale** (MySQL compatible, gratuit)
- **Railway** (PostgreSQL/SQLite)
- **Render** (auto-deploy depuis GitHub)
- **Fly.io** (ultra-fast global)

## Dépannage

### "Cannot find module 'better-sqlite3'"
```bash
cd backend && npm install better-sqlite3 sqlite3
```

### "database is locked"
- Autre processus accède à la DB
- Attends quelques secondes et réessaye
- SQLite utilise WAL mode pour meilleure concurrence

### "Recipients count is 0"
- Base vide car première exécution
- Attend l'initialisation (5 sec)
- Ou ajoute manuellement via POST /recipients

### Voir un rapport de toutes les données
```bash
curl http://localhost:3001/recipients | jq .
curl http://localhost:3001/stats | jq .
curl http://localhost:3001/history | jq .
```

## Migration depuis mock

Si tu avais l'ancienne version (en mémoire):
1. Simplement remplace par `node recipient_lookup_service_db.js`
2. Les données _locales_ mock ne sont plus - DB commence vide
3. Réinjecte les données nécessaires ou utilise les 23 pré-chargées
4. C'est tout! La DB SQLite prend le relai

**Note:** L'ancienne version `recipient_lookup_service.js` (mock) est toujours là si tu veux l'utiliser, mais recommandé d'utiliser `recipient_lookup_service_db.js` (vraie DB) maintenant.

## Support

Fichiers de référence:
- `backend/recipient_lookup_service_db.js` - Source du service
- `RECIPIENT_LOOKUP_API_SPEC.md` - API spec
- `backend/recipients.db` - Base de données

Questions? Regarde les logs ou teste les endpoints curl ci-dessus!
