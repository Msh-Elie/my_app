// =======================
// paydunya.js — rail de paiement couvrant Celtis Bénin
// =======================
// PawaPay n'intègre pas Celtis (absent d'active-conf, vérifié). FedaPay le
// référence sous le mode `sbin`, mais le compte sandbox n'a ni le droit de
// charge directe (HTTP 400) ni celui de décaissement (HTTP 403) — un blocage
// administratif, pas technique.
//
// PayDunya expose les deux sens pour Celtis, et c'est documenté :
//   • collecte     : POST /v1/softpay/celtiis-cash  (après création d'une facture)
//   • décaissement : withdraw_mode « celtiis-cash » (API de déboursement)
//
// Docs : https://developers.paydunya.com/doc/FR/softpay
//        https://developers.paydunya.com/doc/FR/api_deboursement
import fetch from 'node-fetch';

const MASTER_KEY = process.env.PAYDUNYA_MASTER_KEY || '';
const PRIVATE_KEY = process.env.PAYDUNYA_PRIVATE_KEY || '';
const TOKEN = process.env.PAYDUNYA_TOKEN || '';
const BASE = (process.env.PAYDUNYA_BASE || 'https://app.paydunya.com/api').replace(/\/+$/, '');

// « test » tant que le compte n'est pas validé ; « live » en production.
const MODE = (process.env.PAYDUNYA_MODE || 'test').toLowerCase();

export const PAYDUNYA_ENABLED = !!(MASTER_KEY && PRIVATE_KEY && TOKEN);

if (!PAYDUNYA_ENABLED) {
  console.warn(
    "⚠️ Clés PayDunya absentes (PAYDUNYA_MASTER_KEY / _PRIVATE_KEY / _TOKEN) : "
    + "Celtis Bénin restera indisponible."
  );
}

/// Libellé d'opérateur → mode de retrait PayDunya.
///
/// Seul Celtis y est routé pour l'instant : MTN et Moov passent déjà par
/// PawaPay. La table reste ouverte si un autre opérateur venait à manquer.
const WITHDRAW_MODES = {
  CELTIS: 'celtiis-cash',
  CELTIIS: 'celtiis-cash',
};

/// Marque d'un libellé « MARQUE PAYS » (« CELTIS BJ » → « CELTIS »).
function brandOf(label) {
  const parts = String(label || '').trim().toUpperCase().split(/\s+/).filter(Boolean);
  if (parts.length > 1 && parts[parts.length - 1].length === 2) parts.pop();
  return parts.join(' ');
}

/// Cet opérateur peut-il être servi par PayDunya ?
export function supportsProvider(label) {
  return Object.hasOwn(WITHDRAW_MODES, brandOf(label));
}

export function withdrawModeFor(label) {
  return WITHDRAW_MODES[brandOf(label)] ?? null;
}

/// PayDunya attend un numéro **sans indicatif pays** (`account_alias`).
///
/// L'application manipule des MSISDN complets (« 2290151469075 ») : garder
/// l'indicatif désignerait un bénéficiaire qui n'existe pas.
export function toLocalNumber(phoneNumber, countryCode = '229') {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  return digits.startsWith(countryCode) ? digits.slice(countryCode.length) : digits;
}

// --- Normalisation des statuts vers le vocabulaire commun du backend -------
// (ACCEPTED = en cours, COMPLETED = succès, FAILED = échec définitif)

/// Statuts du déboursement : created, pending, success, failed.
export function normalizeDisburseStatus(raw) {
  const s = String(raw || '').toLowerCase();
  if (s === 'success') return 'COMPLETED';
  if (s === 'failed') return 'FAILED';
  return 'ACCEPTED';
}

/// Statuts d'une facture de paiement : pending, completed, cancelled, failed.
export function normalizeCheckoutStatus(raw) {
  const s = String(raw || '').toLowerCase();
  if (s === 'completed') return 'COMPLETED';
  if (s === 'cancelled' || s === 'canceled' || s === 'failed') return 'FAILED';
  return 'ACCEPTED';
}

function headers() {
  return {
    'Content-Type': 'application/json',
    'PAYDUNYA-MASTER-KEY': MASTER_KEY,
    'PAYDUNYA-PRIVATE-KEY': PRIVATE_KEY,
    'PAYDUNYA-TOKEN': TOKEN,
    'PAYDUNYA-MODE': MODE,
  };
}

