// =======================
// db.js — persistance (utilisateurs + transactions)
// =======================
// Deux pilotes, une seule interface :
//
//   • PostgreSQL  — dès que DATABASE_URL est défini (production / Render).
//   • SQLite      — sinon, dans un fichier local (développement, tests).
//
// POURQUOI : sur Render (plan gratuit), le système de fichiers est éphémère.
// L'instance s'arrête après 15 min d'inactivité et redémarre sur un disque
// vierge : le fichier SQLite — et donc tous les comptes créés — disparaissait
// à chaque réveil. Une base PostgreSQL gérée vit en dehors du conteneur et
// survit aux redémarrages comme aux déploiements.
//
// L'API est asynchrone dans les deux cas : un accès réseau ne peut pas être
// synchrone, et une interface unique évite d'avoir deux chemins de code.
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const DATABASE_URL = process.env.DATABASE_URL || '';
export const driver = DATABASE_URL ? 'postgres' : 'sqlite';

let pool = null; // PostgreSQL
let sqlite = null; // better-sqlite3

if (driver === 'postgres') {
  const { default: pg } = await import('pg');
  pool = new pg.Pool({
    connectionString: DATABASE_URL,
    // Les bases gérées (Neon, Supabase, Render) imposent TLS ; leur chaîne de
    // certification n'est pas toujours dans le magasin de l'image Node.
    ssl: /\blocalhost\b|\b127\.0\.0\.1\b/.test(DATABASE_URL)
      ? false
      : { rejectUnauthorized: false },
    max: 5,
  });
  console.log('🗄️  Persistance : PostgreSQL (les données survivent aux redémarrages)');
} else {
  const { default: Database } = await import('better-sqlite3');
  const dbPath = process.env.SWITCHMONEY_DB || path.join(__dirname, 'switchmoney.db');
  sqlite = new Database(dbPath);
  sqlite.pragma('journal_mode = WAL');
  console.log(`🗄️  Persistance : SQLite (${dbPath})`);
  if (process.env.RENDER) {
    console.warn(
      '⚠️  SQLite sur Render : le disque est éphémère, les comptes seront perdus '
      + 'au prochain redémarrage. Définissez DATABASE_URL pour utiliser PostgreSQL.'
    );
  }
}

/// Exécute une requête. `sql` utilise les marqueurs positionnels $1, $2…
/// (convertis en ? pour SQLite), ce qui garde une seule écriture des requêtes.
async function query(sql, params = []) {
  if (driver === 'postgres') {
    const result = await pool.query(sql, params);
    return result.rows;
  }
  const statement = sqlite.prepare(sql.replace(/\$(\d+)/g, '?'));
  return statement.reader ? statement.all(...params) : (statement.run(...params), []);
}

async function queryOne(sql, params = []) {
  const rows = await query(sql, params);
  return rows[0] ?? null;
}

// --- Schéma -------------------------------------------------------------
// Les deux moteurs divergent sur les clés auto-incrémentées et les dates :
// on écrit donc le schéma une fois par moteur plutôt que de chercher un
// dialecte commun illisible.
//
// Le schéma PostgreSQL est exporté pour que les tests le rejouent tel quel
// contre un vrai moteur Postgres (voir test/postgres_dialect.test.mjs) : la
// base de production ne peut pas être le premier endroit où ce SQL s'exécute.
export const POSTGRES_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS users (
     id SERIAL PRIMARY KEY,
     phone TEXT NOT NULL UNIQUE,
     name TEXT NOT NULL,
     email TEXT,
     pin_hash TEXT NOT NULL,
     pin_salt TEXT NOT NULL,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW()
   )`,
  `CREATE TABLE IF NOT EXISTS transactions (
     id TEXT PRIMARY KEY,
     user_id INTEGER,
     type TEXT,
     status TEXT,
     payload TEXT NOT NULL,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW()
   )`,
  'CREATE INDEX IF NOT EXISTS idx_tx_user ON transactions(user_id)',
  'CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type)',
];

/// Requêtes partagées par les deux moteurs (marqueurs $1, $2… convertis pour
/// SQLite par `query`). Exportées pour être vérifiées en test.
export const SQL = {
  txSelect: 'SELECT payload FROM transactions WHERE id = $1',
  txSelectAll: 'SELECT id, payload FROM transactions',
  txSelectByUser: 'SELECT id, payload FROM transactions WHERE user_id = $1',
  txUpsert: `INSERT INTO transactions (id, user_id, type, status, payload, updated_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
       ON CONFLICT(id) DO UPDATE SET
         user_id = COALESCE(EXCLUDED.user_id, transactions.user_id),
         type = EXCLUDED.type,
         status = EXCLUDED.status,
         payload = EXCLUDED.payload,
         updated_at = CURRENT_TIMESTAMP`,
  userByPhone: 'SELECT * FROM users WHERE phone = $1',
  userById: 'SELECT * FROM users WHERE id = $1',
  userInsert: `INSERT INTO users (phone, name, email, pin_hash, pin_salt)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
  userUpdateProfile: `UPDATE users SET name = $1, email = $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $3 RETURNING *`,
  userUpdatePin: `UPDATE users SET pin_hash = $1, pin_salt = $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $3`,
  userCount: 'SELECT COUNT(*) AS n FROM users',
};

