// =======================
// server.js (PawaPay v2 avec debug)
// =======================
import express from "express";
import fetch from "node-fetch";
import dotenv from "dotenv";
import crypto from "crypto";
import { v4 as uuidv4 } from "uuid";

dotenv.config({ path: './backend/.env' });

const app = express();
app.use(express.json());

// --- Configuration ---
const PORT = process.env.PORT || 3000;
const PAWA_BASE = process.env.PAWA_BASE || "https://api.sandbox.pawapay.io/v2";
const PAWA_TOKEN = process.env.PAWA_TOKEN || ""; // Bearer token sandbox
const CALLBACK_SECRET = process.env.CALLBACK_SECRET || "change_this_secret";
const BASE_URL = process.env.BASE_URL || "https://your-ngrok-url.ngrok.io";

// --- Mémoire temporaire (à remplacer par DB en prod) ---
const transactions = new Map(); // depositId -> { type, status, deposit, payout, meta }

// --- Vérification HMAC ---
function verifySignature(rawBody, signatureHeader) {
  if (!signatureHeader) return false;
  const hmac = crypto.createHmac("sha256", CALLBACK_SECRET);
  hmac.update(rawBody);
  const expected = hmac.digest("hex");
  const sig = signatureHeader.replace(/^sha256=/, "");
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sig));
}

// --- Mapping des providers vers format PawaPay ---
function mapProviderToPawaPay(provider) {
  const providerMap = {
    "MTN BJ": "MTN_BEN",
    "MOOV BJ": "MOOV_BEN",
    "CELTIS BJ": "CELTIS_BEN",
    "MTN CI": "MTN_CIV",
    "MOOV CI": "MOOV_CIV",
    "MOOV BF": "MOOV_BFA",
    "OM BF": "ORANGE_BFA",
    "MTN CM": "MTN_CMR",
    "OM CM": "ORANGE_CMR",
    "MTN CG": "MTN_COG",
    "MTN CI": "MTN_CIV",
    "MOOV CI": "MOOV_CIV",
    "OM CI": "ORANGE_CIV",
    "WAVE CI": "WAVE_CIV",
    "MTN GH": "MTN_GHA",
    "VODAFONE GH": "VODAFONE_GHA",
    "AIRTEL GH": "AIRTELTIGO_GHA",
    "MTN GN": "MTN_GIN",
    "OM GN": "ORANGE_GIN",
    "AIRTEL KE": "AIRTEL_KEN",
    "SAFARICOM KE": "SAFARICOM_KEN",
    "OM ML": "ORANGE_MLI",
    "MOOV ML": "MOOV_MLI",
    "AIRTEL NE": "AIRTEL_NER",
    "OM NE": "ORANGE_NER",
    "AIRTEL CD": "AIRTEL_COD",
    "OM CD": "ORANGE_COD",
    "M-PESA CD": "MPESA_COD",
    "OM SN": "ORANGE_SEN",
    "WAVE SN": "WAVE_SEN",
    "YAS TG": "YAS_TGO",
    "TOGO TG": "TOGOCEL_TGO",
    "MOOV GA": "MOOV_GAB",
    "AIRTEL GA": "AIRTEL_GAB"
  };
  return providerMap[provider] || provider.replace(" ", "_").toUpperCase();
}

// =======================
// 1️⃣ Dépôt simple (v2)
// =======================
app.post("/api/deposits", async (req, res) => {
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
      metadata: [
        {
          fieldName: "note",
          fieldValue: "Flutter test"
        }
      ]
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
    
    transactions.set(depositId, { type: "deposit", status: data.status || "PENDING", deposit: data });
    res.status(r.status).json({ depositId, pawaResponse: data });

  } catch (err) {
    console.error("Error /api/deposits", err);
    res.status(500).json({ error: "internal_server_error", details: String(err) });
  }
});

