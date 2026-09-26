// =======================
// fedapay.js — rail de paiement secondaire, utilisé uniquement pour Celtis
// Bénin (PawaPay ne l'intègre pas du tout — vérifié sur active-conf sandbox).
// Doc : https://docs.fedapay.com (transactions = dépôts, payouts = décaissements)
// =======================
import fetch from 'node-fetch';

const FEDAPAY_SECRET_KEY = process.env.FEDAPAY_SECRET_KEY || '';
const FEDAPAY_BASE = (process.env.FEDAPAY_BASE || 'https://sandbox-api.fedapay.com/v1').replace(/\/+$/, '');

export const FEDAPAY_ENABLED = !!FEDAPAY_SECRET_KEY;
if (!FEDAPAY_ENABLED) {
  console.warn("⚠️ FEDAPAY_SECRET_KEY absent : les transferts impliquant Celtis Bénin échoueront (aucun autre rail ne le supporte).");
}

// Code opérateur FedaPay pour Celtis Bénin (confirmé via leur doc officielle,
// table des payment methods : collection ET payout) ET présent dans les
// `modes` de la devise XOF du compte — le code n'est donc pas en cause.
const CELTIS_MODE = 'sbin';

// --- Capacités réellement ouvertes sur le compte FedaPay ------------------
// Vérifié le 2026-09-25 sur le compte sandbox 22166 :
//   POST /transactions        -> 200  (création OK)
//   POST /{mode} (charge API) -> 400 "Opération non autorisée"  (sbin, moov ET
//                                mtn : c'est l'API de charge directe qui est
//                                fermée, pas l'opérateur Celtis)
//   POST /payouts             -> 403 "Opération non autorisée"
// Tant que FedaPay n'a pas ouvert ces deux droits sur le compte, on ne peut
// ni charger directement, ni décaisser. Le checkout hébergé (payment_url),
// lui, répond 200 et reste donc la seule voie de dépôt fonctionnelle.
//
// Passez ces variables à "true" dans backend/.env une fois que FedaPay a
// activé les droits correspondants — aucun autre changement n'est requis.
const asBool = (v, fallback = false) =>
  v === undefined || v === '' ? fallback : String(v).toLowerCase() === 'true';

const FEDAPAY_PAYOUTS_ENABLED = asBool(process.env.FEDAPAY_PAYOUTS_ENABLED, false);
const FEDAPAY_DIRECT_CHARGE_ENABLED = asBool(process.env.FEDAPAY_DIRECT_CHARGE_ENABLED, false);

// Mémorise un refus constaté à l'exécution : inutile de retenter (et surtout
// de débiter un expéditeur) si le compte n'a pas le droit de décaisser.
let payoutsRefusedAtRuntime = false;

/// Le rail FedaPay peut-il décaisser (= servir de destination) ?
export function fedapayPayoutsAvailable() {
  return FEDAPAY_ENABLED && FEDAPAY_PAYOUTS_ENABLED && !payoutsRefusedAtRuntime;
}

/// Raison lisible à remonter à l'app quand le décaissement est impossible.
export function fedapayPayoutUnavailableReason() {
  if (!FEDAPAY_ENABLED) return 'FEDAPAY_SECRET_KEY non configuré';
  return "Le compte FedaPay n'a pas le droit « payout » (HTTP 403 « Opération non "
    + "autorisée »). Celtis ne peut pas encore recevoir de transfert.";
}

// FedaPay renvoie ce message quand le compte n'a pas le droit demandé — aussi
// bien en 400 (charge directe) qu'en 403 (payout).
function isPermissionError(err) {
  return /Opération non autorisée/i.test(String(err?.message || err));
}

export function isCeltisProvider(label) {
  const key = String(label || '').toUpperCase();
  return key.includes('CELTIS') || key === CELTIS_MODE.toUpperCase();
}

function headers() {
  return {
    Authorization: `Bearer ${FEDAPAY_SECRET_KEY}`,
    'Content-Type': 'application/json',
  };
}

// FedaPay attend un MSISDN international ("+229...") et un code pays 2 lettres.
function toFedapayPhone(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  const withPlus = digits.startsWith('229') ? `+${digits}` : `+229${digits}`;
  return { number: withPlus, country: 'bj' };
}

// --- Normalisation des statuts FedaPay vers le vocabulaire commun du backend
// (ACCEPTED = en cours, COMPLETED = succès, FAILED = échec définitif) ---
function normalizeTransactionStatus(raw) {
  const s = String(raw || '').toLowerCase();
  if (s === 'approved' || s === 'transferred') return 'COMPLETED';
  if (s === 'declined' || s === 'canceled' || s === 'expired') return 'FAILED';
  return 'ACCEPTED'; // pending, refunded (transitoire), ou inconnu
}

function normalizePayoutStatus(raw) {
  const s = String(raw || '').toLowerCase();
  if (s === 'sent' || s === 'success') return 'COMPLETED';
  if (s === 'failed' || s === 'error') return 'FAILED';
  return 'ACCEPTED'; // pending, started, processing
}

async function fedapayFetch(path, options) {
  const r = await fetch(`${FEDAPAY_BASE}${path}`, { ...options, headers: headers() });
  const data = await r.json().catch(() => null);
  if (!r.ok) {
    // On garde le statut et le message FedaPay sur l'erreur : c'est ce qui
    // permet de distinguer un refus de droits d'une vraie panne.
    const err = new Error(
      `FedaPay ${path} -> HTTP ${r.status}: ${data?.message || JSON.stringify(data)}`
    );
    err.status = r.status;
    err.payload = data;
    throw err;
  }
  return data;
}

