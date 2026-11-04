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
    try {
      await directory.delete(recursive: true);
    } on PathNotFoundException {
      // Also raised, naming the directory, when an entry inside it vanishes
      // mid-walk. A leftover temp directory changes no result.
    }
  });

  /// Waits for Hive to delete [name]'s lock file, the last step of closing it.
  /// Gives up without failing, since this only keeps tearDown out of a race.
  Future<void> lockReleased(String name) async {
    final lock = File('${directory.path}/$name.lock');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (lock.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

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
      boxName,
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
      expect(store.isDegraded, isFalse);

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

  // How often the rebuild loses its race with Hive's close depends on
  // timing, so one upgrade is not enough.
  test('the rebuild survives Hive still closing the refused box', () async {
    final base = boxName;
    for (var upgrade = 0; upgrade < 50; upgrade++) {
      boxName = '${base}_$upgrade';
      await writeLegacyCache();
      final store = open();
      await store.storeTransaction(
        testTransaction(internalId: 'after-upgrade'),
        wallet,
      );
      expect(store.isDegraded, isFalse, reason: 'upgrade $upgrade');
      await store.close();
    }
  });

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
      // Refusing the whole box is equally acceptable. Hive then closes it
      // unawaited; let that finish before tearDown deletes the directory.
      await lockReleased(boxName);
    }

    expect(recovered, 0);
  });
}
