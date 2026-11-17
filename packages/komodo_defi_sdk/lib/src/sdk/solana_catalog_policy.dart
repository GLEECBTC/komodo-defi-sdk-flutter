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

  // The same few spellings repeat across the whole catalog.
  static final _resolvedTypes = <String, CoinSubClass?>{};

  /// Also filters custom assets, which can be merged after source transforms.
  bool allows(Asset asset) => _allows({
    asset.protocol.subClass,
    ..._subClasses(asset.protocol.config),
  }, asset.protocol.config);

  /// Unknown programs and Token-2022 fixtures never become classic SPL assets.
  bool allowsConfig(JsonMap config) => _allows(_subClasses(config), config);

  /// Every protocol this entry may be handled as. Assets resolve the top-level
  /// `type` through the lenient [CoinSubClass.parse] ("Solana", "SOL", "SPL"),
  /// so it and the engine's `protocol.type` are resolved the same way here
  /// instead of being matched against one spelling.
  static Set<CoinSubClass> _subClasses(JsonMap config) {
    final protocol = config['protocol'];
    final subClasses = <CoinSubClass>{};
    for (final type in [
      config['type'],
      if (protocol is Map) protocol['type'],
    ]) {
      if (type is! String) continue;
      final subClass = _resolvedTypes.putIfAbsent(
        type,
        () => CoinSubClass.tryParse(type),
      );
      if (subClass != null) subClasses.add(subClass);
    }
    return subClasses;
  }

  bool _allows(Set<CoinSubClass> subClasses, JsonMap config) {
    if (!subClasses.any(solanaCoinSubClasses.contains)) return true;
    if (!capabilities.enabled) return false;
    if (!subClasses.contains(CoinSubClass.solanaToken)) return true;
    final protocol = config['protocol'];
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
