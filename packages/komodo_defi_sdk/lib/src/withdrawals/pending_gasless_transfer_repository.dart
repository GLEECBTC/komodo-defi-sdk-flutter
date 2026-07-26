import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_storage_keys.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// Minimal key/value operations required by the encrypted GasFree journal.
abstract interface class GaslessTransferKeyValueStorage {
  /// Whether an encrypted value exists for [key].
  Future<bool> containsKey(String key);

  /// Reads and decrypts [key], or returns `null` when no value is available.
  Future<String?> read(String key);

  /// Encrypts and stores [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes [key] when it exists.
  Future<void> delete(String key);
}

/// Optional capability for discovering old journal keys whose wallet name is
/// no longer known.
///
/// Implementations must return only keys beginning with the requested prefix
/// and fail closed when more than the requested maximum number of matching
/// keys exist. Values remain behind
/// the ordinary guarded [GaslessTransferKeyValueStorage.read] path.
// This is intentionally a capability interface implemented by production web
// storage and test stores, rather than widening every key/value store.
// ignore: one_member_abstracts
abstract interface class GaslessTransferKeyDiscovery {
  /// Returns at most [maxKeys] key names beginning with [prefix].
  Future<Set<String>> keysWithPrefix(String prefix, {required int maxKeys});
}

/// Raised when secure storage reports that journal data exists but cannot
/// return its plaintext value.
///
/// Treating this as an empty journal could permit a blind relay resubmission,
/// so callers must fail closed until the storage entry is readable again.
class GaslessTransferStorageReadException implements Exception {
  /// Creates a source-free secure-storage read failure.
  const GaslessTransferStorageReadException();

  @override
  String toString() => 'GasFree transfer journal could not be read securely';
}

/// Source-free corruption error for decrypted journal contents.
///
/// Dart's JSON [FormatException] retains a source excerpt, which may contain
/// wallet addresses or amounts. This exception is safe to surface in logs.
class GaslessTransferStorageFormatException implements Exception {
  /// Creates a source-free persisted-data format failure.
  const GaslessTransferStorageFormatException();

  @override
  String toString() => 'GasFree transfer journal contains invalid data';
}

/// Raised while old journal data still needs fresh wallet-source ownership
/// verification.
///
/// GasFree journals created before authentication-scoped storage keys can be
/// shared by wallet contexts with the same public-key hash. Callers must use
/// [PendingGaslessTransferRepository.listAmbiguousLegacyTransfers] and
/// [PendingGaslessTransferRepository.resolveAmbiguousLegacyTransfers] before
/// treating the current context's journal as readable or empty.
class GaslessTransferLegacyResolutionException implements Exception {
  /// Creates a blocker for unresolved legacy wallet ownership.
  const GaslessTransferLegacyResolutionException();

  @override
  String toString() =>
      'GasFree transfer journal requires wallet-source verification';
}

