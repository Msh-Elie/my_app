import fetch from 'node-fetch';
import dotenv from 'dotenv';
import path from 'path';

// load same .env as server
const __dirname = path.dirname(new URL(import.meta.url).pathname).replace(/^\//, '');
dotenv.config({ path: path.resolve(__dirname, '.env') });
const PAWA_BASE = process.env.PAWA_BASE || 'https://api.sandbox.pawapay.io/v2';
const PAWA_TOKEN = process.env.PAWA_TOKEN;

async function test() {
  const body = {
    depositId: 'fef2da73-5336-4d47-a88e-fc6a13a6126b',
    payer: { type:'MMO', accountDetails:{phoneNumber:'2290151469075', provider:'MTN_MOMO_BEN'}},
    clientReferenceId:'INV-testdup',
    customerMessage:'DupTest',
    amount:'2000',
    currency: 'XOF',
    metadata: [
      { fieldName:'fee', fieldValue:'100' },
      { fieldName:'fieldValue', fieldValue:'oops' }
    ]
  };
  const res = await fetch(`${PAWA_BASE}/deposits`, {
    method:'POST', headers:{'Authorization': `Bearer ${PAWA_TOKEN}`, 'Content-Type':'application/json'},
    body: JSON.stringify(body)
  });
  const data = await res.json();
  console.log('response', data);
}

 test().catch(console.error);