async function call(path, { method = 'POST', body } = {}) {
  const r = await fetch(BASE + path, {
    method,
    headers: headers(),
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json().catch(() => null);
  if (!r.ok) {
    const detail = data?.response_text || data?.message || JSON.stringify(data);
    const err = new Error('PayDunya ' + path + ' -> HTTP ' + r.status + ': ' + detail);
    err.status = r.status;
    err.payload = data;
    throw err;
  }
  return data;
}

/// PayDunya renvoie `response_code: "00"` en cas de succès applicatif, même
/// sous un HTTP 200 : un autre code signale un refus, qu'il ne faut surtout
/// pas confondre avec une réussite.
function assertAccepted(data, path) {
  const code = data?.response_code;
  if (code !== undefined && String(code) !== '00') {
    const detail = data?.response_text || 'sans détail';
    const err = new Error('PayDunya ' + path + ' refusé (code ' + code + '): ' + detail);
    err.payload = data;
    throw err;
  }
  return data;
}

// =======================
// Collecte — facture, puis débit du compte Celtis
// =======================
export async function paydunyaInitiateDeposit({
  amount,
  phoneNumber,
  description,
  customerName = 'Client SwitchMoney',
  customerEmail = 'client@switchmoney.bj',
}) {
  if (!PAYDUNYA_ENABLED) throw new Error('Clés PayDunya non configurées');

  const invoice = assertAccepted(
    await call('/v1/checkout-invoice/create', {
      body: {
        invoice: {
          total_amount: Math.round(Number(amount)),
          description: description || 'Transfert SwitchMoney',
        },
        store: { name: 'SwitchMoney' },
      },
    }),
    '/v1/checkout-invoice/create',
  );

  const token = invoice?.token;
  if (!token) {
    throw new Error('Réponse PayDunya inattendue (pas de token) : ' + JSON.stringify(invoice));
  }

  // Débit effectif : l'opérateur pousse une demande de confirmation au client.
  const charge = await call('/v1/softpay/celtiis-cash', {
    body: {
      celtiis_cash_customer_fullname: customerName,
      celtiis_cash_customer_email: customerEmail,
      phone_number: toLocalNumber(phoneNumber),
      payment_token: token,
    },
  });

  return {
    providerTransactionId: token,
    // `success: false` signale un refus immédiat ; sinon le client doit encore
    // valider sur son téléphone, donc le dépôt reste « en cours ».
    status: charge?.success === false ? 'FAILED' : 'ACCEPTED',
    requiresCustomerAction: charge?.success !== false,
    raw: { invoice, charge },
  };
}

export async function paydunyaCheckDepositStatus(token) {
  const data = await call('/v1/checkout-invoice/confirm/' + token, { method: 'GET' });
  return { status: normalizeCheckoutStatus(data?.status), raw: data };
}

// =======================
// Décaissement — facture de déboursement, puis soumission
// =======================
export async function paydunyaInitiatePayout({
  amount,
  phoneNumber,
  provider,
  merchantReference,
  callbackUrl,
}) {
  if (!PAYDUNYA_ENABLED) throw new Error('Clés PayDunya non configurées');

  const withdrawMode = withdrawModeFor(provider);
  if (!withdrawMode) {
    throw new Error('Opérateur non couvert par PayDunya : ' + provider);
  }

  const invoice = assertAccepted(
    await call('/v2/disburse/get-invoice', {
      body: {
        account_alias: toLocalNumber(phoneNumber),
        amount: Math.round(Number(amount)),
        withdraw_mode: withdrawMode,
        callback_url: callbackUrl || (process.env.BACKEND_BASE || '') + '/paydunya/callback',
      },
    }),
    '/v2/disburse/get-invoice',
  );

  const disburseInvoice = invoice?.disburse_token || invoice?.token;
  if (!disburseInvoice) {
    throw new Error(
      'Réponse PayDunya inattendue (pas de disburse_token) : ' + JSON.stringify(invoice),
    );
  }

  // Rien ne part tant que la facture n'est pas soumise : c'est cette seconde
  // étape qui déclenche réellement le virement.
  const submitted = assertAccepted(
    await call('/v2/disburse/submit-invoice', {
      body: {
        disburse_invoice: disburseInvoice,
        disburse_id: merchantReference || 'SM-' + Date.now(),
      },
    }),
    '/v2/disburse/submit-invoice',
  );

  return {
    providerPayoutId: disburseInvoice,
    status: normalizeDisburseStatus(submitted?.status ?? 'pending'),
    raw: { invoice, submitted },
  };
}

export async function paydunyaCheckPayoutStatus(disburseInvoice) {
  const data = await call('/v2/disburse/check-status', {
    body: { disburse_invoice: disburseInvoice },
  });
  return { status: normalizeDisburseStatus(data?.status), raw: data };
}

/// PayDunya peut-il décaisser ? Contrairement à FedaPay, aucun droit
/// supplémentaire n'est à faire ouvrir : les clés suffisent.
export function paydunyaPayoutsAvailable() {
  return PAYDUNYA_ENABLED;
}

export function paydunyaUnavailableReason() {
  return 'Clés PayDunya non configurées (PAYDUNYA_MASTER_KEY, PAYDUNYA_PRIVATE_KEY, PAYDUNYA_TOKEN).';
}
