import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_startup_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_factory.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_service.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

export 'package:komodo_defi_framework/src/client/kdf_api_client.dart';
export 'package:komodo_defi_framework/src/config/event_streaming_config.dart';
export 'package:komodo_defi_framework/src/config/kdf_config.dart';
export 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
export 'package:komodo_defi_framework/src/config/kdf_startup_config.dart';
export 'package:komodo_defi_framework/src/services/seed_node_service.dart';
export 'package:komodo_defi_framework/src/streaming/event_streaming_service.dart';
export 'package:komodo_defi_framework/src/streaming/events/kdf_event.dart';

export 'src/operations/kdf_operations_interface.dart';

class KomodoDefiFramework implements ApiClient {
  static const Duration _versionProbeTimeout = Duration(seconds: 2);
  static const Duration _stopPollInterval = Duration(milliseconds: 250);
  static const Duration _stopSettleDelay = Duration(milliseconds: 250);

  factory KomodoDefiFramework.create({
    required IKdfHostConfig hostConfig,
    void Function(String)? externalLogger,
  }) {
    return KomodoDefiFramework._(
      hostConfig: hostConfig,
      externalLogger: externalLogger,
      // client: KdfApiClient(this, rpcPassword: hostConfig.rpcPassword),
    );
  }

  /// TODO: Test if this factory method works as expected.
  factory KomodoDefiFramework.createWithOperations({
    required IKdfHostConfig hostConfig,
    required IKdfOperations kdfOperations,
    void Function(String)? externalLogger,
  }) {
    return KomodoDefiFramework._(
      hostConfig: hostConfig,
      externalLogger: externalLogger,
      // client: KdfApiClient(this, rpcPassword: hostConfig.rpcPassword),
    ).._kdfOperations = kdfOperations;
  }
  KomodoDefiFramework._({
    required IKdfHostConfig hostConfig,
    void Function(String)? externalLogger,
    // required KdfApiClient? client,
  }) : _hostConfig = hostConfig {
    _kdfOperations = createKdfOperations(
      hostConfig: hostConfig,
      logCallback: _log,
    );

    if (externalLogger != null) {
      _initLogStream(externalLogger);
    }
  }

  /// Enable debug logging for RPC calls (method names, durations, success/failure)
  /// This can be controlled via app configuration
  static bool enableDebugLogging = true;

  final Logger _logger = Logger('KomodoDefiFramework');

  // late final ApiClient client;
  final IKdfHostConfig _hostConfig;

  ApiClient get client => this;

  Future<void> _initLogStream(LogCallback logCallback) async {
    if (_loggerSub != null) {
      await _loggerSub!.cancel();

      _loggerSub = null;
    }

    _loggerSub = _logStream.stream.listen(
      logCallback,
      onError: (Object error, StackTrace stackTrace) {
        // Log the error internally but don't propagate it to avoid crashing
        if (kDebugMode) {
          print('[KomodoDefiFramework] Error in external logger callback:');
          print('  Error: $error');
          print('  Stack trace:\n$stackTrace');
        }
      },
      cancelOnError: false, // Continue listening even if the callback throws
    );
  }

  StreamSubscription<String>? _loggerSub;

  // final IKdfHostConfig _hostConfig;
  late final IKdfOperations _kdfOperations;

  final StreamController<String> _logStream = StreamController.broadcast();

  Stream<String> get logStream => _logStream.stream;

  void _log(String message) {
    if (!_logStream.isClosed) {
      _logStream.add(message);
    }
  }

  // Streaming service (web: SharedWorker; native: SSE)
  // NOTE: SSE connection should be tied to authentication state.
  // Do NOT call initialize() automatically - let the application control when to connect.
  KdfEventStreamingService? _streamingService;
  KdfEventStreamingService get streaming {
    return _streamingService ??= KdfEventStreamingService(
      hostConfig: _hostConfig,
    );
  }

  //TODO! Figure out best way to handle overlap between startup and host
  //TODO! Handle common KDF operations startup log scanning here or in a
  //shared class. This is important to ensure consistent startup error handling
  //across different KDF operations implementations.
  Future<KdfStartupResult> startKdf(
    KdfStartupConfig startupConfig, {
    bool validateHostConfig = true,
  }) async {
    _log('Starting KDF main...');

    if (validateHostConfig) {
      _assertHostConfigMatchesStartupConfig(startupConfig, _hostConfig);
    }

    final startParams = startupConfig.encodeStartParams();
    final result = await _kdfOperations.kdfMain(startParams);
    _log('KDF main result: $result');
    return result;
  }

