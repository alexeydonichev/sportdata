import { createCipheriv, createDecipheriv, randomBytes } from "crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;
const TAG_LENGTH = 16;

function getKey(): Buffer {
  const key = process.env.ENCRYPTION_KEY;
  if (!key || key.length !== 64) {
    throw new Error("ENCRYPTION_KEY must be a 64-char hex string (32 bytes)");
  }
  return Buffer.from(key, "hex");
}

/**
 * Encrypts plaintext with AES-256-GCM.
 * Returns: base64(iv + ciphertext + authTag)
 */
export function encrypt(plaintext: string): string {
  const key = getKey();
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  // iv (12) + ciphertext (variable) + tag (16)
  const result = Buffer.concat([iv, encrypted, tag]);
  return result.toString("base64");
}

/**
 * Decrypts base64(iv + ciphertext + authTag) back to plaintext.
 */
export function decrypt(encryptedBase64: string): string {
  const key = getKey();
  const data = Buffer.from(encryptedBase64, "base64");

  if (data.length < IV_LENGTH + TAG_LENGTH + 1) {
    throw new Error("Invalid encrypted data");
  }

  const iv = data.subarray(0, IV_LENGTH);
  const tag = data.subarray(data.length - TAG_LENGTH);
  const ciphertext = data.subarray(IV_LENGTH, data.length - TAG_LENGTH);

  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}

/**
 * Masks an API key for display: shows first 4 and last 4 chars.
 */
export function maskKey(key: string): string {
  if (key.length <= 8) return "****";
  return key.slice(0, 4) + "****" + key.slice(-4);
}
