import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Selects assets and coverage without activating assets as a side effect.
class PrivateKeyExportRequest {
  /// Defaults to assets touched by this SDK session and the wallet mode.
  const PrivateKeyExportRequest({
    this.assets,
    this.mode,
    this.startIndex,
    this.endIndex,
    this.accountIndex,
  });

  /// Explicit targets, or activated/pending/failed assets when omitted.
  final List<AssetId>? assets;

  /// Defaults to the authenticated wallet derivation mode.
  final KeyExportMode? mode;

  /// Inclusive first external address, defaulting to zero.
  final int? startIndex;

  /// Inclusive last external address, defaulting to start plus ten.
  final int? endIndex;

  /// HD account, defaulting to zero for offline export.
  final int? accountIndex;

  /// Whether the caller explicitly selected HD address or account coverage.
  bool get hasExplicitRange =>
      startIndex != null || endIndex != null || accountIndex != null;

  @override
  String toString() => 'PrivateKeyExportRequest(redacted)';
}

/// Invalidates all results when authentication or verified identity changes.
class PrivateKeyExportSessionChangedException implements Exception {
  /// Contains no wallet details or secret material.
  const PrivateKeyExportSessionChangedException();

  @override
  String toString() => 'Private key export session changed';
}
