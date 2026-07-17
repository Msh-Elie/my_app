import { sanitizeMetadata } from './server.js';

const samples = [
  { fieldName: 'a', fieldValue: '1' },          // old incorrect style
  { fieldName: 'fieldValue', fieldValue: 'oops' },
  { fieldName: 'a', fieldValue: 'dup' },
  { fieldValue: 'noName' },
  null,
  { fieldName: 'b', fieldValue: '2' },
  { orderId: 'ORD-1' },                         // already correct style
  { customerId: 'user', isPII: true },          // object with two keys
];
console.log('input:', samples);
console.log('output:', sanitizeMetadata(samples));
