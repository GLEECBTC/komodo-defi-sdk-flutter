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

  /// Finds a transfer by either its required request ID or accepted trace ID.
  Future<PendingGaslessTransfer?> find(WalletId walletId, String identity);

  Future<PendingGaslessTransfer?> findByRequestId(
    WalletId walletId,
    String requestId,
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
  static const _schemaVersion = 2;

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
    yield await list(walletId);
    await for (final changedScope in _changes.stream) {
      if (changedScope == scope) yield await list(walletId);
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
              transfer.requestId == identity || transfer.traceId == identity,
        )
        .firstOrNull;
  }

  @override
  Future<PendingGaslessTransfer?> findByRequestId(
    WalletId walletId,
    String requestId,
  ) async {
    final transfers = await list(walletId);
    return transfers
        .where((transfer) => transfer.requestId == requestId)
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
          requestId: transfer.requestId,
          traceId: transfer.traceId,
        );
        return;
      }

      final transfers = await _readUnlocked(walletId);
      // Replace the entire request/trace correlation set in one encrypted
      // write. Replacing only the first match can leave the original
      // request-only reservation beside the accepted trace record, locking the
      // custody source forever after a crash or migration.
      transfers.removeWhere(
        (item) =>
            item.requestId == transfer.requestId ||
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
            item.requestId == transfer.requestId ||
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
          transfer.requestId == identity || transfer.traceId == identity,
    );
    final requestIds = correlated.map((transfer) => transfer.requestId).toSet();
    final traceIds = correlated
        .map((transfer) => transfer.traceId)
        .whereType<String>()
        .toSet();
    transfers.removeWhere(
      (transfer) =>
          transfer.requestId == identity ||
          transfer.traceId == identity ||
          requestIds.contains(transfer.requestId) ||
          (transfer.traceId != null && traceIds.contains(transfer.traceId)),
    );
    await _writeUnlocked(walletId, transfers);
    _changes.add(_walletScope(walletId));
  }

  Future<void> _removeCorrelatedUnlocked(
    WalletId walletId, {
    required String requestId,
    String? traceId,
  }) async {
    final transfers = await _readUnlocked(walletId)
      ..removeWhere(
        (transfer) =>
            transfer.requestId == requestId ||
            (traceId != null && transfer.traceId == traceId),
      );
    await _writeUnlocked(walletId, transfers);
    _changes.add(_walletScope(walletId));
  }

  Future<List<PendingGaslessTransfer>> _read(WalletId walletId) =>
      _readUnlocked(walletId);

  Future<List<PendingGaslessTransfer>> _readUnlocked(WalletId walletId) async {
    final key = _keyFor(walletId);
    final legacyKey = _legacyKeyFor(walletId);
    final encoded = await _storage.read(key);
    final legacyEncoded = legacyKey == key
        ? null
        : await _storage.read(legacyKey);
    final current = _decodeTransfers(encoded);
    final legacy = _decodeTransfers(legacyEncoded);
    if (current == null && legacy == null) return <PendingGaslessTransfer>[];
    final transfers = _mergeCorrelatedTransfers([
      ...?current?.transfers,
      ...?legacy?.transfers,
    ]);
    final needsMigration =
        current?.needsMigration == true ||
        legacy != null ||
        legacy?.needsMigration == true;
    if (needsMigration) {
      await _writeUnlocked(walletId, transfers);
      if (legacyKey != key) await _storage.delete(legacyKey);
    }
    return transfers;
  }

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
        final sameRequest = existing.requestId == candidate.requestId;
        if (sameRequest) {
          return existing.traceId == candidate.traceId ||
              existing.traceId == null ||
              candidate.traceId == null;
        }
        return sameTrace &&
            (existing.requestId.startsWith('legacy:') ||
                candidate.requestId.startsWith('legacy:'));
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
    final requestId = metadata.requestId.startsWith('legacy:')
        ? (left.requestId.startsWith('legacy:')
              ? right.requestId
              : left.requestId)
        : metadata.requestId;
    return PendingGaslessTransfer(
      traceId: metadata.traceId ?? lifecycle.traceId,
      requestId: requestId,
      provider: metadata.provider ?? lifecycle.provider,
      tokenContract: metadata.tokenContract ?? lifecycle.tokenContract,
      authorizationNonce:
          metadata.authorizationNonce ?? lifecycle.authorizationNonce,
      authorizationVersion:
          metadata.authorizationVersion ?? lifecycle.authorizationVersion,
      authorizationAmount:
          metadata.authorizationAmount ?? lifecycle.authorizationAmount,
      authorizationMaxFee:
          metadata.authorizationMaxFee ?? lifecycle.authorizationMaxFee,
      assetId: metadata.assetId,
      network: metadata.network,
      sourceAddress: metadata.sourceAddress,
      custodyAddress: metadata.custodyAddress,
      destinationAddress: metadata.destinationAddress,
      requestedAmount: metadata.requestedAmount,
      signedMaxFee: metadata.signedMaxFee,
      authorizationDeadline: metadata.authorizationDeadline,
      authorizationFingerprint: metadata.authorizationFingerprint,
      balanceChanges: metadata.balanceChanges,
      fee: lifecycle.fee,
      acceptedAt: left.acceptedAt.isBefore(right.acceptedAt)
          ? left.acceptedAt
          : right.acceptedAt,
      updatedAt: left.updatedAt.isAfter(right.updatedAt)
          ? left.updatedAt
          : right.updatedAt,
      state: lifecycle.state,
      verificationMode: metadata.verificationMode,
    );
  }

  int _transferRichness(PendingGaslessTransfer transfer) {
    var score = transfer.traceId == null ? 0 : 100;
    if (transfer.state != GaslessTransferState.preparing) score += 20;
    if (transfer.provider?.isNotEmpty == true) score++;
    if (transfer.tokenContract?.isNotEmpty == true) score++;
    if (transfer.authorizationAmount?.isNotEmpty == true) score++;
    if (transfer.authorizationMaxFee?.isNotEmpty == true) score++;
    return score;
  }

  int _stateRank(GaslessTransferState state) => switch (state) {
    GaslessTransferState.preparing ||
    GaslessTransferState.rejectedBeforeRelay => 0,
    GaslessTransferState.submittedPending => 1,
    GaslessTransferState.confirming => 2,
    GaslessTransferState.submittedUnknown => 3,
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
    final stableIdentity = walletId.pubkeyHash?.trim();
    if (stableIdentity == null || stableIdentity.isEmpty) {
      throw StateError(
        'GasFree pending storage requires an authenticated wallet identity',
      );
    }
    final walletHash = sha256.convert(utf8.encode(stableIdentity));
    return '${_prefix}v2_$walletHash';
  }

  String _walletScope(WalletId walletId) =>
      walletId.pubkeyHash?.trim() ?? walletId.compoundId;

  String _legacyKeyFor(WalletId walletId) {
    final walletHash = sha256.convert(utf8.encode(walletId.compoundId));
    return '${_prefix}v1_$walletHash';
  }
}
