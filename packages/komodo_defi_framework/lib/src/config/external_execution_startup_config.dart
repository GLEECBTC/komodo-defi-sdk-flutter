import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Startup configuration for KDF-owned external execution.
///
/// The default is deliberately fail-closed. Client-materialized transactions
/// are never configurable through this SDK surface and are always disabled in
/// the serialized KDF configuration.
final class ExternalExecutionStartupConfig {
  const ExternalExecutionStartupConfig({this.lifi = const LifiStartupConfig()});

  /// Li.Fi discovery and Case-A execution switches.
  final LifiStartupConfig lifi;

  /// Throws when this configuration could enable an unsafe transport.
  void validate() => lifi.validate();

  /// Encodes the strict KDF `external_execution` startup object.
  JsonMap toJson() {
    validate();
    return {
      'allow_client_materialized_transaction': false,
      'client_materialized_evm_targets': <String, dynamic>{},
      'lifi': lifi.toJson(),
    };
  }
}

/// Startup switches and transport selection for KDF's Li.Fi integration.
final class LifiStartupConfig {
  const LifiStartupConfig({
    this.enabled = false,
    this.caseAEnabled = false,
    this.transport = const LifiTransport.disabled(),
    this.allowDirectNonProduction = false,
  });

  /// Enables Li.Fi-backed external execution inside KDF.
  final bool enabled;

  /// Enables KDF-owned Case-A discovery, quote, prepare, and execution.
  final bool caseAEnabled;

  /// Selects the fixed direct origin or the Gleec proxy boundary.
  final LifiTransport transport;

  /// Explicit non-production override for direct Li.Fi transport.
  ///
  /// This value is validated by the SDK and is intentionally never serialized
  /// to KDF. Production callers must use [LifiTransport.gleecProxy].
  final bool allowDirectNonProduction;

  /// Throws when the switches or selected transport are not fail-closed.
  void validate() {
    if (caseAEnabled && !enabled) {
      throw StateError(
        'Li.Fi Case-A execution requires Li.Fi external execution to be '
        'enabled.',
      );
    }
    transport.validate(
      enabled: enabled,
      allowDirectNonProduction: allowDirectNonProduction,
    );
  }

  JsonMap toJson() {
    validate();
    return {
      'enabled': enabled,
      'case_a_enabled': caseAEnabled,
      'integrator': 'gleec-kdf',
      'transport': transport.toJson(),
    };
  }
}

/// The only Li.Fi transports accepted by the SDK startup boundary.
sealed class LifiTransport {
  const LifiTransport();

  /// Disables all Li.Fi network transport, including reconciliation.
  ///
  /// This is the fail-closed default for builds that have not supplied the
  /// production proxy boundary. It cannot be combined with an enabled Li.Fi
  /// startup configuration.
  const factory LifiTransport.disabled() = _DisabledLifiTransport;

  /// Uses Li.Fi's fixed direct origin.
  ///
  /// A direct configuration is rejected unless the caller also sets
  /// [LifiStartupConfig.allowDirectNonProduction], even when new execution is
  /// disabled. There is no proxy fallback.
  const factory LifiTransport.direct() = _DirectLifiTransport;

  /// Uses a fixed Gleec proxy base URL ending in the exact `/lifi/v1` path.
  const factory LifiTransport.gleecProxy(String baseUrl) =
      _GleecProxyLifiTransport;

  JsonMap toJson();

  void validate({
    required bool enabled,
    required bool allowDirectNonProduction,
  });
}

/// Direct fixed-origin transport, restricted to explicit non-production use.
final class _DirectLifiTransport extends LifiTransport {
  const _DirectLifiTransport();

  @override
  JsonMap toJson() => const {'transport_type': 'direct'};

  @override
  void validate({
    required bool enabled,
    required bool allowDirectNonProduction,
  }) {
    if (!allowDirectNonProduction) {
      throw StateError(
        'Direct Li.Fi transport requires an explicit non-production override, '
        'including while new execution is disabled.',
      );
    }
  }
}

/// Inert transport used until a trusted proxy (or explicit non-production
/// direct override) is configured.
final class _DisabledLifiTransport extends LifiTransport {
  const _DisabledLifiTransport();

  @override
  JsonMap toJson() => const {'transport_type': 'disabled'};

  @override
  void validate({
    required bool enabled,
    required bool allowDirectNonProduction,
  }) {
    if (enabled) {
      throw StateError(
        'Li.Fi external execution requires an explicit usable transport.',
      );
    }
  }
}

/// Gleec's fixed Li.Fi proxy transport.
final class _GleecProxyLifiTransport extends LifiTransport {
  const _GleecProxyLifiTransport(this.baseUrl);

  /// Absolute HTTPS proxy URL with the exact `/lifi/v1` path.
  final String baseUrl;

  @override
  JsonMap toJson() {
    _validatedUri();
    return {'transport_type': 'gleec_proxy', 'base_url': baseUrl};
  }

  @override
  void validate({
    required bool enabled,
    required bool allowDirectNonProduction,
  }) {
    _validatedUri();
  }

  Uri _validatedUri() {
    final uri = Uri.tryParse(baseUrl);
    final isValid =
        uri != null &&
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.path == '/lifi/v1' &&
        !uri.hasQuery &&
        !uri.hasFragment;
    if (!isValid) {
      throw FormatException(
        'Li.Fi proxy URL must be absolute HTTPS without credentials, query, '
        'or fragment and use the exact /lifi/v1 path.',
        baseUrl,
      );
    }
    return uri;
  }
}
