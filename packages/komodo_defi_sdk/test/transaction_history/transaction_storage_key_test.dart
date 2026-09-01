import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';

void main() {
  final wallet = testWallet();
  final asset = testAssetId();

  group('key layout', () {
    test('is fixed-width up to the trailing id', () {
      final key = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        internalId: 'tx-0',
      );

      expect(key, matches(RegExp(r'^[0-9a-f]{20}\|[0-9a-f]{20}\|\d{16}\|.+$')));
    });

    test('parse inverts build', () {
      final prefix = TransactionStorageKey.prefix(wallet, asset);
      final timestamp = DateTime.utc(2026, 7, 10, 11, 12, 13, 140, 150);
      final key = TransactionStorageKey.build(
        prefix: prefix,
        timestamp: timestamp,
        internalId: 'tx-0',
      );

      final parts = TransactionStorageKey.parse(key)!;
      expect(parts.prefix, prefix);
      expect(parts.idToken, 'tx-0');
      expect(parts.idTokenIsHashed, isFalse);
      expect(parts.timestampMicros, timestamp.microsecondsSinceEpoch);
    });

    test('parse handles an internal id containing the separator', () {
      const internalId = 'weird|id|with|pipes';
      final key = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        internalId: internalId,
      );

      expect(TransactionStorageKey.parse(key)!.idToken, internalId);
    });

    test('parse rejects malformed keys', () {
      for (final malformed in [
        '',
        'nope',
        'short|short|123|tx',
        // Right shape, wrong widths.
        '${'a' * 19}|${'b' * 20}|${'0' * 16}|tx',
        '${'a' * 20}|${'b' * 20}|${'0' * 15}|tx',
        // Missing the trailing id.
        '${'a' * 20}|${'b' * 20}|${'0' * 16}|',
      ]) {
        expect(
          TransactionStorageKey.parse(malformed),
          isNull,
          reason: 'should reject "$malformed"',
        );
      }
    });
  });

  group('length guard', () {
    test('a realistic key is far inside the limit', () {
      final key = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        // A TRON tx hash, which is the long end of what KDF actually returns.
        internalId: 'a' * 64,
      );
      expect(utf8.encode(key).length, lessThan(150));
    });

    test('hashes an over-budget internal id instead of overflowing', () {
      final key = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        internalId: 'z' * 5000,
      );

      expect(
        utf8.encode(key).length,
        lessThanOrEqualTo(TransactionStorageKey.maxKeyBytes),
      );
      expect(TransactionStorageKey.parse(key)!.idTokenIsHashed, isTrue);
    });

    test('the budget counts UTF-8 bytes, not code units', () {
      // Four bytes per code unit, so 60 characters is 240 bytes: over the
      // 190-byte token budget even though the string is short.
      final key = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        internalId: '\u{1F600}' * 60,
      );

      expect(
        utf8.encode(key).length,
        lessThanOrEqualTo(TransactionStorageKey.maxKeyBytes),
      );
      expect(TransactionStorageKey.parse(key)!.idTokenIsHashed, isTrue);
    });

    test('distinct over-budget ids hash to distinct keys', () {
      String keyFor(String id) => TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(2026, 7, 10),
        internalId: id,
      );

      expect(keyFor('a' * 5000), isNot(keyFor('${'a' * 4999}b')));
    });

    test('refuses to emit a key over the Hive limit', () {
      // Hive writes the key length as a single unvalidated byte, so an
      // over-long key would wrap it and corrupt the box rather than fail.
      expect(
        () => TransactionStorageKey.build(
          prefix: 'x' * 300,
          timestamp: DateTime.utc(2026, 7, 10),
          internalId: 'tx-0',
        ),
        throwsA(isA<TransactionStorageException>()),
      );
    });
  });

  group('timestamp encoding', () {
    test('is monotonic in the encoded string order', () {
      final earlier = TransactionStorageKey.encodeTimestamp(
        DateTime.utc(2026, 7, 10),
      );
      final later = TransactionStorageKey.encodeTimestamp(
        DateTime.utc(2026, 7, 11),
      );
      expect(earlier.compareTo(later), isNegative);
    });

    test('preserves microsecond resolution', () {
      final a = DateTime.utc(2026, 7, 10, 0, 0, 0, 0, 1);
      final b = DateTime.utc(2026, 7, 10, 0, 0, 0, 0, 2);
      expect(
        TransactionStorageKey.encodeTimestamp(a),
        isNot(TransactionStorageKey.encodeTimestamp(b)),
      );
    });

    test('clamps pre-epoch timestamps to zero', () {
      expect(
        TransactionStorageKey.encodeTimestamp(DateTime.utc(1900)),
        '0' * TransactionStorageKey.timestampLength,
      );
    });

    test('stays fixed-width for far-future timestamps', () {
      expect(
        TransactionStorageKey.encodeTimestamp(DateTime.utc(9999, 12, 31)),
        hasLength(TransactionStorageKey.timestampLength),
      );
    });
  });

  group('asset tokens', () {
    test('equal assets produce equal tokens', () {
      expect(
        TransactionStorageKey.assetToken(testAssetId()),
        TransactionStorageKey.assetToken(
          // Same props, different incidental metadata.
          testAssetId(name: 'Tether USD', derivationPath: null),
        ),
      );
    });

    test('differing assets produce differing tokens', () {
      final base = TransactionStorageKey.assetToken(testAssetId());
      final byId = TransactionStorageKey.assetToken(testAssetId(id: 'KMD'));
      final bySubClass = TransactionStorageKey.assetToken(
        testAssetId(subClass: CoinSubClass.erc20),
      );
      final byChain = TransactionStorageKey.assetToken(
        testAssetId(chainId: AssetChainId(chainId: 1)),
      );

      expect({base, byId, bySubClass, byChain}, hasLength(4));
    });

    test('no asset prefix contains another', () {
      final prefixes = [
        for (final assetId in [
          testAssetId(),
          testAssetId(id: 'KMD'),
          testAssetId(subClass: CoinSubClass.erc20),
        ])
          TransactionStorageKey.prefix(wallet, assetId),
      ];

      for (final a in prefixes) {
        for (final b in prefixes) {
          if (identical(a, b)) continue;
          expect(a.startsWith(b), isFalse);
        }
      }
    });
  });

  group('wallet tokens', () {
    test('isolate derivation methods', () {
      expect(
        TransactionStorageKey.walletToken(testWallet()),
        isNot(
          TransactionStorageKey.walletToken(
            testWallet(derivationMethod: DerivationMethod.iguana),
          ),
        ),
      );
    });

    test('isolate private key policies', () {
      final tokens = {
        TransactionStorageKey.walletToken(testWallet()),
        TransactionStorageKey.walletToken(
          testWallet(privKeyPolicy: const PrivateKeyPolicy.trezor()),
        ),
        TransactionStorageKey.walletToken(
          testWallet(
            privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-a'),
          ),
        ),
        TransactionStorageKey.walletToken(
          testWallet(
            privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-b'),
          ),
        ),
      };
      expect(tokens, hasLength(4));
    });

    test('isolate pubkey hashes', () {
      expect(
        TransactionStorageKey.walletToken(testWallet(pubkeyHash: 'aaaa')),
        isNot(
          TransactionStorageKey.walletToken(testWallet(pubkeyHash: 'bbbb')),
        ),
      );
    });

    test('are hex, so they can never contain the separator', () {
      expect(
        TransactionStorageKey.walletToken(testWallet()),
        matches(RegExp('^[0-9a-f]{${TransactionStorageKey.tokenLength}}\$')),
      );
    });
  });
}
