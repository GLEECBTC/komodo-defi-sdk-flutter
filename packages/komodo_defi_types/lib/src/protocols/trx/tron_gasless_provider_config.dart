import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// The GasFree relay transport used for Tron gas-free (gasless) transfers.
///
/// Serializes as the `service` field of [TronGaslessProviderConfig], matching
/// the KDF `tron_gasless_provider` contract. The enum is snake_case-tagged and
/// heterogeneous: the proxy variant is the bare string `"komodo_proxy"`, while
/// the direct variant is an object keyed by `gas_free`.
sealed class GaslessService extends Equatable {
  const GaslessService();

  factory GaslessService.fromJson(Object json) {
    if (json is String) {
      if (json == 'komodo_proxy') return const GaslessServiceKomodoProxy();
      throw ArgumentError('Unknown gasless service type');
    }
    if (json is Map) {
      final map = JsonMap.from(json);
      final gasFree = map.valueOrNull<JsonMap>('gas_free');
      if (gasFree != null) {
        return GaslessServiceGasFree(
          apiKey: gasFree.value<String>('api_key'),
          apiSecret: gasFree.value<String>('api_secret'),
          unsafeAllowDirectHmac:
              gasFree.valueOrNull<bool>('unsafe_allow_direct_hmac') ?? false,
        );
      }
    }
    throw ArgumentError('Unknown gasless service type');
  }

  /// Returns either a [String] (`"komodo_proxy"`) or a [JsonMap]
  /// (`{"gas_free": {...}}`) for direct embedding in the `service` slot.
  Object toJson();
}

/// Route gasless transfers through a Komodo/Gleec proxy that holds the GasFree
/// API credentials server-side. No secrets are embedded in the client.
class GaslessServiceKomodoProxy extends GaslessService {
  const GaslessServiceKomodoProxy();

  @override
  Object toJson() => 'komodo_proxy';

  @override
  List<Object?> get props => const [];
}

/// Call the GasFree API directly with an API key/secret. Not recommended for
/// shipped clients, as it embeds credentials in the request.
class GaslessServiceGasFree extends GaslessService {
  const GaslessServiceGasFree({
    required this.apiKey,
    required this.apiSecret,
    this.unsafeAllowDirectHmac = false,
  });

  final String apiKey;
  final String apiSecret;

  /// Explicit development-only opt-in required by KDF for direct HMAC mode.
  final bool unsafeAllowDirectHmac;

  @override
  Object toJson() => {
    'gas_free': {
      'api_key': apiKey,
      'api_secret': apiSecret,
      if (unsafeAllowDirectHmac)
        'unsafe_allow_direct_hmac': unsafeAllowDirectHmac,
    },
  };

  @override
  List<Object?> get props => [unsafeAllowDirectHmac];

  @override
  String toString() =>
      'GaslessServiceGasFree(apiKey: <redacted>, apiSecret: <redacted>)';
}

/// Configuration for the Tron GasFree provider, supplied at platform (TRX)
/// activation as the `tron_gasless_provider` activation param.
///
/// Enables gas-free TRC20 transfers where the network fee is paid in the token
/// rather than in TRX. This object carries provider credentials when using the
/// direct [GaslessServiceGasFree] variant, so it is held in memory only and
/// never persisted to disk.
class TronGaslessProviderConfig extends Equatable {
  const TronGaslessProviderConfig({
    required this.baseUrl,
    required this.service,
    required this.serviceProvider,
    this.allowServiceProviderDiscovery = false,
    this.unsafeAllowInsecureHttp = false,
    this.requestTimeoutMs = 15000,
    this.statusPollIntervalMs = 3000,
  });

  factory TronGaslessProviderConfig.fromJson(JsonMap json) {
    return TronGaslessProviderConfig(
      baseUrl: json.value<String>('base_url'),
      service: GaslessService.fromJson(json.value<Object>('service')),
      serviceProvider: json.valueOrNull<String>('service_provider'),
      allowServiceProviderDiscovery:
          json.valueOrNull<bool>('allow_service_provider_discovery') ?? false,
      unsafeAllowInsecureHttp:
          json.valueOrNull<bool>('unsafe_allow_insecure_http') ?? false,
      requestTimeoutMs: json.valueOrNull<int>('request_timeout_ms') ?? 15000,
      statusPollIntervalMs:
          json.valueOrNull<int>('status_poll_interval_ms') ?? 3000,
    );
  }

