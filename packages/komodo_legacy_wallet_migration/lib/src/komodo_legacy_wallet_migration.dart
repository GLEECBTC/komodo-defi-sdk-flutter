import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_password_verifier.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_secure_storage.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_shared_preferences_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_metadata_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_platform.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_cleanup_result.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_migration_exception.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_record.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_secrets.dart';

/// Legacy wallet migration utilities for Komodo/Gleec SDK apps.
class KomodoLegacyWalletMigration {
  /// Creates a migration service with injectable storage/platform adapters.
  KomodoLegacyWalletMigration({
    LegacyWalletMetadataStore? metadataStore,
    LegacySecureStorage? secureStorage,
    LegacySharedPreferencesStore? sharedPreferencesStore,
    LegacyPasswordVerifier? passwordVerifier,
    LegacyWalletPlatform? platform,
  }) : _metadataStore = metadataStore ?? SqfliteLegacyWalletMetadataStore(),
       _secureStorage = secureStorage ?? FlutterLegacySecureStorage(),
       _sharedPreferencesStore =
           sharedPreferencesStore ?? FlutterLegacySharedPreferencesStore(),
       _passwordVerifier =
           passwordVerifier ?? const Argon2LegacyPasswordVerifier(),
       _platform = platform ?? const DefaultLegacyWalletPlatform();

  final LegacyWalletMetadataStore _metadataStore;
  final LegacySecureStorage _secureStorage;
  final LegacySharedPreferencesStore _sharedPreferencesStore;
  final LegacyPasswordVerifier _passwordVerifier;
  final LegacyWalletPlatform _platform;

  static const String _seedPrefix = 'KeyEncryption.SEED';
  static const String _pinPrefix = 'KeyEncryption.PIN';
  static const String _camoPinPrefix = 'KeyEncryption.CAMOPIN';
  static const String _passwordPrefix = 'password';
  static const String _genericPinKey = 'pin';
  static const String _genericCamoPinKey = 'camoPin';
  static const String _genericPassphraseKey = 'passphrase';
  static const String _zhtlcSyncTypeKey = 'zhtlcSyncType';
  static const String _zhtlcSyncStartDateKey = 'zhtlcSyncStartDate';
  static const String _zCoinActivationRequestedKeyPrefix =
      'z-coin-activation-requested-';
  static const String _disallowScreenshotKey = 'disallowScreenshot';

  /// Whether the current runtime can access legacy native wallet storage.
  bool get isSupportedPlatform => _platform.isSupportedPlatform;

  /// Lists legacy native wallets available for migration on this device.
  Future<List<LegacyWalletRecord>> listLegacyWallets() async {
    if (!isSupportedPlatform) {
      return const <LegacyWalletRecord>[];
    }

    return _metadataStore.listWallets();
  }

