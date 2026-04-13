import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'activation_params.freezed.dart';
part 'activation_params.g.dart';

/// Defines additional parameters used for activation. These params may vary depending
/// on the coin type.
///
/// Key parameters include:
/// - [requiredConfirmations]: Confirmations to wait for steps in swap
/// - [requiresNotarization]: For dPoW protected coins, waits for transactions to be notarized
/// - [privKeyPolicy]: Sets private key handling mode (default: ContextPrivKey)
/// - [minAddressesNumber]: For HD wallets, minimum additional addresses to generate
/// - [scanPolicy]: HD wallet address scanning behavior
/// - [gapLimit]: Maximum number of empty addresses in a row for HD wallets
/// - [mode]: Activation mode configuration for QTUM, UTXO & ZHTLC coins
///
class ActivationParams implements RpcRequestParams {
  const ActivationParams({
    this.requiredConfirmations,
    this.requiresNotarization = false,
    this.privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
    this.minAddressesNumber,
    this.scanPolicy,
    this.gapLimit,
    this.mode,
  });

  /// Creates [ActivationParams] from configuration JSON
  factory ActivationParams.fromConfigJson(JsonMap json) {
    final mode = ActivationMode.fromConfig(
      json,
      type: ActivationModeType.electrum,
    );

    return ActivationParams(
      requiredConfirmations: json.valueOrNull<int>('required_confirmations'),
      requiresNotarization:
          json.valueOrNull<bool>('requires_notarization') ?? false,
      privKeyPolicy: PrivateKeyPolicy.fromLegacyJson(
        json.valueOrNull<dynamic>('priv_key_policy'),
      ),
      minAddressesNumber: json.valueOrNull<int>('min_addresses_number'),
      scanPolicy: json.valueOrNull<String>('scan_policy') == null
          ? null
          : ScanPolicy.parse(json.value<String>('scan_policy')),
      gapLimit: json.valueOrNull<int>('gap_limit'),
      mode: mode,
    );
  }

  /// Optional. Number of confirmations to wait for during swap steps.
  /// Defaults to value in the coins file if not set.
  final int? requiredConfirmations;

  /// Optional, defaults to false. For dPoW protected coins, a true value will wait
  /// for transactions to be notarised when doing swaps.
  final bool requiresNotarization;

  /// Configuration for coin activation mode. Required for QTUM, UTXO & ZHTLC coins.
  final ActivationMode? mode;

  /// Whether to use Trezor hardware wallet or context private key.
  /// Defaults to ContextPrivKey.
  final PrivateKeyPolicy? privKeyPolicy;

  /// HD wallets only. How many additional addresses to generate at a minimum.
  final int? minAddressesNumber;

  /// HD wallets only. Whether or not to scan for new addresses.
  /// Note that 'scan' will result in multiple requests to the Komodo DeFi Framework.
  final ScanPolicy? scanPolicy;

  /// HD wallets only. The max number of empty addresses in a row.
  /// If transactions were sent to an address outside the gap_limit,
  /// they will not be identified when scanning.
  final int? gapLimit;

  @override
  @mustCallSuper
  JsonMap toRpcParams() {
    return {
      if (requiredConfirmations != null)
        'required_confirmations': requiredConfirmations,
      'requires_notarization': requiresNotarization,
      // IMPORTANT: Serialization format varies by coin type:
      // - ETH/ERC20: Uses full JSON object format with type discrimination
      // - Other coins: Uses legacy PascalCase string format for backward compatibility
      // This difference is maintained for API compatibility reasons.
      'priv_key_policy':
          (privKeyPolicy ?? const PrivateKeyPolicy.contextPrivKey())
              .pascalCaseName,
      if (minAddressesNumber != null)
        'min_addresses_number': minAddressesNumber,
      if (scanPolicy != null) 'scan_policy': scanPolicy!.value,
      if (gapLimit != null) 'gap_limit': gapLimit,
      if (mode != null) 'mode': mode!.toJsonRequest(),
    };
  }

