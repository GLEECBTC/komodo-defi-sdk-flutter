import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_password_verifier.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_secure_storage.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_shared_preferences_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_metadata_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KomodoLegacyWalletMigration', () {
    late _FakeMetadataStore metadataStore;
    late _FakeSecureStorage secureStorage;
    late _FakeSharedPreferencesStore sharedPreferencesStore;
    late _FakePasswordVerifier passwordVerifier;
    late _FakePlatform platform;
    late KomodoLegacyWalletMigration migration;

    const storedWallet = LegacyWalletRecord(
      walletId: 'wallet-1',
      walletName: 'Legacy Wallet',
      activatedCoins: <String>['KMD', 'BTC'],
      isCurrentWallet: true,
    );

    setUp(() {
      metadataStore = _FakeMetadataStore(
        wallets: <LegacyWalletRecord>[storedWallet],
      );
      secureStorage = _FakeSecureStorage();
      sharedPreferencesStore = _FakeSharedPreferencesStore();
      passwordVerifier = _FakePasswordVerifier(isValid: true);
      platform = const _FakePlatform(isSupportedPlatform: true);
      migration = KomodoLegacyWalletMigration(
        metadataStore: metadataStore,
        secureStorage: secureStorage,
        sharedPreferencesStore: sharedPreferencesStore,
        passwordVerifier: passwordVerifier,
        platform: platform,
      );
    });

    test(
      'listLegacyWallets returns metadata store wallets on supported platforms',
      () async {
        final wallets = await migration.listLegacyWallets();

        expect(wallets, <LegacyWalletRecord>[storedWallet]);
        expect(metadataStore.listWalletsCalls, 1);
      },
    );

    test(
      'listLegacyWallets returns empty list on unsupported platforms',
      () async {
        migration = KomodoLegacyWalletMigration(
          metadataStore: metadataStore,
          secureStorage: secureStorage,
          sharedPreferencesStore: sharedPreferencesStore,
          passwordVerifier: passwordVerifier,
          platform: const _FakePlatform(isSupportedPlatform: false),
        );

        final wallets = await migration.listLegacyWallets();

        expect(wallets, isEmpty);
        expect(metadataStore.listWalletsCalls, 0);
      },
    );

    test(
      'readWalletSecrets prefers direct seed lookup and returns plaintext seed',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'word1 word2 word3',
        });

        final secrets = await migration.readWalletSecrets(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(passwordVerifier.passwordsChecked, isEmpty);
        expect(passwordVerifier.hashesChecked, isEmpty);
        expect(
          secureStorage.readCalls,
          <String>['KeyEncryption.SEEDsecretLegacy Walletwallet-1'],
        );
        expect(secrets.seedPhrase, 'word1 word2 word3');
        expect(secrets.sourceWallet, storedWallet);
        expect(
          secrets.secureStorageKeysToDelete,
          <String>[
            'KeyEncryption.SEEDsecretLegacy Walletwallet-1',
            'passwordKeyEncryption.SEEDLegacy Walletwallet-1',
            'KeyEncryption.PINsecretLegacy Walletwallet-1',
            'KeyEncryption.CAMOPINsecretLegacy Walletwallet-1',
            'wallet-1_task_id_KMD',
            'wallet-1_task_id_BTC',
          ],
        );
        expect(
          secrets.genericStorageKeysToDelete,
          <String>['pin', 'camoPin', 'passphrase'],
        );
      },
    );

    test(
      'readWalletSecrets returns the seed even if the optional verifier fails',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'word1 word2 word3',
        });
        passwordVerifier.isValid = false;

        final secrets = await migration.readWalletSecrets(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(secrets.seedPhrase, 'word1 word2 word3');
        expect(passwordVerifier.passwordsChecked, isEmpty);
        expect(
          secureStorage.readCalls,
          <String>['KeyEncryption.SEEDsecretLegacy Walletwallet-1'],
        );
      },
    );

    test(
      'readWalletSecrets rejects invalid passwords after the seed key misses',
      () async {
        secureStorage
                .values['passwordKeyEncryption.SEEDLegacy Walletwallet-1'] =
            'hash-value';
        passwordVerifier.isValid = false;

        await expectLater(
          () => migration.readWalletSecrets(
            wallet: storedWallet,
            password: 'wrong',
          ),
          throwsA(
            isA<LegacyWalletMigrationException>().having(
              (error) => error.type,
              'type',
              LegacyWalletMigrationExceptionType.incorrectPassword,
            ),
          ),
        );

        expect(
          secureStorage.readCalls,
          <String>[
            'KeyEncryption.SEEDwrongLegacy Walletwallet-1',
            'passwordKeyEncryption.SEEDLegacy Walletwallet-1',
          ],
        );
      },
    );

    test(
      'readWalletSecrets treats missing seed data key as incorrect password',
      () async {
        secureStorage
                .values['passwordKeyEncryption.SEEDLegacy Walletwallet-1'] =
            'hash-value';

        await expectLater(
          () => migration.readWalletSecrets(
            wallet: storedWallet,
            password: 'wrong',
          ),
          throwsA(
            isA<LegacyWalletMigrationException>().having(
              (error) => error.type,
              'type',
              LegacyWalletMigrationExceptionType.incorrectPassword,
            ),
          ),
        );

        expect(
          secureStorage.readCalls,
          <String>[
            'KeyEncryption.SEEDwrongLegacy Walletwallet-1',
            'passwordKeyEncryption.SEEDLegacy Walletwallet-1',
          ],
        );
        expect(passwordVerifier.passwordsChecked, <String>['wrong']);
        expect(passwordVerifier.hashesChecked, <String>['hash-value']);
      },
    );

    test(
      'readWalletSecrets resolves the original wallet name by wallet id',
      () async {
        secureStorage
                .values['passwordKeyEncryption.SEEDLegacy Walletwallet-1'] =
            'hash-value';
        secureStorage.values['KeyEncryption.SEEDsecretLegacy Walletwallet-1'] =
            'seed words';

        final secrets = await migration.readWalletSecrets(
          wallet: const LegacyWalletRecord(
            walletId: 'wallet-1',
            walletName: 'Sanitized_Name',
          ),
          password: 'secret',
        );

        expect(secrets.seedPhrase, 'seed words');
        expect(
          secureStorage.readCalls.last,
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1',
        );
      },
    );

    test(
      'readWalletSecrets includes legacy special-case state and cleanup keys',
      () async {
        const zhtlcWallet = LegacyWalletRecord(
          walletId: 'wallet-z',
          walletName: 'Z Wallet',
          activatedCoins: <String>['ARRR'],
          isCurrentWallet: true,
          walletExtras: <String, dynamic>{
            'activate_pin_protection': true,
            'enable_camo': true,
          },
        );
        metadataStore = _FakeMetadataStore(
          wallets: const <LegacyWalletRecord>[zhtlcWallet],
        );
        migration = KomodoLegacyWalletMigration(
          metadataStore: metadataStore,
          secureStorage: secureStorage,
          sharedPreferencesStore: sharedPreferencesStore,
          passwordVerifier: passwordVerifier,
          platform: platform,
        );
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDZ Walletwallet-z': 'hash-value',
          'KeyEncryption.SEEDsecretZ Walletwallet-z': 'seed words',
        });
        sharedPreferencesStore.values.addAll(<String, Object?>{
          'z-coin-activation-requested-wallet-z': <String>['ARRR'],
          'zhtlcSyncType': 'specifiedDate',
          'zhtlcSyncStartDate': '2025-01-02T03:04:05.000Z',
          'disallowScreenshot': true,
        });

        final secrets = await migration.readWalletSecrets(
          wallet: zhtlcWallet,
          password: 'secret',
        );

        expect(secrets.requestedZhtlcCoinIds, <String>['ARRR']);
        expect(secrets.legacyZhtlcSyncType, 'specifiedDate');
        expect(
          secrets.legacyZhtlcSyncStartDate,
          DateTime.parse('2025-01-02T03:04:05.000Z').toUtc(),
        );
        expect(
          secrets.walletExtras,
          <String, dynamic>{
            'activate_pin_protection': true,
            'enable_camo': true,
            'disallow_screenshot': true,
          },
        );
        expect(
          secrets.sharedPreferencesKeysToDelete,
          <String>['z-coin-activation-requested-wallet-z'],
        );
        expect(
          secrets.secureStorageKeysToDelete,
          contains('wallet-z_task_id_ARRR'),
        );
      },
    );

    test(
      'deleteLegacyWalletData removes DB rows and secure storage keys',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'seed words',
        });

        final result = await migration.deleteLegacyWalletData(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(result.isComplete, isTrue);
        expect(metadataStore.deletedWalletIds, <String>['wallet-1']);
        expect(
          secureStorage.deleteCalls,
          <String>[
            'KeyEncryption.SEEDsecretLegacy Walletwallet-1',
            'passwordKeyEncryption.SEEDLegacy Walletwallet-1',
            'KeyEncryption.PINsecretLegacy Walletwallet-1',
            'KeyEncryption.CAMOPINsecretLegacy Walletwallet-1',
            'wallet-1_task_id_KMD',
            'wallet-1_task_id_BTC',
            'pin',
            'camoPin',
            'passphrase',
          ],
        );
      },
    );

    test(
      'deleteLegacyWalletData uses provided secrets without re-reading storage',
      () async {
        const secrets = LegacyWalletSecrets(
          sourceWallet: storedWallet,
          seedPhrase: 'seed words',
          secureStorageKeysToDelete: <String>[
            'KeyEncryption.SEEDsecretLegacy Walletwallet-1',
          ],
        );

        final result = await migration.deleteLegacyWalletData(
          wallet: storedWallet,
          password: 'secret',
          secrets: secrets,
        );

        expect(result.isComplete, isTrue);
        expect(secureStorage.readCalls, isEmpty);
        expect(metadataStore.deletedWalletIds, <String>['wallet-1']);
      },
    );

    test(
      'deleteLegacyWalletData returns partial and keeps metadata when a '
      'critical key fails deletion',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'seed words',
        });
        secureStorage.keysThatFailDeletion.add(
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1',
        );

        final result = await migration.deleteLegacyWalletData(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(result.status, LegacyWalletCleanupStatus.partial);
        expect(result.metadataDeleted, isFalse);
        expect(metadataStore.deletedWalletIds, isEmpty);
        expect(
          result.failedSecureStorageKeys,
          <String>['KeyEncryption.SEEDsecretLegacy Walletwallet-1'],
        );
      },
    );

    test(
      'deleteLegacyWalletData returns partial when generic key deletion fails '
      'after metadata cleanup',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'seed words',
        });
        secureStorage.keysThatFailDeletion.add('passphrase');

        final result = await migration.deleteLegacyWalletData(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(result.status, LegacyWalletCleanupStatus.partial);
        expect(result.metadataDeleted, isTrue);
        expect(metadataStore.deletedWalletIds, <String>['wallet-1']);
        expect(result.failedSecureStorageKeys, <String>['passphrase']);
      },
    );

    test(
      'deleteLegacyWalletData returns partial when shared-preferences cleanup '
      'fails after metadata cleanup',
      () async {
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDLegacy Walletwallet-1': 'hash-value',
          'KeyEncryption.SEEDsecretLegacy Walletwallet-1': 'seed words',
        });
        sharedPreferencesStore.values['z-coin-activation-requested-wallet-1'] =
            <String>['ARRR'];
        sharedPreferencesStore.keysThatFailDeletion.add(
          'z-coin-activation-requested-wallet-1',
        );

        final result = await migration.deleteLegacyWalletData(
          wallet: storedWallet,
          password: 'secret',
        );

        expect(result.status, LegacyWalletCleanupStatus.partial);
        expect(result.metadataDeleted, isTrue);
        expect(result.warningMessage, contains('shared-preferences'));
      },
    );

    test(
      'readWalletSecrets omits generic session keys for a non-current wallet '
      'when others remain',
      () async {
        const otherWallet = LegacyWalletRecord(
          walletId: 'wallet-2',
          walletName: 'Other Wallet',
          activatedCoins: <String>['ETH'],
        );
        metadataStore = _FakeMetadataStore(
          wallets: const <LegacyWalletRecord>[storedWallet, otherWallet],
        );
        migration = KomodoLegacyWalletMigration(
          metadataStore: metadataStore,
          secureStorage: secureStorage,
          sharedPreferencesStore: sharedPreferencesStore,
          passwordVerifier: passwordVerifier,
          platform: platform,
        );
        secureStorage.values.addAll(<String, String>{
          'passwordKeyEncryption.SEEDOther Walletwallet-2': 'hash-value',
          'KeyEncryption.SEEDsecretOther Walletwallet-2': 'seed words',
        });

        final secrets = await migration.readWalletSecrets(
          wallet: otherWallet,
          password: 'secret',
        );

        expect(secrets.genericStorageKeysToDelete, isEmpty);
      },
    );
  });
}