/// Secure-storage implementation used by production SDK instances.
class SecureGaslessTransferStorage
    implements GaslessTransferKeyValueStorage, GaslessTransferKeyDiscovery {
  /// Creates production storage, optionally backed by an injected instance.
  SecureGaslessTransferStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<Set<String>> keysWithPrefix(String prefix, {required int maxKeys}) =>
      discoverSecureStorageKeysWithPrefix(_storage, prefix, maxKeys: maxKeys);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Durable storage contract for unresolved GasFree relay transfers.
abstract interface class PendingGaslessTransferRepository {
  /// Returns old unscoped records that still need current-context ownership
  /// verification.
  ///
  /// This is the only journal read permitted before legacy resolution. The
  /// returned source addresses are untrusted persisted input; the manager must
  /// compare them with a fresh, wallet-generation-checked KDF address result.
  Future<List<PendingGaslessTransfer>> listAmbiguousLegacyTransfers(
    WalletId walletId,
  );

  /// Resolves old records only for asset groups with fresh KDF address proof.
  ///
  /// Every map entry must contain the complete non-empty set of source
  /// addresses freshly fetched for that exact asset and wallet context.
  /// Matching records are adopted into the scoped journal. Non-matching
  /// records are excluded only for this authentication context. Asset groups
  /// omitted from the map remain unresolved and continue to block all ordinary
  /// journal operations.
  Future<void> resolveAmbiguousLegacyTransfers(
    WalletId walletId, {
    required Map<String, Set<String>> ownedSourceAddressesByAsset,
  });

  /// Returns every unresolved transfer for [walletId].
  Future<List<PendingGaslessTransfer>> list(WalletId walletId);

  /// Emits the current transfers and subsequent journal changes.
  Stream<List<PendingGaslessTransfer>> watch(WalletId walletId);

  /// Finds a transfer by either its local journal ID or accepted trace ID.
  Future<PendingGaslessTransfer?> find(WalletId walletId, String identity);

  /// Finds a transfer by its local [journalId].
  Future<PendingGaslessTransfer?> findByJournalId(
    WalletId walletId,
    String journalId,
  );

  /// Finds an accepted transfer by its KDF [traceId].
  Future<PendingGaslessTransfer?> findByTraceId(
    WalletId walletId,
    String traceId,
  );

  /// Inserts or replaces a correlated non-terminal [transfer].
  Future<void> upsert(WalletId walletId, PendingGaslessTransfer transfer);

  /// Atomically reserves one unresolved send per wallet/asset/custody source.
  Future<bool> reserve(WalletId walletId, PendingGaslessTransfer transfer);

  /// Removes the transfer correlated with [identity].
  Future<void> remove(WalletId walletId, String identity);
}

final class _DecodedPendingTransfers {
  const _DecodedPendingTransfers({
    required this.transfers,
    required this.needsMigration,
  });

  final List<PendingGaslessTransfer> transfers;
  final bool needsMigration;
}

final class _LegacyTransferSnapshot {
  const _LegacyTransferSnapshot({
    required this.transfers,
    required this.storageKeys,
  });

  final List<PendingGaslessTransfer> transfers;
  final Set<String> storageKeys;
}

final class _LegacyResolution {
  const _LegacyResolution({
    this.claimed = const <String>{},
    this.excluded = const <String>{},
  });

  final Set<String> claimed;
  final Set<String> excluded;

  Set<String> get all => <String>{...claimed, ...excluded};
}

/// Versioned, encrypted repository for unresolved GasFree relay transfers.
class SecurePendingGaslessTransferRepository
    implements PendingGaslessTransferRepository {
  /// Creates an encrypted, wallet-scoped pending-transfer repository.
  SecurePendingGaslessTransferRepository({
    GaslessTransferKeyValueStorage? storage,
  }) : _storage = storage ?? SecureGaslessTransferStorage();

  static const _prefix = 'gasless_pending_transfers_';
  // V4 stores the U256 authorization deadline as a decimal string. Older
  // numeric records remain readable and are normalized on scoped writes.
  static const _schemaVersion = 4;
  static const _legacyAliasSchemaVersion = 2;
  static const _legacyResolutionSchemaVersion = 1;
  static const _maxAmbiguousLegacyAliasesPerWallet = 16;
  static const _maxScopedLegacyAliasesPerWallet = 64;
  static const _maxDiscoveredLegacyCompoundKeys = 64;
  static const _maxLegacyResolutionsPerWallet = 1024;

  final GaslessTransferKeyValueStorage _storage;
  static final Mutex _processMutex = Mutex();

  @override
  Future<List<PendingGaslessTransfer>> listAmbiguousLegacyTransfers(
    WalletId walletId,
  ) {
    return _protect(() async {
      final snapshot = await _readLegacySnapshot(walletId);
      final resolution = await _readLegacyResolution(walletId);
      return snapshot.transfers
          .where(
            (transfer) =>
                !resolution.all.contains(_legacyFingerprint(transfer)),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<void> resolveAmbiguousLegacyTransfers(
    WalletId walletId, {
    required Map<String, Set<String>> ownedSourceAddressesByAsset,
  }) {
    return _protect(() async {
      if (ownedSourceAddressesByAsset.values.any((addresses) {
        return addresses.isEmpty ||
            addresses.any(
              (address) => address.isEmpty || address.trim() != address,
            );
      })) {
        throw ArgumentError.value(
          ownedSourceAddressesByAsset,
          'ownedSourceAddressesByAsset',
          'Fresh source-address sets must be non-empty',
        );
      }

      final snapshot = await _readLegacySnapshot(walletId);
      final resolution = await _readLegacyResolution(walletId);
      final unresolved = snapshot.transfers.where(
        (transfer) => !resolution.all.contains(_legacyFingerprint(transfer)),
      );
      final resolvable = unresolved.where(
        (transfer) => ownedSourceAddressesByAsset.containsKey(transfer.assetId),
      );
      if (resolvable.isEmpty) return;

      // Persist rename-stable discovery before writing either adopted records
      // or their resolution hashes. An interrupted migration must continue to
      // find every old compound-name key after a wallet rename.
      await _writeLegacyAliases(walletId, snapshot.storageKeys);

      final claimed = <String>{...resolution.claimed};
      final excluded = <String>{...resolution.excluded};
      final adopted = <PendingGaslessTransfer>[];
      for (final transfer in resolvable) {
        final fingerprint = _legacyFingerprint(transfer);
        final ownedSources = ownedSourceAddressesByAsset[transfer.assetId]!;
        if (ownedSources.contains(transfer.sourceAddress)) {
          claimed.add(fingerprint);
          excluded.remove(fingerprint);
          adopted.add(transfer);
        } else {
          excluded.add(fingerprint);
          claimed.remove(fingerprint);
        }
      }

      // Write adopted transfers first. If this succeeds but the resolution
      // write is interrupted, the next verification pass safely merges the
      // same records again. The inverse ordering could hide a transfer whose
      // scoped journal write never completed.
      if (adopted.isNotEmpty) {
        final current = await _readCurrentUnlocked(walletId);
        await _writeUnlocked(
          walletId,
          _mergeCorrelatedTransfers([...current, ...adopted]),
        );
      }
      await _writeLegacyResolution(
        walletId,
        _LegacyResolution(claimed: claimed, excluded: excluded),
      );
      notifyGaslessTransferChanged();
    });
  }

  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) {
    return _protect(() => _read(walletId));
  }

  @override
  Stream<List<PendingGaslessTransfer>> watch(WalletId walletId) async* {
    // Subscribe before reading the initial snapshot. A mutation concurrent
    // with that read is buffered instead of disappearing between the initial
    // yield and the broadcast-stream subscription.
    final changes = StreamController<void>();
    final subscription = gaslessTransferChanges.listen(
      (_) => changes.add(null),
    );
    try {
      yield await list(walletId);
      await for (final _ in changes.stream) {
        yield await list(walletId);
      }
    } finally {
      await subscription.cancel();
      // A single-subscription controller's close future does not complete
      // until it has been listened to. Cancellation can occur while this
      // async generator is still paused at its initial yield, before the
      // `await for` attaches that listener.
      unawaited(changes.close());
    }
  }

  @override
  Future<PendingGaslessTransfer?> find(
    WalletId walletId,
    String identity,
  ) async {
    final transfers = await list(walletId);
    return transfers
        .where(
          (transfer) =>
              transfer.journalId == identity || transfer.traceId == identity,
        )
        .firstOrNull;
  }

  @override
  Future<PendingGaslessTransfer?> findByJournalId(
    WalletId walletId,
    String journalId,
  ) async {
    final transfers = await list(walletId);
    return transfers
        .where((transfer) => transfer.journalId == journalId)
        .firstOrNull;
  }

  @override
  Future<PendingGaslessTransfer?> findByTraceId(
    WalletId walletId,
    String traceId,
  ) async {
    final transfers = await list(walletId);
    return transfers
        .where((transfer) => transfer.traceId == traceId)
        .firstOrNull;
  }

  @override
  Future<void> upsert(WalletId walletId, PendingGaslessTransfer transfer) {
    return _protect(() async {
      if (transfer.state.isTerminal) {
        await _removeCorrelatedUnlocked(
          walletId,
          journalId: transfer.journalId,
          traceId: transfer.traceId,
        );
        return;
      }

      final transfers = await _readUnlocked(walletId)
        // Replace the entire journal/trace correlation set in one encrypted
        // write. Replacing only the first match can leave the original
        // journal-only reservation beside the accepted trace record, locking
        // the custody source forever after a crash or migration.
        ..removeWhere(
          (item) =>
              item.journalId == transfer.journalId ||
              (transfer.traceId != null && item.traceId == transfer.traceId),
        )
        ..add(transfer);
      await _writeUnlocked(walletId, transfers);
      notifyGaslessTransferChanged();
    });
  }

  @override
  Future<bool> reserve(WalletId walletId, PendingGaslessTransfer transfer) {
    return _protect(() async {
      final transfers = await _readUnlocked(walletId);
      final conflicts = transfers.any(
        (item) =>
            item.journalId == transfer.journalId ||
            (item.assetId == transfer.assetId &&
                item.custodyAddress == transfer.custodyAddress),
      );
      if (conflicts) return false;
      transfers.add(transfer);
      await _writeUnlocked(walletId, transfers);
      notifyGaslessTransferChanged();
      return true;
    });
  }

  @override
  Future<void> remove(WalletId walletId, String identity) {
    return _protect(() => _removeUnlocked(walletId, identity));
  }

  Future<T> _protect<T>(Future<T> Function() operation) {
    return _processMutex.protect(() => withGaslessTransferLock(operation));
  }

  Future<void> _removeUnlocked(WalletId walletId, String identity) async {
    final transfers = await _readUnlocked(walletId);
    final correlated = transfers.where(
      (transfer) =>
          transfer.journalId == identity || transfer.traceId == identity,
    );
    final journalIds = correlated.map((transfer) => transfer.journalId).toSet();
    final traceIds = correlated
        .map((transfer) => transfer.traceId)
        .whereType<String>()
        .toSet();
    transfers.removeWhere(
      (transfer) =>
          transfer.journalId == identity ||
          transfer.traceId == identity ||
          journalIds.contains(transfer.journalId) ||
          (transfer.traceId != null && traceIds.contains(transfer.traceId)),
    );
    await _writeUnlocked(walletId, transfers);
    notifyGaslessTransferChanged();
  }

  Future<void> _removeCorrelatedUnlocked(
    WalletId walletId, {
    required String journalId,
    String? traceId,
  }) async {
    final transfers = await _readUnlocked(walletId)
      ..removeWhere(
        (transfer) =>
            transfer.journalId == journalId ||
            (traceId != null && transfer.traceId == traceId),
      );
    await _writeUnlocked(walletId, transfers);
    notifyGaslessTransferChanged();
  }

  Future<List<PendingGaslessTransfer>> _read(WalletId walletId) =>
      _readUnlocked(walletId);

  Future<List<PendingGaslessTransfer>> _readUnlocked(WalletId walletId) async {
    final legacy = await _readLegacySnapshot(walletId);
    final resolution = await _readLegacyResolution(walletId);
    final hasUnresolved = legacy.transfers.any(
      (transfer) => !resolution.all.contains(_legacyFingerprint(transfer)),
    );
    if (hasUnresolved) {
      throw const GaslessTransferLegacyResolutionException();
    }
    return _readCurrentUnlocked(walletId);
  }

  Future<List<PendingGaslessTransfer>> _readCurrentUnlocked(
    WalletId walletId,
  ) async {
    final current = _decodeTransfers(await _readStoredValue(_keyFor(walletId)));
    if (current == null) return <PendingGaslessTransfer>[];
    if (current.needsMigration) {
      await _writeUnlocked(walletId, current.transfers);
    }
    return current.transfers;
  }

  Future<_LegacyTransferSnapshot> _readLegacySnapshot(WalletId walletId) async {
    final storageKeys = <String>{
      ...await _discoverLegacyCompoundKeys(),
      ...await _readLegacyAliases(walletId),
      ...await _readAmbiguousLegacyAliases(walletId),
      ..._legacyScopedNamespaceKeysFor(walletId),
      ..._ambiguousPubkeyKeysFor(walletId),
      ..._legacyCompoundKeysFor(walletId),
    };
    final populatedKeys = <String>{};
    final transfers = <PendingGaslessTransfer>[];
    for (final storageKey in storageKeys) {
      final encoded = await _readStoredValue(storageKey);
      final decoded = _decodeTransfers(encoded);
      if (decoded == null) continue;
      final sanitized = _encodeTransfers(decoded.transfers);
      if (encoded != sanitized) {
        // Shared legacy journals could retain signed relay authorization
        // fields even if their envelope claimed a current schema. Rewrite
        // every successfully decoded shape in place before ownership
        // classification, preserving recovery metadata while removing all
        // replayable material. Older clients see V4 as unsupported and fail
        // closed instead of writing the unsafe shape back.
        await _writeTransfersAtKey(storageKey, decoded.transfers);
      }
      if (decoded.transfers.isEmpty) continue;
      populatedKeys.add(storageKey);
      transfers.addAll(decoded.transfers);
    }
    return _LegacyTransferSnapshot(
      transfers: _mergeCorrelatedTransfers(transfers),
      storageKeys: populatedKeys,
    );
  }

  Future<Set<String>> _discoverLegacyCompoundKeys() async {
    final storage = _storage;
    if (storage is! GaslessTransferKeyDiscovery) return const <String>{};
    final discovery = storage as GaslessTransferKeyDiscovery;

    final keys = await discovery.keysWithPrefix(
      '${_prefix}v1_',
      maxKeys: _maxDiscoveredLegacyCompoundKeys,
    );
    if (keys.any((key) => !_isLegacyCompoundStorageKey(key))) {
      // Discovery is a trust boundary: even a custom implementation may not
      // widen the scan beyond the exact, digest-suffixed V1 journal shape.
      throw const GaslessTransferStorageFormatException();
    }
    return keys;
  }

  Future<Set<String>> _readLegacyAliases(WalletId walletId) async {
    final aliases = <String>{};
    for (final entry in _legacyAliasStorageKeysFor(walletId).entries) {
      final encoded = await _readStoredValue(entry.key);
      if (encoded == null || encoded.isEmpty) continue;

      final decoded = _decodeStoredJson(encoded);
      if (decoded is! Map) {
        throw const FormatException(
          'Pending GasFree legacy alias storage is not an object',
        );
      }
      final json = convertToJsonMap(decoded);
      final unknownKeys = json.keys.toSet()
        ..removeAll(const {'version', 'wallet_namespace', 'legacy_keys'});
      if (unknownKeys.isNotEmpty) {
        throw const GaslessTransferStorageFormatException();
      }
      if (json.valueOrNull<int>('version') != _legacyAliasSchemaVersion) {
        throw StateError(
          'Pending GasFree legacy alias storage requires a newer schema',
        );
      }
      if (json.valueOrNull<String>('wallet_namespace') != entry.value) {
        throw StateError(
          'Pending GasFree legacy alias storage has the wrong wallet owner',
        );
      }
      final rawKeys = json['legacy_keys'];
      if (rawKeys is! List ||
          rawKeys.length > _maxScopedLegacyAliasesPerWallet ||
          rawKeys.any((key) => key is! String)) {
        throw const FormatException(
          'Pending GasFree legacy alias storage has invalid keys',
        );
      }
      final keys = rawKeys.cast<String>().toSet();
      if (keys.length != rawKeys.length ||
          keys.any((key) => !_isAmbiguousStorageKey(key))) {
        throw const FormatException(
          'Pending GasFree legacy alias storage has invalid keys',
        );
      }
      aliases.addAll(keys);
    }
    if (aliases.length > _maxScopedLegacyAliasesPerWallet) {
      throw StateError(
        'Pending GasFree legacy alias storage exceeds '
        '$_maxScopedLegacyAliasesPerWallet keys',
      );
    }
    return aliases;
  }

  Future<Set<String>> _readAmbiguousLegacyAliases(WalletId walletId) async {
    final aliases = <String>{};
    for (final aliasKey in _ambiguousLegacyAliasKeysFor(walletId)) {
      final encoded = await _readStoredValue(aliasKey);
      if (encoded == null || encoded.isEmpty) continue;
      final decoded = _decodeStoredJson(encoded);
      if (decoded is! Map) {
        throw const GaslessTransferStorageFormatException();
      }
      final json = convertToJsonMap(decoded);
      final unknownKeys = json.keys.toSet()
        ..removeAll(const {'version', 'wallet_fingerprint', 'legacy_keys'});
      if (unknownKeys.isNotEmpty ||
          json.valueOrNull<int>('version') != 1 ||
          !_ambiguousWalletFingerprints(
            walletId,
          ).contains(json.valueOrNull<String>('wallet_fingerprint'))) {
        throw const GaslessTransferStorageFormatException();
      }
      final rawKeys = json['legacy_keys'];
      if (rawKeys is! List ||
          rawKeys.length > _maxAmbiguousLegacyAliasesPerWallet ||
          rawKeys.any((key) => key is! String)) {
        throw const GaslessTransferStorageFormatException();
      }
      final keys = rawKeys.cast<String>().toSet();
      if (keys.length != rawKeys.length ||
          keys.any((key) => !_isLegacyCompoundStorageKey(key))) {
        throw const GaslessTransferStorageFormatException();
      }
      aliases.addAll(keys);
    }
    return aliases;
  }

  Future<_LegacyResolution> _readLegacyResolution(WalletId walletId) async {
    final encoded = await _readStoredValue(_legacyResolutionKeyFor(walletId));
    if (encoded == null || encoded.isEmpty) return const _LegacyResolution();
    final decoded = _decodeStoredJson(encoded);
    if (decoded is! Map) {
      throw const GaslessTransferStorageFormatException();
    }
    final json = convertToJsonMap(decoded);
    final unknownKeys = json.keys.toSet()
      ..removeAll(const {'version', 'wallet_namespace', 'claimed', 'excluded'});
    if (unknownKeys.isNotEmpty ||
        json.valueOrNull<int>('version') != _legacyResolutionSchemaVersion ||
        json.valueOrNull<String>('wallet_namespace') !=
            _walletNamespace(walletId)) {
      throw const GaslessTransferStorageFormatException();
    }
    final claimed = _readFingerprintSet(json['claimed']);
    final excluded = _readFingerprintSet(json['excluded']);
    if (claimed.intersection(excluded).isNotEmpty ||
        claimed.length + excluded.length > _maxLegacyResolutionsPerWallet) {
      throw const GaslessTransferStorageFormatException();
    }
    return _LegacyResolution(claimed: claimed, excluded: excluded);
  }

  Set<String> _readFingerprintSet(Object? raw) {
    if (raw is! List ||
        raw.length > _maxLegacyResolutionsPerWallet ||
        raw.any((value) => value is! String)) {
      throw const GaslessTransferStorageFormatException();
    }
    final values = raw.cast<String>().toSet();
    if (values.length != raw.length ||
        values.any((value) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(value))) {
      throw const GaslessTransferStorageFormatException();
    }
    return values;
  }

  Future<String?> _readStoredValue(String key) async {
    final existedBeforeRead = await _storage.containsKey(key);
    final encoded = await _storage.read(key);
    if (encoded != null && encoded.isNotEmpty) return encoded;

    // Check again so a value that appeared concurrently but could not be
    // decrypted is never mistaken for an absent journal. A concurrent delete
    // may cause a conservative, retryable failure, which is safer than a
    // false-empty result for no-blind-resubmit guarantees.
    if (existedBeforeRead || await _storage.containsKey(key)) {
      throw const GaslessTransferStorageReadException();
    }
    return null;
  }

  Future<void> _writeLegacyAliases(
    WalletId walletId,
    Set<String> legacyKeys,
  ) async {
    if (legacyKeys.isEmpty) return;
    final current = await _readLegacyAliases(walletId);
    final aliases = <String>{...current, ...legacyKeys};
    if (aliases.length > _maxScopedLegacyAliasesPerWallet) {
      throw StateError(
        'Pending GasFree legacy alias storage exceeds '
        '$_maxScopedLegacyAliasesPerWallet keys',
      );
    }
    if (aliases.any((key) => !_isAmbiguousStorageKey(key))) {
      throw const FormatException(
        'Pending GasFree legacy alias storage has invalid keys',
      );
    }
    final sortedAliases = aliases.toList()..sort();
    await _storage.write(
      _legacyAliasKeyFor(walletId),
      jsonEncode({
        'version': _legacyAliasSchemaVersion,
        'wallet_namespace': _walletNamespace(walletId),
        'legacy_keys': sortedAliases,
      }),
    );
  }

  Future<void> _writeLegacyResolution(
    WalletId walletId,
    _LegacyResolution resolution,
  ) async {
    if (resolution.claimed.intersection(resolution.excluded).isNotEmpty ||
        resolution.claimed.length + resolution.excluded.length >
            _maxLegacyResolutionsPerWallet) {
      throw StateError('Pending GasFree legacy resolution storage is invalid');
    }
    final claimed = resolution.claimed.toList()..sort();
    final excluded = resolution.excluded.toList()..sort();
    await _storage.write(
      _legacyResolutionKeyFor(walletId),
      jsonEncode({
        'version': _legacyResolutionSchemaVersion,
        'wallet_namespace': _walletNamespace(walletId),
        'claimed': claimed,
        'excluded': excluded,
      }),
    );
  }

  _DecodedPendingTransfers? _decodeTransfers(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = _decodeStoredJson(encoded);
    final List<dynamic> rawTransfers;
    var needsMigration = false;
    if (decoded is List) {
      // Pre-versioned development builds stored the transfer array directly.
      rawTransfers = decoded;
      needsMigration = true;
    } else if (decoded is Map) {
      late final JsonMap json;
      late final int version;
      try {
        json = convertToJsonMap(decoded);
        version = json.valueOrNull<int>('version') ?? 0;
      } on Object {
        // Persisted input passes through generated readers that can throw
        // Error subclasses. Replace every such failure at this privacy
        // boundary so decrypted source values never reach logs.
        throw const GaslessTransferStorageFormatException();
      }
      if (version > _schemaVersion) {
        // Keep the original encrypted value untouched. The caller must surface
        // this blocker instead of silently hiding a possibly submitted relay.
        throw StateError(
          'Pending GasFree storage requires a newer schema: $version',
        );
      }
      if (version < _schemaVersion) needsMigration = true;
      final transfers = json['transfers'];
      if (transfers is! List) {
        throw const FormatException(
          'Pending GasFree storage has no transfer list',
        );
      }
      rawTransfers = transfers;
    } else {
      throw const FormatException(
        'Pending GasFree storage is not a list or object',
      );
    }

    if (rawTransfers.any((item) => item is! Map)) {
      throw const FormatException(
        'Pending GasFree storage contains an invalid transfer',
      );
    }
    final List<PendingGaslessTransfer> transfers;
    try {
      transfers = <PendingGaslessTransfer>[
        for (final item in rawTransfers)
          PendingGaslessTransfer.fromJson(
            convertToJsonMap(item as Map<dynamic, dynamic>),
          ),
      ]..removeWhere((transfer) => transfer.state.isTerminal);
      if (transfers.any(_hasInvalidPersistedIdentity)) {
        throw const FormatException(
          'Pending GasFree transfer has invalid identity fields',
        );
      }
    } on Object {
      // See the envelope guard above. ArgumentError from invalid generated
      // enum values is input corruption too and can contain decrypted source.
      throw const GaslessTransferStorageFormatException();
    }
    transfers.sort((a, b) => a.acceptedAt.compareTo(b.acceptedAt));
    return _DecodedPendingTransfers(
      transfers: transfers,
      needsMigration: needsMigration,
    );
  }

  bool _hasInvalidPersistedIdentity(PendingGaslessTransfer transfer) {
    final requiredValues = <String>[
      transfer.journalId,
      transfer.assetId,
      transfer.network,
      transfer.sourceAddress,
      transfer.custodyAddress,
      transfer.destinationAddress,
    ];
    final traceId = transfer.traceId;
    return requiredValues.any(
          (value) => value.isEmpty || value.trim() != value,
        ) ||
        (traceId != null && (traceId.isEmpty || traceId.trim() != traceId));
  }

  Object? _decodeStoredJson(String encoded) {
    try {
      return jsonDecode(encoded);
    } on FormatException {
      throw const GaslessTransferStorageFormatException();
    }
  }

  List<PendingGaslessTransfer> _mergeCorrelatedTransfers(
    List<PendingGaslessTransfer> candidates,
  ) {
    final merged = <PendingGaslessTransfer>[];
    for (final candidate in candidates) {
      final index = merged.indexWhere((existing) {
        final sameTransferContext =
            existing.assetId == candidate.assetId &&
            existing.network == candidate.network &&
            existing.sourceAddress == candidate.sourceAddress &&
            existing.custodyAddress == candidate.custodyAddress &&
            existing.destinationAddress == candidate.destinationAddress;
        if (!sameTransferContext) return false;
        final sameTrace =
            existing.traceId != null &&
            candidate.traceId != null &&
            existing.traceId == candidate.traceId;
        final sameJournal = existing.journalId == candidate.journalId;
        if (sameJournal) {
          return existing.traceId == candidate.traceId ||
              existing.traceId == null ||
              candidate.traceId == null;
        }
        return sameTrace &&
            (existing.journalId.startsWith('legacy:') ||
                candidate.journalId.startsWith('legacy:'));
      });
      if (index < 0) {
        merged.add(candidate);
        continue;
      }
      merged[index] = _richerTransfer(merged[index], candidate);
    }
    merged.sort((a, b) => a.acceptedAt.compareTo(b.acceptedAt));
    return merged;
  }

  PendingGaslessTransfer _richerTransfer(
    PendingGaslessTransfer left,
    PendingGaslessTransfer right,
  ) {
    final metadata = _transferRichness(right) > _transferRichness(left)
        ? right
        : left;
    final lifecycle =
        _stateRank(right.state) > _stateRank(left.state) ||
            (_stateRank(right.state) == _stateRank(left.state) &&
                right.updatedAt.isAfter(left.updatedAt))
        ? right
        : left;
    final journalId = metadata.journalId.startsWith('legacy:')
        ? (left.journalId.startsWith('legacy:')
              ? right.journalId
              : left.journalId)
        : metadata.journalId;
    return PendingGaslessTransfer(
      traceId: metadata.traceId ?? lifecycle.traceId,
      journalId: journalId,
      assetId: metadata.assetId,
      network: metadata.network,
      sourceAddress: metadata.sourceAddress,
      custodyAddress: metadata.custodyAddress,
      destinationAddress: metadata.destinationAddress,
      requestedAmount: metadata.requestedAmount,
      signedMaxFee: metadata.signedMaxFee,
      authorizationDeadline: metadata.authorizationDeadline,
      balanceChanges: metadata.balanceChanges,
      fee: lifecycle.fee,
      acceptedAt: left.acceptedAt.isBefore(right.acceptedAt)
          ? left.acceptedAt
          : right.acceptedAt,
      updatedAt: left.updatedAt.isAfter(right.updatedAt)
          ? left.updatedAt
          : right.updatedAt,
      state: lifecycle.state,
    );
  }

  int _transferRichness(PendingGaslessTransfer transfer) {
    var score = transfer.traceId == null ? 0 : 100;
    if (transfer.state != GaslessTransferState.preparing) score += 20;
    return score;
  }

  int _stateRank(GaslessTransferState state) => switch (state) {
    GaslessTransferState.preparing ||
    GaslessTransferState.rejectedBeforeRelay => 0,
    // Unknown is a no-resubmit safety state, not authoritative relay
    // progression. It supersedes a pre-submit reservation, but an accepted
    // trace state recovered from KDF supersedes it.
    GaslessTransferState.submittedUnknown => 1,
    GaslessTransferState.submittedPending => 2,
    GaslessTransferState.confirming => 3,
    GaslessTransferState.confirmed || GaslessTransferState.failedFinal => 4,
  };

  Future<void> _writeUnlocked(
    WalletId walletId,
    List<PendingGaslessTransfer> transfers,
  ) async {
    final key = _keyFor(walletId);
    if (transfers.isEmpty) {
      await _storage.delete(key);
      return;
    }
    await _writeTransfersAtKey(key, transfers);
  }

  Future<void> _writeTransfersAtKey(
    String key,
    List<PendingGaslessTransfer> transfers,
  ) async {
    await _storage.write(key, _encodeTransfers(transfers));
  }

  String _encodeTransfers(List<PendingGaslessTransfer> transfers) =>
      jsonEncode({
        'version': _schemaVersion,
        'transfers': transfers.map((transfer) => transfer.toJson()).toList(),
      });

  String _keyFor(WalletId walletId) {
    return '${_prefix}v3_${_walletNamespace(walletId)}';
  }

  Set<String> _legacyCompoundKeysFor(WalletId walletId) {
    final pubkeyHash = _normalizedPubkeyHash(walletId);
    final identities = <String>{
      walletId.compoundId,
      '${walletId.name}:$pubkeyHash',
    };
    return {
      for (final identity in identities)
        '${_prefix}v1_${sha256.convert(utf8.encode(identity))}',
    };
  }

  Set<String> _legacyScopedNamespaceKeysFor(WalletId walletId) => {
    for (final namespace in legacyWalletStorageNamespaces(walletId))
      '${_prefix}v3_$namespace',
  };

  String _legacyAliasKeyFor(WalletId walletId) =>
      '${_prefix}legacy_aliases_v2_${_walletNamespace(walletId)}';

  Map<String, String> _legacyAliasStorageKeysFor(WalletId walletId) {
    final currentNamespace = _walletNamespace(walletId);
    final namespaces = <String>{
      currentNamespace,
      ...legacyWalletStorageNamespaces(walletId),
    };
    return {
      for (final namespace in namespaces)
        '${_prefix}legacy_aliases_v2_$namespace': namespace,
    };
  }

  String _legacyResolutionKeyFor(WalletId walletId) =>
      '${_prefix}legacy_resolution_v1_${_walletNamespace(walletId)}';

  Set<String> _ambiguousPubkeyKeysFor(WalletId walletId) => {
    for (final fingerprint in _ambiguousWalletFingerprints(walletId))
      '${_prefix}v2_$fingerprint',
  };

  Set<String> _ambiguousLegacyAliasKeysFor(WalletId walletId) => {
    for (final fingerprint in _ambiguousWalletFingerprints(walletId))
      '${_prefix}legacy_aliases_v1_$fingerprint',
  };

  Set<String> _ambiguousWalletFingerprints(WalletId walletId) {
    final rawPubkeyHash = _requiredPubkeyHash(walletId);
    final identities = <String>{rawPubkeyHash, rawPubkeyHash.toLowerCase()};
    return {
      for (final identity in identities)
        sha256.convert(utf8.encode(identity)).toString(),
    };
  }

  String _walletNamespace(WalletId walletId) {
    _requiredPubkeyHash(walletId);
    return walletStorageNamespace(walletId);
  }

  String _normalizedPubkeyHash(WalletId walletId) =>
      _requiredPubkeyHash(walletId).toLowerCase();

  String _requiredPubkeyHash(WalletId walletId) {
    final pubkeyHash = walletId.pubkeyHash?.trim();
    if (pubkeyHash == null || pubkeyHash.isEmpty) {
      throw StateError(
        'GasFree pending storage requires an authenticated wallet identity',
      );
    }
    return pubkeyHash;
  }

  String _legacyFingerprint(PendingGaslessTransfer transfer) {
    final canonicalIdentity = jsonEncode({
      'asset_id': transfer.assetId,
      'authorization_deadline': transfer.authorizationDeadline.toString(),
      'custody_address': transfer.custodyAddress,
      'destination_address': transfer.destinationAddress,
      'journal_id': transfer.journalId,
      'network': transfer.network,
      'requested_amount': transfer.requestedAmount.toString(),
      'signed_max_fee': transfer.signedMaxFee.toString(),
      'source_address': transfer.sourceAddress,
      'trace_id': transfer.traceId,
    });
    return sha256.convert(utf8.encode(canonicalIdentity)).toString();
  }

  bool _isLegacyCompoundStorageKey(String key) {
    const prefix = '${_prefix}v1_';
    if (!key.startsWith(prefix)) return false;
    final digest = key.substring(prefix.length);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  }

  bool _isAmbiguousPubkeyStorageKey(String key) {
    const prefix = '${_prefix}v2_';
    if (!key.startsWith(prefix)) return false;
    final digest = key.substring(prefix.length);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  }

  bool _isLegacyScopedNamespaceStorageKey(String key) {
    const prefix = '${_prefix}v3_v1:';
    if (!key.startsWith(prefix)) return false;
    final digest = key.substring(prefix.length);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  }

  bool _isAmbiguousStorageKey(String key) =>
      _isLegacyCompoundStorageKey(key) ||
      _isAmbiguousPubkeyStorageKey(key) ||
      _isLegacyScopedNamespaceStorageKey(key);
}
