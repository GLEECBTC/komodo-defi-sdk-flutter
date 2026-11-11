import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// A token enabled with its SOL platform. The token's empty activation fields
/// are flattened by KDF, so this is `{ticker, protocol?}` on the wire.
class SolanaTokenRequest {
  const SolanaTokenRequest({required this.ticker, this.protocol});

  factory SolanaTokenRequest.fromJson(JsonMap json) => SolanaTokenRequest(
    ticker: json.value<String>('ticker'),
    protocol: json.valueOrNull<JsonMap>('protocol'),
  );

  final String ticker;
  final JsonMap? protocol;

  JsonMap toJson() => {
    'ticker': ticker,
    if (protocol != null) 'protocol': validateSolanaTokenProtocol(protocol!),
  };
}

/// Validates a complete trusted token override before dispatching to KDF.
/// Mint-only discovery is not part of the Solana activation contract.
JsonMap validateSolanaTokenProtocol(JsonMap protocol) {
  final data = protocol['protocol_data'];
  if (protocol['type'] != 'SOLANATOKEN' || data is! Map<String, dynamic>) {
    throw const FormatException('Expected a complete SOLANATOKEN protocol');
  }
  for (final key in ['platform', 'mint_address', 'program_id']) {
    if (data[key] is! String || (data[key] as String).isEmpty) {
      throw FormatException('Solana token protocol requires $key');
    }
  }
  final decimals = data['decimals'];
  if (decimals is! int || decimals < 0 || decimals > 255) {
    throw const FormatException(
      'Solana token protocol requires valid decimals',
    );
  }
  return protocol;
}

/// Solana uses a single address from the current internal wallet. Generic HD,
/// hardware-wallet, and notarization parameters are deliberately not emitted.
class SolanaActivationParams extends ActivationParams {
  const SolanaActivationParams({
    required this.nodes,
    this.tokensParams = const [],
    this.txHistory = true,
  });

  factory SolanaActivationParams.fromJson(JsonMap json) =>
      SolanaActivationParams(
        nodes: json.value<JsonList>('nodes').map(SolanaNode.fromJson).toList(),
        tokensParams:
            json
                .valueOrNull<JsonList>('tokens_params')
                ?.map(SolanaTokenRequest.fromJson)
                .toList() ??
            const [],
        txHistory: json.valueOrNull<bool>('tx_history') ?? true,
      );

  final List<SolanaNode> nodes;
  final List<SolanaTokenRequest> tokensParams;
  final bool txHistory;

  SolanaActivationParams copyWith({
    List<SolanaNode>? nodes,
    List<SolanaTokenRequest>? tokensParams,
    bool? txHistory,
  }) => SolanaActivationParams(
    nodes: nodes ?? this.nodes,
    tokensParams: tokensParams ?? this.tokensParams,
    txHistory: txHistory ?? this.txHistory,
  );

  @override
  // Solana has its own request schema, not ActivationParams' generic schema.
  // ignore: must_call_super
  JsonMap toRpcParams() {
    if (nodes.isEmpty) {
      throw const FormatException(
        'Solana activation requires at least one RPC node',
      );
    }
    for (final node in nodes) {
      final uri = Uri.tryParse(node.url);
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('Solana RPC nodes must use HTTP or HTTPS');
      }
    }
    return {
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'tokens_params': tokensParams.map((token) => token.toJson()).toList(),
      'tx_history': txHistory,
    };
  }

  @override
  SolanaActivationParams genericCopyWith({
    int? requiredConfirmations,
    bool? requiresNotarization,
    PrivateKeyPolicy? privKeyPolicy,
    int? minAddressesNumber,
    ScanPolicy? scanPolicy,
    int? gapLimit,
    ActivationMode? mode,
  }) {
    if (privKeyPolicy != null &&
        privKeyPolicy != const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an internal wallet');
    }
    return this;
  }
}

class SolanaTokenActivationParams extends ActivationParams {
  const SolanaTokenActivationParams();

  @override
  // ignore: must_call_super
  JsonMap toRpcParams() => {};

  @override
  SolanaTokenActivationParams genericCopyWith({
    int? requiredConfirmations,
    bool? requiresNotarization,
    PrivateKeyPolicy? privKeyPolicy,
    int? minAddressesNumber,
    ScanPolicy? scanPolicy,
    int? gapLimit,
    ActivationMode? mode,
  }) {
    if (privKeyPolicy != null &&
        privKeyPolicy != const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an internal wallet');
    }
    return this;
  }
}
