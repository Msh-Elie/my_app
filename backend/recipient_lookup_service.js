import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

// Mock database - in production, replace with real DB (PostgreSQL, MongoDB, etc)
const recipientDatabase = {
  // Benin (BJ)
  '22951469075': { name: 'Alain Dossou', phone: '22951469075', provider: 'MTN BJ' },
  '22964502183': { name: 'Carole Azanmedi', phone: '22964502183', provider: 'MOOV BJ' },
  '22966135792': { name: 'Ibrahim Sahi', phone: '22966135792', provider: 'CELTIS BJ' },
  
  // Nigeria (NG)
  '2348123456789': { name: 'Chioma Obi', phone: '2348123456789', provider: 'MTN NG' },
  '2349012345678': { name: 'Tunde Olawale', phone: '2349012345678', provider: 'GLO NG' },
  '2347030000000': { name: 'Amarachi Eze', phone: '2347030000000', provider: 'AIRTEL NG' },
  '2348093000000': { name: 'Seun Adebayo', phone: '2348093000000', provider: '9MOBILE NG' },
  
  // Senegal (SN)
  '221701234567': { name: 'Fatou Ndiaye', phone: '221701234567', provider: 'ORANGE SN' },
  '221764123456': { name: 'Moussa Sarr', phone: '221764123456', provider: 'SONATEL SN' },
  '221757654321': { name: 'Aissatou Diallo', phone: '221757654321', provider: 'FREE SN' },
  
  // Ghana (GH)
  '233242123456': { name: 'Kwame Asante', phone: '233242123456', provider: 'MTN GH' },
  '233501234567': { name: 'Ama Mensah', phone: '233501234567', provider: 'VODAFONE GH' },
  '233551234567': { name: 'Kofi Appiah', phone: '233551234567', provider: 'AIRTEL GH' },
  
  // Mali (ML)
  '223765432109': { name: 'Daouda Toure', phone: '223765432109', provider: 'ORANGE ML' },
  '223698123456': { name: 'Fatoumata Ba', phone: '223698123456', provider: 'SOTELMA ML' },
  
  // South Africa (ZA)
  '27721234567': { name: 'Mandla Nkosi', phone: '27721234567', provider: 'MTN ZA' },
  '27741234567': { name: 'Thandi Mkhize', phone: '27741234567', provider: 'VODACOM ZA' },
  
  // Kenya (KE)
  '254701234567': { name: 'David Kipchoge', phone: '254701234567', provider: 'SAFARICOM KE' },
  '254702345678': { name: 'Zainab Hassan', phone: '254702345678', provider: 'AIRTEL KE' },
  
  // Morocco (MA)
  '212612345678': { name: 'Ahmed Ben Youssef', phone: '212612345678', provider: 'MAROC TELECOM' },
  '212661234567': { name: 'Leila El Mouhssine', phone: '212661234567', provider: 'ORANGE MA' },
  
  // Côte d'Ivoire (CI)
  '22501234567': { name: 'Kofi Mensah', phone: '22501234567', provider: 'MTN CI' },
  '22507123456': { name: 'Yolande Kouassi', phone: '22507123456', provider: 'ORANGE CI' },
};

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'recipient-lookup', timestamp: new Date() });
});

/**
 * Main lookup endpoint
 * POST /lookup
 * 
 * Request:
 * {
 *   "phoneNumber": "22951469075",
 *   "provider": "MTN BJ"
 * }
 * 
 * Response:
 * {
 *   "resolved": true,
 *   "name": "Alain Dossou",
 *   "phoneNumber": "22951469075",
 *   "provider": "MTN BJ"
 * }
 */
