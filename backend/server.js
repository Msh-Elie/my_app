// =======================
// server.js (PawaPay v2 avec debug)
// =======================
import express from "express";
import cors from "cors";
import fetch from "node-fetch";
import dotenv from "dotenv";
import crypto from "crypto";
import { v4 as uuidv4 } from "uuid";
import path from "path";

// attempt to load .env from the same directory as this script (needs to work whether
// `node server.js` is run from the backend folder or from the repo root).
const __dirname = path.dirname(new URL(import.meta.url).pathname);
// Windows paths from URL may start with a slash, strip it if necessary
const normalizedDir = __dirname.replace(/^\//, "");
const envPath = path.resolve(normalizedDir, ".env");
console.log(`📁 Loading environment from: ${envPath}`);
const result = dotenv.config({ path: envPath });
if (result.error) {
  console.warn("⚠️ .env file could not be loaded", result.error);
}

// db.js et auth.js lisent process.env : l'import dynamique après dotenv.config
// garantit que .env est chargé avant l'initialisation de ces modules.
const { transactionStore, users, driver: dbDriver } = await import("./db.js");
const { authRouter, requireAuth, optionalAuth } = await import("./auth.js");
// Lookup des bénéficiaires fusionné dans ce process (plus de second service
// à déployer/maintenir séparément) — voir backend/recipient_lookup.js
const { lookupRecipientSync } = await import("./recipient_lookup.js");
// Rail de paiement secondaire, utilisé uniquement pour Celtis Bénin (PawaPay
// ne l'intègre pas du tout) — voir backend/fedapay.js
const fedapay = await import("./fedapay.js");

// Détermine quel prestataire traite un opérateur donné. Extensible : ajouter
// une entrée ici (et dans fedapay.isCeltisProvider ou un module équivalent)
// suffit pour router un nouvel opérateur non couvert par PawaPay.
function resolveRail(providerLabel) {
  return fedapay.isCeltisProvider(providerLabel) ? 'fedapay' : 'pawapay';
}

const app = express();
app.use(cors());
// Simple request logger (debug)
app.use((req, res, next) => {
  console.log('➡️ REQ', req.method, req.path, 'CT:', req.headers['content-type']);
  next();
});

// Root POST for any unexpected callbacks; respond 200 so client doesn't see 404
app.post('/', (req, res) => {
  console.log('Received POST /; ignoring payload');
  res.status(200).send('OK');
});

// Ping léger pour les health checks de l'hébergeur (Render, etc.) et pour
// réveiller le service depuis l'app sans dépendre de PawaPay ni d'un jeton.
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

// Middleware spécial: capter le body brut pour la route /api/predict-provider avant que body-parser classique ne tente de le parser
app.use((req, res, next) => {
  if (req.path === '/api/predict-provider') {
    let raw = '';
    req.setEncoding('utf8');
    req.on('data', chunk => raw += chunk);
    req.on('end', () => {
      req.rawBody = raw;
      try {
        req.jsonBody = raw ? JSON.parse(raw) : null;
      } catch (e) {
        req.jsonBody = null;
      }
      next();
    });
  } else {
    next();
  }
});

// JSON body parser global (avec sauvegarde du raw dans req.rawBody)
app.use(express.json({ verify: (req, res, buf) => { req.rawBody = buf && buf.toString(); } }));

// --- Configuration ---
const PORT = process.env.PORT || 3000;
let PAWA_BASE = process.env.PAWA_BASE || "https://api.sandbox.pawapay.io/v2";
// make sure we speak to the v2 API; users might forget the suffix in .env
if (!PAWA_BASE.endsWith("/v2")) {
  console.warn("⚠️ PAWA_BASE doesn't end with /v2, appending automatically");
  PAWA_BASE = PAWA_BASE.replace(/\/+$/, "") + "/v2";
}
// Le token PawaPay DOIT venir de l'environnement (backend/.env) — jamais du code.
const PAWA_TOKEN = process.env.PAWA_TOKEN || "";
if (!PAWA_TOKEN) {
  console.error("❌ PAWA_TOKEN manquant. Copiez backend/.env.example vers backend/.env et renseignez votre jeton sandbox PawaPay.");
  process.exit(1);
}
const CALLBACK_SECRET = process.env.CALLBACK_SECRET || "change_this_secret";
const BASE_URL = process.env.BASE_URL || "https://your-ngrok-url.ngrok.io";
const RECIPIENT_LOOKUP_URL = process.env.RECIPIENT_LOOKUP_URL || "";
const RECIPIENT_LOOKUP_TOKEN = process.env.RECIPIENT_LOOKUP_TOKEN || "";
const MTN_MOMO_LOOKUP_URL = process.env.MTN_MOMO_LOOKUP_URL || "";
const MTN_MOMO_LOOKUP_TOKEN = process.env.MTN_MOMO_LOOKUP_TOKEN || "";
const RECIPIENT_LOOKUP_TIMEOUT_MS = Number(process.env.RECIPIENT_LOOKUP_TIMEOUT_MS || 6000);

// destinataires supplémentaires pour les frais et pour Pawapay (options .env)
const FEE_RECIPIENT = process.env.FEE_RECIPIENT || "2290151469075"; // numéro qui recevra les frais
const PAWAPAY_RECEIVER = process.env.PAWAPAY_RECEIVER; // numéro à utiliser pour la part due à Pawapay
const PAWAPAY_PROVIDER = process.env.PAWAPAY_PROVIDER; // facultatif: provider de Pawapay


// --- Persistance SQLite (voir db.js) ---
// Même interface que l'ancienne Map (get/set/entries) mais chaque écriture
// est enregistrée dans backend/switchmoney.db : rien n'est perdu au redémarrage.
const transactions = transactionStore; // depositId -> { type, status, deposit, payout, meta, userId }

// --- Routes d'authentification (inscription, connexion, profil) ---
app.use('/api/auth', authRouter);

// Statuts PawaPay considérés comme définitifs (plus de polling ensuite)
const FINAL_SUCCESS_STATUSES = new Set(['COMPLETED', 'SUCCESS', 'DUPLICATE_IGNORED']);
const FINAL_FAILURE_STATUSES = new Set(['FAILED', 'REJECTED', 'CANCELLED', 'ERROR']);

function toDisplayProvider(value) {
  if (!value) return '';
  return String(value).replace(/_/g, ' ').trim();
}

function logoUrlForProvider(providerOrAsset) {
  const key = String(providerOrAsset || '').toUpperCase();
  if (!key) return null;

  // Operator logos (public assets)
  if (key.includes('MTN')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/New-mtn-logo.jpg/200px-New-mtn-logo.jpg';
  if (key.includes('AIRTEL')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Airtel_logo.svg/240px-Airtel_logo.svg.png';
  if (key.includes('MOOV')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/Moov_Africa_logo.svg/240px-Moov_Africa_logo.svg.png';
  if (key.includes('ORANGE') || key.includes('OM ')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c8/Orange_logo.svg/200px-Orange_logo.svg.png';
  if (key.includes('WAVE')) return 'https://wave.com/img/wave-logo.png';
  if (key.includes('VODAFONE')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a6/Vodafone_icon.svg/240px-Vodafone_icon.svg.png';
  if (key.includes('SAFARICOM')) return 'https://upload.wikimedia.org/wikipedia/en/thumb/8/8e/Safaricom_logo.svg/320px-Safaricom_logo.svg.png';
  if (key.includes('CELTIS')) return 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Generic_mobile_network_icon.png/128px-Generic_mobile_network_icon.png';

  // Crypto and fintech assets
  if (key.includes('USDT')) return 'https://cryptologos.cc/logos/tether-usdt-logo.png?v=040';
  if (key.includes('TRX')) return 'https://cryptologos.cc/logos/tron-trx-logo.png?v=040';
  if (key.includes('DERIV')) return 'https://deriv.com/static/brand/deriv-symbol.png';
  if (key.includes('VOLET')) return 'https://volet.com/favicon.ico';

  return null;
}

function normalizeHistoryStatus(rawStatus) {
  const status = String(rawStatus || '').toUpperCase();
  if (FINAL_SUCCESS_STATUSES.has(status)) return 'valide';
  if (FINAL_FAILURE_STATUSES.has(status)) return 'echec';
  return 'en_cours';
}

function formatDateDDMMYYYY(dateValue) {
  const date = dateValue instanceof Date ? dateValue : new Date(dateValue || Date.now());
  const dd = String(date.getDate()).padStart(2, '0');
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const yyyy = date.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

async function buildHistoryItems(limit = 50, userId = null) {
  const source = userId != null
    ? await transactions.entriesForUser(userId)
    : await transactions.entries();
  const entries = source
    .map(([id, tx]) => ({ id, tx }))
    .filter(({ tx }) => tx && tx.type === 'transfer');

  entries.sort((a, b) => {
    const da = new Date(a.tx?.createdAt || a.tx?.updatedAt || 0).getTime();
    const db = new Date(b.tx?.createdAt || b.tx?.updatedAt || 0).getTime();
    return db - da;
  });

  return entries.slice(0, limit).map(({ id, tx }) => {
    const createdAt = tx.createdAt || tx.updatedAt || Date.now();
    const meta = tx.meta || {};

    const fromProvider = toDisplayProvider(meta.senderProviderRaw || meta.senderProvider || tx.deposit?.payer?.accountDetails?.provider || '');
    const toProvider = toDisplayProvider(meta.receiverProviderRaw || meta.receiverProvider || '');
    const amount = meta.amount != null ? String(meta.amount) : '';
    const currency = tx.deposit?.currency || meta.currency || 'XOF';
    // On reflète le statut réel du dépôt PawaPay (mis à jour par polling ou
    // callback) — plus de "SUCCESS" forcé dès que la requête HTTP est acceptée.
    const statusSource = tx.status || tx.deposit?.status || tx.payoutStatus;
    const status = normalizeHistoryStatus(statusSource);

    return {
      id,
      date: formatDateDDMMYYYY(createdAt),
      status,
      from: fromProvider,
      to: toProvider,
      amount: `${amount} ${currency}`.trim(),
      fromLogo: logoUrlForProvider(fromProvider),
      toLogo: logoUrlForProvider(toProvider),
      rawStatus: statusSource || 'PENDING'
    };
  });
}

// --- Vérification HMAC ---
function verifySignature(rawBody, signatureHeader) {
  if (!signatureHeader || !rawBody) return false;
  const hmac = crypto.createHmac("sha256", CALLBACK_SECRET);
  hmac.update(rawBody);
  const expected = Buffer.from(hmac.digest("hex"));
  const sig = Buffer.from(String(signatureHeader).replace(/^sha256=/, ""));
  // timingSafeEqual lève une exception si les longueurs diffèrent
  if (expected.length !== sig.length) return false;
  return crypto.timingSafeEqual(expected, sig);
}

// Activez VERIFY_CALLBACK_SIGNATURE=true dans .env pour rejeter les callbacks
// non signés (nécessite que le même secret soit configuré côté émetteur).
const VERIFY_CALLBACK_SIGNATURE = process.env.VERIFY_CALLBACK_SIGNATURE === 'true';

// --- Mapping des providers vers format PawaPay (fallback statique) ---
function mapProviderToPawaPay(provider) {
  const providerMap = {
    "MTN BJ": "MTN_MOMO_BEN",
    "MOOV BJ": "MOOV_BEN",
    "CELTIS BJ": "CELTIS_BEN",
    "MTN CI": "MTN_MOMO_CIV",
    "MOOV CI": "MOOV_CIV",
    "OM CI": "ORANGE_CIV",
    "ORANGE CI": "ORANGE_CIV",
    "MOOV BF": "MOOV_BFA",
    "OM BF": "ORANGE_BFA",
    "MTN CM": "MTN_MOMO_CMR",
    "OM CM": "ORANGE_CMR",
    "MTN CG": "MTN_MOMO_COG",
    "WAVE CI": "WAVE_CIV",
    "MTN GH": "MTN_MOMO_GHA",
    "VODAFONE GH": "VODAFONE_GHA",
    "AIRTEL GH": "AIRTELTIGO_GHA",
    "MTN GN": "MTN_MOMO_GIN",
    "OM GN": "ORANGE_GIN",
    "AIRTEL KE": "AIRTEL_KEN",
    // code vérifié sur active-conf sandbox : Safaricom Kenya = MPESA_KEN
    "SAFARICOM KE": "MPESA_KEN",
    "OM ML": "ORANGE_MLI",
    "MOOV ML": "MOOV_MLI",
    "AIRTEL NE": "AIRTEL_NER",
    "OM NE": "ORANGE_NER",
    "AIRTEL CD": "AIRTEL_COD",
    "OM CD": "ORANGE_COD",
    // code vérifié sur active-conf sandbox : M-Pesa RDC = VODACOM_MPESA_COD
    "M-PESA CD": "VODACOM_MPESA_COD",
    "VODACOM CD": "VODACOM_MPESA_COD",
    "OM SN": "ORANGE_SEN",
    "WAVE SN": "WAVE_SEN",
    "FREE SN": "FREE_SEN",
    "YAS TG": "TOGOCOM_TGO",
    "TOGO TG": "TOGOCOM_TGO",
    "AT GH": "AIRTELTIGO_GHA",
    "TELECEL GH": "VODAFONE_GHA",
    "MOOV GA": "MOOV_GAB",
    "AIRTEL GA": "AIRTEL_GAB"
  };

  // accept either space‑separated names or underscore variants
  if (providerMap[provider]) {
    return providerMap[provider];
  }
  // try replacing underscores with spaces and look again
  if (provider.includes('_')) {
    const withSpaces = provider.replace(/_/g, ' ');
    if (providerMap[withSpaces]) return providerMap[withSpaces];
  }
  // fallback to generic uppercased underscore format
  return provider.replace(/\s+/g, '_').toUpperCase();
}

// --- Utility: sanitize metadata array passed to PawaPay ---
// The documentation specifies that metadata is an array of objects where each
// object contains a single field whose key is the metadata name and whose
// value is the metadata value.  A common mistake is to send
// { fieldName: 'foo', fieldValue: 'bar' } which leads to each object having a
// `fieldValue` key.  PawaPay then complains about duplicates of `fieldValue`.
//
// This helper accepts either the correct shape or the improper {fieldName,
// fieldValue} shape and always returns an array of properly formed objects. It
// also deduplicates names and drops invalid entries.
function sanitizeMetadata(arr) {
  if (!Array.isArray(arr)) return [];
  const seen = new Set();
  const out = [];
  for (const item of arr) {
    if (!item || typeof item !== 'object') continue;

    let name;
    let value;

    if ('fieldName' in item && 'fieldValue' in item) {
      name = item.fieldName;
      value = item.fieldValue;
    } else {
      const keys = Object.keys(item);
      for (const k of keys) {
        if (k === 'fieldValue') continue; // reserved/incorrect
        if (seen.has(k)) {
          console.warn('Dropping duplicate metadata key', k, 'in', item);
          continue;
        }
        seen.add(k);
        out.push({ [k]: item[k] });
      }
      continue;
    }

    if (!name || name === 'fieldValue' || seen.has(name)) {
      console.warn('Dropping invalid metadata entry', item);
      continue;
    }

    seen.add(name);
    out.push({ [name]: value });
  }
  return out;
}

// --- Map prefix (dial code) to 3-letter country for active-conf calls and currency fallback ---
const prefixToCountry = {
  "229": { country: 'BEN', currency: 'XOF' },
  "226": { country: 'BFA', currency: 'XOF' },
  "237": { country: 'CMR', currency: 'XAF' },
  "242": { country: 'COG', currency: 'XAF' },
  "225": { country: 'CIV', currency: 'XOF' },
  "233": { country: 'GHA', currency: 'GHS' },
  "224": { country: 'GIN', currency: 'GNF' },
  "254": { country: 'KEN', currency: 'KES' },
  "223": { country: 'MLI', currency: 'XOF' },
  "227": { country: 'NER', currency: 'XOF' },
  "243": { country: 'COD', currency: 'CDF' },
  "221": { country: 'SEN', currency: 'XOF' },
  "228": { country: 'TGO', currency: 'XOF' },
  "241": { country: 'GAB', currency: 'XAF' }
};

// code pays ISO-3 (PawaPay) -> code 2 lettres utilisé par l'app dans ses libellés
const countryTo2Letter = {
  BEN: 'BJ', BFA: 'BF', CMR: 'CM', COG: 'CG', CIV: 'CI', GHA: 'GH',
  GIN: 'GN', KEN: 'KE', MLI: 'ML', NER: 'NE', COD: 'CD', SEN: 'SN',
  TGO: 'TG', GAB: 'GA',
};

// --- Familles de marques : un même opérateur apparaît sous plusieurs noms
// (OM = Orange Money, Safaricom = M-Pesa, Vodafone GH = Telecel, etc.).
// Utilisé pour comparer la prédiction PawaPay au choix de l'utilisateur sans
// faux « mauvais réseau ».
const BRAND_FAMILIES = {
  'OM': 'ORANGE', 'ORANGE': 'ORANGE',
  'MPESA': 'MPESA', 'M-PESA': 'MPESA', 'SAFARICOM': 'MPESA', 'VODACOM': 'MPESA',
  'VODAFONE': 'TELECEL', 'TELECEL': 'TELECEL',
  'AT': 'AIRTELTIGO', 'AIRTELTIGO': 'AIRTELTIGO',
  'YAS': 'TOGOCOM', 'TOGO': 'TOGOCOM', 'TOGOCOM': 'TOGOCOM', 'TOGOCEL': 'TOGOCOM',
};

function brandFamilyOfCode(code) {
  const first = String(code || '').toUpperCase().split('_')[0];
  return BRAND_FAMILIES[first] || first;
}

function countryOfCode(code) {
  const parts = String(code || '').toUpperCase().split('_');
  return parts.length > 1 ? parts[parts.length - 1] : '';
}

// --- Cache pour active-conf ---
const activeConfCache = new Map();

async function fetchActiveConf(country) {
  if (!country) return null;
  if (activeConfCache.has(country)) return activeConfCache.get(country);

  try {
    const r = await fetch(`${PAWA_BASE}/active-conf?country=${country}&operationType=DEPOSIT`, {
      method: 'GET',
      headers: { 'Authorization': `Bearer ${PAWA_TOKEN}` }
    });
    const data = await r.json();
    activeConfCache.set(country, data);
    return data;
  } catch (err) {
    console.error('Erreur fetchActiveConf', err);
    return null;
  }
}

function findProviderCodeInConf(conf, displayName) {
  if (!conf || !conf.countries) return null;
  for (const c of conf.countries) {
    if (!c.providers) continue;
    for (const p of c.providers) {
      try {
        if (!p.displayName) continue;
        const dn = String(p.displayName).toUpperCase();
        if (dn.includes(displayName.split(' ')[0].toUpperCase()) || displayName.split(' ')[0].toUpperCase().includes(dn)) {
          return p.provider; // exact provider code from Pawapay
        }
      } catch (e) { /* ignore */ }
    }
  }
  return null;
}

function deriveRecipientLabel(phoneNumber, provider) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  const providerLabel = String(provider || 'Compte').split(' ')[0];
  const suffix = digits.length <= 4 ? digits : digits.slice(-4);
  return suffix ? `Compte ${providerLabel} • ${suffix}` : `Compte ${providerLabel}`;
}

function extractNameCandidate(payload) {
  const candidates = [
    payload?.name,
    payload?.fullName,
    payload?.displayName,
    payload?.customerName,
    payload?.accountName,
    payload?.beneficiaryName,
    payload?.recipientName,
    payload?.data?.name,
    payload?.data?.fullName,
    payload?.data?.displayName,
    payload?.data?.customerName,
    payload?.data?.accountName,
    payload?.recipient?.name,
    payload?.recipient?.fullName,
    payload?.beneficiary?.name,
  ];

  for (const value of candidates) {
    if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

async function postJsonWithTimeout(url, headers, body, timeoutMs = 6000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    let data = null;
    try {
      data = await response.json();
    } catch (_) {
      data = null;
    }

    return { response, data };
  } finally {
    clearTimeout(timer);
  }
}

// === Calcul des frais côté serveur (même logique que le client)
function computeFee(amount) {
  const mont = Number(amount);
  if (isNaN(mont) || mont <= 0) return 0;
  if (mont <= 1000) return 50;
  else if (mont <= 5000) return 100;
  else if (mont <= 10000) return 200;
  else if (mont <= 15000) return 300;
  else if (mont <= 20000) return 400;
  else if (mont <= 25000) return 500;
  else if (mont <= 50000) return 1000;
  else if (mont <= 75000) return 1500;
  else if (mont <= 100000) return 2000;
  else if (mont <= 150000) return 2500;
  else if (mont <= 200000) return 3000;
  else if (mont <= 300000) return 4000;
  else return 5000;
}

// === Création d'un payout vers le destinataire (générique)
// `purpose` permet de distinguer le paiement principal, le versement des frais
// ou la part due à Pawapay.  Il est ajouté à la note et aux metadata.
async function createPayoutForTransfer(txId, payoutAmount, receiverPhone, receiverProvider, purpose = 'transfer', rail = 'pawapay') {
  const payoutId = uuidv4();
  const noteText = purpose === 'fee'
    ? 'Payout frais'
    : purpose === 'pawapay'
      ? 'Payout Pawapay'
      : 'Payout transfer';

  if (rail === 'fedapay') {
    console.log(`📤 Création payout FedaPay (${purpose}) pour transfer ${txId}`);
    try {
      const result = await fedapay.fedapayInitiatePayout({
        amount: payoutAmount,
        currency: 'XOF',
        phoneNumber: receiverPhone,
        description: noteText,
        merchantReference: `SM-${txId}-${purpose}`,
      });
      console.log('📥 Réponse Payout FedaPay:', JSON.stringify(result.raw, null, 2));

      const tx = await transactions.get(txId) || {};
      tx.payoutInitiated = true;
      tx.payout = result.raw;
      tx.payoutId = payoutId;
      tx.payoutProviderId = result.providerPayoutId;
      tx.payoutRail = 'fedapay';
      tx.payoutStatus = result.status;
      await transactions.set(txId, tx);

      return { payoutId, pawaResponse: result.raw, status: 200 };
    } catch (err) {
      console.error('Erreur createPayoutForTransfer (fedapay)', err);
      const tx = await transactions.get(txId) || {};
      tx.payoutInitiated = false;
      tx.payoutError = String(err);
      await transactions.set(txId, tx);
      return { error: String(err) };
    }
  }

  const payoutBody = {
    payoutId,
    recipient: {
      type: "MMO",
      accountDetails: {
        phoneNumber: receiverPhone,
        provider: mapProviderToPawaPay(receiverProvider)
      }
    },
    clientReferenceId: `AUTO-PO-${Date.now()}`,
    customerMessage: noteText,
    amount: String(payoutAmount),
    currency: "XOF",
    metadata: sanitizeMetadata([
      { fieldName: "fromTransferTx", fieldValue: txId },
      { fieldName: "purpose", fieldValue: purpose }
    ])
  };

  console.log(`📤 Création automatique de payout (${purpose}) pour transfer ${txId}:`, JSON.stringify(payoutBody, null, 2));
  try {
    const r = await fetch(`${PAWA_BASE}/payouts`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${PAWA_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify(payoutBody)
    });

    const data = await r.json();
    console.log("📥 Réponse Payout automatique:", JSON.stringify(data, null, 2));

    const tx = await transactions.get(txId) || {};
    tx.payoutInitiated = true;
    tx.payout = data;
    tx.payoutId = payoutId;
    tx.payoutStatus = data.status || (r.ok ? "PENDING" : "FAILED");
    await transactions.set(txId, tx);

    return { payoutId, pawaResponse: data, status: r.status };
  } catch (err) {
    console.error("Erreur createPayoutForTransfer", err);
    const tx = await transactions.get(txId) || {};
    tx.payoutInitiated = false;
    tx.payoutError = String(err);
    await transactions.set(txId, tx);
    return { error: String(err) };
  }
}

// === Helper pour créer toutes les payouts reliées à un transfert ===
async function initiatePayoutsForTransfer(txId) {
  const tx = await transactions.get(txId);
  if (!tx || tx.type !== 'transfer' || tx.payoutInitiated) return null;

  const meta = tx.meta || {};
  const { receiverPhone, receiverProvider, senderPhone, senderProvider, fee, payoutAmount, payoutRail } = meta;
  const results = {};

  // paiement principal au destinataire : rail selon l'opérateur du destinataire
  results.main = await createPayoutForTransfer(txId, payoutAmount, receiverPhone, receiverProvider, 'transfer', payoutRail || 'pawapay');

  // envoi des frais au numéro configuré (ou défaut) — toujours via PawaPay
  // (numéro opérationnel fixe du développeur, jamais un compte Celtis)
  if (fee && fee > 0 && FEE_RECIPIENT) {
    const providerForFee = senderProvider || receiverProvider || '';
    results.fee = await createPayoutForTransfer(txId, fee, FEE_RECIPIENT, providerForFee, 'fee', 'pawapay');
  }

  // part due à Pawapay, si configurée — toujours via PawaPay également
  if (PAWAPAY_RECEIVER) {
    // par défaut on envoie le même montant que les frais, mais cela peut être
    // modifié pour correspondre à votre modèle tarifaire
    const pawapayAmt = fee || 0;
    const pawapayProvider = PAWAPAY_PROVIDER || senderProvider || receiverProvider || '';
    results.pawapay = await createPayoutForTransfer(txId, pawapayAmt, PAWAPAY_RECEIVER, pawapayProvider, 'pawapay', 'pawapay');
  }

  // Depuis le passage à SQLite, get() renvoie une copie : on relit la
  // transaction pour ne pas écraser les champs (payoutStatus, payoutId…)
  // écrits par createPayoutForTransfer pendant les awaits ci-dessus.
  const freshTx = await transactions.get(txId) || tx;
  freshTx.payouts = freshTx.payouts || [];
  freshTx.payouts.push({ extra: results });
  freshTx.payoutInitiated = true;
  await transactions.set(txId, freshTx);
  return results;
}

// =======================
// Suivi actif du statut d'un dépôt (polling PawaPay)
// =======================
// Les callbacks sandbox ne peuvent pas atteindre une machine locale sans
// tunnel public : on interroge donc directement l'API PawaPay jusqu'à
// obtenir un statut définitif, puis on déclenche les payouts.
// Renvoie toujours la même forme { status, raw }, quel que soit le
// prestataire — c'est ce qui permet à refreshTransferStatus de rester
// agnostique du rail (PawaPay ou FedaPay).
async function fetchDepositStatus(depositId, tx) {
  if (tx?.meta?.depositRail === 'fedapay') {
    const providerTransactionId = tx.deposit?.providerTransactionId;
    if (!providerTransactionId) return null;
    try {
      return await fedapay.fedapayCheckDepositStatus(providerTransactionId);
    } catch (err) {
      console.error('Erreur fetchDepositStatus (fedapay)', depositId, String(err));
      return null;
    }
  }

  try {
    const r = await fetch(`${PAWA_BASE}/deposits/${depositId}`, {
      headers: { 'Authorization': `Bearer ${PAWA_TOKEN}` }
    });
    const raw = await r.json().catch(() => null);
    if (!raw) return null;
    // v2 renvoie { data: {...} } ; on reste tolérant aux autres formes
    const dep = raw?.data ?? (Array.isArray(raw) ? raw[0] : raw);
    if (!dep || typeof dep !== 'object' || !dep.status) return null;
    return { status: String(dep.status).toUpperCase(), raw: dep };
  } catch (err) {
    console.error('Erreur fetchDepositStatus', depositId, String(err));
    return null;
  }
}

async function refreshTransferStatus(depositId) {
  const tx = await transactions.get(depositId);
  if (!tx) return null;

  const current = String(tx.status || '').toUpperCase();
  const alreadyFinal = FINAL_SUCCESS_STATUSES.has(current) || FINAL_FAILURE_STATUSES.has(current);
  if (alreadyFinal && (tx.type !== 'transfer' || tx.payoutInitiated)) return tx;

  const result = await fetchDepositStatus(depositId, tx);
  if (result && result.status) {
    tx.status = result.status;
    tx.lastStatusCheck = result.raw;
    tx.updatedAt = new Date().toISOString();
    await transactions.set(depositId, tx);
    if (tx.type === 'transfer' && !tx.payoutInitiated && FINAL_SUCCESS_STATUSES.has(tx.status)) {
      console.log(`🔔 Deposit ${depositId} complété (polling), création des payouts`);
      await initiatePayoutsForTransfer(depositId);
    }
  }
  return await transactions.get(depositId);
}

const activePolls = new Set();
function startDepositPolling(depositId, { intervalMs = 4000, maxAttempts = 25 } = {}) {
  if (activePolls.has(depositId)) return;
  activePolls.add(depositId);
  let attempts = 0;
  const timer = setInterval(async () => {
    attempts++;
    try {
      const tx = await refreshTransferStatus(depositId);
      const status = String(tx?.status || '').toUpperCase();
      const isFinal = FINAL_SUCCESS_STATUSES.has(status) || FINAL_FAILURE_STATUSES.has(status);
      if (!tx || isFinal || attempts >= maxAttempts) {
        clearInterval(timer);
        activePolls.delete(depositId);
        console.log(`⏱️ Fin du polling ${depositId} (statut: ${status || 'inconnu'}, tentatives: ${attempts})`);
      }
    } catch (err) {
      console.error('Erreur polling deposit', depositId, String(err));
      if (attempts >= maxAttempts) {
        clearInterval(timer);
        activePolls.delete(depositId);
      }
    }
  }, intervalMs);
  // ne pas empêcher l'arrêt propre du processus
  timer.unref?.();
}

// =======================
// 1️⃣ Dépôt simple (v2)
// =======================
app.post("/api/deposits", requireAuth, async (req, res) => {
  try {
    const { amount, phoneNumber, provider, clientReferenceId, customerMessage } = req.body;
    if (!amount || !phoneNumber || !provider) {
      return res.status(400).json({ error: "amount, phoneNumber, provider requis" });
    }

    const depositId = uuidv4();

    const body = {
      depositId,
      payer: {
        type: "MSISDN",
        address: {
          value: phoneNumber
        },
        provider: mapProviderToPawaPay(provider)
      },
      clientReferenceId: clientReferenceId || `INV-${Date.now()}`,
      customerMessage: customerMessage || "Transfert",
      amount: String(amount),
      currency: "XOF",
      correspondent: {
        type: "MSISDN",
        address: {
          value: phoneNumber
        },
        provider: mapProviderToPawaPay(provider)
      },
      metadata: sanitizeMetadata([
        {
          fieldName: "note",
          fieldValue: "Flutter test"
        }
      ])
    };

    console.log("📤 Dépôt envoyé à PawaPay:", JSON.stringify(body, null, 2));

    const r = await fetch(`${PAWA_BASE}/deposits`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${PAWA_TOKEN}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    const data = await r.json();
    console.log("📥 Réponse de PawaPay:", JSON.stringify(data, null, 2));
    
    await transactions.set(depositId, { type: "deposit", userId: req.user.id, status: data.status || "PENDING", deposit: data });
    res.status(r.status).json({ depositId, pawaResponse: data });

  } catch (err) {
    console.error("Error /api/deposits", err);
    res.status(500).json({ error: "internal_server_error", details: String(err) });
  }
});

// =======================
// 2️⃣ Payout simple (v2)
// =======================
app.post("/api/payouts", requireAuth, async (req, res) => {
  try {
    const { amount, phoneNumber, provider, clientReferenceId, note } = req.body;
    if (!amount || !phoneNumber || !provider) {
      return res.status(400).json({ error: "amount, phoneNumber, provider requis" });
    }

    const payoutId = uuidv4();
    const body = {
      payoutId,
      recipient: {
        type: "MMO",
        accountDetails: {
          phoneNumber: phoneNumber,
          provider: mapProviderToPawaPay(provider)
        }
      },
      clientReferenceId: clientReferenceId || `PO-${Date.now()}`,
      customerMessage: note || "Payout",
      amount: String(amount),
      currency: "XOF",
      metadata: sanitizeMetadata([
        {
          fieldName: "note",
          fieldValue: "Flutter test"
        }
      ])
    };

    console.log("📤 Payout envoyé à PawaPay:", JSON.stringify(body, null, 2));

    const r = await fetch(`${PAWA_BASE}/payouts`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${PAWA_TOKEN}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    const data = await r.json();
    console.log("📥 Réponse de PawaPay:", JSON.stringify(data, null, 2));
    
    await transactions.set(payoutId, { type: "payout", userId: req.user.id, status: data.status || "PENDING", payout: data });
    res.status(r.status).json({ payoutId, pawaResponse: data });

  } catch (err) {
    console.error("Error /api/payouts", err);
    res.status(500).json({ error: "internal_server_error", details: String(err) });
  }
});

// =======================
// 3️⃣ Transfert complet (dépôt -> payout) - VERSION SIMPLIFIÉE
// =======================
app.post("/api/transfer", requireAuth, async (req, res) => {
  try {
    // Vérifier token PawaPay
    if (!PAWA_TOKEN) return res.status(500).json({ error: 'PAWA_TOKEN missing on server. Set it in backend/.env' });

    // Le client peut envoyer soit un payload simplifié, soit un objet Pawapay-like
    const { amount, senderPhone, senderProvider, receiverPhone, receiverProvider, receiverProviderCode, depositId: clientDepositId, payer, currency: clientCurrency } = req.body;

    let depositId = clientDepositId || uuidv4();

    // Calcul frais
    const fee = computeFee(amount);
    const payoutAmount = Number(amount) - fee;
    if (payoutAmount <= 0) return res.status(400).json({ error: "Amount insufficient after fees" });

    // Déterminer l'origine du phone pour chercher active-conf / devise par défaut
    const prefix = String((payer?.accountDetails?.phoneNumber || senderPhone || '').slice(0, 3));
    const prefixInfo = prefixToCountry[prefix] || null;
    const country = prefixInfo ? prefixInfo.country : null;
    const defaultCurrency = prefixInfo ? prefixInfo.currency : (clientCurrency || 'XOF');
    const currency = clientCurrency || defaultCurrency;

    // Routage : Celtis Bénin n'existe pas chez PawaPay, on bascule ce
    // transfert (ou seulement le payout) vers FedaPay — voir resolveRail().
    const senderProviderRawLabel = String(payer?.accountDetails?.provider || senderProvider || '');
    const receiverProviderRawLabel = String(receiverProvider || '');
    const depositRail = resolveRail(senderProviderRawLabel);
    const payoutRail = resolveRail(receiverProviderRawLabel);

    // GARDE-FOU : ne jamais débiter un expéditeur si le rail du destinataire
    // ne sait pas décaisser. Sans ce contrôle, un transfert vers Celtis
    // réussit le dépôt puis échoue au payout (FedaPay 403) : l'argent est
    // prélevé sans jamais être livré. On refuse donc en amont.
    if (payoutRail === 'fedapay' && !fedapay.fedapayPayoutsAvailable()) {
      console.warn(`⛔ Transfert refusé : destination ${receiverProviderRawLabel} non décaissable.`);
      return res.status(503).json({
        error: 'payout_rail_unavailable',
        provider: receiverProviderRawLabel,
        message: `${receiverProviderRawLabel} ne peut pas encore recevoir de transfert. `
          + 'Aucun montant n\'a été prélevé.',
        details: fedapay.fedapayPayoutUnavailableReason(),
      });
    }

    let providerCode = null; // uniquement pertinent pour le rail PawaPay
    let depData;
    let isDepositRequestOk;
    let depResStatusCode = 502; // code HTTP renvoyé au client en cas d'échec

    if (depositRail === 'fedapay') {
      console.log(`🔄 Transfert (deposit) routé vers FedaPay (expéditeur: ${senderProviderRawLabel})`);
      try {
        const result = await fedapay.fedapayInitiateDeposit({
          amount,
          currency,
          phoneNumber: payer?.accountDetails?.phoneNumber || senderPhone,
          description: `Transfert ${senderProviderRawLabel} -> ${receiverProviderRawLabel}`,
        });
        depData = {
          status: result.status,
          currency,
          provider: 'fedapay',
          providerTransactionId: result.providerTransactionId,
          // Présent quand la charge directe n'est pas ouverte sur le compte :
          // l'app doit ouvrir cette page pour que le client valide son paiement.
          checkoutUrl: result.checkoutUrl,
          requiresCustomerAction: result.requiresCustomerAction === true,
          mode: result.mode,
          raw: result.raw,
        };
        isDepositRequestOk = result.status !== 'FAILED';
      } catch (err) {
        console.error('Erreur dépôt FedaPay', err);
        depData = { status: 'FAILED', error: String(err) };
        isDepositRequestOk = false;
      }
    } else {
      // Résoudre le provider pour Pawapay
      if (payer?.accountDetails?.provider) {
        // si c'est déjà un code plausiblement correct (contient underscore),
        // on le fait néanmoins passer par la fonction de mapping pour éviter
        // d'envoyer à PawaPay un code erroné comme "MTN_BJ".
        const prov = payer.accountDetails.provider;
        if (typeof prov === 'string' && prov.includes('_') && prov === prov.toUpperCase()) {
          providerCode = mapProviderToPawaPay(prov);
        } else {
          // essayer via active-conf si possible
          const conf = await fetchActiveConf(country);
          providerCode = findProviderCodeInConf(conf, String(prov));
          if (!providerCode) providerCode = mapProviderToPawaPay(String(prov));
        }
      } else if (senderProvider) {
        const conf = await fetchActiveConf(country);
        providerCode = findProviderCodeInConf(conf, String(senderProvider)) || mapProviderToPawaPay(String(senderProvider));
      } else {
        return res.status(400).json({ error: 'Provider or payer required' });
      }

      // Construire le body Pawapay conforme à la doc
      const depositBody = {
        depositId,
        payer: {
          type: 'MMO',
          accountDetails: {
            phoneNumber: payer?.accountDetails?.phoneNumber || senderPhone,
            provider: providerCode
          }
        },
        clientReferenceId: `INV-${Date.now()}`,
        customerMessage: 'Transfert Flutter',
        amount: String(amount),
        currency,
        metadata: sanitizeMetadata([
          { fieldName: 'transfer_type', fieldValue: 'peer_to_peer' },
          { fieldName: 'fee', fieldValue: String(fee) },
          { fieldName: 'payoutAmount', fieldValue: String(payoutAmount) }
        ])
      };

      console.log("🔄 Transfert (deposit) envoyé à PawaPay:", JSON.stringify(depositBody, null, 2));

      const depRes = await fetch(`${PAWA_BASE}/deposits`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${PAWA_TOKEN}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(depositBody)
      });

      depData = await depRes.json();
      console.log("📥 Réponse de dépôt PawaPay:", JSON.stringify(depData, null, 2));
      isDepositRequestOk = depRes.ok;
      depResStatusCode = depRes.status;
    }

    // stocker la transaction et métadonnées nécessaires
    await transactions.set(depositId, {
      type: 'transfer',
      userId: req.user.id,
      // Statut réel renvoyé par le prestataire (ACCEPTED en général) ; il
      // sera mis à jour par le polling ou le callback jusqu'à COMPLETED/FAILED.
      status: String(depData.status || (isDepositRequestOk ? 'ACCEPTED' : 'FAILED')).toUpperCase(),
      deposit: depData,
      meta: {
        senderPhone: payer?.accountDetails?.phoneNumber || senderPhone,
        senderProvider: depositRail === 'fedapay' ? senderProviderRawLabel : providerCode,
        senderProviderRaw: senderProviderRawLabel || providerCode,
        depositRail,
        payoutRail,
        receiverPhone,
        // code PawaPay exact si le client l'a fourni, sinon libellé à mapper
        receiverProvider: receiverProviderCode || receiverProvider,
        receiverProviderRaw: receiverProvider,
        amount,
        fee,
        payoutAmount,
        currency,
        backendAccepted: isDepositRequestOk
      },
      payoutInitiated: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    if (!isDepositRequestOk) {
      return res.status(502).json({
        error: 'deposit_failed',
        statusCode: depResStatusCode,
        depositId,
        deposit: depData
      });
    }

    // Si le dépôt est déjà COMPLETED, initier immédiatement le payout
    if (depData.status && (depData.status.toUpperCase() === 'COMPLETED' || depData.status.toUpperCase() === 'SUCCESS')) {
      const payoutResult = await initiatePayoutsForTransfer(depositId);
      return res.status(200).json({ depositId, status: await transactions.get(depositId)?.status, deposit: depData, fee, payoutAmount, payoutResult });
    }

    // Sinon : suivi actif du statut côté serveur (le callback reste utilisable
    // en plus si CALLBACK_URL est joignable publiquement).
    startDepositPolling(depositId);
    return res.status(200).json({
      depositId,
      status: await transactions.get(depositId)?.status,
      deposit: depData,
      fee,
      payoutAmount,
      // Remonté au premier niveau pour que l'app n'ait pas à fouiller `deposit`
      ...(depData.checkoutUrl ? { checkoutUrl: depData.checkoutUrl } : {}),
      ...(depData.requiresCustomerAction ? { requiresCustomerAction: true } : {}),
      note: 'Deposit initiated; status is tracked server-side (polling + callback). Poll GET /api/transfer-status/:id from the client.'
    });

  } catch (err) {
    console.error('Erreur transfert complet:', err);
    res.status(500).json({ error: 'transfer_failed', details: String(err) });
  }
});

// =======================
// 4️⃣ Callbacks génériques (dépôt / payout)
// =======================
app.post("/pawapay/callback", express.json({ verify: (req, res, buf) => { req.rawBody = buf; } }), async (req, res) => {
  // Vérification HMAC opt-in (VERIFY_CALLBACK_SIGNATURE=true dans .env)
  if (VERIFY_CALLBACK_SIGNATURE) {
    const signature = req.headers['x-signature'] || req.headers['x-pawapay-signature'];
    if (!verifySignature(req.rawBody, signature)) {
      console.warn('🚫 Callback rejeté : signature HMAC absente ou invalide');
      return res.status(401).send('invalid signature');
    }
  }

  const payload = req.body;
  const depositId = payload.depositId || payload.payoutId;
  const tx = await transactions.get(depositId);

  if (tx) {
    const oldStatus = tx.status || "";
    const callbackStatus = String(payload.status || payload.transactionStatus || '').toUpperCase();
    if (callbackStatus === 'COMPLETED' || callbackStatus === 'SUCCESS' || callbackStatus === 'DUPLICATE_IGNORED') {
      tx.status = 'SUCCESS';
    } else if (callbackStatus) {
      tx.status = callbackStatus;
    } else {
      tx.status = tx.status || 'unknown';
    }
    tx.updatedAt = new Date().toISOString();
    tx.callbackPayload = payload;
    await transactions.set(depositId, tx);
    console.log("📦 Callback reçu:", payload);

    // Si callback pour un dépôt lié à un transfert et qu'il vient d'être complété, initier le payout
    try {
      const statusUp = (payload.status || payload.transactionStatus || "").toUpperCase();
      if (tx.type === "transfer" && !tx.payoutInitiated && (statusUp === "COMPLETED" || statusUp === "SUCCESS")) {
        console.log(`🔔 Deposit ${depositId} complété, création de payouts associés`);
        const payoutResult = await initiatePayoutsForTransfer(depositId);
        console.log("Résultat création payouts (callback):", payoutResult);
      }
    } catch (err) {
      console.error("Erreur lors du traitement du callback pour payout automatique:", err);
    }
  }

  res.status(200).send("OK");
});

// =======================
// 5️⃣ Endpoint debug
// =======================
app.get("/api/tx/:id", requireAuth, async (req, res) => {
  const tx = await transactions.get(req.params.id);
  if (!tx) return res.status(404).json({ error: "not found" });
  // une transaction rattachée à un utilisateur n'est visible que par lui
  if (tx.userId != null && tx.userId !== req.user.id) {
    return res.status(403).json({ error: "forbidden" });
  }
  res.json(tx);
});

// =======================
// 5c️⃣ Statut d'un transfert (polling côté client)
// =======================
// Rafraîchit le statut auprès de PawaPay si nécessaire, déclenche les payouts
// quand le dépôt est complété, et renvoie un statut normalisé pour l'UI.
app.get('/api/transfer-status/:id', requireAuth, async (req, res) => {
  try {
    const id = req.params.id;
    let tx = await transactions.get(id);
    if (!tx) return res.status(404).json({ error: 'not_found' });
    if (tx.userId != null && tx.userId !== req.user.id) {
      return res.status(403).json({ error: 'forbidden' });
    }

    tx = await refreshTransferStatus(id) || tx;
    const status = String(tx.status || 'PENDING').toUpperCase();
    return res.json({
      depositId: id,
      status,
      uiStatus: normalizeHistoryStatus(status),
      payoutInitiated: !!tx.payoutInitiated,
      payoutStatus: tx.payoutStatus || null,
      updatedAt: tx.updatedAt || null,
    });
  } catch (err) {
    console.error('Error /api/transfer-status', err);
    return res.status(500).json({ error: 'status_failed', details: String(err) });
  }
});

// =======================
// 5b️⃣ History endpoint for frontend tab
// =======================
app.get('/api/history', requireAuth, async (req, res) => {
  try {
    const rawLimit = Number(req.query.limit || 50);
    const limit = Number.isFinite(rawLimit) ? Math.max(1, Math.min(rawLimit, 200)) : 50;
    // chaque utilisateur ne voit que ses propres transferts
    const items = await buildHistoryItems(limit, req.user.id);
    res.json({ total: items.length, items });
  } catch (err) {
    console.error('Error /api/history', err);
    res.status(500).json({ error: 'history_failed', details: String(err) });
  }
});

// Export helpers for unit testing or external use (not used by the server itself)
export { mapProviderToPawaPay, findProviderCodeInConf, computeFee, sanitizeMetadata, initiatePayoutsForTransfer, createPayoutForTransfer, transactions, normalizeHistoryStatus, verifySignature, brandFamilyOfCode, countryOfCode };

// Endpoint utilitaire pour simuler un callback PawaPay (LOCAL TEST ONLY)
// Désactivé par défaut : mettre ENABLE_SIMULATE=true dans .env pour l'activer.
// Sans ce garde-fou, n'importe qui pouvant joindre le serveur pourrait forcer
// une transaction en COMPLETED et déclencher de vrais payouts.
app.post("/api/simulate-callback", async (req, res) => {
  try {
    if (process.env.ENABLE_SIMULATE !== 'true') {
      return res.status(403).json({ error: 'simulate_disabled', message: 'Set ENABLE_SIMULATE=true in backend/.env to enable this test endpoint.' });
    }
    const { id, status } = req.body;
    if (!id || !status) return res.status(400).json({ error: "id and status required" });
    const tx = await transactions.get(id);
    if (!tx) return res.status(404).json({ error: "tx not found" });

    // Simuler payload et réutiliser la logique de callback
    const payload = { depositId: id, status };
    // Emuler l'appel au callback
    if (tx) {
      tx.status = status;
      tx.callbackPayload = payload;
      await transactions.set(id, tx);
      console.log("[SIM] Callback reçu:", payload);
      // déclencher création de payout si nécessaire
      const statusUp = (status || "").toUpperCase();
      if (tx.type === "transfer" && !tx.payoutInitiated && (statusUp === "COMPLETED" || statusUp === "SUCCESS")) {
        const payoutResult = await initiatePayoutsForTransfer(id);
        return res.json({ ok: true, payoutResult });
      }
    }

    res.json({ ok: true });
  } catch (err) {
    console.error("Erreur simulate-callback", err);
    res.status(500).json({ error: String(err) });
  }
});

// =======================
// 6️⃣ Endpoint de test PawaPay
// =======================
app.get("/api/test-pawapay", async (req, res) => {
  try {
    // Interroge un vrai endpoint PawaPay (active-conf) pour valider token + réseau
    const testRes = await fetch(`${PAWA_BASE}/active-conf?country=BEN&operationType=DEPOSIT`, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${PAWA_TOKEN}`
      }
    });

    res.status(200).json({
      status: testRes.status,
      statusText: testRes.statusText,
      connected: testRes.ok
    });
  } catch (err) {
    res.status(500).json({ error: "connection_failed", details: String(err) });
  }
});

// =======================
// 6b️⃣ Liste des opérateurs réellement disponibles (source: PawaPay active-conf)
// =======================
// L'app charge cette liste au démarrage : libellés, préfixes téléphoniques et
// codes PawaPay exacts. Fini les tables codées en dur qui divergent du réel.
app.get('/api/providers', async (req, res) => {
  try {
    const items = [];
    for (const [prefix, info] of Object.entries(prefixToCountry)) {
      const conf = await fetchActiveConf(info.country);
      const countries = conf?.countries || [];
      for (const c of countries) {
        for (const p of (c.providers || [])) {
          if (!p?.provider) continue;
          const cc2 = countryTo2Letter[info.country] || info.country;
          const brand = String(p.displayName || p.provider.split('_')[0]).trim();
          items.push({
            label: `${brand.toUpperCase()} ${cc2}`,
            code: p.provider,
            displayName: brand,
            country: info.country,
            countryCode: cc2,
            prefix: `+${prefix}`,
            currency: info.currency,
          });
        }
      }
    }
    // Celtis Bénin n'existe pas chez PawaPay (absent d'active-conf) — routé
    // vers FedaPay (voir fedapay.js). Ses capacités dépendent des droits
    // ouverts sur le compte FedaPay, d'où le champ `capabilities` : l'app
    // s'en sert pour n'autoriser Celtis que là où il fonctionne vraiment.
    items.push({
      label: 'CELTIS BJ',
      code: 'CELTIS_BEN',
      displayName: 'Celtiis',
      country: 'BEN',
      countryCode: 'BJ',
      prefix: '+229',
      currency: 'XOF',
      capabilities: {
        deposit: fedapay.FEDAPAY_ENABLED,
        payout: fedapay.fedapayPayoutsAvailable(),
      },
      unavailableReason: fedapay.fedapayPayoutsAvailable()
        ? null
        : fedapay.fedapayPayoutUnavailableReason(),
    });

    // Les opérateurs PawaPay savent faire les deux (c'est vérifié par
    // active-conf en amont) : on l'explicite pour uniformiser le contrat.
    for (const item of items) {
      if (!item.capabilities) {
        item.capabilities = { deposit: true, payout: true };
      }
    }

    items.sort((a, b) => a.label.localeCompare(b.label));
    res.json({ total: items.length, source: items.length ? 'pawapay_active_conf+fedapay' : 'unavailable', providers: items });
  } catch (err) {
    console.error('Error /api/providers', err);
    res.status(500).json({ error: 'providers_failed', details: String(err) });
  }
});

// =======================
// 7️⃣ Predict-provider wrapper
// =======================
app.post('/api/predict-provider', async (req, res) => {
  try {
    let phoneNumber, expectedProvider, expectedProviderCode;
    const source = (req.jsonBody && Object.keys(req.jsonBody).length > 0)
      ? req.jsonBody
      : (req.body && Object.keys(req.body).length > 0)
        ? req.body
        : (() => {
            try {
              return req.rawBody ? JSON.parse(req.rawBody) : null;
            } catch (e) {
              return undefined; // JSON invalide
            }
          })();
    if (source === undefined) {
      console.error('Raw body parse failed:', req.rawBody);
      return res.status(400).json({ error: 'Invalid JSON' });
    }
    phoneNumber = source?.phoneNumber;
    expectedProvider = source?.expectedProvider;
    expectedProviderCode = source?.expectedProviderCode;

    if (!phoneNumber) return res.status(400).json({ error: 'phoneNumber required' });

    // Celtis Bénin n'est pas dans le réseau PawaPay : leur predict-provider ne
    // peut structurellement pas le reconnaître et renverrait un faux "mauvais
    // réseau". On fait confiance au choix de l'utilisateur pour cet opérateur.
    if (fedapay.isCeltisProvider(expectedProviderCode) || fedapay.isCeltisProvider(expectedProvider)) {
      console.log(`🔎 Predict provider ignoré pour Celtis (${phoneNumber}) — non couvert par PawaPay`);
      return res.status(200).json({
        pawaStatus: 200,
        predicted: { provider: 'CELTIS_BEN', phoneNumber, note: 'not_covered_by_pawapay' },
        matches: true,
      });
    }

    console.log(`🔎 Predict provider for: ${phoneNumber} (expected: ${expectedProviderCode || expectedProvider || 'none'})`);

    const r = await fetch(`${PAWA_BASE}/predict-provider`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${PAWA_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ phoneNumber })
    });

    const data = await r.json();
    console.log('📥 Predict result:', JSON.stringify(data, null, 2));

    // Comparaison prédiction / choix utilisateur.
    // 1) codes PawaPay exacts si le client les fournit (le plus fiable)
    // 2) sinon libellé mappé, comparé par famille de marque + pays pour ne pas
    //    produire de faux « mauvais réseau » (OM vs ORANGE, Safaricom vs MPESA…)
    let matches = null;
    if (data?.provider) {
      const predicted = String(data.provider).toUpperCase();
      const reference = expectedProviderCode
        ? String(expectedProviderCode).toUpperCase()
        : (expectedProvider ? mapProviderToPawaPay(expectedProvider).toUpperCase() : null);
      if (reference) {
        matches = predicted === reference ||
          (brandFamilyOfCode(predicted) === brandFamilyOfCode(reference) &&
           countryOfCode(predicted) === countryOfCode(reference));
      }
    }

    // Always respond 200 to the Flutter client; embed PawaPay's status code for debugging
    const statusCode = r.ok ? r.status : 200;
    console.log('➡️ Sending /api/predict-provider response', { statusCode, pawaStatus: r.status, predicted: data, matches });
    return res.status(statusCode).json({
      pawaStatus: r.status,
      predicted: data,
      matches
    });
  } catch (err) {
    console.error('Erreur /api/predict-provider', err);
    // In case of our own bug, still return 200 with error info to avoid crashing the app
    return res.status(200).json({ predicted: { failureReason: { failureCode: 'LOCAL_ERROR', failureMessage: String(err) } }, matches: null });
  }
});

app.post('/api/resolve-recipient', async (req, res) => {
  try {
    const body = req.body || req.jsonBody || {};
    const phoneNumber = String(body.phoneNumber || '').trim();
    const provider = String(body.provider || '').trim();

    if (!phoneNumber) {
      return res.status(400).json({ error: 'phoneNumber required' });
    }

    const fallbackName = deriveRecipientLabel(phoneNumber, provider);

    const attempts = [];

    // MTN MoMo-like priority path when configured.
    if (provider.toUpperCase().startsWith('MTN') && MTN_MOMO_LOOKUP_URL) {
      attempts.push({
        source: 'mtn_momo_lookup',
        url: MTN_MOMO_LOOKUP_URL,
        token: MTN_MOMO_LOOKUP_TOKEN,
        body: {
          phoneNumber,
          msisdn: phoneNumber,
          provider,
        },
      });
    }

    if (RECIPIENT_LOOKUP_URL) {
      attempts.push({
        source: 'provider_lookup',
        url: RECIPIENT_LOOKUP_URL,
        token: RECIPIENT_LOOKUP_TOKEN,
        body: { phoneNumber, provider },
      });
    }

    // Lookup interne (in-process, pas de réseau) : base de bénéficiaires
    // fusionnée dans ce service — voir recipient_lookup.js.
    const localMatch = lookupRecipientSync(phoneNumber, provider);
    if (localMatch.resolved) {
      return res.status(200).json({
        resolved: true,
        source: 'database',
        displayName: localMatch.displayName,
      });
    }

    if (!attempts.length) {
      return res.status(200).json({
        resolved: false,
        source: 'derived',
        displayName: fallbackName,
        reason: 'lookup_not_configured',
      });
    }

    for (const attempt of attempts) {
      const headers = { 'Content-Type': 'application/json' };
      if (attempt.token) {
        headers.Authorization = `Bearer ${attempt.token}`;
      }

      try {
        const { response, data } = await postJsonWithTimeout(
          attempt.url,
          headers,
          attempt.body,
          RECIPIENT_LOOKUP_TIMEOUT_MS,
        );

        const resolvedName = extractNameCandidate(data);
        if (response.ok && resolvedName) {
          return res.status(200).json({
            resolved: true,
            source: attempt.source,
            displayName: resolvedName,
          });
        }
      } catch (lookupErr) {
        console.warn(`resolve-recipient: ${attempt.source} failed`, String(lookupErr));
      }
    }

    return res.status(200).json({
      resolved: false,
      source: 'derived',
      displayName: fallbackName,
      reason: 'name_not_found',
    });
  } catch (err) {
    console.error('Erreur /api/resolve-recipient', err);
    return res.status(200).json({
      resolved: false,
      source: 'derived',
      displayName: deriveRecipientLabel(req.body?.phoneNumber, req.body?.provider),
      reason: 'local_error',
    });
  }
});

// simple helper used by several routes so we don’t repeat ourselves
async function pawaRequest(path, body) {
  const r = await fetch(`${PAWA_BASE}${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${PAWA_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  let data;
  try { data = await r.json(); } catch(e) { data = null; }
  return { ok: r.ok, status: r.status, data };
}

// =======================
// 8️⃣ Deposit wrapper (see https://docs.pawapay.io/v2/api-reference/deposits/initiate-deposit)
// =======================
app.post('/api/deposit', requireAuth, async (req, res) => {
  try {
    const body = req.body || {};
    // ensure we have a depositId (uuidv4 helper imported earlier)
    if (!body.depositId) body.depositId = uuidv4();

    console.log('➡️ Initiate deposit', body);
    const { ok, status, data } = await pawaRequest('/deposits', body);
    console.log('📥 /deposits response', { status, data });

    // if the gateway rejected the request we still forward the JSON but send 200
    const clientStatus = ok ? status : 200;
    return res.status(clientStatus).json({ pawaStatus: status, data });
  } catch (err) {
    console.error('Error /api/deposit', err);
    return res.status(500).json({ error: 'backend_error', details: String(err) });
  }
});

// =======================
// 9️⃣ Payout wrapper (https://docs.pawapay.io/v2/api-reference/payouts/initiate-payout)
// =======================
app.post('/api/payout', requireAuth, async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.payoutId) body.payoutId = uuidv4();

    console.log('➡️ Initiate payout', body);
    const { ok, status, data } = await pawaRequest('/payouts', body);
    console.log('📥 /payouts response', { status, data });

    const clientStatus = ok ? status : 200;
    return res.status(clientStatus).json({ pawaStatus: status, data });
  } catch (err) {
    console.error('Error /api/payout', err);
    return res.status(500).json({ error: 'backend_error', details: String(err) });
  }
});

// catch-all handler so unexpected JS exceptions don't crash
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'internal', details: String(err) });
});

// En mode test (import depuis node --test) on n'ouvre pas de port.
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, "0.0.0.0", async () => {
    console.log(`✅ Backend PawaPay v2 prêt sur http://0.0.0.0:${PORT}`);
    console.log(`🔑 Token présent: ${!!PAWA_TOKEN} (len=${PAWA_TOKEN.length})`);
    console.log(`🔑 Token (masked): ${PAWA_TOKEN ? PAWA_TOKEN.slice(0,4)+"..."+PAWA_TOKEN.slice(-4) : '<none>'}`);
    console.log(`🌐 Base URL: ${PAWA_BASE}`);
    // Le nombre de comptes au démarrage rend immédiatement visible une base
    // repartie de zéro — le symptôme d'un stockage non persistant.
    try {
      console.log(`👤 Comptes enregistrés: ${await users.count()} (pilote: ${dbDriver})`);
    } catch (err) {
      console.error('❌ Base de données injoignable au démarrage:', String(err));
    }
  });
}

export { app };