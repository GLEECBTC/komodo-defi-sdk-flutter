import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/security/private_key_conversion_extension.dart';
import 'package:komodo_defi_sdk/src/security/private_key_export_request.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A capability tied to a verified wallet and authentication transition.
/// Retain it across confirmation and save dialogs, checking before disclosure.
class PrivateKeyExportSession {
  const PrivateKeyExportSession._(this.walletId, this.generation, this._owner);

  final Object _owner;

  /// Verified wallet selected when the operation began.
  final WalletId walletId;

  /// Source-owned epoch; also changes on same-wallet reauthentication.
  final int generation;

  @override
  String toString() => 'PrivateKeyExportSession(redacted)';
}

/// Recovery operations bound to the authoritative authentication generation.
class SecurityManager {
  /// Creates recovery operations for the current authenticated wallet.
  SecurityManager(
    this._client,
    this._auth,
    this._assetProvider,
    this._activationCoordinator,
  );

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;
  final Object _sessionOwner = Object();
  bool _disposed = false;

  /// Captures an authenticated wallet with a verified public identity.
  Future<PrivateKeyExportSession> captureExportSession() async {
    if (_disposed || _auth.isAuthTransitionInProgress) {
      throw const PrivateKeyExportSessionChangedException();
    }
    final generation = _auth.authGeneration;
    final user = await _auth.currentUser;
    if (generation != _auth.authGeneration ||
        _auth.isAuthTransitionInProgress) {
      throw const PrivateKeyExportSessionChangedException();
    }
    if (user == null) throw AuthException.notSignedIn();
    if (user.walletId.pubkeyHash?.trim().isNotEmpty != true) {
      throw const PrivateKeyExportSessionChangedException();
    }
    return PrivateKeyExportSession._(user.walletId, generation, _sessionOwner);
  }

  /// Rejects intervening sign-outs, restarts, or verified identity changes.
  Future<void> ensureExportSessionCurrent(
    PrivateKeyExportSession session,
  ) async {
    _checkGeneration(session);
    final user = await _auth.currentUser;
    _checkGeneration(session);
    final identity = user?.walletId.pubkeyHash?.trim().toLowerCase();
    if (user == null ||
        identity == null ||
        identity.isEmpty ||
        identity != session.walletId.pubkeyHash?.trim().toLowerCase() ||
        user.walletId.authOptions != session.walletId.authOptions) {
      throw const PrivateKeyExportSessionChangedException();
    }
  }

  void _checkGeneration(PrivateKeyExportSession session) {
    if (!identical(session._owner, _sessionOwner) ||
        _disposed ||
        _auth.authGeneration != session.generation ||
        _auth.isAuthTransitionInProgress) {
      throw const PrivateKeyExportSessionChangedException();
    }
  }

  /// Final synchronous disclosure guard after fresh asynchronous verification.
  /// Call immediately before clipboard, file-write, or share handoff, with no
  /// intervening await; this closes the caller's final continuation race.
  void ensureExportSessionCurrentSync(PrivateKeyExportSession session) {
    _checkGeneration(session);
  }

  Future<T> _guarded<T>(
    PrivateKeyExportSession session,
    Future<T> Function() operation,
  ) async {
    await ensureExportSessionCurrent(session);
    try {
      return await operation();
    } finally {
      // Failures also invalidate the entire export if the session changed.
      await ensureExportSessionCurrent(session);
      _checkGeneration(session);
    }
  }

  Future<List<AssetId>> _targets(
    List<AssetId>? explicit,
    PrivateKeyExportSession session,
  ) async {
    if (explicit != null) return explicit.toSet().toList();
    final activated = await _guarded(
      session,
      _assetProvider.getActivatedAssets,
    );
    return {
      ...activated.map((asset) => asset.id),
      ..._activationCoordinator.activationStates.keys,
    }.toList();
  }

  KeyExportMode _validate(
    PrivateKeyExportRequest request,
    PrivateKeyExportSession session,
  ) {
    final mode =
        request.mode ??
        (session.walletId.isHd ? KeyExportMode.hd : KeyExportMode.iguana);
    if (mode == KeyExportMode.iguana && request.hasExplicitRange) {
      throw ArgumentError('Address ranges require HD export mode');
    }
    final start = request.startIndex ?? 0;
    final end = request.endIndex ?? start + 10;
    if (start < 0 ||
        end > 0x7fffffff ||
        (request.accountIndex ?? 0) > 0x7fffffff ||
        end < start ||
        end - start > 100 ||
        (request.accountIndex ?? 0) < 0) {
      throw ArgumentError('Invalid private key export range');
    }
    return mode;
  }

