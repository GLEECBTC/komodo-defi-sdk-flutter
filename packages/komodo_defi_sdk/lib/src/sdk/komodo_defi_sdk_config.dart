// sdk_config.dart
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Application-owned amendment of one normalized asset configuration.
///
/// The callback runs before the SDK parses the configuration into an [Asset].
/// It must return a new map and should preserve fields it does not own.
typedef AssetConfigTransform = JsonMap Function(JsonMap config);

class KomodoDefiSdkConfig {
  const KomodoDefiSdkConfig({
    this.defaultAssets = const {'KMD', 'BTC', 'ETH', 'DOC', 'MARTY'},
    this.preActivateDefaultAssets = true,
    this.preActivateHistoricalAssets = true,
    this.preActivateCustomTokenAssets = true,
    this.persistTransactionHistory = true,
    this.maxPreActivationAttempts = 3,
    this.activationRetryDelay = const Duration(seconds: 2),
    this.activatedAssetsCacheTtl = const Duration(seconds: 10),
    this.activatedAssetsCacheFetchTimeout = const Duration(seconds: 30),
    this.marketDataConfig = const MarketDataConfig(),
    this.tronProApiKey,
    this.tronGaslessProvider,
    this.assetConfigTransform,
  });

  /// Set of asset IDs that should be enabled by default
  final Set<String> defaultAssets;

  /// Whether to automatically activate default assets on login
  final bool preActivateDefaultAssets;

  /// Whether to automatically activate previously used assets on login
  final bool preActivateHistoricalAssets;

  /// Whether to automatically activate custom tokens on login
  final bool preActivateCustomTokenAssets;

  /// Whether transaction history is cached on disk between sessions.
  ///
  /// When enabled, a coin details page renders its known history immediately on
  /// a cold start instead of waiting for the first network round trip. The
  /// cache is derived state and is always refreshed from the network, so
  /// disabling this costs latency rather than correctness.
  ///
  /// Two caveats worth knowing. Cached history survives sign-out - deleting
  /// the wallet is what clears it, through the `onWalletDeletion` purge that
  /// `bootstrap` registers alongside the pubkey cache, the activation config
  /// store and the wallet asset list. And the store is unbounded, mirroring
  /// the in-memory behaviour it replaces.
  final bool persistTransactionHistory;

  /// Maximum number of retry attempts for pre-activation
  final int maxPreActivationAttempts;

  /// Delay between retry attempts
  final Duration activationRetryDelay;

  /// Time-to-live for the activated assets cache.
  /// Set to [Duration.zero] to disable caching.
  final Duration activatedAssetsCacheTtl;

  /// Liveness ceiling on a single activated-assets read.
  ///
  /// Not a latency budget: it exists so `get_enabled_coins` can never fail to
  /// return, which would otherwise defeat every deadline built on top of it.
  final Duration activatedAssetsCacheFetchTimeout;

  /// Configuration for market data repositories
  final MarketDataConfig marketDataConfig;

  /// No longer used. Transaction history now uses TRONGrid which requires no
  /// API key. Retained for backward compatibility.
  final String? tronProApiKey;

  /// Optional Tron GasFree provider config. When set, TRX platform activations
  /// enable gas-free (gasless) TRC20 transfers where the fee is paid in the
  /// token. Held in memory only — never persisted.
  final TronGaslessProviderConfig? tronGaslessProvider;

  /// Optional application policy applied to each normalized asset config
  /// before it enters the SDK asset registry.
  ///
  /// Product allowlists belong here rather than in generic SDK capability
  /// logic. SDK bootstrap applies the transform to bundled, remote, and cached
  /// registry views without persisting its result.
  final AssetConfigTransform? assetConfigTransform;

  KomodoDefiSdkConfig copyWith({
    Set<String>? defaultAssets,
    bool? preActivateDefaultAssets,
    bool? preActivateHistoricalAssets,
    bool? preActivateCustomTokenAssets,
    bool? persistTransactionHistory,
    int? maxPreActivationAttempts,
    Duration? activationRetryDelay,
    Duration? activatedAssetsCacheTtl,
    Duration? activatedAssetsCacheFetchTimeout,
    MarketDataConfig? marketDataConfig,
    String? tronProApiKey,
    TronGaslessProviderConfig? tronGaslessProvider,
    AssetConfigTransform? assetConfigTransform,
  }) {
    return KomodoDefiSdkConfig(
      defaultAssets: defaultAssets ?? this.defaultAssets,
      preActivateDefaultAssets:
          preActivateDefaultAssets ?? this.preActivateDefaultAssets,
      preActivateHistoricalAssets:
          preActivateHistoricalAssets ?? this.preActivateHistoricalAssets,
      preActivateCustomTokenAssets:
          preActivateCustomTokenAssets ?? this.preActivateCustomTokenAssets,
      persistTransactionHistory:
          persistTransactionHistory ?? this.persistTransactionHistory,
      maxPreActivationAttempts:
          maxPreActivationAttempts ?? this.maxPreActivationAttempts,
      activationRetryDelay: activationRetryDelay ?? this.activationRetryDelay,
      activatedAssetsCacheTtl:
          activatedAssetsCacheTtl ?? this.activatedAssetsCacheTtl,
      activatedAssetsCacheFetchTimeout:
          activatedAssetsCacheFetchTimeout ??
          this.activatedAssetsCacheFetchTimeout,
      marketDataConfig: marketDataConfig ?? this.marketDataConfig,
      tronProApiKey: tronProApiKey ?? this.tronProApiKey,
      tronGaslessProvider: tronGaslessProvider ?? this.tronGaslessProvider,
      assetConfigTransform: assetConfigTransform ?? this.assetConfigTransform,
    );
  }
}