  /// Reads the plaintext seed and cleanup keys for [wallet].
  Future<LegacyWalletSecrets> readWalletSecrets({
    required LegacyWalletRecord wallet,
    required String password,
  }) async {
    try {
      final wallets = await _listWallets();
      final sourceWallet = _findWalletById(wallet, wallets);
      final cleanupKeys = _buildSecureStorageKeys(
        wallet: sourceWallet,
        password: password,
      );
      final requestedZhtlcCoinIds = await _readRequestedZhtlcCoinIds(
        sourceWallet.walletId,
      );
      final zhtlcTickers = <String>{
        ...sourceWallet.activatedCoins,
        ...requestedZhtlcCoinIds,
      };
      final walletExtras = await _readWalletExtras(sourceWallet);
      final seedPhrase = await _secureStorage.read(cleanupKeys.seedKey);
      if (seedPhrase != null && seedPhrase.isNotEmpty) {
        return LegacyWalletSecrets(
          sourceWallet: sourceWallet,
          seedPhrase: seedPhrase,
          secureStorageKeysToDelete: <String>[
            ...cleanupKeys.toDelete,
            ...zhtlcTickers.map(
              (ticker) => '${sourceWallet.walletId}_task_id_$ticker',
            ),
          ],
          genericStorageKeysToDelete:
              _shouldDeleteGenericSessionKeys(
                sourceWallet: sourceWallet,
                wallets: wallets,
              )
              ? const <String>[
                  _genericPinKey,
                  _genericCamoPinKey,
                  _genericPassphraseKey,
                ]
              : const <String>[],
          sharedPreferencesKeysToDelete: <String>[
            '$_zCoinActivationRequestedKeyPrefix${sourceWallet.walletId}',
          ],
          requestedZhtlcCoinIds: requestedZhtlcCoinIds,
          legacyZhtlcSyncType:
              (await _sharedPreferencesStore.read(_zhtlcSyncTypeKey))
                  as String?,
          legacyZhtlcSyncStartDate: _parseLegacySyncStartDate(
            await _sharedPreferencesStore.read(_zhtlcSyncStartDateKey),
          ),
          walletExtras: walletExtras,
        );
      }

      final hashKey = _passwordHashKey(sourceWallet);
      final passwordHash = await _secureStorage.read(hashKey);
      if (passwordHash != null) {
        final isValid = await _passwordVerifier.verifySeedPassword(
          password: password,
          encodedHash: passwordHash,
        );
        if (!isValid) {
          throw const LegacyWalletMigrationException.incorrectPassword();
        }
      }

      throw const LegacyWalletMigrationException.incorrectPassword();
    } on LegacyWalletMigrationException {
      rethrow;
    } on Object catch (error) {
      throw LegacyWalletMigrationException.storageAccessError(
        'Failed to read legacy wallet secrets: $error',
      );
    }
  }

  /// Deletes legacy database rows and secure-storage keys for [wallet].
  Future<LegacyWalletCleanupResult> deleteLegacyWalletData({
    required LegacyWalletRecord wallet,
    required String password,
    LegacyWalletSecrets? secrets,
  }) async {
    if (!isSupportedPlatform) {
      return const LegacyWalletCleanupResult.skipped(
        warningMessage:
            'Legacy native wallet cleanup skipped on unsupported platform.',
      );
    }

    try {
      final resolvedSecrets =
          secrets ??
          await readWalletSecrets(
            wallet: wallet,
            password: password,
          );

      final criticalDeletionResult = await _deleteSecureStorageKeys(
        resolvedSecrets.secureStorageKeysToDelete,
      );
      final genericDeletionResult = await _deleteSecureStorageKeys(
        resolvedSecrets.genericStorageKeysToDelete,
      );
      final sharedPrefsDeletionResult = await _deleteSharedPreferencesKeys(
        resolvedSecrets.sharedPreferencesKeysToDelete,
      );

      var metadataDeleted = false;
      String? warningMessage;
      final failedCriticalKeys = criticalDeletionResult.failedKeys;
      if (failedCriticalKeys.isEmpty) {
        try {
          await _metadataStore.deleteWalletData(
            walletId: resolvedSecrets.sourceWallet.walletId,
          );
          metadataDeleted = true;
        } on LegacyWalletMigrationException catch (error) {
          warningMessage = error.message;
        }
      } else {
        warningMessage =
            'Legacy secret cleanup incomplete. '
            'The legacy wallet remains listed so cleanup can be retried.';
      }

      final deletedKeys = <String>[
        ...criticalDeletionResult.deletedKeys,
        ...genericDeletionResult.deletedKeys,
      ];
      final failedKeys = <String>[
        ...criticalDeletionResult.failedKeys,
        ...genericDeletionResult.failedKeys,
      ];
      final failedSharedPreferencesKeys = sharedPrefsDeletionResult.failedKeys;

      if (metadataDeleted &&
          failedKeys.isEmpty &&
          failedSharedPreferencesKeys.isEmpty) {
        return LegacyWalletCleanupResult.complete(
          metadataDeleted: true,
          deletedSecureStorageKeys: deletedKeys,
        );
      }

      return LegacyWalletCleanupResult.partial(
        metadataDeleted: metadataDeleted,
        deletedSecureStorageKeys: deletedKeys,
        failedSecureStorageKeys: failedKeys,
        warningMessage:
            warningMessage ??
            (failedSharedPreferencesKeys.isNotEmpty
                ? 'Legacy wallet cleanup incomplete. '
                      'Some legacy shared-preferences entries '
                      'could not be deleted.'
                : 'Legacy wallet cleanup incomplete. '
                      'Some legacy secure-storage entries '
                      'could not be deleted.'),
      );
    } on LegacyWalletMigrationException {
      rethrow;
    } on Object catch (error) {
      throw LegacyWalletMigrationException.storageAccessError(
        'Failed to delete legacy wallet data: $error',
      );
    }
  }

