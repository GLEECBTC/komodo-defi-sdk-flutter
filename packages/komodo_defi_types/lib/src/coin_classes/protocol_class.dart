import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/json_type_utils.dart';

/// Base class for all protocol definitions
abstract class ProtocolClass with ExplorerUrlMixin implements Equatable {
  const ProtocolClass({
    required this.subClass,
    required this.config,
    this.supportedProtocols = const [],
    this.isCustomToken = false,
  });

  /// Creates the appropriate protocol class from JSON config
  factory ProtocolClass.fromJson(JsonMap json, {CoinSubClass? requestedType}) {
    final primaryType =
        requestedType ?? CoinSubClass.parse(json.value<String>('type'));
    final otherTypes =
        json
            .valueOrNull<List<dynamic>>('other_types')
            ?.map((type) => CoinSubClass.parse(type as String))
            .toList() ??
        [];

    // If a specific type is requested, update the config
    final configToUse = requestedType != null && requestedType != primaryType
        ? (JsonMap.of(json)
            ..['type'] = requestedType.toString().split('.').last)
        : json;
    try {
      return switch (primaryType) {
        CoinSubClass.utxo || CoinSubClass.smartChain => UtxoProtocol.fromJson(
          configToUse,
          supportedProtocols: otherTypes,
        ),
        // SLP is no longer supported by its own protocol (BCH)
        // CoinSubClass.slp => SlpProtocol.fromJson(
        //     configToUse,
        //     supportedProtocols: otherTypes,
        //   ),
        CoinSubClass.avx20 ||
        CoinSubClass.bep20 ||
        CoinSubClass.ftm20 ||
        CoinSubClass.matic ||
        CoinSubClass.hrc20 ||
        CoinSubClass.arbitrum ||
        CoinSubClass.base ||
        CoinSubClass.moonriver ||
        CoinSubClass.moonbeam ||
        CoinSubClass.ethereumClassic ||
        CoinSubClass.ubiq ||
        CoinSubClass.krc20 ||
        CoinSubClass.ewt ||
        CoinSubClass.hecoChain ||
        CoinSubClass.rskSmartBitcoin ||
        CoinSubClass.erc20 => Erc20Protocol.fromJson(json),
        CoinSubClass.qrc20 => QtumProtocol.fromJson(json),
        CoinSubClass.zhtlc => ZhtlcProtocol.fromJson(json),
        CoinSubClass.tendermintToken ||
        CoinSubClass.tendermint => TendermintProtocol.fromJson(
          configToUse,
          supportedProtocols: otherTypes,
        ),
        CoinSubClass.sia => SiaProtocol.fromJson(
          configToUse,
          supportedProtocols: otherTypes,
        ),
        // ignore: deprecated_member_use_from_same_package
        CoinSubClass.slp ||
        CoinSubClass.smartBch ||
        CoinSubClass.unknown => throw UnsupportedProtocolException(
          'Unsupported protocol type: ${primaryType.formatted}',
        ),
        // _ => throw UnsupportedProtocolException(
        //     'Unsupported protocol type: ${subClass.formatted}',
        //   ),
      };
    } catch (e, s) {
      if (kDebugMode) debugPrintStack(stackTrace: s);
      throw ProtocolParsingException(primaryType, e.toString());
    }
  }

  final CoinSubClass subClass;
  final JsonMap config;
  final List<CoinSubClass> supportedProtocols;

  /// Whether this is a custom token activated by the user.
  /// Only EVM tokens are supported (e.g. ETH), and they are activated
  /// as wallet-only.
  final bool isCustomToken;

  /// Whether this protocol supports multiple addresses per wallet
  bool get supportsMultipleAddresses;

  /// Whether this protocol requires HD wallet mode
  bool get requiresHdWallet;

  /// Core protocol properties that all protocols must implement
  String? get derivationPath => config.valueOrNull<String>('derivation_path');
  bool get isTestnet => config.valueOrNull<bool>('is_testnet') ?? false;
  ActivationRpcData get requiredServers => ActivationRpcData.fromJson(config);

  /// Explorer URL handling is now delegated to the ExplorerUrlPattern class
  @override
  ExplorerUrlPattern get explorerPattern => ExplorerUrlPattern.fromJson(config);

  /// Whether the protocol supports memos
  /// Only ZHTLC and UTXO protocols support memos
  bool get isMemoSupported;

  /// Convert protocol back to JSON representation
  JsonMap toJson() => {
    ...config,
    'sub_class': subClass.toString().split('.').last,
    'is_custom_token': isCustomToken,
    if (supportedProtocols.isNotEmpty)
      'other_types': supportedProtocols
          .map((p) => p.toString().split('.').last)
          .toList(),
  };

  /// Check if this protocol supports a given protocol type
  bool supportsProtocolType(CoinSubClass type) {
    return subClass == type || supportedProtocols.contains(type);
  }

  /// Creates an alternate protocol instance for a supported protocol type
  ProtocolClass? createProtocolVariant(CoinSubClass type) {
    if (!supportsProtocolType(type) || type == subClass) return null;

    final variantConfig = JsonMap.from(config)
      ..['type'] = type.toString().split('.').last;

    return ProtocolClass.fromJson(variantConfig);
  }

  /// Declarative streaming capabilities based on protocol subclass and
  /// whether the asset is a child token (e.g. QRC20 token).
  bool supportsBalanceStreaming({required bool isChildAsset}) {
    // Unsupported: SLP tokens, Tendermint tokens, Sia (feature-gated)
    if (subClass == CoinSubClass.slp ||
        subClass == CoinSubClass.tendermintToken ||
        subClass == CoinSubClass.sia) {
      return false;
    }
    // QRC20 tokens (child assets) do not support balance streaming
    if (subClass == CoinSubClass.qrc20 && isChildAsset) {
      return false;
    }
    return true;
  }

  bool supportsTxHistoryStreaming({required bool isChildAsset}) {
    // EVM does not support tx history streaming in KDF
    if (evmCoinSubClasses.contains(subClass)) {
      return false;
    }
    // Unsupported: QRC20 tokens, SLP tokens, Tendermint tokens
    if (subClass == CoinSubClass.slp ||
        subClass == CoinSubClass.tendermintToken ||
        subClass == CoinSubClass.sia) {
      return false;
    }
    if (subClass == CoinSubClass.qrc20 && isChildAsset) {
      return false;
    }
    return true;
  }

  ActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) => ActivationParams.fromConfigJson(
    config,
  ).genericCopyWith(privKeyPolicy: privKeyPolicy);

  String? get contractAddress => config.valueOrNull<String>('contract_address');

  @override
  List<Object?> get props => [
    subClass,
    supportedProtocols,
    isCustomToken,
    requiresHdWallet,
    derivationPath,
    isTestnet,
  ];

  @override
  bool? get stringify => false;
}
