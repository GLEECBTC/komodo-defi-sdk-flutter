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
    this.maxPreActivationAttempts = 3,
    this.activationRetryDelay = const Duration(seconds: 2),
    this.activatedAssetsCacheTtl = const Duration(seconds: 10),
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

  /// Maximum number of retry attempts for pre-activation
  final int maxPreActivationAttempts;

  /// Delay between retry attempts
  final Duration activationRetryDelay;

  /// Time-to-live for the activated assets cache.
  /// Set to [Duration.zero] to disable caching.
  final Duration activatedAssetsCacheTtl;

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
    int? maxPreActivationAttempts,
    Duration? activationRetryDelay,
    Duration? activatedAssetsCacheTtl,
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
      maxPreActivationAttempts:
          maxPreActivationAttempts ?? this.maxPreActivationAttempts,
      activationRetryDelay: activationRetryDelay ?? this.activationRetryDelay,
      activatedAssetsCacheTtl:
          activatedAssetsCacheTtl ?? this.activatedAssetsCacheTtl,
      marketDataConfig: marketDataConfig ?? this.marketDataConfig,
      tronProApiKey: tronProApiKey ?? this.tronProApiKey,
      tronGaslessProvider: tronGaslessProvider ?? this.tronGaslessProvider,
      assetConfigTransform: assetConfigTransform ?? this.assetConfigTransform,
    );
  }
}
