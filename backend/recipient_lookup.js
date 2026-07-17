// =======================
// recipient_lookup.js — base de bénéficiaires partagée (nom affiché à la
// confirmation, façon MTN MoMo).
//
// Exporte :
//  - lookupRecipientSync(phoneNumber, provider) : lecture directe, utilisée
//    en interne par server.js (POST /api/resolve-recipient) — pas d'appel
//    HTTP, donc pas de dépendance à un second service sur Render.
//  - recipientLookupRouter : les mêmes routes qu'avant (health, lookup,
//    admin CRUD) pour l'outil autonome recipient_lookup_service_db.js
//    (usage local uniquement — jamais monté publiquement par server.js,
//    les routes d'écriture n'ont pas d'authentification).
// =======================
import express from 'express';
import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// RECIPIENTS_DB permet de pointer vers un disque persistant Render
// (ex: /var/data/recipients.db) sans changer de code.
const dbPath = process.env.RECIPIENTS_DB || path.join(__dirname, 'recipients.db');

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS recipients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone_number TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    provider TEXT NOT NULL,
    country_code TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS lookup_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone_number TEXT NOT NULL,
    provider TEXT,
    resolved INTEGER DEFAULT 0,
    name TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_phone ON recipients(phone_number);
  CREATE INDEX IF NOT EXISTS idx_provider ON recipients(provider);
  CREATE INDEX IF NOT EXISTS idx_country ON recipients(country_code);
`);

const count = db.prepare('SELECT COUNT(*) as cnt FROM recipients').get();
if (count.cnt === 0) {
  const sampleRecipients = [
    { phone: '22951469075', name: 'MENSAH Elie Exaucé', provider: 'MTN BJ', country: 'BJ' },
    { phone: '22964502183', name: 'Carole Azanmedi', provider: 'MOOV BJ', country: 'BJ' },
    { phone: '22966135792', name: 'Ibrahim Sahi', provider: 'MTN BJ', country: 'BJ' },
    { phone: '2348123456789', name: 'Chioma Obi', provider: 'MTN NG', country: 'NG' },
    { phone: '2349012345678', name: 'Tunde Olawale', provider: 'GLO NG', country: 'NG' },
    { phone: '2347030000000', name: 'Amarachi Eze', provider: 'AIRTEL NG', country: 'NG' },
    { phone: '2348093000000', name: 'Seun Adebayo', provider: '9MOBILE NG', country: 'NG' },
    { phone: '221701234567', name: 'Fatou Ndiaye', provider: 'ORANGE SN', country: 'SN' },
    { phone: '221764123456', name: 'Moussa Sarr', provider: 'FREE SN', country: 'SN' },
    { phone: '221757654321', name: 'Aissatou Diallo', provider: 'FREE SN', country: 'SN' },
    { phone: '233242123456', name: 'Kwame Asante', provider: 'MTN GH', country: 'GH' },
    { phone: '233501234567', name: 'Ama Mensah', provider: 'VODAFONE GH', country: 'GH' },
    { phone: '233551234567', name: 'Kofi Appiah', provider: 'AIRTEL GH', country: 'GH' },
    { phone: '223765432109', name: 'Daouda Toure', provider: 'OM ML', country: 'ML' },
    { phone: '223698123456', name: 'Fatoumata Ba', provider: 'MOOV ML', country: 'ML' },
    { phone: '254701234567', name: 'David Kipchoge', provider: 'SAFARICOM KE', country: 'KE' },
    { phone: '254702345678', name: 'Zainab Hassan', provider: 'AIRTEL KE', country: 'KE' },
    { phone: '22501234567', name: 'Kofi Mensah', provider: 'MTN CI', country: 'CI' },
    { phone: '22507123456', name: 'Yolande Kouassi', provider: 'OM CI', country: 'CI' },
  ];

  const insertStmt = db.prepare(`
    INSERT INTO recipients (phone_number, name, provider, country_code)
    VALUES (?, ?, ?, ?)
  `);
  const seed = db.transaction(() => {
    for (const r of sampleRecipients) insertStmt.run(r.phone, r.name, r.provider, r.country);
  });
  seed();
}

function normalizeLookupPhone(phoneNumber, provider = '') {
  const digits = String(phoneNumber || '').replace(/[^0-9]/g, '');
  const upperProvider = String(provider || '').toUpperCase();

  if (upperProvider.endsWith('BJ') && digits.startsWith('01') && digits.length === 10) {
    return `229${digits.slice(2)}`;
  }
  if (upperProvider.endsWith('BJ') && digits.startsWith('0') && digits.length === 10) {
    return `229${digits.slice(1)}`;
  }
  if (digits.startsWith('22901') && digits.length >= 13) {
    return `229${digits.slice(5)}`;
  }
  if (digits.startsWith('2290') && digits.length >= 12) {
    return `229${digits.slice(4)}`;
  }
  return digits;
}

const lookupStmt = db.prepare(`
  SELECT name, provider, country_code FROM recipients WHERE phone_number = ? LIMIT 1