app.post('/lookup', async (req, res) => {
  try {
    const { phoneNumber, provider } = req.body;

    // Validate input
    if (!phoneNumber || !provider) {
      return res.status(400).json({
        resolved: false,
        reason: 'missing_fields',
        message: 'phoneNumber and provider are required',
      });
    }

    // Normalize phone number (remove spaces, dashes)
    const normalizedPhone = phoneNumber.replace(/[\s\-()]/g, '');

    // Simulate network delay (optional - removes for instant responses)
    // await new Promise(resolve => setTimeout(resolve, Math.random() * 300));

    // Look up in database
    const recipient = recipientDatabase[normalizedPhone];

    if (recipient) {
      // Success case
      return res.json({
        resolved: true,
        name: recipient.name,
        phoneNumber: recipient.phone,
        provider: recipient.provider,
        displayName: recipient.name,
        timestamp: new Date(),
      });
    }

    // Recipient not found - still return 200 with resolved: false
    // This allows the backend to fall back to derived label
    return res.json({
      resolved: false,
      phoneNumber: normalizedPhone,
      provider,
      reason: 'not_found',
      message: `No recipient found for ${normalizedPhone}`,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error('Lookup error:', error);
    return res.json({
      resolved: false,
      reason: 'server_error',
      message: error.message,
      timestamp: new Date(),
    });
  }
});

/**
 * Batch lookup endpoint (optional)
 * POST /lookup/batch
 * 
 * Useful if frontend needs to lookup multiple recipients at once
 */
app.post('/lookup/batch', async (req, res) => {
  try {
    const { recipients } = req.body; // array of {phoneNumber, provider}

    if (!Array.isArray(recipients)) {
      return res.status(400).json({
        error: 'recipients must be an array',
      });
    }

    const results = recipients.map(({ phoneNumber, provider }) => {
      const normalizedPhone = phoneNumber.replace(/[\s\-()]/g, '');
      const recipient = recipientDatabase[normalizedPhone];

      if (recipient) {
        return {
          resolved: true,
          phoneNumber: recipient.phone,
          provider: recipient.provider,
          name: recipient.name,
          displayName: recipient.name,
        };
      }

      return {
        resolved: false,
        phoneNumber: normalizedPhone,
        provider,
        reason: 'not_found',
      };
    });

    return res.json({ results, timestamp: new Date() });
  } catch (error) {
    console.error('Batch lookup error:', error);
    return res.status(500).json({
      error: error.message,
      timestamp: new Date(),
    });
  }
});

/**
 * List all recipients (for testing/admin)
 * GET /recipients
 */
app.get('/recipients', (req, res) => {
  const recipients = Object.values(recipientDatabase);
  res.json({
    total: recipients.length,
    recipients,
  });
});

/**
 * Add recipient (for testing/admin)
 * POST /recipients
 */
app.post('/recipients', express.json(), (req, res) => {
  const { phoneNumber, name, provider } = req.body;

  if (!phoneNumber || !name || !provider) {
    return res.status(400).json({
      error: 'phoneNumber, name, and provider are required',
    });
  }

  const normalizedPhone = phoneNumber.replace(/[\s\-()]/g, '');
  recipientDatabase[normalizedPhone] = {
    name,
    phone: normalizedPhone,
    provider,
  };

  res.status(201).json({
    message: 'Recipient added',
    phoneNumber: normalizedPhone,
    name,
    provider,
  });
});

/**
 * Delete recipient (for testing/admin)
 * DELETE /recipients/:phoneNumber
 */
app.delete('/recipients/:phoneNumber', (req, res) => {
  const { phoneNumber } = req.params;
  if (recipientDatabase[phoneNumber]) {
    delete recipientDatabase[phoneNumber];
    return res.json({ message: 'Recipient deleted', phoneNumber });
  }
  res.status(404).json({ error: 'Recipient not found' });
});

// Error handling
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: err.message,
    timestamp: new Date(),
  });
});

const PORT = process.env.RECIPIENT_LOOKUP_PORT || 3001;

app.listen(PORT, () => {
  console.log(`🔍 Recipient Lookup Service running on http://localhost:${PORT}`);
  console.log(`   POST http://localhost:${PORT}/lookup - Lookup recipient`);
  console.log(`   GET  http://localhost:${PORT}/health - Health check`);
  console.log(`   GET  http://localhost:${PORT}/recipients - List all recipients`);
});