  ActivationParams genericCopyWith({
    int? requiredConfirmations,
    bool? requiresNotarization,
    PrivateKeyPolicy? privKeyPolicy,
    int? minAddressesNumber,
    ScanPolicy? scanPolicy,
    int? gapLimit,
    ActivationMode? mode,
  }) {
    return ActivationParams(
      requiredConfirmations:
          requiredConfirmations ?? this.requiredConfirmations,
      requiresNotarization: requiresNotarization ?? this.requiresNotarization,
      privKeyPolicy:
          privKeyPolicy ??
          this.privKeyPolicy ??
          const PrivateKeyPolicy.contextPrivKey(),
      minAddressesNumber: minAddressesNumber ?? this.minAddressesNumber,
      scanPolicy: scanPolicy ?? this.scanPolicy,
      gapLimit: gapLimit ?? this.gapLimit,
      mode: mode ?? this.mode,
    );
  }
}

/// Defines the private key policy for activation
/// API uses pascal case for PrivKeyPolicy types, so we use it as the
/// union key case to ensure compatibility with existing APIs.
@Freezed(unionKey: 'type', unionValueCase: FreezedUnionCase.pascal)
abstract class PrivateKeyPolicy with _$PrivateKeyPolicy {
  /// Private constructor to allow for additional methods and properties
  const PrivateKeyPolicy._();

  /// Use context private key (default)
  const factory PrivateKeyPolicy.contextPrivKey() = _ContextPrivKey;

  /// Use Trezor hardware wallet
  const factory PrivateKeyPolicy.trezor() = _Trezor;

  /// Use MetaMask for activation. WASM (web) only.
  const factory PrivateKeyPolicy.metamask() = _Metamask;

  /// Use WalletConnect for hardware wallet activation
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory PrivateKeyPolicy.walletConnect(String sessionTopic) =
      _WalletConnect;

  factory PrivateKeyPolicy.fromJson(Map<String, dynamic> json) =>
      _$PrivateKeyPolicyFromJson(json);

  /// Converts a string or map to a [PrivateKeyPolicy]
  /// Throws [ArgumentError] if the input is invalid
  /// If the input is null, defaults to [PrivateKeyPolicy.contextPrivKey]
  /// If the input is a string, it must match one of the known policy types.
  /// If the input is a map, it must contain a 'type' key with a valid policy type.
  /// If the input is a map with a 'session_topic' key, it will be used for
  /// [PrivateKeyPolicy.walletConnect].
  factory PrivateKeyPolicy.fromLegacyJson(dynamic privKeyPolicy) {
    if (privKeyPolicy == null) {
      return const PrivateKeyPolicy.contextPrivKey();
    }

    if (privKeyPolicy is Map && privKeyPolicy['type'] != null) {
      return PrivateKeyPolicy.fromJson(privKeyPolicy as JsonMap);
    }

    if (privKeyPolicy is! String) {
      throw ArgumentError(
        'Invalid private key policy type: ${privKeyPolicy.runtimeType}',
      );
    }

    switch (privKeyPolicy) {
      case 'ContextPrivKey':
      case 'context_priv_key':
        return const PrivateKeyPolicy.contextPrivKey();
      case 'Trezor':
      case 'trezor':
        return const PrivateKeyPolicy.trezor();
      case 'Metamask':
      case 'metamask':
        return const PrivateKeyPolicy.metamask();
      case 'WalletConnect':
      case 'wallet_connect':
        return const PrivateKeyPolicy.walletConnect('');
      default:
        throw ArgumentError('Unknown private key policy type: $privKeyPolicy');
    }
  }