`);
const logStmt = db.prepare(`
  INSERT INTO lookup_history (phone_number, provider, resolved, name) VALUES (?, ?, ?, ?)
`);

/// Lecture directe (pas de réseau) : utilisée par server.js.
export function lookupRecipientSync(phoneNumber, provider) {
  const normalizedPhone = normalizeLookupPhone(phoneNumber, provider);
  const recipient = lookupStmt.get(normalizedPhone);

  try {
    logStmt.run(normalizedPhone, provider || null, recipient ? 1 : 0, recipient?.name || null);
  } catch (_) { /* la journalisation ne doit jamais faire échouer un lookup */ }

  if (!recipient) {
    return { resolved: false, phoneNumber: normalizedPhone, reason: 'not_found', source: 'database' };
  }
  return {
    resolved: true,
    name: recipient.name,
    displayName: recipient.name,
    phoneNumber: normalizedPhone,
    provider: recipient.provider,
    countryCode: recipient.country_code,
    source: 'database',
  };
}

// --- Router HTTP autonome (usage local via recipient_lookup_service_db.js
// uniquement — écritures non authentifiées, à ne jamais exposer publiquement) ---
export const recipientLookupRouter = express.Router();

recipientLookupRouter.get('/health', (req, res) => {
  const stats = db.prepare('SELECT COUNT(*) as cnt FROM recipients').get();
  res.json({ status: 'ok', service: 'recipient-lookup-db', recipients_count: stats.cnt, db_file: dbPath, timestamp: new Date() });
});

recipientLookupRouter.post('/lookup', (req, res) => {
  const { phoneNumber, provider } = req.body || {};
  if (!phoneNumber || !provider) {
    return res.status(400).json({ resolved: false, reason: 'missing_fields' });
  }
  res.json(lookupRecipientSync(phoneNumber, provider));
});

recipientLookupRouter.get('/recipients', (req, res) => {
  const recipients = db.prepare('SELECT phone_number, name, provider, country_code, created_at FROM recipients ORDER BY country_code, provider, name').all();
  res.json({ total: recipients.length, recipients, timestamp: new Date() });
});

recipientLookupRouter.post('/recipients', (req, res) => {
  const { phoneNumber, name, provider, countryCode } = req.body || {};
  if (!phoneNumber || !name || !provider || !countryCode) {
    return res.status(400).json({ error: 'phoneNumber, name, provider, and countryCode are required' });
  }
  const normalizedPhone = normalizeLookupPhone(phoneNumber, provider);
  try {
    const info = db.prepare('INSERT INTO recipients (phone_number, name, provider, country_code) VALUES (?, ?, ?, ?)')
      .run(normalizedPhone, name, provider.toUpperCase(), countryCode.toUpperCase());
    res.status(201).json({ message: 'Recipient added', id: info.lastInsertRowid, phoneNumber: normalizedPhone, name, provider, countryCode });
  } catch (err) {
    if (String(err.message).includes('UNIQUE')) {
      return res.status(409).json({ error: 'Recipient with this phone number already exists', phoneNumber: normalizedPhone });
    }
    res.status(500).json({ error: err.message });
  }
});

recipientLookupRouter.delete('/recipients/:phoneNumber', (req, res) => {
  const normalizedPhone = normalizeLookupPhone(req.params.phoneNumber);
  const info = db.prepare('DELETE FROM recipients WHERE phone_number = ?').run(normalizedPhone);
  if (info.changes === 0) return res.status(404).json({ error: 'Recipient not found' });
  res.json({ message: 'Recipient deleted', phoneNumber: normalizedPhone });
});

recipientLookupRouter.get('/stats', (req, res) => {
  const recipients = db.prepare('SELECT COUNT(*) as cnt FROM recipients').get();
  const lookups = db.prepare('SELECT COUNT(*) as cnt FROM lookup_history').get();
  res.json({ recipients: recipients.cnt, total_lookups: lookups.cnt, db_file: dbPath, db_size: fs.statSync(dbPath).size, timestamp: new Date() });
});
