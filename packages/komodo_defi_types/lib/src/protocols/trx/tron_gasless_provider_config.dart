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
  const GaslessServiceGasFree({required this.apiKey, required this.apiSecret});

  final String apiKey;
  final String apiSecret;

  @override
  Object toJson() => {
    'gas_free': {'api_key': apiKey, 'api_secret': apiSecret},
  };

  @override
  List<Object?> get props => [apiKey, apiSecret];

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
    this.serviceProvider,
    this.requestTimeoutMs = 15000,
    this.statusPollIntervalMs = 3000,
  });

  factory TronGaslessProviderConfig.fromJson(JsonMap json) {
    return TronGaslessProviderConfig(
      baseUrl: json.value<String>('base_url'),
      service: GaslessService.fromJson(json.value<Object>('service')),
      serviceProvider: json.valueOrNull<String>('service_provider'),
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
  ///
  /// When omitted, KDF resolves the first provider offered by the configured
  /// service on first use and caches it for the activation lifetime.
  final String? serviceProvider;

  /// Request timeout for GasFree API calls, in milliseconds.
  final int requestTimeoutMs;

  /// Polling interval for transfer status checks, in milliseconds.
  final int statusPollIntervalMs;

  JsonMap toJson() => {
    'base_url': baseUrl,
    'service': service.toJson(),
    if (serviceProvider?.trim().isNotEmpty ?? false)
      'service_provider': serviceProvider!.trim(),
    'request_timeout_ms': requestTimeoutMs,
    'status_poll_interval_ms': statusPollIntervalMs,
  };

  /// Validate the documented KDF activation shape before startup.
  void validate() {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must be an absolute URL');
    }
    final scheme = uri.scheme.toLowerCase();
    switch (service) {
      case GaslessServiceGasFree():
        if (scheme != 'https') {
          throw ArgumentError.value(
            baseUrl,
            'baseUrl',
            'Direct GasFree mode requires HTTPS',
          );
        }
        if (uri.path.isNotEmpty && uri.path != '/') {
          throw ArgumentError.value(
            baseUrl,
            'baseUrl',
            'Direct GasFree mode requires a host-only URL',
          );
        }
      case GaslessServiceKomodoProxy():
        if (scheme != 'http' && scheme != 'https') {
          throw ArgumentError.value(
            baseUrl,
            'baseUrl',
            'Komodo proxy mode requires HTTP or HTTPS',
          );
        }
    }
    // KDF deserializes both values as unsigned integers without imposing
    // client-side minimums or maximums.
    if (requestTimeoutMs < 0) {
      throw RangeError.value(requestTimeoutMs, 'requestTimeoutMs');
    }
    if (statusPollIntervalMs < 0) {
      throw RangeError.value(statusPollIntervalMs, 'statusPollIntervalMs');
    }
  }

  @override
  List<Object?> get props => [
    baseUrl,
    service,
    serviceProvider,
    requestTimeoutMs,
    statusPollIntervalMs,
  ];
}
