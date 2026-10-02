import { expect, test } from '@playwright/test';
import { generateLicenseKey, validateLicenseKey } from '../../lib/license';

test('license generator produces valid keys matching Swift test vectors', () => {
  // Test vectors from LicenseValidatorTests.swift
  const vectors = ['BEEF1234', '00000000', 'FFFFFFFF', '0A1B2C3D'];
  for (const payload of vectors) {
    const key = generateLicenseKey(payload);
    expect(validateLicenseKey(key)).toBe(true);
    expect(key.startsWith(`BNDX-${payload.slice(0, 4)}-${payload.slice(4, 8)}-`)).toBe(true);
  }

  // Specifically check BEEF1234 checksum: 64 * 2654 = 169856 -> 0x9780
  expect(generateLicenseKey('BEEF1234')).toBe('BNDX-BEEF-1234-9780');
});

test('license generator produces valid random keys', () => {
  for (let i = 0; i < 10; i++) {
    const key = generateLicenseKey();
    expect(validateLicenseKey(key)).toBe(true);
  }
});

test('license validator rejects malformed and corrupted keys', () => {
  const badKeys = [
    '',
    'BNDX-BEEF-1234',                 // too few groups
    'XXXX-BEEF-1234-9780',            // wrong prefix
    'BNDX-BEEF-1234-0000',            // wrong checksum
    'BNDX-BEEF-1234-ZZZZ',            // non-hex checksum
    'BNDX-BEE-1234-9780',             // wrong group length
    'BNDX-GGGG-1234-9780',            // non-hex payload
  ];
  for (const key of badKeys) {
    expect(validateLicenseKey(key)).toBe(false);
  }
});
