// =======================
// db.js — persistance SQLite partagée (users + transactions)
// =======================
import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.SWITCHMONEY_DB || path.join(__dirname, 'switchmoney.db');

export const db = new Database(dbPath);
db.pragma('journal_mode = WAL');

db.exec(`
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

// --- Store de transactions compatible avec l'ancienne Map en mémoire ---
// server.js utilisait `transactions.get/set/entries`; cette classe garde la
// même interface mais écrit chaque transaction dans SQLite, donc rien n'est
// perdu au redémarrage du serveur.
class TransactionStore {
  constructor(database) {
    this.db = database;
    this.selectOne = database.prepare('SELECT payload FROM transactions WHERE id = ?');
    this.selectAll = database.prepare('SELECT id, payload FROM transactions');
    this.selectByUser = database.prepare('SELECT id, payload FROM transactions WHERE user_id = ?');
    this.upsert = database.prepare(`
      INSERT INTO transactions (id, user_id, type, status, payload, updated_at)
      VALUES (@id, @userId, @type, @status, @payload, CURRENT_TIMESTAMP)
      ON CONFLICT(id) DO UPDATE SET
        user_id = COALESCE(excluded.user_id, transactions.user_id),
        type = excluded.type,
        status = excluded.status,
        payload = excluded.payload,
        updated_at = CURRENT_TIMESTAMP
    `);
  }

  get(id) {
    if (!id) return undefined;
    const row = this.selectOne.get(String(id));
    if (!row) return undefined;
    try {
      return JSON.parse(row.payload);
    } catch {
      return undefined;
    }
  }

  set(id, tx) {
    this.upsert.run({
      id: String(id),
      userId: tx?.userId ?? null,
      type: tx?.type ?? null,
      status: tx?.status ?? null,
      payload: JSON.stringify(tx ?? {}),
    });
    return this;
  }

  has(id) {
    return this.get(id) !== undefined;
  }

  entries() {
    const rows = this.selectAll.all();
    return rows
      .map((row) => {
        try {
          return [row.id, JSON.parse(row.payload)];
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  }

  entriesForUser(userId) {
    const rows = this.selectByUser.all(userId);
    return rows
      .map((row) => {
        try {
          return [row.id, JSON.parse(row.payload)];
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  }
}

export const transactionStore = new TransactionStore(db);

// --- Requêtes utilisateurs ---
export const userQueries = {
  insert: db.prepare(`
    INSERT INTO users (phone, name, email, pin_hash, pin_salt)
    VALUES (@phone, @name, @email, @pinHash, @pinSalt)
  `),
  byPhone: db.prepare('SELECT * FROM users WHERE phone = ?'),
  byId: db.prepare('SELECT * FROM users WHERE id = ?'),
  updateProfile: db.prepare(`
    UPDATE users SET name = @name, email = @email, updated_at = CURRENT_TIMESTAMP
    WHERE id = @id
  `),
  updatePin: db.prepare(`
    UPDATE users SET pin_hash = @pinHash, pin_salt = @pinSalt, updated_at = CURRENT_TIMESTAMP
    WHERE id = @id
  `),
};
