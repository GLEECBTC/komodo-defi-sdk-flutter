import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class Asset extends Equatable {
  const Asset({
    required this.id,
    required this.protocol,
    required this.isWalletOnly,
    required this.signMessagePrefix,
  });

  factory Asset.fromJsonWithId(JsonMap json, {required AssetId assetId}) {
    // Create protocol of the type specified in the AssetId
    final protocol = ProtocolClass.fromJson(
      json,
      requestedType: assetId.subClass,
    );

    return Asset(
      id: assetId,
      protocol: protocol,
      isWalletOnly: json.valueOrNull<bool>('wallet_only') ?? false,
      signMessagePrefix: json.valueOrNull<String>('sign_message_prefix'),
    );
  }

  factory Asset.fromJson(JsonMap json, {Set<AssetId>? knownIds}) {
    final assetId = AssetId.parse(json, knownIds: knownIds);
    final protocol = ProtocolClass.fromJson(json);
    return Asset(
      id: assetId,
      protocol: protocol,
      isWalletOnly: json.valueOrNull<bool>('wallet_only') ?? false,
      signMessagePrefix: json.valueOrNull<String>('sign_message_prefix'),
    );
  }

  /// Creates a variant of this asset with a different protocol type
  Asset? createVariant(CoinSubClass protocolType) {
    if (!protocol.supportsProtocolType(protocolType)) return null;

    final variantProtocol = protocol.createProtocolVariant(protocolType);
    if (variantProtocol == null) return null;

    return Asset(
      id: id.copyWith(subClass: protocolType),
      protocol: variantProtocol,
      isWalletOnly: isWalletOnly,
      signMessagePrefix: signMessagePrefix,
    );
  }

  /// Gets all supported protocol variants of this asset
  Set<Asset> get protocolVariants {
    return protocol.supportedProtocols
        .map(createVariant)
        .whereType<Asset>()
        .toSet();
  }

  final AssetId id;
  final ProtocolClass protocol;
  final bool isWalletOnly;
  final String? signMessagePrefix;

  /// Whether this asset supports message signing.
  ///
  /// Solana signs Ed25519 messages without a Bitcoin-style message prefix.
  /// Other protocols use the configured `sign_message_prefix` capability.
  bool get supportsMessageSigning =>
      protocol.isSolana || signMessagePrefix != null;

  /// Creates a copy of this Asset with optionally modified fields.
  Asset copyWith({
    AssetId? id,
    ProtocolClass? protocol,
    bool? isWalletOnly,
    String? signMessagePrefix,
  }) {
    return Asset(
      id: id ?? this.id,
      protocol: protocol ?? this.protocol,
      isWalletOnly: isWalletOnly ?? this.isWalletOnly,
      signMessagePrefix: signMessagePrefix ?? this.signMessagePrefix,
    );
  }

  /// Whether KDF supports balance streaming for this asset.
  bool get supportsBalanceStreaming =>
      protocol.supportsBalanceStreaming(isChildAsset: id.parentId != null);

  /// Whether KDF supports transaction history streaming for this asset.
  bool get supportsTxHistoryStreaming =>
      protocol.supportsTxHistoryStreaming(isChildAsset: id.parentId != null);

  JsonMap toJson() => {
    'protocol': protocol.toJson(),
    'id': id.toJson(),
    'wallet_only': isWalletOnly,
    if (signMessagePrefix != null) 'sign_message_prefix': signMessagePrefix,
  };

  @override
  List<Object?> get props => [id, protocol, isWalletOnly, signMessagePrefix];

  @override
  String toString() => 'Asset(${toJson()})';
}
