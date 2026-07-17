// simple ESM script using global fetch
(async () => {
  try {
    const r = await fetch('http://localhost:3000/api/predict-provider', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ phoneNumber: '22951469075', expectedProvider: 'MTN BJ' })
    });
    console.log('client status', r.status);
    console.log('client body', await r.text());
  } catch (e) {
    console.error('client error', e);
  }
})();
