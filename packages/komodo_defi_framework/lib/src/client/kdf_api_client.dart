import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

class KdfApiClient implements ApiClient {
  KdfApiClient(
    this._rpcCallback,
    // this.
    /*{required String rpcPassword}*/
  ) {
    _logger = Logger('KdfApiClient');
  }

  final JsonMap Function(JsonMap) _rpcCallback;
  // final Future<StopStatus> Function() _stopCallback;

  // String? _rpcPassword;

  late final Logger _logger;

  /// Enable debug logging for RPC calls (method names, durations, success/failure)
  /// This can be controlled via app configuration
  static bool enableDebugLogging = true;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    // if (!await isInitialized()) {
    //   throw StateError('API client is not initialized');
    // }

    if (!enableDebugLogging) {
      return _rpcCallback(request);
    }

    // Extract method name for logging
    final method = request['method'] as String?;
    final isGasless = _isGaslessRequest(method, request);
    final stopwatch = Stopwatch()..start();

    // Log activation parameters before the call
    if (method != null && _isActivationMethod(method) && !isGasless) {
      _logActivationParameters(method, request);
    } else if (isGasless) {
      _logger.info('[RPC] GasFree request started');
    }

    try {
      final response = _rpcCallback(request);
      stopwatch.stop();

      _logger.info(
        '[RPC] ${method ?? 'unknown'} completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Log electrum-related methods with more detail
      if (method != null && _isElectrumRelatedMethod(method) && !isGasless) {
        _logger.info(
          '[ELECTRUM] Method: $method, Duration: ${stopwatch.elapsedMilliseconds}ms',
        );
        _logElectrumConnectionInfo(method, response);
      }

      return response;
    } catch (e) {
      stopwatch.stop();
      _logger.warning(
        '[RPC] ${isGasless ? 'GasFree' : method ?? 'unknown'} failed after '
        '${stopwatch.elapsedMilliseconds}ms',
      );
      rethrow;
    }
  }

  bool _isElectrumRelatedMethod(String method) {
    return method.contains('electrum') ||
        method.contains('enable') ||
        method.contains('utxo') ||
        method == 'get_enabled_coins' ||
        method == 'my_balance';
  }

  bool _isActivationMethod(String method) {
    return method.contains('enable') ||
        method.contains('task::enable') ||
        method.contains('task_enable');
  }

  bool _isGaslessRequest(String? method, JsonMap request) =>
      (method?.startsWith('gasless::') ?? false) ||
      _containsGaslessConfiguration(request);

  bool _containsGaslessConfiguration(Object? value) {
    if (value is Map) {
      if (value.containsKey('tron_gasless_provider') ||
          value['fee_method'] == 'gasless' ||
          value['relay_type'] == 'tron_gasfree') {
        return true;
      }
      return value.values.any(_containsGaslessConfiguration);
    }
    if (value is Iterable) {
      return value.any(_containsGaslessConfiguration);
    }
    return false;
  }

  void _logActivationParameters(String method, JsonMap request) {
    try {
      final params = request['params'] as Map<String, dynamic>?;
      if (params == null) return;

      final ticker = params['ticker'] as String?;
      final activationParams =
          params['activation_params'] as Map<String, dynamic>?;

      if (ticker != null) {
        _logger.info('[ACTIVATION] Enabling coin: $ticker');
      }

      if (activationParams != null) {
        // Log key activation parameters
        final mode = activationParams['mode'];
        final nodes = activationParams['nodes'];
        final servers = activationParams['servers'];
        final rpcUrls = activationParams['rpc_urls'];
        final tokensRequests = activationParams['erc20_tokens_requests'];
        final bchUrls = activationParams['bchd_urls'];

        final paramsSummary = <String, dynamic>{};

        if (mode != null) paramsSummary['mode'] = mode;
        if (nodes != null) {
          paramsSummary['nodes_count'] = (nodes as List).length;
        }
        if (servers != null) {
          paramsSummary['electrum_servers_count'] = (servers as List).length;
        }
        if (rpcUrls != null) {
          paramsSummary['rpc_urls_count'] = (rpcUrls as List).length;
        }
        if (tokensRequests != null) {
          paramsSummary['tokens_count'] = (tokensRequests as List).length;
        }
        if (bchUrls != null) {
          paramsSummary['bchd_urls_count'] = (bchUrls as List).length;
        }

        // Add other relevant fields
        if (activationParams['swap_contract_address'] != null) {
          paramsSummary['swap_contract'] =
              activationParams['swap_contract_address'];
        }
        if (activationParams['platform'] != null) {
          paramsSummary['platform'] = activationParams['platform'];
        }
        if (activationParams['contract_address'] != null) {
          paramsSummary['contract_address'] =
              activationParams['contract_address'];
        }

        _logger.info('[ACTIVATION] Parameters: $paramsSummary');

        // Never log full activation parameters: provider credentials, wallet
        // material, or other secrets may be nested in this object.
      }
    } catch (e) {
      // Silently ignore logging errors
      _logger.fine('[ACTIVATION] Parameter logging failed');
    }
  }

  void _logElectrumConnectionInfo(String method, JsonMap response) {
    try {
      // Log connection information from enable responses
      if (method.contains('enable') && response['result'] != null) {
        final result = response['result'] as Map<String, dynamic>?;
        if (result != null) {
          final address = result['address'] as String?;
          final balance = result['balance'] as String?;
          _logger.info(
            '[ELECTRUM] Coin enabled - Address: ${address ?? 'N/A'}, Balance: ${balance ?? 'N/A'}',
          );

          // Log server information if available
          if (result['servers'] != null) {
            final servers = result['servers'];
            _logger.info('[ELECTRUM] Connected servers: $servers');
          }
        }
      }

      // Log balance information
      if (method == 'my_balance' && response['result'] != null) {
        final result = response['result'] as Map<String, dynamic>?;
        if (result != null) {
          final coin = result['coin'] as String?;
          final balance = result['balance'] as String?;
          _logger.info(
            '[ELECTRUM] Balance query - Coin: ${coin ?? 'N/A'}, Balance: ${balance ?? 'N/A'}',
          );
        }
      }
    } catch (e) {
      // Silently ignore logging errors
    }
  }

  // Not sure if this belongs here
  // @override
  // Future<void> stop() async {
  //   final status = await _stopCallback();
  //   if (status != StopStatus.ok) {
  //     throw StateError('Failed to stop API client: $status');
  //   }
  // }

  // @override
  // Future<bool> isInitialized() {
  //   return _kdf.isRunning();
  // }
}