  /// Returns the PascalCase name of the private key policy type
  ///
  /// Examples:
  /// - `PrivateKeyPolicy.contextPrivKey()` → `"ContextPrivKey"`
  /// - `PrivateKeyPolicy.trezor()` → `"Trezor"`
  /// - `PrivateKeyPolicy.metamask()` → `"Metamask"`
  /// - `PrivateKeyPolicy.walletConnect(...)` → `"WalletConnect"`
  String get pascalCaseName {
    switch (runtimeType) {
      case _ContextPrivKey:
        return 'ContextPrivKey';
      case _Trezor:
        return 'Trezor';
      case _Metamask:
        return 'Metamask';
      case _WalletConnect:
        return 'WalletConnect';
      default:
        // Fallback: convert snake_case from JSON to PascalCase
        final snakeCaseType = toJson()['type'] as String;
        return snakeCaseType
            .split('_')
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join();
    }
  }
}

/// Utility to normalize PrivateKeyPolicy RPC serialization across protocols.
///
/// - For ETH/ERC20 protocols, the API expects a JSON object form.
/// - For other protocols, the legacy PascalCase string is used.
class PrivKeyPolicySerializer {
  static dynamic toRpc(
    PrivateKeyPolicy policy, {
    required CoinSubClass protocol,
  }) {
    if (evmCoinSubClasses.contains(protocol)) {
      return policy.toJson();
    }
    return policy.pascalCaseName;
  }
}

/// Defines the type of activation mode for QTUM, UTXO & ZHTLC coins
enum ActivationModeType {
  /// Use Electrum servers for activation
  electrum,

  /// Use native blockchain node
  native,

  /// Use light wallet mode (ZHTLC coins only)
  lightWallet;

  String get value {
    switch (this) {
      case ActivationModeType.electrum:
        return 'Electrum';
      case ActivationModeType.native:
        return 'Native';
      case ActivationModeType.lightWallet:
        return 'Light';
    }
  }
}

/// Defines the activation mode for QTUM, BCH, UTXO & ZHTLC coins
class ActivationMode {
  ActivationMode({required this.rpc, this.rpcData})
    : assert(
        (rpc != ActivationModeType.native.value && rpcData != null) ||
            (rpc == ActivationModeType.native.value && rpcData == null),
        'rpcData can only be provided for LightWallet or Electrum modes',
      );

  /// Creates an [ActivationMode] from configuration JSON
  factory ActivationMode.fromConfig(
    JsonMap json, {
    required ActivationModeType type,
  }) {
    return ActivationMode(
      rpc: type.value,
      rpcData: type == ActivationModeType.native
          ? null
          : ActivationRpcData.fromJson(json),
    );
  }

  /// RPC mode: 'Native' for running a native blockchain node, 'Electrum' for using
  /// electrum servers, or 'Light' for ZHTLC coins
  final String rpc;

  /// Configuration data for Electrum or Light mode
  final ActivationRpcData? rpcData;

  JsonMap toJsonRequest() => {
    'rpc': rpc,
    if (rpcData != null)
      'rpc_data': rpcData!.toJsonRequest(
        forLightWallet: rpc == ActivationModeType.lightWallet.value,
      ),
  };
}

/// Defines how to scan for new addresses in HD wallets
enum ScanPolicy {
  /// Do not scan for new addresses
  doNotScan,

  /// Only scan if this is a new wallet
  scanIfNewWallet,

  /// Always scan for new addresses (will result in multiple API requests)
  scan;

  static Set<String> get validPolicies => {
    'do_not_scan',
    'scan_if_new_wallet',
    'scan',
  };

  static bool isValidScanPolicy(String policy) =>
      validPolicies.contains(policy);

  /// Parses a string into a [ScanPolicy]
  /// Throws [ArgumentError] if the policy string is invalid
  static ScanPolicy parse(String policy) {
    if (!isValidScanPolicy(policy)) {
      throw ArgumentError.value(policy, 'policy', 'Invalid scan policy');
    }

    switch (policy) {
      case 'do_not_scan':
        return ScanPolicy.doNotScan;
      case 'scan_if_new_wallet':
        return ScanPolicy.scanIfNewWallet;
      case 'scan':
        return ScanPolicy.scan;
      default:
        throw ArgumentError.value(policy, 'policy', 'Invalid scan policy');
    }
  }

