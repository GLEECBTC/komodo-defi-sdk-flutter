@TestOn('browser')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_storage_keys.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

const _originalWallet = WalletId(
  name: 'gasfree-web-prefix-original',
  pubkeyHash: 'gasfree-web-prefix-public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _renamedWallet = WalletId(
  name: 'gasfree-web-prefix-renamed',
  pubkeyHash: 'gasfree-web-prefix-public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);

final class _UnreadableDiscoveredWebStorage
    implements GaslessTransferKeyValueStorage, GaslessTransferKeyDiscovery {
  _UnreadableDiscoveredWebStorage(this.unreadableKey);

  final String unreadableKey;

  @override
  Future<bool> containsKey(String key) async => key == unreadableKey;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<Set<String>> keysWithPrefix(String prefix, {required int maxKeys}) {
    return discoverSecureStorageKeysWithPrefix(
      const FlutterSecureStorage(),
      prefix,
      maxKeys: maxKeys,
    );
  }

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('Unexpected write to unreadable journal');
  }
}

void main() {
  test(
    'web prefix discovery recovers a V1 journal renamed before discovery',
    () async {
      final namespace = walletStorageNamespace(_renamedWallet);
      final legacyKey =
          'gasless_pending_transfers_v1_'
          '${sha256.convert(utf8.encode(_originalWallet.compoundId))}';
      final currentKey = 'gasless_pending_transfers_v3_$namespace';
      final aliasKey = 'gasless_pending_transfers_legacy_aliases_v2_$namespace';
      final resolutionKey =
          'gasless_pending_transfers_legacy_resolution_v1_$namespace';

      final acceptedAt = DateTime.utc(2026, 7, 10, 12);
      final transfer = PendingGaslessTransfer(
        journalId: 'web-prefix-journal',
        traceId: 'web-prefix-trace',
        assetId: 'USDT-TRC20',
        network: '728126428',
        sourceAddress: 'TWebSource',
        custodyAddress: 'TWebCustody',
        destinationAddress: 'TWebDestination',
        requestedAmount: Decimal.parse('5'),
        signedMaxFee: Decimal.parse('2'),
        authorizationDeadline: BigInt.from(1783690000),
        balanceChanges: BalanceChanges(
          netChange: Decimal.parse('-7'),
          receivedByMe: Decimal.zero,
          spentByMe: Decimal.parse('7'),
          totalAmount: Decimal.parse('5'),
        ),
        fee: FeeInfo.tronGasless(
          coin: 'USDT-TRC20',
          feeMethod: 'gasless',
          providerName: 'gasfree',
          gasfreeAddress: 'TWebCustody',
          transferFee: Decimal.one,
          totalTokenFee: Decimal.one,
          signedMaxFee: Decimal.parse('2'),
        ),
        acceptedAt: acceptedAt,
        updatedAt: acceptedAt,
        state: GaslessTransferState.submittedPending,
      );
      final unsafeTransfer = transfer.toJson()
        ..['signed_authorization'] = {'sig': 'must-not-survive'};
      final encodedLegacy = jsonEncode({
        'version': 1,
        'transfers': [unsafeTransfer],
      });
      FlutterSecureStorage.setMockInitialValues({legacyKey: encodedLegacy});
      // The mock supplies encrypted-value semantics while this raw marker
      // exercises the browser-only key-name enumerator used by production.
      final rawStorageKey = 'FlutterSecureStorage.$legacyKey';
      web.window.localStorage.setItem(rawStorageKey, 'encrypted-marker');

      final storage = SecureGaslessTransferStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      addTearDown(() async {
        await storage.delete(legacyKey);
        await storage.delete(currentKey);
        await storage.delete(aliasKey);
        await storage.delete(resolutionKey);
        web.window.localStorage.removeItem(rawStorageKey);
      });

      expect(
        await repository.listAmbiguousLegacyTransfers(_renamedWallet),
        hasLength(1),
      );
      expect(
        await storage.read(legacyKey),
        isNot(contains('must-not-survive')),
      );

      await repository.resolveAmbiguousLegacyTransfers(
        _renamedWallet,
        ownedSourceAddressesByAsset: const {
          'USDT-TRC20': {'TWebSource'},
        },
      );

      expect(
        await repository.findByTraceId(_renamedWallet, 'web-prefix-trace'),
        isNotNull,
      );
      expect(await storage.containsKey(legacyKey), isTrue);
    },
  );

  test('web-discovered unreadable V1 ciphertext fails closed', () async {
    final legacyKey =
        'gasless_pending_transfers_v1_'
        '${sha256.convert(utf8.encode('unreadable-web-v1-journal'))}';
    final rawStorageKey = 'FlutterSecureStorage.$legacyKey';
    web.window.localStorage.setItem(rawStorageKey, 'invalid-ciphertext');
    addTearDown(() => web.window.localStorage.removeItem(rawStorageKey));

    final repository = SecurePendingGaslessTransferRepository(
      storage: _UnreadableDiscoveredWebStorage(legacyKey),
    );

    await expectLater(
      repository.listAmbiguousLegacyTransfers(_renamedWallet),
      throwsA(isA<GaslessTransferStorageReadException>()),
    );
  });
}