  /// Strict offline compatibility API. Failures remain failures; no online
  /// single-key substitution or silent omission of unsupported assets occurs.
  Future<Map<AssetId, List<PrivateKey>>> getPrivateKeys({
    List<AssetId>? assets,
    KeyExportMode? mode,
    int? startIndex,
    int? endIndex,
    int? accountIndex,
  }) async {
    final selectedAssets = assets?.toList(growable: false);
    final session = await captureExportSession();
    final request = PrivateKeyExportRequest(
      assets: assets,
      mode: mode,
      startIndex: startIndex,
      endIndex: endIndex,
      accountIndex: accountIndex,
    );
    final resolvedMode = _validate(request, session);
    final targets = await _targets(selectedAssets, session);
    if (targets.any((id) => _isTron(id, _assetProvider.fromId(id)))) {
      throw UnsupportedError(
        'TRX and TRC20 private key export is unavailable until KDF supports it',
      );
    }
    if (targets.isEmpty) return {};
    final response = await _guarded(
      session,
      () => _client.rpc.wallet.getPrivateKeys(
        coins: targets.map((asset) => asset.id).toList(),
        mode: resolvedMode,
        startIndex: startIndex,
        endIndex: endIndex,
        accountIndex: accountIndex,
      ),
    );
    final result = response.toPrivateKeyInfoMap({
      for (final asset in targets) asset.id: asset,
    });
    if ((response.isHdResponse != (resolvedMode == KeyExportMode.hd)) ||
        (response.hdKeys?.length ?? response.standardKeys?.length) !=
            targets.length ||
        result.length != targets.length ||
        targets.any((asset) => result[asset]?.isNotEmpty != true)) {
      throw const FormatException('Incomplete private key export response');
    }
    await ensureExportSessionCurrent(session);
    _checkGeneration(session);
    return result;
  }

  /// Strict offline convenience wrapper for one asset.
  Future<Map<AssetId, List<PrivateKey>>> getPrivateKey(
    AssetId asset, {
    KeyExportMode? mode,
    int? startIndex,
    int? endIndex,
    int? accountIndex,
  }) => getPrivateKeys(
    assets: [asset],
    mode: mode,
    startIndex: startIndex,
    endIndex: endIndex,
    accountIndex: accountIndex,
  );

  /// Reports unsupported assets individually. Never activates an asset.
  Future<PrivateKeyExportResult> exportPrivateKeys({
    PrivateKeyExportRequest request = const PrivateKeyExportRequest(),
    PrivateKeyExportSession? session,
  }) async {
    final selectedAssets = request.assets?.toList(growable: false);
    final context = session ?? await captureExportSession();
    await ensureExportSessionCurrent(context);
    final mode = _validate(request, context);
    final targets = await _targets(selectedAssets, context);
    final outcomes = List<PrivateKeyExportOutcome?>.filled(
      targets.length,
      null,
    );
    var next = 0;
    Future<void> worker() async {
      while (next < targets.length) {
        _checkGeneration(context);
        final index = next++;
        final id = targets[index];
        final asset = _assetProvider.fromId(id);
        if (_isTron(id, asset)) {
          outcomes[index] = _unavailable(
            id,
            PrivateKeyExportFailure.unsupportedProtocol,
          );
        } else if (asset == null) {
          outcomes[index] = _unavailable(
            id,
            PrivateKeyExportFailure.assetUnavailable,
          );
        } else {
          outcomes[index] = await _offline(asset, request, mode, context);
        }
      }
    }

    // Bounds the expensive offline derivation RPCs to two concurrent calls.
    await Future.wait([worker(), worker()]);
    await ensureExportSessionCurrent(context);
    _checkGeneration(context);
    return PrivateKeyExportResult(
      outcomes: outcomes.cast<PrivateKeyExportOutcome>(),
    );
  }