  String _passwordHashKey(LegacyWalletRecord wallet) {
    return '$_passwordPrefix$_seedPrefix${wallet.walletName}${wallet.walletId}';
  }

  _SecureStorageKeys _buildSecureStorageKeys({
    required LegacyWalletRecord wallet,
    required String password,
  }) {
    final suffix = '${wallet.walletName}${wallet.walletId}';
    final seedKey = '$_seedPrefix$password$suffix';
    return _SecureStorageKeys(
      seedKey: seedKey,
      toDelete: <String>[
        seedKey,
        _passwordHashKey(wallet),
        '$_pinPrefix$password$suffix',
        '$_camoPinPrefix$password$suffix',
      ],
    );
  }

  Future<List<LegacyWalletRecord>> _listWallets() {
    return _metadataStore.listWallets();
  }

  LegacyWalletRecord _findWalletById(
    LegacyWalletRecord wallet,
    List<LegacyWalletRecord> wallets,
  ) {
    for (final candidate in wallets) {
      if (candidate.walletId == wallet.walletId) {
        return candidate;
      }
    }

    throw LegacyWalletMigrationException.walletNotFound(wallet.walletId);
  }

  bool _shouldDeleteGenericSessionKeys({
    required LegacyWalletRecord sourceWallet,
    required List<LegacyWalletRecord> wallets,
  }) {
    return sourceWallet.isCurrentWallet || wallets.length == 1;
  }

  Future<_KeyDeletionResult> _deleteSecureStorageKeys(List<String> keys) async {
    final deletedKeys = <String>[];
    final failedKeys = <String>[];

    for (final key in keys) {
      try {
        await _secureStorage.delete(key);
        deletedKeys.add(key);
      } on Object {
        failedKeys.add(key);
      }
    }

    return _KeyDeletionResult(
      deletedKeys: deletedKeys,
      failedKeys: failedKeys,
    );
  }

  Future<_KeyDeletionResult> _deleteSharedPreferencesKeys(
    List<String> keys,
  ) async {
    final deletedKeys = <String>[];
    final failedKeys = <String>[];

    for (final key in keys) {
      try {
        await _sharedPreferencesStore.delete(key);
        deletedKeys.add(key);
      } on Object {
        failedKeys.add(key);
      }
    }

    return _KeyDeletionResult(
      deletedKeys: deletedKeys,
      failedKeys: failedKeys,
    );
  }

  Future<List<String>> _readRequestedZhtlcCoinIds(String walletId) async {
    final rawValue = await _sharedPreferencesStore.read(
      '$_zCoinActivationRequestedKeyPrefix$walletId',
    );
    if (rawValue is List<Object?>) {
      return rawValue.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  Future<Map<String, dynamic>> _readWalletExtras(
    LegacyWalletRecord sourceWallet,
  ) async {
    final extras = <String, dynamic>{...sourceWallet.walletExtras};
    final disallowScreenshot = await _sharedPreferencesStore.read(
      _disallowScreenshotKey,
    );
    if (disallowScreenshot is bool) {
      extras['disallow_screenshot'] = disallowScreenshot;
    }
    return extras;
  }

  DateTime? _parseLegacySyncStartDate(Object? rawValue) {
    if (rawValue is String && rawValue.isNotEmpty) {
      return DateTime.tryParse(rawValue)?.toUtc();
    }
    return null;
  }
}

class _SecureStorageKeys {
  const _SecureStorageKeys({required this.seedKey, required this.toDelete});

  final String seedKey;
  final List<String> toDelete;
}

class _KeyDeletionResult {
  const _KeyDeletionResult({
    required this.deletedKeys,
    required this.failedKeys,
  });

  final List<String> deletedKeys;
  final List<String> failedKeys;
}
