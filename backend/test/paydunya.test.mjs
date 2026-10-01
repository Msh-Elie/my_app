// Tests du rail PayDunya : les fonctions pures (routage, format de numéro,
// normalisation des statuts) sont vérifiables sans clés ni réseau.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

process.env.PAYDUNYA_MASTER_KEY = 'test-master';
process.env.PAYDUNYA_PRIVATE_KEY = 'test-private';
process.env.PAYDUNYA_TOKEN = 'test-token';

const paydunya = await import('../paydunya.js');

describe('couverture des opérateurs', () => {
  test('Celtis est reconnu, quelle que soit son orthographe', () => {
    assert.equal(paydunya.supportsProvider('CELTIS BJ'), true);
    assert.equal(paydunya.supportsProvider('CELTIIS BJ'), true);
    assert.equal(paydunya.supportsProvider('celtis bj'), true);
    assert.equal(paydunya.withdrawModeFor('CELTIS BJ'), 'celtiis-cash');
  });

  test('les opérateurs servis par PawaPay ne sont pas détournés', () => {
    // MTN et Moov passent par PawaPay : les router ici serait une régression.
    assert.equal(paydunya.supportsProvider('MTN BJ'), false);
    assert.equal(paydunya.supportsProvider('MOOV BJ'), false);
    assert.equal(paydunya.supportsProvider('WAVE CI'), false);
    assert.equal(paydunya.withdrawModeFor('MTN BJ'), null);
  });

  test('un libellé vide ou inconnu ne casse rien', () => {
    assert.equal(paydunya.supportsProvider(''), false);
    assert.equal(paydunya.supportsProvider(null), false);
    assert.equal(paydunya.supportsProvider('TRUC XX'), false);
  });
});

describe('format du numéro de bénéficiaire', () => {
  // PayDunya attend `account_alias` sans indicatif pays : le laisser
  // désignerait un compte inexistant, et l'argent partirait dans le vide.
  test("retire l'indicatif du Bénin", () => {
    assert.equal(paydunya.toLocalNumber('2290151469075'), '0151469075');
    assert.equal(paydunya.toLocalNumber('+229 01 51 46 90 75'), '0151469075');
  });

  test('laisse un numéro déjà local intact', () => {
    assert.equal(paydunya.toLocalNumber('0151469075'), '0151469075');
  });

  test('tolère les entrées vides', () => {
    assert.equal(paydunya.toLocalNumber(''), '');
    assert.equal(paydunya.toLocalNumber(null), '');
  });
});

describe('normalisation des statuts de déboursement', () => {
  test('seul « success » vaut un succès', () => {
    assert.equal(paydunya.normalizeDisburseStatus('success'), 'COMPLETED');
    assert.equal(paydunya.normalizeDisburseStatus('SUCCESS'), 'COMPLETED');
  });

  test('« failed » est un échec définitif', () => {
    assert.equal(paydunya.normalizeDisburseStatus('failed'), 'FAILED');
  });

  test('tout le reste reste en cours', () => {
    // Traiter un statut inconnu comme un succès libérerait un transfert non
    // confirmé : le repli doit toujours être « en cours ».
    for (const raw of ['created', 'pending', '', null, undefined, 'bizarre']) {
      assert.equal(paydunya.normalizeDisburseStatus(raw), 'ACCEPTED');
    }
  });
});

describe('normalisation des statuts de facture', () => {
  test('« completed » vaut un succès', () => {
    assert.equal(paydunya.normalizeCheckoutStatus('completed'), 'COMPLETED');
  });

  test('annulation et échec sont définitifs', () => {
    assert.equal(paydunya.normalizeCheckoutStatus('cancelled'), 'FAILED');
    assert.equal(paydunya.normalizeCheckoutStatus('canceled'), 'FAILED');
    assert.equal(paydunya.normalizeCheckoutStatus('failed'), 'FAILED');
  });

  test('« pending » et l\'inconnu restent en cours', () => {
    for (const raw of ['pending', '', null, 'autre']) {
      assert.equal(paydunya.normalizeCheckoutStatus(raw), 'ACCEPTED');
    }
  });
});

describe('disponibilité du rail', () => {
  test('les clés présentes suffisent à décaisser', () => {
    // Contrairement à FedaPay, aucun droit supplémentaire n'est à obtenir.
    assert.equal(paydunya.PAYDUNYA_ENABLED, true);
    assert.equal(paydunya.paydunyaPayoutsAvailable(), true);
  });

  test('un opérateur non couvert est refusé avant tout appel réseau', async () => {
    await assert.rejects(
      () => paydunya.paydunyaInitiatePayout({
        amount: 1000,
        phoneNumber: '2290151469075',
        provider: 'MTN BJ',
      }),
      /non couvert par PayDunya/,
    );
  });
});