  Future<MainStatus> kdfMainStatus() async {
    final status = await _kdfOperations.kdfMainStatus();
    _log('KDF main status: $status');

    // Checking if KDF is running using `version` method covers the case
    // where implementations do not run as a singleton. E.g. `kdfMainStatus`
    // for `kdfOperationsLocalExecutable` will return `MainStatus.notRunning`
    // if that instance does not have a process running even if KDF is
    // running in another instance. Consider refactoring the architecture
    // to take this into account.
    if (status == MainStatus.notRunning) {
      final version = await _kdfOperations.version();
      if (version != null) {
        return MainStatus.rpcIsUp;
      }
    }

    return status;
  }

  Future<StopStatus> kdfStop() async {
    _log('Stopping KDF...');
    final result = await _kdfOperations.kdfStop();
    _log('KDF stop result: $result');

    // Drop any stale keep-alive socket before verifying shutdown. Otherwise,
    // the post-stop version() fallback can hang on Android while the native
    // thread is already tearing down.
    resetHttpClient();

    // Wait for native status to settle without probing RPC over HTTP.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(_stopPollInterval);
      final stillRunning = await isRunning(allowVersionFallback: false);
      if (!stillRunning) {
        await Future<void>.delayed(_stopSettleDelay);
        if (!await isRunning(allowVersionFallback: false)) {
          return result;
        }
      }
    }

