import 'package:equatable/equatable.dart';

/// Capabilities of the selected KDF build, independent of coin metadata.
///
/// Keep defaults disabled until the corresponding engine and integration tests
/// have passed. A remote coin catalog must not enable unsupported operations.
class SolanaCapabilities extends Equatable {
  const SolanaCapabilities({
    this.enabled = false,
    this.splMaxEnabled = false,
    this.token2022Enabled = false,
    this.devnetTradingEnabled = false,
  });

  final bool enabled;
  final bool splMaxEnabled;
  final bool token2022Enabled;
  final bool devnetTradingEnabled;

  @override
  List<Object?> get props => [
    enabled,
    splMaxEnabled,
    token2022Enabled,
    devnetTradingEnabled,
  ];
}
