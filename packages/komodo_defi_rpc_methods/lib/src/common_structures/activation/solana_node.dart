import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Solana HTTP RPC endpoint. KDF accepts only the URL in this node object.
class SolanaNode extends Equatable {
  const SolanaNode({required this.url});

  factory SolanaNode.fromJson(JsonMap json) =>
      SolanaNode(url: json.value<String>('url'));

  final String url;

  JsonMap toJson() => {'url': url};

  @override
  List<Object?> get props => [url];
}
