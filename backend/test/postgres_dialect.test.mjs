// Vérifie que le SQL destiné à PostgreSQL s'exécute réellement sur PostgreSQL.
//
// La base de production ne doit pas être le premier endroit où ce SQL tourne :
// SERIAL, RETURNING, ON CONFLICT … EXCLUDED et les marqueurs $1 se comportent
// différemment de SQLite. PGlite est un vrai PostgreSQL (compilé en WASM), donc
// le dialecte est validé sans serveur à installer.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';

// Import sans DATABASE_URL : db.js démarre en SQLite, mais les constantes SQL
// exportées sont celles utilisées par le pilote PostgreSQL.
delete process.env.DATABASE_URL;
process.env.SWITCHMONEY_DB = ':memory:';
const { POSTGRES_SCHEMA, SQL } = await import('../db.js');

let pg;

before(async () => {
  pg = new PGlite();
  for (const statement of POSTGRES_SCHEMA) await pg.query(statement);
});

after(async () => {
  await pg?.close();
});

test('le schéma PostgreSQL se crée, et deux fois sans erreur', async () => {
  // CREATE TABLE IF NOT EXISTS doit être rejouable : Render relance le
  // processus à chaque déploiement.
  for (const statement of POSTGRES_SCHEMA) await pg.query(statement);
  const tables = await pg.query(
    "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename",
  );
  assert.deepEqual(tables.rows.map((r) => r.tablename), ['transactions', 'users']);
});

test('insertion d\'un utilisateur : SERIAL + RETURNING', async () => {
  const res = await pg.query(SQL.userInsert, [
    '22951469075', 'Elie Mensah', 'e@test.bj', 'hash', 'salt',
  ]);
  const user = res.rows[0];
  assert.equal(user.phone, '22951469075');
  assert.equal(user.name, 'Elie Mensah');
  assert.ok(Number.isInteger(user.id), 'id auto-incrémenté attendu');
  assert.ok(user.created_at, 'created_at renseigné par défaut');
});

test('le numéro est unique (contrainte 23505)', async () => {
  await assert.rejects(
    () => pg.query(SQL.userInsert, ['22951469075', 'Doublon', null, 'h', 's']),
    (err) => {
      // auth.js s'appuie sur ce code pour renvoyer un 409 plutôt qu'un 500.
      assert.equal(err.code ?? err.cause?.code, '23505');
      return true;
    },
  );
});

test('recherche par numéro et par identifiant', async () => {
  const byPhone = await pg.query(SQL.userByPhone, ['22951469075']);
  assert.equal(byPhone.rows.length, 1);

  const id = byPhone.rows[0].id;
  const byId = await pg.query(SQL.userById, [id]);
  assert.equal(byId.rows[0].phone, '22951469075');

  const absent = await pg.query(SQL.userByPhone, ['22900000000']);
  assert.equal(absent.rows.length, 0);
});

test('mise à jour du profil et du PIN', async () => {
  const { rows } = await pg.query(SQL.userByPhone, ['22951469075']);
  const id = rows[0].id;

  const updated = await pg.query(SQL.userUpdateProfile, ['Elie M.', 'new@test.bj', id]);
  assert.equal(updated.rows[0].name, 'Elie M.');
  assert.equal(updated.rows[0].email, 'new@test.bj');

  await pg.query(SQL.userUpdatePin, ['nouveau_hash', 'nouveau_sel', id]);
  const after = await pg.query(SQL.userById, [id]);
  assert.equal(after.rows[0].pin_hash, 'nouveau_hash');
});

test('COUNT renvoie un nombre exploitable', async () => {
  const { rows } = await pg.query(SQL.userCount);
  // PostgreSQL renvoie les bigint en chaîne : db.js applique Number().
  assert.equal(Number(rows[0].n), 1);
});

test('upsert de transaction : insertion puis mise à jour du même identifiant', async () => {
  const id = 'dep-001';
  const first = { type: 'transfer', status: 'ACCEPTED', userId: 42, meta: { amount: 5000 } };
  await pg.query(SQL.txUpsert, [id, 42, 'transfer', 'ACCEPTED', JSON.stringify(first)]);

  let res = await pg.query(SQL.txSelect, [id]);
  assert.equal(JSON.parse(res.rows[0].payload).status, 'ACCEPTED');

  const second = { ...first, status: 'COMPLETED' };
  await pg.query(SQL.txUpsert, [id, 42, 'transfer', 'COMPLETED', JSON.stringify(second)]);

  res = await pg.query(SQL.txSelect, [id]);
  assert.equal(JSON.parse(res.rows[0].payload).status, 'COMPLETED');

  const all = await pg.query(SQL.txSelectAll);
  assert.equal(all.rows.length, 1, 'l\'upsert ne doit pas dupliquer la ligne');
});

test('COALESCE préserve user_id quand la mise à jour ne le fournit pas', async () => {
  const id = 'dep-002';
  await pg.query(SQL.txUpsert, [id, 7, 'transfer', 'ACCEPTED', '{}']);
  // Un callback opérateur met à jour le statut sans connaître l'utilisateur.
  await pg.query(SQL.txUpsert, [id, null, 'transfer', 'COMPLETED', '{}']);

  const { rows } = await pg.query('SELECT user_id, status FROM transactions WHERE id = $1', [id]);
  assert.equal(rows[0].user_id, 7, 'le propriétaire ne doit pas être effacé');
  assert.equal(rows[0].status, 'COMPLETED');
});

test('les transactions sont cloisonnées par utilisateur', async () => {
  await pg.query(SQL.txUpsert, ['dep-003', 99, 'transfer', 'ACCEPTED', '{}']);

  const mine = await pg.query(SQL.txSelectByUser, [42]);
  assert.deepEqual(mine.rows.map((r) => r.id), ['dep-001']);

  const others = await pg.query(SQL.txSelectByUser, [99]);
  assert.deepEqual(others.rows.map((r) => r.id), ['dep-003']);
});
