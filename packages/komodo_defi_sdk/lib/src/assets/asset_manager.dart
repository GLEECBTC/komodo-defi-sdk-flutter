import 'dart:async' show StreamSubscription, StreamController, scheduleMicrotask;

import 'package:flutter/foundation.dart' show ValueGetter;
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/sdk/komodo_defi_sdk_config.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Manages the lifecycle and state of crypto assets in the Komodo DeFi Framework.
///
/// The AssetManager is responsible for:
/// * Tracking available assets
/// * Managing asset activation state
/// * Handling automatic activation of assets
/// * Maintaining asset ordering and grouping
///
/// Note: The actual asset activation is handled by the internal
/// [ActivationManager] which is not publicly exposed by design.
/// The [AssetManager] provides proxy methods for backward compatibility.
///
/// ## Usage
///
/// ```dart
/// final assetManager = sdk.assets;
///
/// // Find an asset
/// final btcAssets = assetManager.findAssetsByTicker('BTC');
///
/// // Activate an asset
/// await assetManager.activateAsset(btcAssets.first).last;
///
/// // Get all activated assets
/// final activeAssets = await assetManager.getActivatedAssets();
/// ```
///
/// The manager listens to authentication changes to keep the available asset
/// list in sync with the active wallet's capabilities.
class AssetManager implements IAssetProvider {
  /// Creates a new instance of AssetManager.
  ///
  /// This is typically created by the SDK and shouldn't need to be instantiated
  /// directly.
  AssetManager(
    this._auth,
    this._config,
    ValueGetter<ActivationManager> activationManager,
    this._coins,
    ValueGetter<ActivatedAssetsCache> activatedAssetsCache,
    [ValueGetter<SharedActivationCoordinator>? activationCoordinator],
  ) : _activationManager = activationManager,
      _activatedAssetsCache = activatedAssetsCache,
      _activationCoordinator = activationCoordinator {
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChange);
  }
  final KomodoDefiLocalAuth _auth;
  final KomodoDefiSdkConfig _config;
  final AssetsUpdateManager _coins;

  /// NB: This cannot be used during initialization. This is a workaround
  /// to publicly expose the activation manager's activation methods.
  /// See [activateAsset] and [activateAssets] for more details.
  final ValueGetter<ActivationManager> _activationManager;

  /// Lazily resolved shared activation coordinator to ensure global dedup.
  final ValueGetter<SharedActivationCoordinator>? _activationCoordinator;

  /// Activated assets cache shared across SDK consumers.
  final ValueGetter<ActivatedAssetsCache> _activatedAssetsCache;
  StreamSubscription<KdfUser?>? _authSubscription;
  bool _isDisposed = false;
  AssetFilterStrategy _currentFilterStrategy = const NoAssetFilterStrategy();

  /// Initializes the asset manager.
  ///
  /// This is called automatically by the SDK and shouldn't need to be called
  /// manually.
  Future<void> init() async {
    await _coins.init(defaultPriorityTickers: _config.defaultAssets);
    // call get filtered assets to update the cache
    _coins.filteredAssets(_currentFilterStrategy);
  }

  /// Exposes the currently active commit hash for coins config.
  Future<String?> get currentCoinsCommit async => _coins.getCurrentCommitHash();

  /// Exposes the latest available commit hash for coins config.
  Future<String?> get latestCoinsCommit async => _coins.getLatestCommitHash();

  /// Applies a new [strategy] for filtering available assets.
  ///
  /// This is called whenever the authentication state changes so the
  /// visible asset list always matches the capabilities of the active wallet.
  void setFilterStrategy(AssetFilterStrategy strategy) {
    if (_currentFilterStrategy.strategyId == strategy.strategyId) {
      return;
    }

    _currentFilterStrategy = strategy;
    // call get filtered assets to update the cache
    _coins.filteredAssets(_currentFilterStrategy);
  }

  /// Reacts to authentication changes by updating the active asset filter.
  ///
  /// When a hardware wallet such as Trezor is connected we limit the list of
  /// available assets to only those explicitly supported by that wallet.
  void _handleAuthStateChange(KdfUser? user) {
    if (_isDisposed) return;

    final isTrezor =
        user?.walletId.authOptions.privKeyPolicy ==
        const PrivateKeyPolicy.trezor();

    // Trezor does not support all assets yet, so we apply a filter here
    // to only show assets that are compatible with Trezor.
    // WalletConnect and Metamask will require similar handling in the future.
    final strategy = isTrezor
        ? const TrezorAssetFilterStrategy(hiddenAssets: {'BCH'})
        : const NoAssetFilterStrategy();

    setFilterStrategy(strategy);
    _activatedAssetsCache().invalidate();
  }

  /// Returns an asset by its [AssetId], if available.
  ///
  /// Returns null if no matching asset is found.
  /// Throws [StateError] if called before initialization.
  @override
  Asset? fromId(AssetId id) => _coins.isInitialized
      ? available[id]
      : throw StateError(
          'Assets have not been initialized. Call init() first.',
        );

  /// Returns all available assets, ordered by priority.
  ///
  /// Default assets (configured in [KomodoDefiSdkConfig]) appear first,
  /// followed by other assets in alphabetical order.
  /// The filtering and ordering is handled by the underlying coin_config_manager.
  @override
  Map<AssetId, Asset> get available =>
      Map.unmodifiable(_coins.filteredAssets(_currentFilterStrategy));

  /// Returns currently activated assets for the signed-in user.
  ///
  /// Returns an empty list if no user is signed in.
  @override
  Future<List<Asset>> getActivatedAssets() async {
    return _activatedAssetsCache().getActivatedAssets();
  }

  /// Returns the set of enabled coin tickers for the current user.
  ///
  /// Returns an empty set if no user is signed in.
  @override
  Future<Set<String>> getEnabledCoins() async {
    final activated = await _activatedAssetsCache().getActivatedAssets();
    return activated.map((asset) => asset.id.id).toSet();
  }

  /// Finds all assets matching the given ID String (as is in the coins config).
  ///
  /// Example:
  /// ```dart
  /// final ethAssets = assetManager.findAssetsByTicker('ETH');
  /// for (final asset in ethAssets) {
  ///   print('${asset.id.name} on ${asset.protocol.subClass.formatted}');
  /// }
  /// ```
  @override
  Set<Asset> findAssetsByConfigId(String ticker) {
    return available.values.where((asset) => asset.id.id == ticker).toSet();
  }

  /// Returns child assets for the given parent asset ID.
  ///
  /// For example, this can be used to find all tokens on a particular chain.
  ///
  /// Example:
  /// ```dart
  /// final ethId = assetManager.findAssetsByTicker('ETH').first.id;
  /// final erc20Tokens = assetManager.childAssetsOf(ethId);
  /// ```
  @override
  Set<Asset> childAssetsOf(AssetId parentId) {
    return available.values
        .where(
          (asset) => asset.id.isChildAsset && asset.id.parentId == parentId,
        )
        .toSet();
  }

  /// Activates a single asset.
  ///
  /// This is a proxy method that delegates to the internal [ActivationManager]
  /// for backward compatibility. The [ActivationManager] is not publicly
  /// exposed by design.
  ///
  /// This method may be removed in the future, as the goal is to handle all
  /// activation logic internally and seamlessly.
  ///
  /// Returns a stream of [ActivationProgress] updates.
  Stream<ActivationProgress> activateAsset(Asset asset) {
    final coordinator = _activationCoordinator?.call();
    if (coordinator != null) {
      return coordinator.activateAssetStream(asset);
    }
    return _activationManager().activateAsset(asset);
  }

  /// Activates multiple assets at once.
  ///
  /// This is a proxy method that delegates to the internal [ActivationManager]
  /// for backward compatibility. The [ActivationManager] is not publicly
  /// exposed by design.
  ///
  /// This method may be removed in the future, as the goal is to handle all
  /// activation logic internally and seamlessly.
  ///
  /// Returns a stream of [ActivationProgress] updates.
  Stream<ActivationProgress> activateAssets(List<Asset> assets) {
    final coordinator = _activationCoordinator?.call();
    if (coordinator == null) {
      return _activationManager().activateAssets(assets);
    }

    final controller = StreamController<ActivationProgress>.broadcast();

    scheduleMicrotask(() {
      for (final asset in assets) {
        coordinator
            .activateAssetStream(asset)
            .listen(controller.add, onError: controller.addError);
      }
    });

    return controller.stream;
  }

  /// Disposes of the asset manager, cleaning up resources.
  ///
  /// This is called automatically by the SDK when disposing.
  Future<void> dispose() async {
    _isDisposed = true;
    await _authSubscription?.cancel();
    _activatedAssetsCache().invalidate();
  }
}
