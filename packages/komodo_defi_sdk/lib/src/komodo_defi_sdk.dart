import 'dart:async';
import 'dart:developer';

import 'package:get_it/get_it.dart';
import 'package:komodo_coins/komodo_coins.dart' show KomodoAssetsUpdateManager;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/bootstrap.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart';
import 'package:komodo_defi_sdk/src/message_signing/message_signing_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/storage/secure_rpc_password_mixin.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A high-level SDK that provides a simple way to build cross-platform applications
/// using the Komodo DeFi Framework, with a primary focus on wallet functionality.
///
/// The SDK provides an intuitive abstraction layer over the underlying Komodo DeFi
/// Framework API, handling binary/media file fetching, authentication, asset management,
/// and other core wallet functionality.
///
/// ## Getting Started
///
/// Create and initialize a new SDK instance:
///
/// ```dart
/// final sdk = KomodoDefiSdk();
/// await sdk.initialize();
/// ```
///
/// Or with custom configuration:
///
/// ```dart
/// final sdk = KomodoDefiSdk(
///   host: RemoteConfig(
///     userpass: 'your-password',
///     ipAddress: 'https://your-server.com',
///     port: 7783
///   ),
///   config: KomodoDefiSdkConfig(
///     defaultAssets: {'KMD', 'BTC'},
///     preActivateDefaultAssets: true
///   )
/// );
/// await sdk.initialize();
/// ```
///
/// ## Core Features
///
/// The SDK provides access to several core managers:
///
/// * [auth] - Handles user authentication and wallet management
/// * [assets] - Manages coin/token activation and configuration
/// * [pubkeys] - Handles address generation and management
/// * [transactions] - Manages transaction history and monitoring
/// * [withdrawals] - Handles asset withdrawal operations
/// * [addresses] - Provides address validation and format conversion
///
/// ## Usage Example
///
/// Here's a basic example showing how to authenticate and activate an asset:
///
/// ```dart
/// // Initialize SDK
/// final sdk = KomodoDefiSdk();
/// await sdk.initialize();
///
/// // Sign in user
/// await sdk.auth.signIn(
///   password: 'user-password',
///   walletId: WalletId('my-wallet')
/// );
///
/// // Activate Bitcoin
/// final btc = sdk.assets.findAssetsByTicker('BTC').first;
/// await sdk.assets.activateAsset(btc).last;
///
/// // Get addresses
/// final addresses = await sdk.pubkeys.getPubkeys(btc);
/// print('BTC Addresses: ${addresses.keys.map((k) => k.address).join(", ")}');
/// ```
///
/// ## Cleanup
///
/// Be sure to dispose of the SDK when it's no longer needed:
///
/// ```dart
/// await sdk.dispose();
/// ```
///
/// This will clean up all resources and stop any background operations.
class KomodoDefiSdk with SecureRpcPasswordMixin {
  /// Creates a new instance of [KomodoDefiSdk] with optional host configuration
  /// and SDK configuration.
  ///
  /// If [host] is not provided, defaults to local configuration.
  /// If [config] is not provided, uses default configuration.
  ///
  /// Example:
  /// ```dart
  /// final sdk = KomodoDefiSdk(
  ///   host: RemoteConfig(
  ///     userpass: 'password',
  ///     ipAddress: 'https://example.com',
  ///     port: 7783
  ///   )
  /// );
  /// ```
  factory KomodoDefiSdk({
    IKdfHostConfig? host,
    KomodoDefiSdkConfig? config,
    void Function(String)? onLog,
  }) {
    return KomodoDefiSdk._(
      host,
      config ?? const KomodoDefiSdkConfig(),
      null,
      onLog,
    );
  }

  /// Creates a new SDK instance from an existing KDF framework instance.
  ///
  /// This is useful when you already have a configured framework instance
  /// and want to use it with the SDK.
  ///
  /// Example:
  /// ```dart
  /// final framework = KomodoDefiFramework.create(...);
  /// final sdk = KomodoDefiSdk.fromFramework(framework);
  /// ```
  factory KomodoDefiSdk.fromFramework(
    KomodoDefiFramework framework, {
    KomodoDefiSdkConfig? config,
    void Function(String)? onLog,
  }) {
    return KomodoDefiSdk._(
      null,
      config ?? const KomodoDefiSdkConfig(),
      framework,
      onLog,
    );
  }

  KomodoDefiSdk._(
    this._hostConfig,
    this._config,
    this._kdfFramework,
    this._onLog,
  ) : _container = GetIt.asNewInstance();

  final IKdfHostConfig? _hostConfig;
  final KomodoDefiSdkConfig _config;
  KomodoDefiFramework? _kdfFramework;
  late final GetIt _container;
  bool _isInitialized = false;
  bool _isDisposed = false;
  Future<void>? _initializationFuture;
  final void Function(String)? _onLog;

