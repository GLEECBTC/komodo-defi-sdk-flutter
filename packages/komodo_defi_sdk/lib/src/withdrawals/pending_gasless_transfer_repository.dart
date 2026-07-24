import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

abstract interface class GaslessTransferKeyValueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Secure-storage implementation used by production SDK instances.
class SecureGaslessTransferStorage implements GaslessTransferKeyValueStorage {
  SecureGaslessTransferStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

abstract interface class PendingGaslessTransferRepository {
  Future<List<PendingGaslessTransfer>> list(WalletId walletId);

  Stream<List<PendingGaslessTransfer>> watch(WalletId walletId);

  /// Finds a transfer by either its local journal ID or accepted trace ID.
  Future<PendingGaslessTransfer?> find(WalletId walletId, String identity);

  Future<PendingGaslessTransfer?> findByJournalId(
    WalletId walletId,
    String journalId,
  );

  Future<PendingGaslessTransfer?> findByTraceId(
    WalletId walletId,
    String traceId,
  );

  Future<void> upsert(WalletId walletId, PendingGaslessTransfer transfer);

  /// Atomically reserves one unresolved send per wallet/asset/custody source.
  Future<bool> reserve(WalletId walletId, PendingGaslessTransfer transfer);

  Future<void> remove(WalletId walletId, String identity);
}

final class _DecodedPendingTransfers {
  const _DecodedPendingTransfers(this.transfers, this.needsMigration);

  final List<PendingGaslessTransfer> transfers;
  final bool needsMigration;
}

/// Versioned, encrypted repository for unresolved GasFree relay transfers.
class SecurePendingGaslessTransferRepository
    implements PendingGaslessTransferRepository {
  SecurePendingGaslessTransferRepository({
    GaslessTransferKeyValueStorage? storage,
  }) : _storage = storage ?? SecureGaslessTransferStorage();

  static const _prefix = 'gasless_pending_transfers_';
  static const _schemaVersion = 3;
  static const _legacyAliasSchemaVersion = 1;
  static const _maxLegacyAliasesPerWallet = 16;

  final GaslessTransferKeyValueStorage _storage;
  final Mutex _mutex = Mutex();
  final StreamController<String> _changes = StreamController.broadcast();

  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) {
    return _mutex.protect(() => _read(walletId));
  }