  /// Attempts to parse a string into a [ScanPolicy]
  /// Returns null if the input is null or invalid
  static ScanPolicy? tryParse(String? policy) {
    if (policy == null) {
      return null;
    }

    return parse(policy);
  }

  String get value {
    switch (this) {
      case ScanPolicy.doNotScan:
        return 'do_not_scan';
      case ScanPolicy.scanIfNewWallet:
        return 'scan_if_new_wallet';
      case ScanPolicy.scan:
        return 'scan';
    }
  }
}

/// Contains information about electrum & lightwallet_d servers for coins being used
/// in 'Electrum' or 'Light' mode
class ActivationRpcData {
  ActivationRpcData({
    this.lightWalletDServers,
    this.electrum,
    this.syncParams,
    this.minConnected,
    this.maxConnected = 1,
  }) : assert(
         minConnected == null || minConnected >= 1,
         'min_connected must be at least 1',
       ),
       assert(
         minConnected == null || (maxConnected ?? 1) >= minConnected,
         'min_connected cannot exceed max_connected',
       );

  /// Creates [ActivationRpcData] from JSON configuration
  factory ActivationRpcData.fromJson(JsonMap json) {
    return ActivationRpcData(
      lightWalletDServers: json
          .valueOrNull<List<dynamic>>('light_wallet_d_servers')
          ?.cast<String>(),
      // The Komodo API uses 'servers' under rpc_data for Electrum mode.
      // For some legacy ZHTLC examples, 'electrum' may appear at top-level config.
      electrum:
          (json.valueOrNull<List<dynamic>>('servers') ??
                  json.valueOrNull<List<dynamic>>('electrum') ??
                  json.valueOrNull<List<dynamic>>('electrum_servers') ??
                  json.valueOrNull<List<dynamic>>('nodes') ??
                  json.valueOrNull<List<dynamic>>('rpc_urls'))
              ?.map((e) => ActivationServers.fromJsonConfig(e as JsonMap))
              .toList(),
      syncParams: ZhtlcSyncParams.tryParse(
        json.valueOrNull<dynamic>('sync_params'),
      ),
      minConnected: json.valueOrNull<int>('min_connected'),
      maxConnected: json.valueOrNull<int>('max_connected'),
    );
  }

  /// ZHTLC only. A list of urls which are hosting lightwallet_d servers for a coin
  final List<String>? lightWalletDServers;

  /// List of electrum servers for QTUM, BCH & UTXO coins
  final List<ActivationServers>? electrum;

  /// Minimum number of electrum servers to keep connected. Optional.
  final int? minConnected;

  /// Maximum number of electrum servers to keep connected. Defaults to 1.
  final int? maxConnected;

  /// ZHTLC coins only. Optional. Defines where to start scanning blockchain
  /// data on activation when provided by the client.
  ///
  /// If omitted, backend-side behavior applies (for example resuming from
  /// persisted sync state or using backend defaults).
  ///
  /// Supported values:
  /// - Earliest: start from the coin's `sapling_activation_height`
  /// - Height: start from a specific block height
  /// - Date: start from a specific unix timestamp
  final ZhtlcSyncParams? syncParams;

  bool get isEmpty =>
      (lightWalletDServers == null || lightWalletDServers!.isEmpty) &&
      (electrum == null || electrum!.isEmpty) &&
      syncParams == null;

  JsonMap toJsonRequest({bool forLightWallet = false}) => {
    if (lightWalletDServers != null)
      'light_wallet_d_servers': lightWalletDServers,
    if (electrum != null)
      (forLightWallet ? 'electrum_servers' : 'servers'): electrum!
          .map((e) => e.toJsonRequest())
          .toList(),
    if (electrum != null) 'max_connected': (maxConnected ?? 1),
    if (minConnected != null) 'min_connected': minConnected,
    if (syncParams != null) 'sync_params': syncParams!.toJsonRequest(),
  };
}

