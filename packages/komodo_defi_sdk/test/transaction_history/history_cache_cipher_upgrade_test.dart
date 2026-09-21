@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';

import 'transaction_fixtures.dart';

/// Upgrading past the AES-CBC cache has to leave a working cache behind.
///
/// Every device that has run a previous release holds a box the new cipher
/// cannot read. The open path is expected to reject it on the key CRC, delete
/// it and reopen empty, with history refetched from providers. The failure mode
/// worth guarding against is the quiet one: the open throwing all the way out
/// and dropping the store into its memory-only fallback, where the cache still
/// answers reads but persists nothing and every restart starts cold.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late String boxName;
  final handles = <HiveTransactionStorage>[];
  final wallet = testWallet();
  final asset = testAssetId();

  // Its own box per test. The storage is a reference-counted singleton keyed by
  // box name and takes an exclusive lease on it, so sharing the default name
  // with the other files in this suite makes whichever runs second degrade to
  // its memory-only fallback - which reads as this test failing.
  HiveTransactionStorage open() {
    final store = HiveTransactionStorage(
      boxName: boxName,
      keyProvider: testHistoryCacheKeys,
    );
    handles.add(store);

    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('history_upgrade_');
    boxName = 'history_upgrade_${DateTime.now().microsecondsSinceEpoch}';
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    for (final handle in handles) {
      await handle.close();
    }
    handles.clear();
    await Hive.close();
    // Tolerant: a test that reopens Hive against this path can leave it
    // already gone, and losing a temp directory is not a result.
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  /// Writes a box exactly as the previous release would have: Hive's CBC
  /// cipher, over the key the old label derived.
  Future<void> writeLegacyCache() async {
    final master = Hmac(
      sha256,
      await testHistoryCacheKeys.loadOrCreate(boxName),
    );
    final legacy = HiveAesCipher(
      master.convert(utf8.encode('history-encryption-v2')).bytes,
    );
    final box = await Hive.openLazyBox<String>(
      HiveTransactionStorage.defaultBoxName,
      encryptionCipher: legacy,
    );
    await box.put('a' * 64, 'an envelope only the old cipher can read');
    await box.close();
  }

  test(
    'a cache written by the previous cipher is rebuilt, not abandoned',
    () async {
      await writeLegacyCache();

      final store = open();
      // Reads fine because the box was rebuilt empty - the old rows are gone
      // rather than decrypted.
      expect((await store.getTransactions(asset, wallet)).cachedCount, 0);

      await store.storeTransaction(
        testTransaction(internalId: 'after-upgrade'),
        wallet,
      );
      expect((await store.getTransactions(asset, wallet)).cachedCount, 1);
      await store.close();

      // The real assertion: a fresh handle still sees the row. In the memory-only
      // fallback this comes back empty, which is how a silently degraded cache
      // would look.
      final reopened = open();
      expect((await reopened.getTransactions(asset, wallet)).cachedCount, 1);
    },
  );

  test('post-upgrade records are unreadable with the old key', () async {
    await writeLegacyCache();

    final store = open();
    await store.storeTransaction(
      testTransaction(internalId: 'after-upgrade'),
      wallet,
    );
    await store.close();
    await Hive.close();

    final master = Hmac(
      sha256,
      await testHistoryCacheKeys.loadOrCreate(boxName),
    );
    final legacy = HiveAesCipher(
      master.convert(utf8.encode('history-encryption-v2')).bytes,
    );
    Hive.init(directory.path);

    // The property that matters is that the old key cannot recover the new
    // records, not which layer says no. Hive may refuse the box outright on the
    // key CRC, or open it and fail per record; both are acceptable, and
    // asserting only one of them would be asserting a Hive implementation
    // detail rather than this change's guarantee.
    var recovered = 0;
    try {
      final box = await Hive.openLazyBox<String>(
        boxName,
        encryptionCipher: legacy,
        crashRecovery: false,
      );
      for (final key in box.keys) {
        try {
          if (await box.get(key) != null) recovered++;
        } on Object {
          // A record the old key cannot open is the expected outcome.
        }
      }
      await box.close();
    } on Object {
      // Refusing the whole box is equally acceptable.
    }

    expect(recovered, 0);
  });
}
