import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_migration_exception.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_record.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Minimal metadata-store interface for legacy native wallet migration.
abstract interface class LegacyWalletMetadataStore {
  /// Lists legacy wallets discovered in the native wallet database.
  Future<List<LegacyWalletRecord>> listWallets();

  /// Deletes all persisted database rows associated with [walletId].
  Future<void> deleteWalletData({required String walletId});
}

/// `sqflite` adapter for reading the legacy native wallet database.
class SqfliteLegacyWalletMetadataStore implements LegacyWalletMetadataStore {
  /// Creates a metadata store backed by the legacy `AtomicDEX.db` database.
  SqfliteLegacyWalletMetadataStore({
    Future<String> Function()? documentsPathProvider,
  }) : _documentsPathProvider =
           documentsPathProvider ?? _defaultDocumentsPathProvider;

  final Future<String> Function() _documentsPathProvider;

  static Future<String> _defaultDocumentsPathProvider() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> _databasePath() async {
    final documentsPath = await _documentsPathProvider();
    return p.join(documentsPath, 'AtomicDEX.db');
  }

  @override
  Future<List<LegacyWalletRecord>> listWallets() async {
    try {
      final databasePath = await _databasePath();
      if (!await databaseExists(databasePath)) {
        return const <LegacyWalletRecord>[];
      }

      final database = await openDatabase(databasePath, readOnly: true);
      try {
        final walletRows = await database.query(
          'Wallet',
          columns: [
            'id',
            'name',
            'activate_pin_protection',
            'activate_bio_protection',
            'switch_pin_log_out_on_exit',
            'enable_camo',
            'is_camo_active',
            'camo_fraction',
            'camo_balance',
            'camo_session_started_at',
          ],
        );
        final currentWalletRows = await database.query(
          'CurrentWallet',
          columns: ['id'],
        );
        final activatedCoinRows = await database.query(
          'ListOfCoinsActivated',
          columns: ['wallet_id', 'coins'],
        );

        final currentWalletIds = currentWalletRows
            .map((row) => row['id'])
            .whereType<String>()
            .toSet();
        final activatedCoinsByWalletId = <String, List<String>>{
          for (final row in activatedCoinRows)
            if (row['wallet_id'] is String)
              row['wallet_id']! as String: _parseActivatedCoins(row['coins']),
        };

        return walletRows
            .map(
              (row) => LegacyWalletRecord(
                walletId: row['id'] as String? ?? '',
                walletName: row['name'] as String? ?? '',
                activatedCoins:
                    activatedCoinsByWalletId[row['id'] as String? ?? ''] ??
                    const <String>[],
                isCurrentWallet: currentWalletIds.contains(row['id']),
                walletExtras: _parseWalletExtras(row),
              ),
            )
            .where((wallet) => wallet.walletId.isNotEmpty)
            .toList(growable: false);
      } finally {
        await database.close();
      }
    } on Object catch (error) {
      throw LegacyWalletMigrationException.storageAccessError(
        'Failed to read legacy wallet metadata: $error',
      );
    }
  }

  @override
  Future<void> deleteWalletData({required String walletId}) async {
    try {
      final databasePath = await _databasePath();
      if (!await databaseExists(databasePath)) {
        return;
      }

      final database = await openDatabase(databasePath);
      try {
        await database.transaction((txn) async {
          await txn.delete('Wallet', where: 'id = ?', whereArgs: [walletId]);
          await txn.delete(
            'CurrentWallet',
            where: 'id = ?',
            whereArgs: [walletId],
          );
          await txn.delete(
            'ListOfCoinsActivated',
            where: 'wallet_id = ?',
            whereArgs: [walletId],
          );
          await txn.delete(
            'WalletSnapshot',
            where: 'wallet_id = ?',
            whereArgs: [walletId],
          );
        });
      } finally {
        await database.close();
      }
    } on Object catch (error) {
      throw LegacyWalletMigrationException.storageAccessError(
        'Failed to delete legacy wallet metadata: $error',
      );
    }
  }

  List<String> _parseActivatedCoins(Object? rawCoins) {
    if (rawCoins is! String || rawCoins.trim().isEmpty) {
      return const <String>[];
    }

    return rawCoins
        .split(',')
        .map((coin) => coin.trim())
        .where((coin) => coin.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _parseWalletExtras(Map<String, Object?> row) {
    final extras = <String, dynamic>{};
    void addBool(String legacyKey, String outputKey) {
      final value = row[legacyKey];
      if (value is int) {
        extras[outputKey] = value == 1;
      } else if (value is bool) {
        extras[outputKey] = value;
      }
    }

    addBool('activate_pin_protection', 'activate_pin_protection');
    addBool('activate_bio_protection', 'activate_bio_protection');
    addBool('switch_pin_log_out_on_exit', 'switch_pin_log_out_on_exit');
    addBool('enable_camo', 'enable_camo');
    addBool('is_camo_active', 'is_camo_active');

    final camoFraction = row['camo_fraction'];
    if (camoFraction is int) {
      extras['camo_fraction'] = camoFraction;
    }

    final camoBalance = row['camo_balance'];
    if (camoBalance is String && camoBalance.isNotEmpty) {
      extras['camo_balance'] = camoBalance;
    }

    final camoSessionStartedAt = row['camo_session_started_at'];
    if (camoSessionStartedAt is int) {
      extras['camo_session_started_at'] = camoSessionStartedAt;
    }

    return extras;
  }
}
