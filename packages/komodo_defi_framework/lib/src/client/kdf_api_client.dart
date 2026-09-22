import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

class KdfApiClient implements ApiClient {
  KdfApiClient(this._rpcCallback);

  final JsonMap Function(JsonMap) _rpcCallback;
  final Logger _logger = Logger('KdfApiClient');

  /// Controls metadata diagnostics only. RPC bodies are never logged.
  static bool enableDebugLogging = true;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = _rpcCallback(request);
      if (enableDebugLogging) {
        _logger.info(
          DiagnosticSanitizer.rpcSummary(
            method: request['method'],
            success: !response.containsKey('error'),
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          ),
        );
      }
      return response;
    } catch (_) {
      if (enableDebugLogging) {
        _logger.warning(
          DiagnosticSanitizer.rpcSummary(
            method: request['method'],
            success: false,
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          ),
        );
      }
      rethrow;
    }
  }
}