  /// The API client for making direct RPC calls.
  ///
  /// While the SDK provides high-level abstractions for most operations,
  /// the client can be used for direct API access when needed.
  ///
  /// Throws [StateError] if accessed before initialization.
  ApiClient get client => _assertSdkInitialized(_container<ApiClient>());

  /// The authentication manager instance.
  ///
  /// Handles user authentication, wallet management, and session state.
  ///
  /// Throws [StateError] if accessed before initialization.
  KomodoDefiLocalAuth get auth =>
      _assertSdkInitialized(_container<KomodoDefiLocalAuth>());

  /// The pubkey manager instance.
  ///
  /// Handles generation and management of addresses for assets.
  ///
  /// Throws [StateError] if accessed before initialization.
  PubkeyManager get pubkeys =>
      _assertSdkInitialized(_container<PubkeyManager>());

  /// The address operations instance.
  ///
  /// Provides functionality for address validation and format conversion.
  ///
  /// Throws [StateError] if accessed before initialization.
  AddressOperations get addresses =>
      _assertSdkInitialized(_container<AddressOperations>());

  /// Service for resolving/persisting activation configuration.
  ActivationConfigService get activationConfigService =>
      _assertSdkInitialized(_container<ActivationConfigService>());

  /// The asset manager instance.
  ///
  /// Handles coin/token activation and configuration.
  ///
  /// Throws [StateError] if accessed before initialization.
  AssetManager get assets => _assertSdkInitialized(_container<AssetManager>());

  /// Activates an asset through the shared activation coordinator.
  ///
  /// This is the preferred path for app code that wants to ensure an asset is
  /// enabled without racing other managers that may be activating the same
  /// asset concurrently.
  Future<bool> ensureAssetActivated(Asset asset) async {
    final coordinator = _assertSdkInitialized(
      _container<SharedActivationCoordinator>(),
    );
    final result = await coordinator.activateAsset(asset);
    return result.isSuccess;
  }

  /// Deletes a persisted custom token from SDK-managed storage.
  ///
  /// This removes the token from the custom-token store and the in-memory
  /// asset registry, then invalidates the activated-assets cache so follow-up
  /// activation checks do not continue resolving the deleted asset.
  Future<void> deleteCustomToken(AssetId assetId) async {
    _assertSdkInitialized(assets);
    await _container<KomodoAssetsUpdateManager>().assets.deleteCustomToken(
      assetId,
    );
    activatedAssetsCache.invalidate();
  }

  /// Cache of activated assets with per-instance TTL.
  ///
  /// Useful for avoiding repeated activation RPC calls across features.
  ActivatedAssetsCache get activatedAssetsCache =>
      _assertSdkInitialized(_container<ActivatedAssetsCache>());

  /// NFT-specific activation helpers.
  NftActivationService get nftActivation =>
      _assertSdkInitialized(_container<NftActivationService>());

  /// The transaction history manager instance.
  ///
  /// Manages transaction history and monitoring.
  ///
  /// Throws [StateError] if accessed before initialization.
  TransactionHistoryManager get transactions =>
      _assertSdkInitialized(_container<TransactionHistoryManager>());

  /// The message signing manager instance.
  ///
  /// Provides functionality to sign and verify messages using cryptocurrencies.
  ///
  /// Throws [StateError] if accessed before initialization.
  MessageSigningManager get messageSigning =>
      _assertSdkInitialized(_container<MessageSigningManager>());

  T _assertSdkInitialized<T>(T val) {
    _assertNotDisposed();
    if (!_isInitialized) {
      throw StateError(
        'Cannot call $T because KomodoDefiSdk is not '
        'initialized. Call initialize() or await ensureInitialized() first.',
      );
    }
    return val;
  }

  void _assertNotDisposed() {
    if (_isDisposed) {
      throw StateError('KomodoDefiSdk has been disposed');
    }
  }

  /// The mnemonic validator instance.
  ///
  /// Provides functionality for validating BIP39 mnemonics.
  ///
  /// Throws [StateError] if accessed before initialization.
  MnemonicValidator get mnemonicValidator =>
      _assertSdkInitialized(_container<MnemonicValidator>());

  /// The withdrawal manager instance.
  ///
  /// Handles asset withdrawal operations.
  ///
  /// Throws [StateError] if accessed before initialization.
  WithdrawalManager get withdrawals =>
      _assertSdkInitialized(_container<WithdrawalManager>());

