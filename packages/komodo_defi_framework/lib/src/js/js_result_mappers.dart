import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:logging/logging.dart';

final _logger = Logger('JsResultMappers');

/// Maps the various possible JS return shapes from `mm2_stop` into [StopStatus].
///
/// Accepts:
/// - `null` (treated as OK for backward-compatibility with legacy behavior)
/// - Numeric codes (int/num)
/// - String responses like "success", "ok", "already_stopped", or a stringified
///   integer code
/// - Objects/Maps that may contain `error`, `result`, or `code` fields
StopStatus mapJsStopResult(dynamic result) {
  if (result == null) return StopStatus.ok;

  if (result is int) return StopStatus.fromDefaultInt(result);
  if (result is num) return StopStatus.fromDefaultInt(result.toInt());

  if (result is String) {
    final normalized = result.trim().toLowerCase();
    if (normalized == 'success' || normalized == 'ok') {
      return StopStatus.ok;
    }
    if (normalized == 'already_stopped' || normalized.contains('already')) {
      return StopStatus.stoppingAlready;
    }
    final maybeCode = int.tryParse(result);
    if (maybeCode != null) return StopStatus.fromDefaultInt(maybeCode);
    return StopStatus.ok;
  }

  if (result is Map) {
    final map = result;
    if (map.containsKey('error') && map['error'] != null) {
      return StopStatus.errorStopping;
    }
    final inner = map['result'];
    if (inner is String) return mapJsStopResult(inner);
    if (inner is num) return StopStatus.fromDefaultInt(inner.toInt());

    final code = map['code'];
    if (code is num) return StopStatus.fromDefaultInt(code.toInt());

    // Log unexpected map structure for debugging
    _logger.fine(
      'Unexpected map structure in stop result, defaulting to ok: $map',
    );
    return StopStatus.ok;
  }

  _logger.fine(
    'Unrecognized stop result type ${result.runtimeType}, defaulting to ok',
  );
  return StopStatus.ok;
}
