# External Recipient Lookup Microservice API Specification

## Overview
The SwitchMoney backend integrates with an optional external recipient lookup service to resolve beneficiary names from phone numbers. This document defines the exact API contract.

## Configuration
Set these environment variables in your `.env` file to enable the service:

```env
RECIPIENT_LOOKUP_URL=https://your-api.example.com/lookup
RECIPIENT_LOOKUP_TOKEN=your-bearer-token
```

## Request Format

**Method:** POST  
**URL:** `{RECIPIENT_LOOKUP_URL}`  
**Authentication:** Bearer token in `Authorization` header

### Request Headers
```
Authorization: Bearer {RECIPIENT_LOOKUP_TOKEN}
Content-Type: application/json
```

### Request Body
```json
{
  "phoneNumber": "22951469075",
  "provider": "MTN BJ"
}
```

**Fields:**
- `phoneNumber` (string, required): Full phone number with country code. Examples: "22951469075" (Benin), "2348123456789" (Nigeria)
- `provider` (string, required): Network operator name with country code. Examples: "MTN BJ", "MTN NG", "ORANGE SN"

## Response Format

### Success Response (200 OK)
The service should return HTTP 200 with a JSON object containing **at least one** of these name fields:

```json
{
  "name": "John Doe",
  "phoneNumber": "22951469075",
  "customerId": "CUST12345"
}
```

**Name Field Candidates** (backend searches in this order):
1. `name`
2. `fullName`
3. `displayName`
4. `customerName`
5. `firstName` + `lastName` (concatenated with space)
6. `accountName`
7. `beneficiaryName`
8. `recipientName`
9. `givenName`
10. `surname`
11. `label`
12. `value`
13. `identity`
14. `username`

**Important:** Any additional fields in the response are ignored; only name extraction is performed.

### Error Cases

The backend gracefully handles all error scenarios. Your service can respond with:

#### Name Not Found (200 OK)
```json
{
  "phoneNumber": "22951469075",
  "provider": "MTN BJ",
  "status": "not_found"
}
```
*Backend will fall back to: `"Compte MTN • 3456"` (derived from phone suffix + provider)*

#### Service Timeout
*No response within 10 seconds*  
→ Backend falls back to derived label

#### Service Error (5xx or other status)
*Any HTTP error response*  
→ Backend falls back to derived label

#### Invalid Request Format
*Missing phoneNumber or provider*  
→ Backend validates input before calling your service; invalid requests never reach the external API

## Implementation Example

### Minimal Implementation (Mock Service)
```javascript
// backend/recipient_lookup_mock.mjs
export async function resolveRecipient(phoneNumber, provider) {
  // Mock database lookup
  const recipients = {
    "22951469075|MTN BJ": { name: "Alain Dossou" },
    "2348123456789|MTN NG": { name: "Chioma Obi" },
  };
  
  const key = `${phoneNumber}|${provider}`;
  const result = recipients[key];
  
  if (result) {
    return { name: result.name };
  }
  
  // Return empty object if not found (backend will derive label)
  return {};
}
```

### Response Time Requirements
- **Target:** < 500ms (matches frontend debounce)
- **Max:** 10s (hard timeout in backend)
- Responses slower than 500ms will miss the UI update but won't block the user

## Backend Integration Details

When you call the endpoint from your frontend (automatic on valid phone number):

```
POST /api/resolve-recipient
{
  "phoneNumber": "22951469075",
  "provider": "MTN BJ"
}
```

The backend will:
1. Validate inputs
2. Call `{RECIPIENT_LOOKUP_URL}` with your phone number and provider
3. Extract name from response (searches 14 name field candidates)
4. Return resolved name in response field `displayName`
5. Set `resolved: true` if name was found, `false` if derived

### Example Backend Response (from frontend)
```json
{
  "resolved": true,
  "source": "external",
  "displayName": "Alain Dossou",
  "reason": "lookup_success"
}
```

Or with fallback:
```json
{
  "resolved": false,
  "source": "derived",
  "displayName": "Compte MTN • 3456",
  "reason": "lookup_not_configured"
}
```

## Frontend Integration

Once your external service is configured:

1. User enters valid phone number → automatically triggers `_lookupRecipientIdentity()`
2. Backend is called with 500ms debounce
3. Confirmation page updates with resolved name
4. Badge changes to green ("Nom vérifié") when name is resolved
5. Transfer payload includes the resolved or derived name

## Testing Your Service

### Test Case 1: Valid Recipient
```bash
curl -X POST https://your-api.example.com/lookup \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Expected backend response:
```json
{
  "resolved": true,
  "source": "external",
  "displayName": "John Doe",
  "reason": "lookup_success"
}
```

### Test Case 2: Recipient Not Found
```bash
curl -X POST https://your-api.example.com/lookup \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "11111111111",
    "provider": "UNKNOWN"
  }'
```

Expected backend response:
```json
{
  "resolved": false,
  "source": "derived",
  "displayName": "Compte UNKNOWN • 1111",
  "reason": "name_not_found"
}
```

### Test Case 3: Service Disabled (No RECIPIENT_LOOKUP_URL)
```bash
# With RECIPIENT_LOOKUP_URL not set
curl -X POST http://localhost:3000/api/resolve-recipient \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "22951469075",
    "provider": "MTN BJ"
  }'
```

Expected response:
```json
{
  "resolved": false,
  "source": "derived",
  "displayName": "Compte MTN • 3456",
  "reason": "lookup_not_configured"
}
```

## Database Integration Tips

If you're querying a database for recipient names:

1. **Key by phone + provider** (most reliable)
   ```sql
   SELECT name FROM recipients 
   WHERE phone = '22951469075' AND provider = 'MTN BJ'
   ```

2. **Or key by phone only** (if provider varies)
   ```sql
   SELECT name FROM recipients 
   WHERE phone LIKE '%951469075'
   ```

3. **Handle multiple matches gracefully**
   - Return first match
   - Or return most recent registration
   - Or return highest balance account

## Performance Optimization

- **Cache frequent lookups** (popular recipients checked repeatedly)
- **Pre-index on phone number** for fast queries
- **Consider response time SLAs**: < 500ms optimal, ≤ 2s acceptable, > 10s will timeout
- **Handle bulk requests** if frontend performs multiple lookups in succession

## Security Recommendations

- **Do not expose PII in logs** (phone numbers may be sensitive)
- **Validate RECIPIENT_LOOKUP_TOKEN** on every request
- **Rate limit per token** to prevent abuse
- **HTTPS only** for all requests
- **Validate input format** in your service (phone should be 7-15 digits, provider format expected)

## Debugging

Enable debug logging in backend (set `DEBUG=*`):
```bash
DEBUG=* node backend/server.js
```

This will show:
- POST request to your lookup service
- Response received
- Name extraction details
- Final displayName returned to frontend

## Fallback Behavior

If your service is unreachable, slow, or returns errors:

**Frontend sees:** Name still displays correctly (derived as `"Compte MTN • 3456"`)  
**Transfer proceeds:** Unaffected, includes the fallback name  
**Badge shows:** "Secure check" (orange) instead of "Nom vérifié" (green)

The system is designed for **non-blocking graceful degradation**.
