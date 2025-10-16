// supabase/functions/_shared/cursor.ts
// Secure cursor encoding/decoding with HMAC signature
// Prevents cursor tampering for pagination

/**
 * Cursor format: base64(created_at,id) + "." + HMAC signature
 * Example: "MjAyNS0wMS0wMVQxMjowMDowMFosaHR0cHM6Ly9leGFtcGxl.a3b2c1d4e5f6"
 */

const HMAC_ALGORITHM = "HMAC";
const HASH_ALGORITHM = "SHA-256";

interface CursorData {
  created_at: string; // ISO 8601 timestamp
  id: string;         // UUID
}

/**
 * Get cursor secret from environment
 * CRITICAL: Set CURSOR_SECRET in Supabase Edge Function secrets
 */
function getCursorSecret(): string {
  const secret = Deno.env.get("CURSOR_SECRET");
  if (!secret) {
    throw new Error("CURSOR_SECRET environment variable not set");
  }
  return secret;
}

/**
 * Generate HMAC signature for cursor data
 */
async function generateSignature(data: string): Promise<string> {
  const secret = getCursorSecret();
  const encoder = new TextEncoder();
  
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: HMAC_ALGORITHM, hash: HASH_ALGORITHM },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    HMAC_ALGORITHM,
    key,
    encoder.encode(data)
  );

  // Convert to hex string
  return Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Encode cursor data into a secure token
 * Returns: base64(created_at,id).signature
 */
export async function encodeCursor(data: CursorData): Promise<string> {
  // Format: created_at,id
  const payload = `${data.created_at},${data.id}`;
  
  // Base64 encode the payload
  const encoder = new TextEncoder();
  const base64Payload = btoa(String.fromCharCode(...encoder.encode(payload)));
  
  // Generate HMAC signature
  const signature = await generateSignature(base64Payload);
  
  // Combine: base64.signature
  return `${base64Payload}.${signature}`;
}

/**
 * Decode and verify cursor token
 * Throws error if signature is invalid or format is wrong
 */
export async function decodeCursor(token: string): Promise<CursorData> {
  // Split token into payload and signature
  const parts = token.split('.');
  if (parts.length !== 2) {
    throw new Error("Invalid cursor format");
  }

  const [base64Payload, providedSignature] = parts;

  // Verify signature
  const expectedSignature = await generateSignature(base64Payload);
  if (providedSignature !== expectedSignature) {
    throw new Error("Invalid cursor signature");
  }

  // Decode base64 payload
  const decoder = new TextDecoder();
  const decodedBytes = Uint8Array.from(atob(base64Payload), c => c.charCodeAt(0));
  const payload = decoder.decode(decodedBytes);

  // Parse payload: created_at,id
  const [created_at, id] = payload.split(',');
  if (!created_at || !id) {
    throw new Error("Invalid cursor data format");
  }

  // Validate timestamp format (basic check)
  if (isNaN(Date.parse(created_at))) {
    throw new Error("Invalid timestamp in cursor");
  }

  // Validate UUID format (basic check)
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(id)) {
    throw new Error("Invalid UUID in cursor");
  }

  return { created_at, id };
}

/**
 * Example usage in an Edge Function:
 * 
 * import { encodeCursor, decodeCursor } from '../_shared/cursor.ts';
 * 
 * // Encoding (when returning results):
 * const cursor = await encodeCursor({
 *   created_at: row.created_at,
 *   id: row.id
 * });
 * 
 * // Decoding (when receiving cursor from client):
 * try {
 *   const { created_at, id } = await decodeCursor(cursorParam);
 *   // Use in WHERE clause: WHERE (created_at, id) < ($1, $2)
 * } catch (error) {
 *   return new Response(JSON.stringify({ error: "Invalid cursor" }), { 
 *     status: 400 
 *   });
 * }
 */