async function createSchema() {
  if (driver === 'postgres') {
    for (const statement of POSTGRES_SCHEMA) await query(statement);
    return;
  }

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      email TEXT,
      pin_hash TEXT NOT NULL,
      pin_salt TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      user_id INTEGER,
      type TEXT,
      status TEXT,
      payload TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_tx_user ON transactions(user_id);
    CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type);
  `);
}

await createSchema();

// --- Store de transactions ----------------------------------------------
// Même vocabulaire que l'ancienne Map en mémoire (get/set/has/entries), mais
// chaque méthode est asynchrone puisqu'elle peut traverser le réseau.
const parsePayload = (row) => {
  try {
    return JSON.parse(row.payload);
  } catch {
    return null;
  }
};

const toEntries = (rows) =>
  rows
    .map((row) => {
      const tx = parsePayload(row);
      return tx ? [row.id, tx] : null;
    })
    .filter(Boolean);

export const transactionStore = {
  async get(id) {
    if (!id) return undefined;
    const row = await queryOne(SQL.txSelect, [String(id)]);
    if (!row) return undefined;
    return parsePayload(row) ?? undefined;
  },

  async set(id, tx) {
    await query(
      SQL.txUpsert,
      [
        String(id),
        tx?.userId ?? null,
        tx?.type ?? null,
        tx?.status ?? null,
        JSON.stringify(tx ?? {}),
      ],
    );
    return this;
  },

  async has(id) {
    return (await this.get(id)) !== undefined;
  },

  async entries() {
    return toEntries(await query(SQL.txSelectAll));
  },

  async entriesForUser(userId) {
    return toEntries(
      await query(SQL.txSelectByUser, [userId]),
    );
  },
};

// --- Utilisateurs --------------------------------------------------------
export const users = {
  byPhone(phone) {
    return queryOne(SQL.userByPhone, [String(phone)]);
  },

  byId(id) {
    return queryOne(SQL.userById, [Number(id)]);
  },

  /// Insère et renvoie la ligne créée (RETURNING est supporté par les deux
  /// moteurs), ce qui évite une seconde requête pour relire l'utilisateur.
  insert({ phone, name, email, pinHash, pinSalt }) {
    return queryOne(
      SQL.userInsert,
      [phone, name, email, pinHash, pinSalt],
    );
  },

  updateProfile({ id, name, email }) {
    return queryOne(
      SQL.userUpdateProfile,
      [name, email, Number(id)],
    );
  },

  updatePin({ id, pinHash, pinSalt }) {
    return query(
      SQL.userUpdatePin,
      [pinHash, pinSalt, Number(id)],
    );
  },

  /// Utilisé au démarrage pour signaler une base vide (symptôme d'un disque
  /// éphémère qui vient d'être réinitialisé).
  async count() {
    const row = await queryOne(SQL.userCount);
    return Number(row?.n ?? 0);
  },
};