  /// Manages security-sensitive wallet operations like private key export.
  ///
  /// Provides authenticated access to sensitive wallet data with proper
  /// security warnings and user authentication checks.
  ///
  /// Throws [StateError] if accessed before initialization.
  SecurityManager get security =>
      _assertSdkInitialized(_container<SecurityManager>());

  /// The price manager instance.
  ///
  /// Provides functionality for fetching asset prices.
  ///
  /// Throws [StateError] if accessed before initialization.
  MarketDataManager get marketData =>
      _assertSdkInitialized(_container<MarketDataManager>());

  /// Provides access to fee management utilities.
  FeeManager get fees => _assertSdkInitialized(_container<FeeManager>());

  /// Provides high-level trading helpers and stream-first watchers.
  TradingManager get trading =>
      _assertSdkInitialized(_container<TradingManager>());

  /// Gets a reference to the balance manager for checking asset balances.
  ///
  /// Provides functionality for checking and monitoring asset balances.
  ///
  /// Throws [StateError] if accessed before initialization.
  BalanceManager get balances =>
      _assertSdkInitialized(_container<BalanceManager>());

  /// The event streaming service instance.
  ///
  /// Provides access to SSE (Server-Sent Events) connection lifecycle management
  /// for real-time balance and transaction history updates.
  ///
  /// Use [KdfEventStreamingService.connectIfNeeded] to establish SSE connection
  /// after authentication, and [KdfEventStreamingService.disconnect] to clean up
  /// on sign-out.
  ///
  /// Throws [StateError] if accessed before initialization.
  KdfEventStreamingService get streaming =>
      _assertSdkInitialized(_container<KomodoDefiFramework>().streaming);

  /// Subscribes to a managed orderbook stream for a trading pair.
  ///
  /// This uses the SDK's internal stream lifecycle manager with reference
  /// counting and automatic `stream::disable` cleanup when the last
  /// subscription is cancelled.
  Future<StreamSubscription<OrderbookEvent>> subscribeToOrderbook({
    required String base,
    required String rel,
  }) {
    final manager = _assertSdkInitialized(_container<EventStreamingManager>());
    return manager.subscribeToOrderbook(base: base, rel: rel);
  }

  /// Subscribes to managed swap status updates.
  ///
  /// The subscription is reference-counted across all callers.
  Future<StreamSubscription<SwapStatusEvent>> subscribeToSwapStatus() {
    final manager = _assertSdkInitialized(_container<EventStreamingManager>());
    return manager.subscribeToSwapStatus();
  }

  /// Subscribes to managed order status updates.
  ///
  /// The subscription is reference-counted across all callers.
  Future<StreamSubscription<OrderStatusEvent>> subscribeToOrderStatus() {
    final manager = _assertSdkInitialized(_container<EventStreamingManager>());
    return manager.subscribeToOrderStatus();
  }

  /// Public stream of framework logs.
  ///
  /// Subscribe to receive human-readable log messages from the underlying
  /// Komodo DeFi Framework. Requires the SDK to be initialized.
  Stream<String> get logStream =>
      _assertSdkInitialized(_container<KomodoDefiFramework>().logStream);

  /// Waits until the percentage of enabled assets among [assetIds] meets or
  /// exceeds [threshold], polling at [pollInterval] until [timeout].
  ///
  /// Returns `true` when the threshold is reached, or `false` if the timeout
  /// elapses first.
  Future<bool> waitForEnabledAssetsToPassThreshold(
    Iterable<AssetId> assetIds, {
    double threshold = 0.5,
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    _assertSdkInitialized(activatedAssetsCache);

    final targets = assetIds.toSet();
    if (targets.isEmpty) {
      throw ArgumentError.value(assetIds, 'assetIds', 'is empty');
    }
    if (threshold <= 0 || threshold > 1) {
      throw ArgumentError.value(threshold, 'threshold', 'must be (0, 1]');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be positive',
      );
    }

    final stopwatch = Stopwatch()..start();
    var forceRefresh = true;

    while (true) {
      final enabled = await activatedAssetsCache.getActivatedAssetIds(
        forceRefresh: forceRefresh,
      );
      forceRefresh = false;

      final matched = enabled.intersection(targets).length;
      final coverage = matched / targets.length;
      if (coverage >= threshold) {
        return true;
      }

      if (stopwatch.elapsed >= timeout) {
        return false;
      }

      final remaining = timeout - stopwatch.elapsed;
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
  }

  /// Convenience helper that accepts asset tickers instead of [AssetId]s.
  /// Matches assets by config ID (`asset.id.id`) before delegating to
  /// [waitForEnabledAssetsToPassThreshold].
  Future<bool> waitForEnabledTickersToPassThreshold(
    Iterable<String> tickers, {
    double threshold = 0.5,
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 2),
  }) {
    final ids = tickers
        .expand((ticker) => assets.findAssetsByConfigId(ticker))
        .map((asset) => asset.id);
    return waitForEnabledAssetsToPassThreshold(
      ids,
      threshold: threshold,
      timeout: timeout,
      pollInterval: pollInterval,
    );
  }

