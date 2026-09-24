@TestOn('browser')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// These are the real platform implementation and registrar, not storage mocks.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
// Register the browser plugin exactly as a Flutter web app does at startup.
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_key_provider.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:web/web.dart' as web;

import 'transaction_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorageWeb.registerWith(webPluginRegistrar);

  test(
    'default history provider persists its key with real browser WebCrypto',
    () async {
      final name =
          'history_platform_key_${DateTime.now().microsecondsSinceEpoch}';
      final storageKey =
          'komodo_tx_history_key_v2.${sha256.convert(utf8.encode(name))}';
      const secureStorage = FlutterSecureStorage();
      final store = HiveTransactionStorage(boxName: name);
      HiveTransactionStorage? reopened;
      addTearDown(() async {
        await store.close();
        await reopened?.close();
        await Hive.deleteBoxFromDisk(name);
        await secureStorage.delete(key: storageKey);
      });
      final original = testTransaction(
        internalId: 'platform-protected-history-sentinel',
      );
      final wallet = testWallet();
      await store.storeTransaction(original, wallet);
      expect(store.isDegraded, isFalse);
      final encodedKey = await secureStorage.read(key: storageKey);
      expect(encodedKey, isNotNull);
      expect(base64Decode(encodedKey!), hasLength(32));
      final rawKey = web.window.localStorage.getItem(
        'FlutterSecureStorage.$storageKey',
      );
      expect(rawKey, isNotNull);
      expect(rawKey, isNot(encodedKey));
      expect(rawKey, isNot(contains(encodedKey)));
      expect(
        await SecureHistoryCacheKeyProvider().loadOrCreate(name),
        base64Decode(encodedKey),
      );
      await store.close();
      reopened = HiveTransactionStorage(boxName: name);
      expect(
        (await reopened.getTransactions(
          testAssetId(),
          wallet,
        )).transactions.single,
        original,
      );
      expect(reopened.isDegraded, isFalse);
    },
  );
}
