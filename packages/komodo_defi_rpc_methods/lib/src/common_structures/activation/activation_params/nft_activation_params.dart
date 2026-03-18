import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Activation parameters for enabling NFT-like tokens on the platform
class NftActivationParams extends ActivationParams {
  NftActivationParams({
    required this.provider,
    super.requiredConfirmations,
    super.requiresNotarization = false,
  });

  factory NftActivationParams.fromJson(JsonMap json) {
    final base = ActivationParams.fromConfigJson(json);

    return NftActivationParams(
      provider: NftProvider.fromJson(json.value<JsonMap>('provider')),
      requiredConfirmations: base.requiredConfirmations,
      requiresNotarization: base.requiresNotarization,
    );
  }

  /// The provider configuration
  final NftProvider provider;

  NftActivationParams copyWith({
    NftProvider? provider,
    int? requiredConfirmations,
    bool? requiresNotarization,
  }) {
    return NftActivationParams(
      provider: provider ?? this.provider,
      requiredConfirmations:
          requiredConfirmations ?? this.requiredConfirmations,
      requiresNotarization: requiresNotarization ?? this.requiresNotarization,
    );
  }

  @override
  Map<String, dynamic> toRpcParams() {
    return {...super.toRpcParams(), 'provider': provider.toJson()};
  }
}

/// Contains information about a provider's URL and proxy settings
class NftProviderInfo {
  const NftProviderInfo({required this.url, required this.komodoProxy});

  factory NftProviderInfo.fromJson(JsonMap json) {
    return NftProviderInfo(
      url: json.value<String>('url'),
      komodoProxy: json.value<bool>('komodo_proxy'),
    );
  }

  /// The URL of the provider
  final String url;

  /// Whether this provider is a Komodo proxy
  final bool komodoProxy;

  /// Converts to JSON representation
  Map<String, dynamic> toJson() => {'url': url, 'komodo_proxy': komodoProxy};
}

/// Contains information about a NFT provider, including its type and
/// the connection details
class NftProvider {
  const NftProvider({required this.type, required this.info});

  factory NftProvider.moralis() => const NftProvider(
    type: 'Moralis',
    info: NftProviderInfo(
      url: 'https://moralis.gleec.com',
      komodoProxy: true,
    ),
  );

  factory NftProvider.fromJson(JsonMap json) {
    return NftProvider(
      type: json.value<String>('type'),
      info: NftProviderInfo.fromJson(json.value<JsonMap>('info')),
    );
  }

  /// The type of provider (e.g., "Moralis")
  // TODO: make this an enum once all providers are known
  final String type;

  /// Connection information for the provider
  final NftProviderInfo info;

  Map<String, dynamic> toJson() => {'type': type, 'info': info.toJson()};
}
