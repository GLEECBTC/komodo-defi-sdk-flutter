import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class SolanaProtocol extends ProtocolClass {
  SolanaProtocol._({required super.config})
    : super(subClass: CoinSubClass.solana);

  factory SolanaProtocol.fromJson(JsonMap json) {
    final nodes = json.valueOrNull<JsonList>('nodes');
    if (nodes == null || nodes.isEmpty) {
      throw MissingProtocolFieldException('RPC nodes', 'nodes');
    }
    for (final node in nodes) {
      SolanaNode.fromJson(node);
    }
    return SolanaProtocol._(config: json);
  }

  List<SolanaNode> get nodes =>
      config.value<JsonList>('nodes').map(SolanaNode.fromJson).toList();

  int get decimals => 9;
  int get requiredConfirmations =>
      config.valueOrNull<int>('required_confirmations') ?? 1;

  @override
  bool get supportsMultipleAddresses => false;
  @override
  bool get requiresHdWallet => false;
  @override
  bool get isMemoSupported => true;

  @override
  SolanaActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
    int? gapLimit,
  }) {
    if (privKeyPolicy != const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an internal wallet');
    }
    return SolanaActivationParams(nodes: nodes);
  }

  @override
  List<Object?> get props => [...super.props, nodes];
}

class SolanaTokenProtocol extends ProtocolClass {
  SolanaTokenProtocol._({required super.config, required super.isCustomToken})
    : super(subClass: CoinSubClass.solanaToken);

  factory SolanaTokenProtocol.fromJson(JsonMap json) {
    validateSolanaTokenProtocol(json.value<JsonMap>('protocol'));
    final data = json.value<JsonMap>('protocol', 'protocol_data');
    for (final key in ['platform', 'mint_address', 'program_id']) {
      if (data.value<String>(key).isEmpty) {
        throw MissingProtocolFieldException(key, 'protocol.protocol_data.$key');
      }
    }
    final decimals = data.value<int>('decimals');
    if (decimals < 0 || decimals > 255) {
      throw const FormatException(
        'Solana token decimals must fit an unsigned byte',
      );
    }
    final parent = json.valueOrNull<String>('parent_coin');
    if (parent != null && parent != data.value<String>('platform')) {
      throw const FormatException(
        'Solana token parent does not match its platform',
      );
    }
    return SolanaTokenProtocol._(
      config: json,
      isCustomToken: json.valueOrNull<bool>('is_custom_token') ?? false,
    );
  }

  static const classicTokenProgramId =
      'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const token2022ProgramId =
      'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';

  JsonMap get protocolData =>
      config.value<JsonMap>('protocol', 'protocol_data');
  String get platform => protocolData.value<String>('platform');
  String get mintAddress => protocolData.value<String>('mint_address');
  String get programId => protocolData.value<String>('program_id');
  int get decimals => protocolData.value<int>('decimals');
  bool get isToken2022 => programId == token2022ProgramId;

  @override
  String get contractAddress => mintAddress;
  @override
  bool get supportsMultipleAddresses => false;
  @override
  bool get requiresHdWallet => false;
  @override
  bool get isMemoSupported => true;

  // KDF emits both token balance and history updates on its platform stream.
  @override
  bool supportsBalanceStreaming({required bool isChildAsset}) => false;
  @override
  bool supportsTxHistoryStreaming({required bool isChildAsset}) => false;

  @override
  SolanaTokenActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
    int? gapLimit,
  }) {
    if (privKeyPolicy != const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an internal wallet');
    }
    return const SolanaTokenActivationParams();
  }

  @override
  List<Object?> get props => [
    ...super.props,
    platform,
    mintAddress,
    programId,
    decimals,
  ];
}
