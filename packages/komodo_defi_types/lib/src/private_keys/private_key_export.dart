import 'package:komodo_defi_types/src/assets/asset_id.dart';
import 'package:komodo_defi_types/src/private_keys/private_key.dart';

/// The scope actually covered by an export, independently of success.
enum PrivateKeyExportCoverageKind {
  offlineHdRange,
  offlineAccount,
  legacyWallet,
}

class PrivateKeyExportCoverage {
  const PrivateKeyExportCoverage({
    required this.kind,
    this.accountIndex,
    this.startIndex,
    this.endIndex,
    this.chain,
    this.derivationPath,
  });

  final PrivateKeyExportCoverageKind kind;
  final int? accountIndex;
  final int? startIndex;
  final int? endIndex;
  final String? chain;
  final String? derivationPath;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (accountIndex != null) 'account_index': accountIndex,
    if (startIndex != null) 'start_index': startIndex,
    if (endIndex != null) 'end_index': endIndex,
    if (chain != null) 'chain': chain,
    if (derivationPath != null) 'derivation_path': derivationPath,
  };

  @override
  String toString() => 'PrivateKeyExportCoverage(${kind.name})';
}

/// Stable reasons suitable for presentation; never carries an RPC payload.
enum PrivateKeyExportFailure {
  unsupportedProtocol,
  assetUnavailable,
  invalidResponse,
  rpcFailed,
}

class PrivateKeyExportOutcome {
  PrivateKeyExportOutcome.success({
    required this.assetId,
    required List<PrivateKey> keys,
    required PrivateKeyExportCoverage coverage,
  }) : keys = List.unmodifiable(keys),
       coverage = coverage,
       failure = null;

  const PrivateKeyExportOutcome.unavailable({
    required this.assetId,
    required this.failure,
  }) : keys = const [],
       coverage = null;

  final AssetId assetId;

  final List<PrivateKey> keys;
  final PrivateKeyExportCoverage? coverage;
  final PrivateKeyExportFailure? failure;
  bool get isSuccess => failure == null && keys.isNotEmpty;

  /// Intentional recovery-file serialization. Do not use for diagnostics.
  Map<String, dynamic> toJson() => {
    'asset_id': assetId.toJson(),
    if (coverage != null) 'coverage': coverage!.toJson(),
    if (failure != null) 'unavailable_reason': failure!.name,
    'keys': keys.map((key) => key.toJson()).toList(),
  };

  @override
  String toString() => 'PrivateKeyExportOutcome(redacted)';
}

class PrivateKeyExportResult {
  PrivateKeyExportResult({required List<PrivateKeyExportOutcome> outcomes})
    : outcomes = List.unmodifiable(outcomes);

  final List<PrivateKeyExportOutcome> outcomes;
  bool get isComplete => outcomes.every((outcome) => outcome.isSuccess);
  bool get hasKeys => outcomes.any((outcome) => outcome.isSuccess);
  Map<AssetId, List<PrivateKey>> get keysByAsset => Map.unmodifiable({
    for (final outcome in outcomes)
      if (outcome.isSuccess) outcome.assetId: outcome.keys,
  });

  /// Intentional recovery-file serialization. Do not use for diagnostics.
  Map<String, dynamic> toJson() => {
    'complete': isComplete,
    'assets': outcomes.map((outcome) => outcome.toJson()).toList(),
  };

  @override
  String toString() => 'PrivateKeyExportResult(redacted)';
}
