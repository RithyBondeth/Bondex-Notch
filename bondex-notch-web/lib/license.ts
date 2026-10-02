import { createHash, randomBytes } from 'node:crypto';

/**
 * Validates a Bondex Notch offline license key against the BNDX-XXXX-XXXX-XXXX format and checksum.
 */
export function validateLicenseKey(rawKey: string): boolean {
  const key = rawKey.toUpperCase().trim();
  const groups = key.split('-');
  if (groups.length !== 4 || groups[0] !== 'BNDX') return false;
  if (!groups.slice(1).every((g) => g.length === 4 && /^[0-9A-F]{4}$/.test(g))) {
    return false;
  }

  const payload = groups[1] + groups[2];
  let sum = 0;
  for (let i = 0; i < payload.length; i++) {
    sum += parseInt(payload[i], 16);
  }
  const checksum = ((sum * 2654) & 0xffff).toString(16).toUpperCase().padStart(4, '0');
  return groups[3] === checksum;
}

/**
 * Generates an offline license key matching the macOS app's LicenseValidator.
 * If no 8-hex-digit payload is supplied, a random or deterministic seed hash is used.
 */
export function generateLicenseKey(seed?: string): string {
  let payload: string;
  if (seed) {
    if (/^[0-9A-Fa-f]{8}$/.test(seed)) {
      payload = seed.toUpperCase();
    } else {
      payload = createHash('sha256').update(seed).digest('hex').slice(0, 8).toUpperCase();
    }
  } else {
    payload = randomBytes(4).toString('hex').toUpperCase();
  }

  let sum = 0;
  for (let i = 0; i < payload.length; i++) {
    sum += parseInt(payload[i], 16);
  }
  const checksum = ((sum * 2654) & 0xffff).toString(16).toUpperCase().padStart(4, '0');
  const a = payload.slice(0, 4);
  const b = payload.slice(4, 8);
  return `BNDX-${a}-${b}-${checksum}`;
}