// =======================
// 2️⃣ Payout simple (v2)
// =======================
app.post("/api/payouts", async (req, res) => {
  try {
    const { amount, phoneNumber, provider, clientReferenceId, note } = req.body;
    if (!amount || !phoneNumber || !provider) {
      return res.status(400).json({ error: "amount, phoneNumber, provider requis" });
    }

    const payoutId = uuidv4();
    const body = {
      payoutId,
      payee: {
        type: "MSISDN",
        address: {
          value: phoneNumber
        },
        provider: mapProviderToPawaPay(provider)
      },
      clientReferenceId: clientReferenceId || `PO-${Date.now()}`,
      note: note || "Payout",
      amount: String(amount),
      currency: "XOF",
      correspondent: {
        type: "MSISDN",
        address: {
          value: phoneNumber
        },
        provider: mapProviderToPawaPay(provider)
      },
      metadata: [
        {
          fieldName: "note",
          fieldValue: "Flutter test"
        }
      ]
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
    
    transactions.set(payoutId, { type: "payout", status: data.status || "PENDING", payout: data });
    res.status(r.status).json({ payoutId, pawaResponse: data });

  } catch (err) {
    console.error("Error /api/payouts", err);
    res.status(500).json({ error: "internal_server_error", details: String(err) });
  }
});

// =======================
// 3️⃣ Transfert complet (dépôt -> payout) - VERSION SIMPLIFIÉE
// =======================
app.post("/api/transfer", async (req, res) => {
  try {
    const { amount, senderPhone, senderProvider, receiverPhone, receiverProvider } = req.body;
    if (!amount || !senderPhone || !senderProvider || !receiverPhone || !receiverProvider) {
      return res.status(400).json({ error: "Champs manquants" });
    }

    const depositId = uuidv4();
    
    // Version simplifiée sans payee d'abord
    const depositBody = {
      depositId,
      payer: {
        type: "MSISDN",
        address: {
          value: senderPhone
        },
        provider: mapProviderToPawaPay(senderProvider)
      },
      clientReferenceId: `INV-${Date.now()}`,
      customerMessage: "Transfert Flutter",
      amount: String(amount),
      currency: "XOF",
      correspondent: {
        type: "MSISDN",
        address: {
          value: senderPhone
        },
        provider: mapProviderToPawaPay(senderProvider)
      },
      metadata: [
        {
          fieldName: "transfer_type",
          fieldValue: "peer_to_peer"
        }
      ]
    };

    console.log("🔄 Transfert envoyé à PawaPay:", JSON.stringify(depositBody, null, 2));

    const depRes = await fetch(`${PAWA_BASE}/deposits`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${PAWA_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify(depositBody)
    });

    const depData = await depRes.json();
    console.log("📥 Réponse de PawaPay:", JSON.stringify(depData, null, 2));
    
    transactions.set(depositId, { 
      type: "transfer", 
      status: depData.status || "PENDING", 
      deposit: depData, 
      meta: { senderPhone, senderProvider, receiverPhone, receiverProvider, amount } 
    });

    res.status(200).json({ depositId, deposit: depData });

  } catch (err) {
    console.error("Erreur transfert complet:", err);
    res.status(500).json({ error: "transfer_failed", details: String(err) });
  }
});

// =======================
// 4️⃣ Callbacks génériques (dépôt / payout)
// =======================
app.post("/pawapay/callback", express.json({ verify: (req, res, buf) => { req.rawBody = buf; } }), (req, res) => {
  const payload = req.body;
  const depositId = payload.depositId || payload.payoutId;
  const tx = transactions.get(depositId);
  if (tx) {
    tx.status = payload.status || "unknown";
    tx.callbackPayload = payload;
    transactions.set(depositId, tx);
    console.log("📦 Callback reçu:", payload);
  }
  res.status(200).send("OK");
});

// =======================
// 5️⃣ Endpoint debug
// =======================
app.get("/api/tx/:id", (req, res) => {
  const tx = transactions.get(req.params.id);
  if (!tx) return res.status(404).json({ error: "not found" });
  res.json(tx);
});

// =======================
// 6️⃣ Endpoint de test PawaPay
// =======================
app.get("/api/test-pawapay", async (req, res) => {
  try {
    // Test simple de connexion à l'API PawaPay
    const testRes = await fetch(`${PAWA_BASE}/health`, {
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
app.listen(PORT, "0.0.0.0", () => {
  console.log(`✅ Backend PawaPay v2 prêt sur http://0.0.0.0:${PORT}`);
  console.log(`🔑 Token présent: ${!!PAWA_TOKEN}`);
  console.log(`🌐 Base URL: ${PAWA_BASE}`);
});