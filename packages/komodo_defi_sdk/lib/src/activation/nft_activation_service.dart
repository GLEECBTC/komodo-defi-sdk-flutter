import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Utilities for managing NFT chain activation lifecycle.
class NftActivationService {
  /// Creates a new service instance.
  NftActivationService(
    this._client,
    this._assetManager,
    this._activatedAssetsCache, {
    required KomodoDefiLocalAuth auth,
    required ActivationManager activationManager,
    ActivationPolicy? activationPolicy,
  }) : _auth = auth,
       _activationManager = activationManager,
       _activationPolicy = activationPolicy ?? ActivationPolicy();

  final KomodoDefiLocalAuth _auth;
  final ActivationManager _activationManager;
  final ActivationPolicy _activationPolicy;
  final ApiClient _client;
  final AssetManager _assetManager;
  final ActivatedAssetsCache _activatedAssetsCache;
  final Logger _logger = Logger('NftActivationService');

  /// Returns the subset of [nftTickers] that are currently active.
  Future<List<String>> getActiveNftChains(Iterable<String> nftTickers) async {
    final session = await _auth.captureSessionContext();
    final activeIds = await _activatedAssetsCache.getActivatedAssetIds();
    _auth.ensureSessionContextCurrent(session);
    if (activeIds.isEmpty) return const [];

    final activeTickers = activeIds.map((id) => id.id).toSet();
    final result = <String>[];
    final seen = <String>{};

    for (final ticker in nftTickers) {
      if (activeTickers.contains(ticker) && seen.add(ticker)) {
        result.add(ticker);
      }
    }

    return result;
  }

  /// Activates a single NFT asset if it's not already active.
  Future<void> enableNft(
    Asset asset, {
    NftActivationParams? activationParams,
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(seconds: 1),
  }) async {
    final session = await _auth.captureSessionContext();
    final params =
        activationParams ??
        NftActivationParams(provider: NftProvider.moralis());
    final active = await _activatedAssetsCache.getActivatedAssetIds();
    _auth.ensureSessionContextCurrent(session);
    if (_activationPolicy.current.isBlocked(asset.id)) {
      _activationPolicy.ensureAllowed(asset.id);
    }
    if (active.contains(asset.id)) {
      _registerRecovery(asset, params, session);
      return;
    }

    await retry(
      () async {
        _auth.ensureSessionContextCurrent(session);
        _activationPolicy.ensureAllowed(asset.id);
        await _client.rpc.nft.enableNft(
          ticker: asset.id.symbol.assetConfigId,
          activationParams: params,
        );
      },
      maxAttempts: maxAttempts,
      shouldRetry: (error) =>
          error is! WalletChangedDisconnectException &&
          error is! ActivationPolicyException,
      backoffStrategy: ExponentialBackoff(initialDelay: initialBackoff),
    );

    _auth.ensureSessionContextCurrent(session);
    _registerRecovery(asset, params, session);
    _activatedAssetsCache.invalidate();
    if (_activationPolicy.current.isBlocked(asset.id)) {
      _activationPolicy.ensureAllowed(asset.id);
    }
  }

  void _registerRecovery(
    Asset asset,
    NftActivationParams params,
    AuthSessionContext session,
  ) => _activationManager.registerRuntimeRecovery(
    asset.id,
    session: session,
    recover: () async {
      _auth.ensureSessionContextCurrent(session);
      await enableNft(asset, activationParams: params);
    },
  );

  /// Ensures all [nftTickers] are activated. Failures are collected and an
  /// aggregate exception is thrown if any activations fail.
  Future<void> enableNftChains(
    Iterable<String> nftTickers, {
    NftActivationParams? activationParams,
  }) async {
    final session = await _auth.captureSessionContext();
    final assetsById = <AssetId, Asset>{};
    for (final ticker in nftTickers) {
      for (final asset in _assetManager.findAssetsByConfigId(ticker)) {
        assetsById[asset.id] = asset;
      }
    }

    if (assetsById.isEmpty) {
      return;
    }

    final errors = <AssetId, Object>{};
    for (final asset in assetsById.values) {
      try {
        _auth.ensureSessionContextCurrent(session);
        await enableNft(asset, activationParams: activationParams);
        _auth.ensureSessionContextCurrent(session);
      } on WalletChangedDisconnectException {
        rethrow;
      } on ActivationPolicyException {
        rethrow;
      } on Object catch (e) {
        _logger.severe('NFT activation failed');
        errors[asset.id] = e;
      }
    }

    if (errors.isNotEmpty) {
      throw NftActivationException(Map.unmodifiable(errors));
    }
  }
}

/// Per-asset failures retained without reducing SDK errors to a string.
final class NftActivationException implements Exception {
  /// Retains each NFT asset's original activation error.
  const NftActivationException(this.failures);

  /// Failures indexed by the affected NFT asset.
  final Map<AssetId, Object> failures;
  @override
  String toString() => 'NFT asset activation failed';
}
