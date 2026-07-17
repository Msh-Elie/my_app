const { mapProviderToPawaPay } = require('./server');

console.log('MTN BJ ->', mapProviderToPawaPay('MTN BJ'));
console.log('MTN_BJ ->', mapProviderToPawaPay('MTN_BJ'));
console.log('CELTIS BJ ->', mapProviderToPawaPay('CELTIS BJ'));
console.log('FOO BAR ->', mapProviderToPawaPay('FOO BAR'));