    throw Exception('Error stopping KDF: KDF did not stop in time.');
  }

  Future<bool> isRunning({bool allowVersionFallback = true}) async {
    final nativeRunning = await _kdfOperations.isRunning();
    if (nativeRunning) {
      return true;
    }

    if (!allowVersionFallback) {
      _log('KDF is not running.');
      return false;
    }

    final running =
        await _kdfOperations.version().timeout(
          _versionProbeTimeout,
          onTimeout: () => null,
        ) !=
        null;
    if (!running) {
      _log('KDF is not running.');
    }
    return running;
  }

  Future<String?> version() async {
    final stopwatch = Stopwatch()..start();
    _log(
      'version(): Starting version RPC call via ${_kdfOperations.operationsName}',
    );
    try {
      final version = await _kdfOperations.version().timeout(
        _versionProbeTimeout,
      );
      stopwatch.stop();
      _log(
        'version(): Completed in ${stopwatch.elapsedMilliseconds}ms, result=$version',
      );
      return version;
    } catch (e) {
      stopwatch.stop();
      _log(
        'version(): Failed after ${stopwatch.elapsedMilliseconds}ms with error: $e',
      );
      rethrow;
    }
  }

  /// Checks if KDF is healthy and responsive by attempting a version RPC call.
  /// Returns true if KDF is running and responsive, false otherwise.
  /// This is useful for detecting when KDF has become unavailable, especially
  /// on mobile platforms after app backgrounding.
  ///
  /// IMPORTANT: This method ONLY relies on actual RPC verification (version() call)
  /// to avoid false positives where native status reports "running" but HTTP listener
  /// is not accepting connections (common after iOS backgrounding).
  Future<bool> isHealthy() async {
    try {
      // Only rely on actual RPC verification - don't trust native status alone
      final versionCheck = await version();
      if (versionCheck == null) {
        _log('KDF health check failed: version call returned null');
        return false;
      }

      _log('KDF health check passed: version=$versionCheck');
      return true;
    } catch (e) {
      _log('KDF health check failed with exception: $e');
      return false;
    }
  }

  /// Resets the HTTP client to drop stale keep-alive connections.
  /// This is useful after KDF has been killed and restarted to ensure
  /// we don't try to reuse dead connections.
  void resetHttpClient() {
    _log('Resetting HTTP client to drop stale connections');
    _kdfOperations.resetHttpClient();
  }

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    if (!enableDebugLogging) {
      final response = (await _kdfOperations.mm2Rpc(
        request..setIfAbsentOrEmpty('userpass', _hostConfig.rpcPassword),
      )).ensureJson();
      if (KdfLoggingConfig.verboseLogging) {
        _log('RPC response: ${response.toJsonString()}');
      }
      return response;
    }

    // Extract method name for logging
    final method = request['method'] as String?;
    final stopwatch = Stopwatch()..start();

    // Log activation parameters before the call
    if (method != null && _isActivationMethod(method)) {
      _logActivationParameters(method, request);
    }

    try {
      final response = (await _kdfOperations.mm2Rpc(
        request..setIfAbsentOrEmpty('userpass', _hostConfig.rpcPassword),
      )).ensureJson();
      stopwatch.stop();

      _logger.info(
        '[RPC] ${method ?? 'unknown'} completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Log electrum-related methods with more detail
      if (method != null && _isElectrumRelatedMethod(method)) {
        _logger.info(
          '[ELECTRUM] Method: $method, Duration: ${stopwatch.elapsedMilliseconds}ms',
        );
        _logElectrumConnectionInfo(method, response);
      }

      if (KdfLoggingConfig.verboseLogging) {
        _log('RPC response: ${response.toJsonString()}');
      }
      return response;
    } catch (e) {
      stopwatch.stop();

      // Detect transport-fatal SocketExceptions that indicate KDF is down/dying
      // errno 32 (EPIPE): Broken pipe - writing to socket whose peer closed
      // errno 54 (ECONNRESET): Connection reset by peer
      // errno 60 (ETIMEDOUT): Operation timed out
      // errno 61 (ECONNREFUSED): Connection refused - no listener on port
      final errorString = e.toString().toLowerCase();
      final isSocketException = errorString.contains('socketexception');
      final isFatalTransportError =
          isSocketException &&
          (errorString.contains('broken pipe') ||
              errorString.contains('errno = 32') ||
              errorString.contains('connection reset') ||
              errorString.contains('errno = 54') ||
              errorString.contains('operation timed out') ||
              errorString.contains('errno = 60') ||
              errorString.contains('connection refused') ||
              errorString.contains('errno = 61'));

      if (isFatalTransportError) {
        final errorType =
            errorString.contains('errno = 32') ||
                errorString.contains('broken pipe')
            ? 'EPIPE (32)'
            : errorString.contains('errno = 54') ||
                  errorString.contains('connection reset')
            ? 'ECONNRESET (54)'
            : errorString.contains('errno = 60') ||
                  errorString.contains('operation timed out')
            ? 'ETIMEDOUT (60)'
            : 'ECONNREFUSED (61)';
        _logger.severe(
          '[RPC] ${method ?? 'unknown'} failed: KDF transport error $errorType. '
          'Resetting HTTP client to drop stale connections.',
        );
        // Reset HTTP client immediately to drop stale keep-alive connections
        resetHttpClient();
      } else {
        _logger.warning(
          '[RPC] ${method ?? 'unknown'} failed after ${stopwatch.elapsedMilliseconds}ms: $e',
        );
      }
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

        // Log full activation params for detailed debugging
        _logger.fine('[ACTIVATION] Full params: $activationParams');
      }
    } catch (e) {
      // Silently ignore logging errors
      _logger.info('[ACTIVATION] Error logging parameters: $e');
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

  void _assertHostConfigMatchesStartupConfig(
    KdfStartupConfig startupConfig,
    IKdfHostConfig hostConfig,
  ) {
    if (startupConfig.rpcPassword != hostConfig.rpcPassword) {
      throw ArgumentError(
        'RPC password mismatch between startup and host configs.',
      );
    }

    if (hostConfig is RemoteConfig) {
      if (startupConfig.rpcIp != hostConfig.ipAddress) {
        throw ArgumentError(
          'RPC IP mismatch between startup and host configs.',
        );
      }

      if (startupConfig.rpcPort != hostConfig.port) {
        throw ArgumentError(
          'RPC port mismatch between startup and host configs.',
        );
      }
    }
  }

  /// Closes the log stream and cancels the logger subscription.
  ///
  /// NB! This does not stop the KDF operations or the KDF process.
  Future<void> dispose() async {
    // Cancel subscription first before closing the stream
    await _loggerSub?.cancel();
    _loggerSub = null;

    // Close the log stream
    if (!_logStream.isClosed) {
      await _logStream.close();
    }

    // Dispose of KDF operations to free native resources
    final operations = _kdfOperations;
    operations.dispose();
  }

  String get operationsName => _kdfOperations.operationsName;
}