  /// Initializes the SDK instance.
  ///
  /// This must be called before using any SDK functionality. The initialization
  /// process sets up all required managers and establishes necessary connections.
  ///
  /// If the SDK is already initialized, this method returns immediately.
  ///
  /// Example:
  /// ```dart
  /// final sdk = KomodoDefiSdk();
  /// await sdk.initialize();
  /// ```
  Future<void> initialize() async {
    _assertNotDisposed();
    if (_isInitialized) return;
    _initializationFuture ??= _initialize();
    await _initializationFuture;
  }

  /// Ensures the SDK is initialized before performing any operation.
  ///
  /// This is a convenience method that can be used instead of [initialize]
  /// when you're not sure if the SDK has already been initialized.
  ///
  /// Example:
  /// ```dart
  /// await sdk.ensureInitialized();
  /// // Now safe to use SDK functionality
  /// ```
  Future<void> ensureInitialized() async {
    _assertNotDisposed();
    if (!_isInitialized) {
      await initialize();
    }
  }

  Future<void> _initialize() async {
    _assertNotDisposed();

    log('KomodoDefiSdk: Starting initialization...', name: 'KomodoDefiSdk');
    final stopwatch = Stopwatch()..start();

    await bootstrap(
      hostConfig: _hostConfig,
      config: _config,
      kdfFramework: _kdfFramework,
      container: _container,
      // Pass onLog callback to bootstrap for direct framework integration
      externalLogger: _onLog,
    );

    _isInitialized = true;

    stopwatch.stop();
    log(
      'KomodoDefiSdk: Initialization completed in ${stopwatch.elapsedMilliseconds}ms',
      name: 'KomodoDefiSdk',
    );
  }

  /// Gets the current user's authentication options.
  ///
  /// Returns null if no user is currently authenticated.
  ///
  /// Example:
  /// ```dart
  /// final options = await sdk.currentUserAuthOptions();
  /// if (options != null) {
  ///   print('Current derivation method: ${options.derivationMethod}');
  /// }
  /// ```
  Future<AuthOptions?> currentUserAuthOptions() async {
    _assertSdkInitialized(auth);
    final user = await auth.currentUser;
    return user == null
        ? null
        : KomodoDefiLocalAuth.storedAuthOptions(user.walletId.name);
  }

  Future<void> _disposeIfRegistered<T extends Object>(
    Future<void> Function(T) fn,
  ) async {
    if (_container.isRegistered<T>()) {
      try {
        await fn(_container<T>());
      } catch (e) {
        log('Error disposing $T: $e');
      }
    }
  }

  /// Disposes of this SDK instance and cleans up all resources.
  ///
  /// This should be called when the SDK is no longer needed to ensure proper
  /// cleanup of resources and background operations.
  ///
  /// NB! By default, this will terminate the KDF process.
  ///
  /// TODO: Consider future refactoring to separate KDF process disposal vs
  /// Dart object disposal.
  ///
  /// Example:
  /// ```dart
  /// await sdk.dispose();
  /// ```
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    if (!_isInitialized) return;

    _isInitialized = false;
    _initializationFuture = null;

    await Future.wait([
      _disposeIfRegistered<EventStreamingManager>((m) => m.dispose()),
      _disposeIfRegistered<KomodoDefiLocalAuth>((m) => m.dispose()),
      _disposeIfRegistered<AssetManager>((m) => m.dispose()),
      _disposeIfRegistered<ActivatedAssetsCache>((m) => m.dispose()),
      _disposeIfRegistered<ActivationManager>((m) => m.dispose()),
      _disposeIfRegistered<ActivationConfigService>((m) async => m.dispose()),
      _disposeIfRegistered<BalanceManager>((m) => m.dispose()),
      _disposeIfRegistered<PubkeyManager>((m) => m.dispose()),
      _disposeIfRegistered<TransactionHistoryManager>((m) => m.dispose()),
      _disposeIfRegistered<MarketDataManager>((m) => m.dispose()),
      _disposeIfRegistered<FeeManager>((m) => m.dispose()),
      _disposeIfRegistered<WithdrawalManager>((m) => m.dispose()),
      _disposeIfRegistered<SecurityManager>((m) => m.dispose()),
    ]);

    // Reset scoped container
    await _container.reset();

    // Clean up framework if we created it
    if (_kdfFramework != null) {
      await _kdfFramework!.dispose();
      _kdfFramework = null;
    }
  }
}
