// Tests unitaires des helpers du serveur (node --test).
// NODE_ENV=test empêche server.js d'ouvrir un port ;
// SWITCHMONEY_DB isole la base SQLite dans un fichier temporaire.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import os from 'os';
import path from 'path';
import fs from 'fs';

process.env.NODE_ENV = 'test';
const tmpDb = path.join(os.tmpdir(), `switchmoney-test-${process.pid}.db`);
process.env.SWITCHMONEY_DB = tmpDb;

const server = await import('../server.js');
const { computeFee, mapProviderToPawaPay, sanitizeMetadata, normalizeHistoryStatus, verifySignature, transactions, brandFamilyOfCode, countryOfCode } = server;

after(() => {
  try { fs.rmSync(tmpDb, { force: true }); } catch {}
  try { fs.rmSync(`${tmpDb}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${tmpDb}-shm`, { force: true }); } catch {}
});

test('computeFee suit la grille tarifaire', () => {
  assert.equal(computeFee(0), 0);
  assert.equal(computeFee(-5), 0);
  assert.equal(computeFee(500), 50);
  assert.equal(computeFee(1000), 50);
  assert.equal(computeFee(1001), 100);
  assert.equal(computeFee(5000), 100);
  assert.equal(computeFee(10000), 200);
  assert.equal(computeFee(20000), 400);
  assert.equal(computeFee(50000), 1000);
  assert.equal(computeFee(100000), 2000);
  assert.equal(computeFee(300000), 4000);
  assert.equal(computeFee(999999), 5000);
});

test('mapProviderToPawaPay mappe les libellés connus', () => {
  assert.equal(mapProviderToPawaPay('MTN BJ'), 'MTN_MOMO_BEN');
  assert.equal(mapProviderToPawaPay('MOOV BJ'), 'MOOV_BEN');
  assert.equal(mapProviderToPawaPay('WAVE SN'), 'WAVE_SEN');
  // codes vérifiés sur active-conf sandbox
  assert.equal(mapProviderToPawaPay('OM CI'), 'ORANGE_CIV');
  assert.equal(mapProviderToPawaPay('SAFARICOM KE'), 'MPESA_KEN');
  assert.equal(mapProviderToPawaPay('M-PESA CD'), 'VODACOM_MPESA_COD');
  assert.equal(mapProviderToPawaPay('AT GH'), 'AIRTELTIGO_GHA');
  // variante underscore acceptée
  assert.equal(mapProviderToPawaPay('MTN_BJ'), 'MTN_MOMO_BEN');
  // inconnu : format générique majuscules + underscores
  assert.equal(mapProviderToPawaPay('FOO XX'), 'FOO_XX');
});

test('brandFamilyOfCode regroupe les marques équivalentes', () => {
  // OM = Orange Money
  assert.equal(brandFamilyOfCode('OM_CI'), brandFamilyOfCode('ORANGE_CIV'));
  // Safaricom = M-Pesa = Vodacom M-Pesa
  assert.equal(brandFamilyOfCode('SAFARICOM_KE'), brandFamilyOfCode('MPESA_KEN'));
  assert.equal(brandFamilyOfCode('VODACOM_MPESA_COD'), brandFamilyOfCode('MPESA_KEN'));
  // marques distinctes non confondues
  assert.notEqual(brandFamilyOfCode('MTN_MOMO_BEN'), brandFamilyOfCode('MOOV_BEN'));
  assert.notEqual(brandFamilyOfCode('AIRTEL_COD'), brandFamilyOfCode('ORANGE_COD'));
});

test('countryOfCode extrait le pays du code provider', () => {
  assert.equal(countryOfCode('MTN_MOMO_BEN'), 'BEN');
  assert.equal(countryOfCode('VODACOM_MPESA_COD'), 'COD');
  assert.equal(countryOfCode(''), '');
  // même marque mais pays différents => match refusé via le pays
  assert.notEqual(countryOfCode('MTN_MOMO_BEN'), countryOfCode('MTN_MOMO_CIV'));
});

test('sanitizeMetadata normalise et déduplique', () => {
  const out = sanitizeMetadata([
    { fieldName: 'a', fieldValue: '1' },
    { b: '2' },
    { fieldName: 'a', fieldValue: 'dup' }, // doublon ignoré
    null,
    'junk',
  ]);
  assert.deepEqual(out, [{ a: '1' }, { b: '2' }]);
  assert.deepEqual(sanitizeMetadata(undefined), []);
});

test('normalizeHistoryStatus distingue valide/echec/en_cours', () => {
  assert.equal(normalizeHistoryStatus('COMPLETED'), 'valide');
  assert.equal(normalizeHistoryStatus('success'), 'valide');
  assert.equal(normalizeHistoryStatus('DUPLICATE_IGNORED'), 'valide');
  assert.equal(normalizeHistoryStatus('FAILED'), 'echec');
  assert.equal(normalizeHistoryStatus('REJECTED'), 'echec');
  assert.equal(normalizeHistoryStatus('ACCEPTED'), 'en_cours');
  assert.equal(normalizeHistoryStatus(''), 'en_cours');
  assert.equal(normalizeHistoryStatus(undefined), 'en_cours');
});

test('verifySignature ne lève pas sur longueurs différentes', () => {
  assert.equal(verifySignature('body', 'sha256=short'), false);
  assert.equal(verifySignature('body', null), false);
  assert.equal(verifySignature(null, 'x'), false);
});

test('transactionStore persiste et relit les transactions', () => {
  const id = `test-${Date.now()}`;
  transactions.set(id, { type: 'transfer', status: 'ACCEPTED', userId: 42, meta: { amount: 1000 } });
  const tx = transactions.get(id);
  assert.equal(tx.status, 'ACCEPTED');
  assert.equal(tx.meta.amount, 1000);

  // mise à jour
  tx.status = 'COMPLETED';
  transactions.set(id, tx);
  assert.equal(transactions.get(id).status, 'COMPLETED');

  // filtrage par utilisateur
  const mine = transactions.entriesForUser(42).map(([txId]) => txId);
  assert.ok(mine.includes(id));
  const others = transactions.entriesForUser(999).map(([txId]) => txId);
  assert.ok(!others.includes(id));
});
