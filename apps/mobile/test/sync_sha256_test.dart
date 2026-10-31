// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/sync/sha256.dart';

/// The sync ledger keys everything on SHA-256 (account keys, day fingerprints).
/// These vectors are FIPS 180-4 / NIST examples plus lengths on both sides of the
/// padding boundaries, produced independently with Python's hashlib.
void main() {
  const vectors = <String, String>{
    '': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq':
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu':
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
    'Zażółć gęślą jaźń ⚡':
        'b7ea028737b4ece03231e74d321fe0f56cb4bff60b1ab16caceb44b83bc86ca0',
  };

  vectors.forEach((input, digest) {
    test(
        'SHA-256 of "${input.length > 20 ? '${input.substring(0, 20)}...' : input}"',
        () {
      expect(sha256Hex(input), digest);
    });
  });

  test('lengths around the 55/56/63/64-byte padding boundaries', () {
    const expected = {
      55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
      56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
      57: 'f13b2d724659eb3bf47f2dd6af1accc87b81f09f59f2b75e5c0bed6589dfe8c6',
      63: '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34',
      64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
      65: '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0',
      119: '31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb',
      120: '2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c',
      128: '6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e',
    };
    expected.forEach((n, digest) {
      expect(sha256Hex('a' * n), digest, reason: '$n bytes');
    });
  });

  test('one million "a" (multi-block message)', () {
    expect(sha256Bytes(List.filled(1000000, 0x61)).length, 32);
    expect(
        sha256Bytes(List.filled(1000000, 0x61))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('bytes and string entry points agree (UTF-8)', () {
    const s = 'Zażółć';
    expect(
        sha256Bytes(utf8.encode(s))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        sha256Hex(s));
  });

  test('account-key shaped input matches the reference value', () {
    expect(
        sha256Hex('0123456789abcdef0123456789abcdef:user-1').substring(0, 32),
        '6fef94d3fa62ad6e494b6a51d1e41433');
  });
}
