import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Deployment policy passed to KDF as `lifi_integrator` at startup.
///
/// KDF requests commission and validates the provider's reported allocation.
/// The recipient is registered with LI.FI; no API key belongs here.
class LifiIntegratorConfig extends Equatable {
  LifiIntegratorConfig({
    required this.name,
    required this.feeBps,
    required this.lifiFeeBps,
  }) {
    if (name.trim().isEmpty || name == 'lifi') {
      throw ArgumentError(
        'A nonblank LI.FI integrator name other than lifi is required',
      );
    }
    if (feeBps < 0 || lifiFeeBps < 0 || feeBps + lifiFeeBps >= 10000) {
      throw ArgumentError(
        'LI.FI fee rates must be nonnegative and total less than 10000 bps',
      );
    }
  }

  /// The integrator identifier registered with LI.FI.
  final String name;

  /// Requested integrator commission, in basis points.
  final int feeBps;

  /// Expected LI.FI share, in basis points, validated by KDF.
  final int lifiFeeBps;

  JsonMap toJson() => {
    'name': name,
    'fee_bps': feeBps,
    'lifi_fee_bps': lifiFeeBps,
  };

  @override
  List<Object?> get props => [name, feeBps, lifiFeeBps];
}
