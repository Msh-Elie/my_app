import fetch from 'node-fetch';
import dotenv from 'dotenv';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';

// load .env like server.js
const __dirname = path.dirname(new URL(import.meta.url).pathname);
const normalizedDir = __dirname.replace(/^\//, '');
const envPath = path.resolve(normalizedDir, '.env');
dotenv.config({ path: envPath });

const BASE = process.env.PAWA_BASE || 'https://api.sandbox.pawapay.io/v2';
const BACKEND = process.env.BACKEND_BASE || 'http://localhost:3000';

async function main() {
  const depositId = uuidv4();
  const payload = {
    amount: 1000,
    senderPhone: '2290151469075',
    senderProvider: 'MTN BJ',
    receiverPhone: '2291234567890',
    receiverProvider: 'MTN BJ',
    depositId,
  };
  console.log('Sending transfer payload', payload);
  const r = await fetch(`${BACKEND}/api/transfer`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await r.json();
  console.log('Transfer response', r.status, JSON.stringify(data, null, 2));

  // if deposit is pending, simulate callback
  if (data.depositId) {
    console.log('Simulating callback completion');
    const sim = await fetch(`${BACKEND}/api/simulate-callback`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: data.depositId, status: 'COMPLETED' }),
    });
    const simData = await sim.json();
    console.log('Callback simulation result', sim.status, JSON.stringify(simData, null, 2));
  }
}

main().catch(err => console.error(err));
