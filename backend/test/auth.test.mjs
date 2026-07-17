// Tests unitaires du module d'authentification (node --test).
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import os from 'os';
import path from 'path';
import fs from 'fs';

process.env.NODE_ENV = 'test';
process.env.AUTH_SECRET = 'unit-test-secret';
const tmpDb = path.join(os.tmpdir(), `switchmoney-auth-test-${process.pid}.db`);
process.env.SWITCHMONEY_DB = tmpDb;

const { signToken, verifyToken } = await import('../auth.js');

after(() => {
  try { fs.rmSync(tmpDb, { force: true }); } catch {}
  try { fs.rmSync(`${tmpDb}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${tmpDb}-shm`, { force: true }); } catch {}
});

test('signToken/verifyToken font l\'aller-retour', () => {
  const token = signToken({ sub: 7, phone: '22951469075' });
  const payload = verifyToken(token);
  assert.equal(payload.sub, 7);
  assert.equal(payload.phone, '22951469075');
  assert.ok(payload.exp > Math.floor(Date.now() / 1000));
});

test('verifyToken rejette les jetons falsifiés', () => {
  const token = signToken({ sub: 7 });
  const [header, body] = token.split('.');
  // payload modifié (sub différent) avec l'ancienne signature
  const forgedBody = Buffer.from(JSON.stringify({ sub: 999, iat: 0, exp: 9999999999 })).toString('base64url');
  assert.equal(verifyToken(`${header}.${forgedBody}.${token.split('.')[2]}`), null);
  // signature tronquée
  assert.equal(verifyToken(`${header}.${body}.abc`), null);
  // formats invalides
  assert.equal(verifyToken('not-a-token'), null);
  assert.equal(verifyToken(''), null);
  assert.equal(verifyToken(null), null);
});

test('verifyToken rejette les jetons expirés', () => {
  // fabrique un jeton correctement signé mais déjà expiré
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ sub: 1, iat: now - 100, exp: now - 10 })).toString('base64url');
  const signature = crypto.createHmac('sha256', 'unit-test-secret').update(`${header}.${body}`).digest('base64url');
  assert.equal(verifyToken(`${header}.${body}.${signature}`), null);
});