class _FakeMetadataStore implements LegacyWalletMetadataStore {
  _FakeMetadataStore({required this.wallets});

  final List<LegacyWalletRecord> wallets;
  int listWalletsCalls = 0;
  final List<String> deletedWalletIds = <String>[];

  @override
  Future<void> deleteWalletData({required String walletId}) async {
    deletedWalletIds.add(walletId);
  }

  @override
  Future<List<LegacyWalletRecord>> listWallets() async {
    listWalletsCalls += 1;
    return wallets;
  }
}

class _FakeSecureStorage implements LegacySecureStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> readCalls = <String>[];
  final List<String> deleteCalls = <String>[];
  final Set<String> keysThatFailDeletion = <String>{};

  @override
  Future<void> delete(String key) async {
    if (keysThatFailDeletion.contains(key)) {
      throw StateError('delete failed for $key');
    }
    deleteCalls.add(key);
  }

  @override
  Future<String?> read(String key) async {
    readCalls.add(key);
    return values[key];
  }
}

class _FakePasswordVerifier implements LegacyPasswordVerifier {
  _FakePasswordVerifier({required this.isValid});

  bool isValid;
  final List<String> passwordsChecked = <String>[];
  final List<String> hashesChecked = <String>[];

  @override
  Future<bool> verifySeedPassword({
    required String password,
    required String encodedHash,
  }) async {
    passwordsChecked.add(password);
    hashesChecked.add(encodedHash);
    return isValid;
  }
}

class _FakePlatform implements LegacyWalletPlatform {
  const _FakePlatform({required this.isSupportedPlatform});

  @override
  final bool isSupportedPlatform;
}

class _FakeSharedPreferencesStore implements LegacySharedPreferencesStore {
  final Map<String, Object?> values = <String, Object?>{};
  final Set<String> keysThatFailDeletion = <String>{};
  final List<String> deleteCalls = <String>[];

  @override
  Future<void> delete(String key) async {
    if (keysThatFailDeletion.contains(key)) {
      throw StateError('delete failed for $key');
    }
    deleteCalls.add(key);
    values.remove(key);
  }

  @override
  Future<Object?> read(String key) async => values[key];
}
