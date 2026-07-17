// =======================
// auth.js — authentification (inscription, connexion PIN, jetons signés)
// =======================
// Zéro dépendance externe : hachage du PIN via crypto.scrypt et jetons
// HMAC-SHA256 au format JWT (header.payload.signature en base64url).
import crypto from 'crypto';
import express from 'express';
import { userQueries } from './db.js';

const AUTH_SECRET = process.env.AUTH_SECRET || '';
const TOKEN_TTL_SECONDS = Number(process.env.AUTH_TOKEN_TTL_SECONDS || 60 * 60 * 24 * 30); // 30 jours

// En sandbox on tolère l'absence d'AUTH_SECRET mais on prévient clairement :
// les jetons signés avec le secret de dev ne valent rien en production.
const effectiveSecret = AUTH_SECRET || 'dev-only-secret-change-me';
if (!AUTH_SECRET) {
  console.warn('⚠️ AUTH_SECRET absent du .env — utilisation d\'un secret de développement. À définir avant toute mise en production.');
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');

export function signToken(payload) {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ ...payload, iat: now, exp: now + TOKEN_TTL_SECONDS }));
  const signature = crypto
    .createHmac('sha256', effectiveSecret)
    .update(`${header}.${body}`)
    .digest('base64url');
  return `${header}.${body}.${signature}`;
}

export function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, body, signature] = parts;
  const expected = crypto
    .createHmac('sha256', effectiveSecret)
    .update(`${header}.${body}`)
    .digest('base64url');
  const sigBuf = Buffer.from(signature);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

// --- Hachage PIN ---
function hashPin(pin, salt) {
  const useSalt = salt || crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(pin), useSalt, 32).toString('hex');
  return { hash, salt: useSalt };
}

function pinMatches(pin, storedHash, storedSalt) {
  const { hash } = hashPin(pin, storedSalt);
  const a = Buffer.from(hash);
  const b = Buffer.from(storedHash);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function sanitizeUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    phone: row.phone,
    name: row.name,
    email: row.email || null,
    createdAt: row.created_at,
  };
}

function normalizePhone(value) {
  return String(value || '').replace(/\D/g, '');
}

function validPin(pin) {
  return /^\d{4,8}$/.test(String(pin || ''));
}

// --- Middlewares ---
export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = verifyToken(token);
  if (!payload || !payload.sub) {
    return res.status(401).json({ error: 'unauthorized', message: 'Jeton manquant ou invalide' });
  }
  const user = userQueries.byId.get(payload.sub);
  if (!user) {
    return res.status(401).json({ error: 'unauthorized', message: 'Utilisateur inconnu' });
  }
  req.user = sanitizeUser(user);
  next();
}

export function optionalAuth(req, _res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = verifyToken(token);
  if (payload && payload.sub) {
    const user = userQueries.byId.get(payload.sub);
    if (user) req.user = sanitizeUser(user);
  }
  next();
}

// --- Routes ---
export const authRouter = express.Router();

authRouter.post('/register', (req, res) => {
  try {
    const name = String(req.body?.name || '').trim();
    const phone = normalizePhone(req.body?.phone);
    const pin = String(req.body?.pin || '');
    const email = String(req.body?.email || '').trim() || null;

    if (name.length < 2) {
      return res.status(400).json({ error: 'invalid_name', message: 'Nom trop court' });
    }
    if (phone.length < 8 || phone.length > 15) {
      return res.status(400).json({ error: 'invalid_phone', message: 'Numéro de téléphone invalide (8 à 15 chiffres, indicatif inclus)' });
    }
    if (!validPin(pin)) {
      return res.status(400).json({ error: 'invalid_pin', message: 'Le PIN doit contenir 4 à 8 chiffres' });
    }
    if (userQueries.byPhone.get(phone)) {
      return res.status(409).json({ error: 'phone_taken', message: 'Un compte existe déjà avec ce numéro' });
    }

    const { hash, salt } = hashPin(pin);
    let info;
    try {
      info = userQueries.insert.run({ phone, name, email, pinHash: hash, pinSalt: salt });
    } catch (err) {
      // course possible : deux inscriptions simultanées avec le même numéro
      if (String(err?.code || '').startsWith('SQLITE_CONSTRAINT')) {
        return res.status(409).json({ error: 'phone_taken', message: 'Un compte existe déjà avec ce numéro' });
      }
      throw err;
    }
    const user = userQueries.byId.get(info.lastInsertRowid);
    const token = signToken({ sub: user.id, phone: user.phone });
    return res.status(201).json({ token, user: sanitizeUser(user) });
  } catch (err) {
    console.error('Erreur /api/auth/register', err);
    return res.status(500).json({ error: 'register_failed', message: 'Erreur interne' });
  }
});

authRouter.post('/login', (req, res) => {
  try {
    const phone = normalizePhone(req.body?.phone);
    const pin = String(req.body?.pin || '');
    const user = userQueries.byPhone.get(phone);
    if (!user || !pinMatches(pin, user.pin_hash, user.pin_salt)) {
      // même message dans les deux cas pour ne pas révéler l'existence du compte
      return res.status(401).json({ error: 'invalid_credentials', message: 'Numéro ou PIN incorrect' });
    }
    const token = signToken({ sub: user.id, phone: user.phone });
    return res.json({ token, user: sanitizeUser(user) });
  } catch (err) {
    console.error('Erreur /api/auth/login', err);
    return res.status(500).json({ error: 'login_failed', message: 'Erreur interne' });
  }
});

authRouter.get('/me', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

authRouter.put('/profile', requireAuth, (req, res) => {
  try {
    const name = String(req.body?.name ?? req.user.name).trim();
    const email = String(req.body?.email ?? req.user.email ?? '').trim() || null;
    if (name.length < 2) {
      return res.status(400).json({ error: 'invalid_name', message: 'Nom trop court' });
    }
    userQueries.updateProfile.run({ id: req.user.id, name, email });
    const user = userQueries.byId.get(req.user.id);
    return res.json({ user: sanitizeUser(user) });
  } catch (err) {
    console.error('Erreur /api/auth/profile', err);
    return res.status(500).json({ error: 'profile_update_failed', message: 'Erreur interne' });
  }
});

authRouter.put('/pin', requireAuth, (req, res) => {
  try {
    const currentPin = String(req.body?.currentPin || '');
    const newPin = String(req.body?.newPin || '');
    if (!validPin(newPin)) {
      return res.status(400).json({ error: 'invalid_pin', message: 'Le nouveau PIN doit contenir 4 à 8 chiffres' });
    }
    const user = userQueries.byId.get(req.user.id);
    if (!pinMatches(currentPin, user.pin_hash, user.pin_salt)) {
      return res.status(401).json({ error: 'invalid_credentials', message: 'PIN actuel incorrect' });
    }
    const { hash, salt } = hashPin(newPin);
    userQueries.updatePin.run({ id: req.user.id, pinHash: hash, pinSalt: salt });
    return res.json({ ok: true });
  } catch (err) {
    console.error('Erreur /api/auth/pin', err);
    return res.status(500).json({ error: 'pin_update_failed', message: 'Erreur interne' });
  }
});