// =======================
// Dépôt (collecte) — création de transaction puis déclenchement de la charge
// =======================
export async function fedapayInitiateDeposit({ amount, currency, phoneNumber, description }) {
  if (!FEDAPAY_ENABLED) throw new Error('FEDAPAY_SECRET_KEY non configuré');

  const phone = toFedapayPhone(phoneNumber);
  const amountInt = Math.round(Number(amount));

  const created = await fedapayFetch('/transactions', {
    method: 'POST',
    body: JSON.stringify({
      description: description || 'Transfert SwitchMoney',
      amount: amountInt,
      currency: { iso: currency || 'XOF' },
      customer: {
        firstname: 'SwitchMoney',
        lastname: 'Client',
        phone_number: phone,
      },
    }),
  });

  const transaction = created?.['v1/transaction'] || created?.transaction || created;
  const transactionId = transaction?.id;
  if (!transactionId) {
    throw new Error(`Réponse FedaPay inattendue (pas d'id de transaction): ${JSON.stringify(created)}`);
  }

  // Générer le jeton de paiement. Il sert à la fois à la charge directe et à
  // la page de paiement hébergée, d'où sa génération systématique.
  const tokenResp = await fedapayFetch(`/transactions/${transactionId}/token`, { method: 'POST' });
  const token = tokenResp?.token || tokenResp?.['v1/transaction']?.token;
  if (!token) {
    throw new Error(`Réponse FedaPay inattendue (pas de token): ${JSON.stringify(tokenResp)}`);
  }
  const checkoutUrl = tokenResp?.url || transaction?.payment_url || null;

  // Voie 1 — charge directe (prompt PIN poussé sur le téléphone, sans quitter
  // l'app). Fermée sur le compte actuel : on retombe alors sur le checkout.
  if (FEDAPAY_DIRECT_CHARGE_ENABLED) {
    try {
      const charge = await fedapayFetch(`/${CELTIS_MODE}`, {
        method: 'POST',
        body: JSON.stringify({ token, phone_number: phone }),
      });
      return {
        providerTransactionId: transactionId,
        status: normalizeTransactionStatus(transaction?.status || 'pending'),
        mode: 'direct_charge',
        checkoutUrl,
        raw: { created: transaction, charge },
      };
    } catch (err) {
      if (!isPermissionError(err)) throw err;
      console.warn(
        `⚠️ Charge directe FedaPay refusée (${err.message}) — bascule sur le checkout hébergé.`
      );
    }
  }

  // Voie 2 — checkout hébergé : l'utilisateur ouvre `checkoutUrl`, choisit
  // Celtis et saisit son PIN sur la page FedaPay. La transaction existe déjà,
  // donc le polling de statut habituel suffit à suivre l'opération.
  return {
    providerTransactionId: transactionId,
    status: normalizeTransactionStatus(transaction?.status || 'pending'),
    mode: 'hosted_checkout',
    requiresCustomerAction: true,
    checkoutUrl,
    raw: { created: transaction },
  };
}

export async function fedapayCheckDepositStatus(providerTransactionId) {
  const data = await fedapayFetch(`/transactions/${providerTransactionId}`, { method: 'GET' });
  const transaction = data?.['v1/transaction'] || data?.transaction || data;
  return { status: normalizeTransactionStatus(transaction?.status), raw: transaction };
}

// =======================
// Payout (décaissement) — création puis déclenchement immédiat
// =======================
export async function fedapayInitiatePayout({ amount, currency, phoneNumber, description, merchantReference }) {
  if (!FEDAPAY_ENABLED) throw new Error('FEDAPAY_SECRET_KEY non configuré');

  const phone = toFedapayPhone(phoneNumber);
  const amountInt = Math.round(Number(amount));

  let created;
  try {
    created = await fedapayFetch('/payouts', {
      method: 'POST',
      body: JSON.stringify({
        amount: amountInt,
        currency: { iso: currency || 'XOF' },
        mode: CELTIS_MODE,
        description: description || 'Payout SwitchMoney',
        customer: {
          firstname: 'SwitchMoney',
          lastname: 'Beneficiaire',
          phone_number: phone,
        },
        merchant_reference: merchantReference || `SM-${Date.now()}`,
      }),
    });
  } catch (err) {
    // 403 « Opération non autorisée » : le compte n'a pas le droit de
    // décaisser. On le mémorise pour que les transferts suivants soient
    // refusés *avant* de débiter un expéditeur.
    if (isPermissionError(err)) {
      payoutsRefusedAtRuntime = true;
      console.error(
        '❌ FedaPay refuse les payouts sur ce compte — Celtis désactivé comme destination jusqu\'à activation du droit.'
      );
    }
    throw err;
  }

  const payout = created?.['v1/payout'] || created?.payout || created;
  const payoutId = payout?.id;
  if (!payoutId) {
    throw new Error(`Réponse FedaPay inattendue (pas d'id de payout): ${JSON.stringify(created)}`);
  }

  const started = await fedapayFetch('/payouts/start', {
    method: 'PUT',
    body: JSON.stringify({ payouts: [{ id: payoutId }] }),
  });

  return {
    providerPayoutId: payoutId,
    status: normalizePayoutStatus(payout?.status || 'pending'),
    raw: { created: payout, started },
  };
}

export async function fedapayCheckPayoutStatus(providerPayoutId) {
  const data = await fedapayFetch(`/payouts/${providerPayoutId}`, { method: 'GET' });
  const payout = data?.['v1/payout'] || data?.payout || data;
  return { status: normalizePayoutStatus(payout?.status), raw: payout };
}
