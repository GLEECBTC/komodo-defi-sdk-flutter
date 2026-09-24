import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Utilities for managing NFT chain activation lifecycle.
class NftActivationService {
  /// Creates a new service instance.
  NftActivationService(
    this._client,
    this._assetManager,
    this._activatedAssetsCache,
  );

  final ApiClient _client;
  final AssetManager _assetManager;
  final ActivatedAssetsCache _activatedAssetsCache;
  final Logger _logger = Logger('NftActivationService');

  /// Returns the subset of [nftTickers] that are currently active.
  Future<List<String>> getActiveNftChains(Iterable<String> nftTickers) async {
    final activeIds = await _activatedAssetsCache.getActivatedAssetIds();
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
    final active = await _activatedAssetsCache.getActivatedAssetIds();
    if (active.contains(asset.id)) {
      return;
    }

    final params =
        activationParams ??
        NftActivationParams(provider: NftProvider.moralis());

    await retry(
      () async {
        await _client.rpc.nft.enableNft(
          ticker: asset.id.symbol.assetConfigId,
          activationParams: params,
        );
      },
      maxAttempts: maxAttempts,
      backoffStrategy: ExponentialBackoff(initialDelay: initialBackoff),
    );

    _activatedAssetsCache.invalidate();
  }

  /// Ensures all [nftTickers] are activated. Failures are collected and an
  /// aggregate exception is thrown if any activations fail.
  Future<void> enableNftChains(
    Iterable<String> nftTickers, {
    NftActivationParams? activationParams,
  }) async {
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
        await enableNft(asset, activationParams: activationParams);
      } on Object catch (e, s) {
        _logger.severe('Failed to enable NFT asset ${asset.id.id}', e, s);
        errors[asset.id] = e;
      }
    }

    if (errors.isNotEmpty) {
      final failedAssets = errors.keys.map((id) => id.id).join(', ');
      final errorSummary = errors.entries
          .map((e) => '${e.key.id}: ${e.value}')
          .join('; ');
      throw Exception(
        'Failed to activate ${errors.length} of ${assetsById.length} NFT assets. '
        'Failed: [$failedAssets]. Errors: $errorSummary',
      );
    }
  }
}
