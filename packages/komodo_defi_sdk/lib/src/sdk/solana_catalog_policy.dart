import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Applies verified engine capabilities to the transient public catalog view.
/// Persisted source configurations remain unchanged for subsequent builds.
class SolanaCatalogPolicy implements CoinConfigTransform {
  /// Creates a catalog policy for one immutable SDK configuration.
  const SolanaCatalogPolicy(this.capabilities);

  /// Capabilities verified by the SDK host.
  final SolanaCapabilities capabilities;

  /// Also filters custom assets, which can be merged after source transforms.
  bool allows(Asset asset) => allowsConfig(asset.protocol.config);

  /// Unknown programs and Token-2022 fixtures never become classic SPL assets.
  bool allowsConfig(JsonMap config) {
    final protocol = config['protocol'];
    final type = protocol is Map ? protocol['type'] : config['type'];
    if (type != 'SOLANA' && type != 'SOLANATOKEN') return true;
    if (!capabilities.enabled) return false;
    if (type == 'SOLANA') return true;
    final data = protocol is Map ? protocol['protocol_data'] : null;
    final program = data is Map ? data['program_id'] : null;
    return program == SolanaTokenProtocol.classicTokenProgramId ||
        (program == SolanaTokenProtocol.token2022ProgramId &&
            capabilities.token2022Enabled);
  }

  @override
  bool needsTransform(JsonMap config) => !allowsConfig(config);

  @override
  JsonMap transform(JsonMap config) =>
      allowsConfig(config) ? JsonMap.of(config) : {...config, 'excluded': true};
}