  /// GasFree API base URL (the proxy endpoint when using
  /// [GaslessServiceKomodoProxy]).
  final String baseUrl;

  /// Provider transport and, for the direct variant, credentials.
  final GaslessService service;

  /// Service-provider TRON address used in the TIP-712 permit.
  final String? serviceProvider;

  /// Development-only opt-in to select the first provider returned by KDF.
  /// Production configurations must pin [serviceProvider].
  final bool allowServiceProviderDiscovery;

  /// Development-only opt-in for a plain-HTTP proxy endpoint.
  final bool unsafeAllowInsecureHttp;

  /// Request timeout for GasFree API calls, in milliseconds.
  final int requestTimeoutMs;

  /// Polling interval for transfer status checks, in milliseconds.
  final int statusPollIntervalMs;

  JsonMap toJson() => {
    'base_url': baseUrl,
    'service': service.toJson(),
    if (serviceProvider?.trim().isNotEmpty ?? false)
      'service_provider': serviceProvider,
    if (allowServiceProviderDiscovery) 'allow_service_provider_discovery': true,
    if (unsafeAllowInsecureHttp) 'unsafe_allow_insecure_http': true,
    'request_timeout_ms': requestTimeoutMs,
    'status_poll_interval_ms': statusPollIntervalMs,
  };

  /// Validate security-sensitive runtime invariants before KDF startup.
  void validate({
    bool allowInsecureTransport = false,
    bool allowDirectCredentials = false,
    bool allowProviderDiscovery = false,
  }) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must be an absolute URL');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https') {
      final explicitlyAllowed =
          scheme == 'http' &&
          unsafeAllowInsecureHttp &&
          allowInsecureTransport &&
          service is GaslessServiceKomodoProxy;
      if (!explicitlyAllowed) {
        throw ArgumentError.value(baseUrl, 'baseUrl', 'HTTPS is required');
      }
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Credentials, query parameters, and fragments are not allowed',
      );
    }
    final String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(uri.path);
    } on FormatException {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Malformed URL path encoding is not allowed',
      );
    }
    if (uri.path.contains('\\') ||
        uri.path.contains('//') ||
        decodedPath.split('/').any((segment) => segment == '..')) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Ambiguous or traversing URL paths are not allowed',
      );
    }
    if (service is GaslessServiceGasFree &&
        uri.path.isNotEmpty &&
        uri.path != '/') {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Direct GasFree mode requires a host-only URL',
      );
    }
    if (allowServiceProviderDiscovery && !allowProviderDiscovery) {
      throw ArgumentError(
        'Service-provider discovery is development-only; pin a provider',
      );
    }
    if ((serviceProvider?.trim().isEmpty ?? true) &&
        !allowServiceProviderDiscovery) {
      throw ArgumentError.value(
        serviceProvider,
        'serviceProvider',
        'A pinned service provider is required',
      );
    }
    if (requestTimeoutMs < 1000 || requestTimeoutMs > 60000) {
      throw RangeError.range(requestTimeoutMs, 1000, 60000, 'requestTimeoutMs');
    }
    if (statusPollIntervalMs < 500 || statusPollIntervalMs > 60000) {
      throw RangeError.range(
        statusPollIntervalMs,
        500,
        60000,
        'statusPollIntervalMs',
      );
    }
    if (service case final GaslessServiceGasFree direct) {
      if (!direct.unsafeAllowDirectHmac || !allowDirectCredentials) {
        throw ArgumentError(
          'Direct GasFree credentials are development-only; use komodo_proxy',
        );
      }
      if (direct.apiKey.trim().isEmpty || direct.apiSecret.trim().isEmpty) {
        throw ArgumentError('Direct GasFree credentials must be non-empty');
      }
    }
  }

  @override
  List<Object?> get props => [
    baseUrl,
    service,
    serviceProvider,
    allowServiceProviderDiscovery,
    unsafeAllowInsecureHttp,
    requestTimeoutMs,
    statusPollIntervalMs,
  ];
}