/// ZHTLC sync parameters shape for KDF API
class ZhtlcSyncParams {
  ZhtlcSyncParams._internal({this.height, this.date, this.isEarliest = false})
    : assert(
        (isEarliest ? 1 : 0) +
                (height != null ? 1 : 0) +
                (date != null ? 1 : 0) ==
            1,
        'Exactly one of earliest, height or date must be provided',
      );

  /// Start from coin's `sapling_activation_height`
  factory ZhtlcSyncParams.earliest() =>
      ZhtlcSyncParams._internal(isEarliest: true);

  /// Start from a specific block height
  factory ZhtlcSyncParams.height(int height) =>
      ZhtlcSyncParams._internal(height: height);

  /// Start from a specific unix timestamp
  factory ZhtlcSyncParams.date(int unixTimestamp) =>
      ZhtlcSyncParams._internal(date: unixTimestamp);

  final int? height;
  final int? date;
  final bool isEarliest;

  /// Best-effort parser supporting all documented and legacy shapes:
  /// - "earliest"
  /// - { "height": <int> }
  /// - { "date": <int> }
  /// - <int> (heuristic: < 1e9 => height, otherwise date)
  static ZhtlcSyncParams? tryParse(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      if (value.toLowerCase() == 'earliest') {
        return ZhtlcSyncParams.earliest();
      }
      // Unknown string value
      return null;
    }

    if (value is int) {
      // Heuristic: timestamps are typically >= 1,000,000,000 (10-digit seconds)
      if (value >= 1000000000) {
        return ZhtlcSyncParams.date(value);
      }
      return ZhtlcSyncParams.height(value);
    }

    if (value is Map) {
      final map = value;
      final dynamic heightVal = map['height'];
      final dynamic dateVal = map['date'];

      if (heightVal is int) {
        return ZhtlcSyncParams.height(heightVal);
      }
      if (dateVal is int) {
        return ZhtlcSyncParams.date(dateVal);
      }
      if ((map['earliest'] == true) ||
          (map['type'] == 'earliest') ||
          (map['type'] == 'Earliest')) {
        return ZhtlcSyncParams.earliest();
      }
      return null;
    }

    return null;
  }

  /// JSON suitable for KDF API
  /// - "earliest" | { "height": int } | { "date": int }
  dynamic toJsonRequest() {
    if (isEarliest) return 'earliest';
    if (height != null) return {'height': height};
    if (date != null) return {'date': date};
    // Should not reach here due to constructor assert, but return null to be safe
    return null;
  }
}

/// Contains information about electrum servers for coins being used in 'Electrum'
/// or 'Light' mode
class ActivationServers {
  ActivationServers({
    required this.url,
    this.wsUrl,
    this.protocol = 'TCP',
    this.disableCertVerification = false,
  });

  /// Creates [ActivationServers] from JSON configuration
  factory ActivationServers.fromJsonConfig(JsonMap json) {
    return ActivationServers(
      url: json.value<String>('url'),
      wsUrl: json.valueOrNull<String>('ws_url'),
      protocol: json.valueOrNull<String>('protocol') ?? 'TCP',
      disableCertVerification:
          json.valueOrNull<bool>('disable_cert_verification') ?? false,
    );
  }

  /// The URL and port for an electrum server
  final String url;

  /// Optional, for WSS only. The URL and port for an electrum server's WSS port
  final String? wsUrl;

  /// Optional, defaults to 'TCP'. Transport protocol used to connect to the server.
  /// Options: 'TCP' or 'SSL'
  final String protocol;

  /// Optional, defaults to false. If true, disables server SSL/TLS certificate
  /// verification (e.g. for self-signed certificates).
  /// WARNING: Use at your own risk!
  final bool disableCertVerification;

  JsonMap toJsonRequest() => {
    'url': url,
    if (wsUrl != null) 'ws_url': wsUrl,
    'protocol': protocol,
    'disable_cert_verification': disableCertVerification,
  };
}
