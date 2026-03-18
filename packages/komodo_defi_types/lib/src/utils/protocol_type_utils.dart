import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Resolves the canonical protocol type from a coin config.
///
/// Generated coin configs encode the concrete asset subtype in the top-level
/// `type` field (`TRX`, `TRC-20`, `AVX-20`, `BEP-20`, etc.).
CoinSubClass resolveProtocolSubClassFromConfig(JsonMap json) =>
    CoinSubClass.parse(json.value<String>('type'));
