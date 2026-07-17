const fee = 100, payoutAmount = 1900;
const depositBody = {
  depositId: 'test',
  payer: { type: 'MMO', accountDetails: { phoneNumber: '2290151469075', provider: 'MTN_MOMO_BEN' } },
  clientReferenceId: 'INV-test',
  customerMessage: 'Transfert Flutter',
  amount: '2000',
  currency: 'XOF',
  metadata: [
    { fieldName: 'transfer_type', fieldValue: 'peer_to_peer' },
    { fieldName: 'fee', fieldValue: String(fee) },
    { fieldName: 'payoutAmount', fieldValue: String(payoutAmount) }
  ]
};
console.log(JSON.stringify(depositBody, null, 2));