  PrivateKeyExportOutcome _unavailable(
    AssetId id,
    PrivateKeyExportFailure failure,
  ) => PrivateKeyExportOutcome.unavailable(assetId: id, failure: failure);

  Future<PrivateKeyExportOutcome> _offline(
    Asset asset,
    PrivateKeyExportRequest request,
    KeyExportMode mode,
    PrivateKeyExportSession session,
  ) async {
    if (asset.id.subClass == CoinSubClass.sia) {
      return _unavailable(
        asset.id,
        PrivateKeyExportFailure.unsupportedProtocol,
      );
    }
    try {
      final response = await _guarded(
        session,
        () => _client.rpc.wallet.getPrivateKeys(
          coins: [asset.id.id],
          mode: mode,
          startIndex: request.startIndex,
          endIndex: request.endIndex,
          accountIndex: request.accountIndex,
        ),
      );
      final keys = response.toPrivateKeyInfoMap({
        asset.id.id: asset.id,
      })[asset.id];
      final shielded = asset.protocol is ZhtlcProtocol;
      if (keys == null ||
          keys.isEmpty ||
          keys.any(
            (key) =>
                key.privateKey.isEmpty ||
                key.publicKeyAddress.isEmpty ||
                (!shielded && key.publicKeySecp256k1.isEmpty),
          ) ||
          (mode == KeyExportMode.hd) != response.isHdResponse) {
        return _unavailable(asset.id, PrivateKeyExportFailure.invalidResponse);
      }
      final start = request.startIndex ?? 0;
      final end = request.endIndex ?? start + 10;
      final account = request.accountIndex ?? 0;
      if (mode == KeyExportMode.hd) {
        final basePath = _configuredPath(asset);
        final expectedPaths = shielded
            ? {"$basePath/$account'"}
            : {
                for (var index = start; index <= end; index++)
                  "$basePath/$account'/0/$index",
              };
        if (keys.length != expectedPaths.length ||
            keys.map((key) => key.hdInfo?.derivationPath).toSet().length !=
                expectedPaths.length ||
            keys
                .map((key) => key.hdInfo?.derivationPath)
                .toSet()
                .difference(expectedPaths)
                .isNotEmpty) {
          return _unavailable(
            asset.id,
            PrivateKeyExportFailure.invalidResponse,
          );
        }
      } else if (keys.length != 1) {
        return _unavailable(asset.id, PrivateKeyExportFailure.invalidResponse);
      }
      return PrivateKeyExportOutcome.success(
        assetId: asset.id,
        keys: keys,
        coverage: PrivateKeyExportCoverage(
          kind: mode == KeyExportMode.hd
              ? shielded
                    ? PrivateKeyExportCoverageKind.offlineAccount
                    : PrivateKeyExportCoverageKind.offlineHdRange
              : PrivateKeyExportCoverageKind.legacyWallet,
          accountIndex: mode == KeyExportMode.hd
              ? request.accountIndex ?? 0
              : null,
          derivationPath: shielded ? keys.single.hdInfo?.derivationPath : null,
          chain: mode == KeyExportMode.hd && !shielded ? 'External' : null,
          startIndex: mode == KeyExportMode.hd && !shielded
              ? request.startIndex ?? 0
              : null,
          endIndex: mode == KeyExportMode.hd && !shielded
              ? request.endIndex ?? (request.startIndex ?? 0) + 10
              : null,
        ),
      );
    } on PrivateKeyExportSessionChangedException {
      rethrow;
    } on FormatException {
      return _unavailable(asset.id, PrivateKeyExportFailure.invalidResponse);
    } on Object {
      return _unavailable(asset.id, PrivateKeyExportFailure.rpcFailed);
    }
  }

  String? _configuredPath(Asset asset) {
    final path = asset.protocol.config['derivation_path'];
    return path is String ? path : asset.id.derivationPath;
  }

  // Keep disabled even when the catalog no longer has metadata for the ID.
  bool _isTron(AssetId id, Asset? asset) =>
      id.subClass == CoinSubClass.trx ||
      id.subClass == CoinSubClass.trc20 ||
      asset?.protocol is TrxProtocol ||
      asset?.protocol is Trc20Protocol;

  /// Releases this manager; it owns no persistent secret cache.
  Future<void> dispose() async {
    _disposed = true;
  }
}