  @override
  Stream<List<PendingGaslessTransfer>> watch(WalletId walletId) async* {
    final scope = _walletScope(walletId);
    // Subscribe before reading the initial snapshot. A mutation concurrent
    // with that read is buffered instead of disappearing between the initial
    // yield and the broadcast-stream subscription.
    final changes = StreamController<void>();
    final subscription = _changes.stream
        .where((changedScope) => changedScope == scope)
        .listen((_) => changes.add(null));
    try {
      yield await list(walletId);
      await for (final _ in changes.stream) {
        yield await list(walletId);
      }
    } finally {
      await subscription.cancel();
      await changes.close();
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
    return _mutex.protect(() async {
      if (transfer.state.isTerminal) {
        await _removeCorrelatedUnlocked(
          walletId,
          journalId: transfer.journalId,
          traceId: transfer.traceId,
        );
        return;
      }

      final transfers = await _readUnlocked(walletId);
      // Replace the entire journal/trace correlation set in one encrypted
      // write. Replacing only the first match can leave the original
      // journal-only reservation beside the accepted trace record, locking the
      // custody source forever after a crash or migration.
      transfers.removeWhere(
        (item) =>
            item.journalId == transfer.journalId ||
            (transfer.traceId != null && item.traceId == transfer.traceId),
      );
      transfers.add(transfer);
      await _writeUnlocked(walletId, transfers);
      _changes.add(_walletScope(walletId));
    });
  }

  @override
  Future<bool> reserve(WalletId walletId, PendingGaslessTransfer transfer) {
    return _mutex.protect(() async {
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
      _changes.add(_walletScope(walletId));
      return true;
    });
  }

  @override
  Future<void> remove(WalletId walletId, String identity) {
    return _mutex.protect(() => _removeUnlocked(walletId, identity));
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
    _changes.add(_walletScope(walletId));
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
    _changes.add(_walletScope(walletId));
  }

  Future<List<PendingGaslessTransfer>> _read(WalletId walletId) =>
      _readUnlocked(walletId);

  Future<List<PendingGaslessTransfer>> _readUnlocked(WalletId walletId) async {
    final key = _keyFor(walletId);
    final currentLegacyKey = _legacyKeyFor(walletId);
    final registeredLegacyKeys = await _readLegacyAliases(walletId);
    final legacyKeys = <String>{...registeredLegacyKeys, currentLegacyKey};
    final encoded = await _storage.read(key);
    final current = _decodeTransfers(encoded);
    final legacy = <(String, _DecodedPendingTransfers)>[];
    for (final legacyKey in legacyKeys) {
      final decoded = _decodeTransfers(await _storage.read(legacyKey));
      if (decoded != null) legacy.add((legacyKey, decoded));
    }

    if (legacy.isNotEmpty) {
      // Register ownership before rewriting the journal. If stable-key
      // migration is interrupted and the wallet is subsequently renamed, the
      // old compound-ID key remains discoverable without enumerating another
      // wallet's secure-storage records.
      await _writeLegacyAliases(
        walletId,
        legacy.map((entry) => entry.$1).toSet(),
      );
    }

    if (current == null && legacy.isEmpty) {
      if (registeredLegacyKeys.isNotEmpty) {
        await _deleteLegacyAliases(walletId);
      }
      return <PendingGaslessTransfer>[];
    }
    final transfers = _mergeCorrelatedTransfers([
      ...?current?.transfers,
      for (final entry in legacy) ...entry.$2.transfers,
    ]);
    final needsMigration = current?.needsMigration == true || legacy.isNotEmpty;
    if (needsMigration) {
      await _writeUnlocked(walletId, transfers);
      for (final entry in legacy) {
        await _storage.delete(entry.$1);
      }
    }
    if (registeredLegacyKeys.isNotEmpty || legacy.isNotEmpty) {
      await _deleteLegacyAliases(walletId);
    }
    return transfers;
  }

  Future<Set<String>> _readLegacyAliases(WalletId walletId) async {
    final encoded = await _storage.read(_legacyAliasKeyFor(walletId));
    if (encoded == null || encoded.isEmpty) return <String>{};

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException(
        'Pending GasFree legacy alias storage is not an object',
      );
    }
    final json = convertToJsonMap(decoded);
    final unknownKeys = json.keys.toSet()
      ..removeAll(const {'version', 'wallet_fingerprint', 'legacy_keys'});
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'Pending GasFree legacy alias storage contains unknown fields: '
        '${unknownKeys.join(', ')}',
      );
    }
    if (json.valueOrNull<int>('version') != _legacyAliasSchemaVersion) {
      throw StateError(
        'Pending GasFree legacy alias storage requires a newer schema',
      );
    }
    if (json.valueOrNull<String>('wallet_fingerprint') !=
        _walletFingerprint(walletId)) {
      throw StateError(
        'Pending GasFree legacy alias storage has the wrong wallet owner',
      );
    }
    final rawKeys = json['legacy_keys'];
    if (rawKeys is! List ||
        rawKeys.length > _maxLegacyAliasesPerWallet ||
        rawKeys.any((key) => key is! String)) {
      throw const FormatException(
        'Pending GasFree legacy alias storage has invalid keys',
      );
    }
    final keys = rawKeys.cast<String>().toSet();
    if (keys.length != rawKeys.length ||
        keys.any((key) => !_isLegacyStorageKey(key))) {
      throw const FormatException(
        'Pending GasFree legacy alias storage has invalid keys',
      );
    }
    return keys;
  }

  Future<void> _writeLegacyAliases(
    WalletId walletId,
    Set<String> legacyKeys,
  ) async {
    if (legacyKeys.isEmpty) return;
    final current = await _readLegacyAliases(walletId);
    final aliases = <String>{...current, ...legacyKeys};
    if (aliases.length > _maxLegacyAliasesPerWallet) {
      throw StateError(
        'Pending GasFree legacy alias storage exceeds '
        '$_maxLegacyAliasesPerWallet keys',
      );
    }
    if (aliases.any((key) => !_isLegacyStorageKey(key))) {
      throw const FormatException(
        'Pending GasFree legacy alias storage has invalid keys',
      );
    }
    final sortedAliases = aliases.toList()..sort();
    await _storage.write(
      _legacyAliasKeyFor(walletId),
      jsonEncode({
        'version': _legacyAliasSchemaVersion,
        'wallet_fingerprint': _walletFingerprint(walletId),
        'legacy_keys': sortedAliases,
      }),
    );
  }

  Future<void> _deleteLegacyAliases(WalletId walletId) =>
      _storage.delete(_legacyAliasKeyFor(walletId));

  _DecodedPendingTransfers? _decodeTransfers(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = jsonDecode(encoded);
    final List<dynamic> rawTransfers;
    var needsMigration = false;
    if (decoded is List) {
      // Pre-versioned development builds stored the transfer array directly.
      rawTransfers = decoded;
      needsMigration = true;
    } else if (decoded is Map) {
      final json = convertToJsonMap(decoded);
      final version = json.valueOrNull<int>('version') ?? 0;
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
    final transfers = <PendingGaslessTransfer>[
      for (final item in rawTransfers)
        PendingGaslessTransfer.fromJson(
          convertToJsonMap(item as Map<dynamic, dynamic>),
        ),
    ]..removeWhere((transfer) => transfer.state.isTerminal);
    transfers.sort((a, b) => a.acceptedAt.compareTo(b.acceptedAt));
    return _DecodedPendingTransfers(transfers, needsMigration);
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
    await _storage.write(
      key,
      jsonEncode({
        'version': _schemaVersion,
        'transfers': transfers.map((transfer) => transfer.toJson()).toList(),
      }),
    );
  }

  String _keyFor(WalletId walletId) {
    return '${_prefix}v2_${_walletFingerprint(walletId)}';
  }

  String _walletScope(WalletId walletId) =>
      walletId.pubkeyHash?.trim() ?? walletId.compoundId;

  String _legacyKeyFor(WalletId walletId) {
    final walletHash = sha256.convert(utf8.encode(walletId.compoundId));
    return '${_prefix}v1_$walletHash';
  }

  String _legacyAliasKeyFor(WalletId walletId) =>
      '${_prefix}legacy_aliases_v1_${_walletFingerprint(walletId)}';

  String _walletFingerprint(WalletId walletId) {
    final stableIdentity = walletId.pubkeyHash?.trim();
    if (stableIdentity == null || stableIdentity.isEmpty) {
      throw StateError(
        'GasFree pending storage requires an authenticated wallet identity',
      );
    }
    return sha256.convert(utf8.encode(stableIdentity)).toString();
  }

  bool _isLegacyStorageKey(String key) {
    const prefix = '${_prefix}v1_';
    if (!key.startsWith(prefix)) return false;
    final digest = key.substring(prefix.length);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  }
}
