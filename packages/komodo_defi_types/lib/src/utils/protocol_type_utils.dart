import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Resolves the canonical protocol type from a coin config.
///
/// Some configs, including TRON assets, use a legacy top-level `type` that
/// describes the token standard while the authoritative protocol lives under
/// `protocol.type`. Prefer the nested protocol type when present.
CoinSubClass resolveProtocolSubClassFromConfig(JsonMap json) {
  final protocolType = json.valueOrNull<String>('protocol', 'type');
  final typeValue = protocolType ?? json.value<String>('type');
  return CoinSubClass.parse(typeValue);
}
