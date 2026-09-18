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

// Exported so a test harness can drive the real binary through the framework's
// own implementation instead of reimplementing its lifecycle. See
// `komodo_defi_harness/lib/src/process_kdf_operations.dart`.
export 'src/native/kdf_executable_finder.dart' show KdfExecutableFinder;
export 'src/operations/kdf_operations_interface.dart';
export 'src/operations/kdf_operations_local_executable.dart'
    show KdfOperationsLocalExecutable;

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
      kdfOperations: kdfOperations,
      // client: KdfApiClient(this, rpcPassword: hostConfig.rpcPassword),
    );
  }
  KomodoDefiFramework._({
    required IKdfHostConfig hostConfig,
    void Function(String)? externalLogger,
    IKdfOperations? kdfOperations,
    // required KdfApiClient? client,
  }) : _hostConfig = hostConfig {
    _kdfOperations =
        kdfOperations ??
        createKdfOperations(hostConfig: hostConfig, logCallback: _log);

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
      (message) {
        try {
          logCallback(message);
        } catch (_) {
          if (kDebugMode) print('KDF diagnostic callback failed');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) print('KDF diagnostic stream failed');
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
    final safeMessage = DiagnosticSanitizer.sanitizeMessage(message);
    if (safeMessage != null && !_logStream.isClosed) {
      _logStream.add(safeMessage);
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
    _log('KDF version probe started');
    try {
      final version = await _kdfOperations.version().timeout(
        _versionProbeTimeout,
      );
      stopwatch.stop();
      _log('KDF version probe completed in ${stopwatch.elapsedMilliseconds}ms');
      return version;
    } catch (e) {
      stopwatch.stop();
      _log('KDF version probe failed in ${stopwatch.elapsedMilliseconds}ms');
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

      _log('KDF health check passed');
      return true;
    } catch (e) {
      _log('KDF health check failed');
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
    final method = request['method'];
    final stopwatch = Stopwatch()..start();
    try {
      final response = (await _kdfOperations.mm2Rpc(
        request..setIfAbsentOrEmpty('userpass', _hostConfig.rpcPassword),
      )).ensureJson();
      final summary = DiagnosticSanitizer.rpcSummary(
        method: method,
        success: !response.containsKey('error'),
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      if (enableDebugLogging) _logger.info(summary);
      if (KdfLoggingConfig.verboseLogging) _log(summary);
      return response;
    } catch (error) {
      final summary = DiagnosticSanitizer.rpcSummary(
        method: method,
        success: false,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      if (enableDebugLogging) _logger.warning(summary);
      if (KdfLoggingConfig.verboseLogging) _log(summary);

      // Preserve transport recovery without sending exception text to any sink.
      // This platform-independent check predates the diagnostic boundary.
      final errorString = error.toString().toLowerCase();
      if (errorString.contains('socketexception') &&
          (errorString.contains('broken pipe') ||
              errorString.contains('errno = 32') ||
              errorString.contains('connection reset') ||
              errorString.contains('errno = 54') ||
              errorString.contains('operation timed out') ||
              errorString.contains('errno = 60') ||
              errorString.contains('connection refused') ||
              errorString.contains('errno = 61'))) {
        resetHttpClient();
      }
      rethrow;
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
    await _streamingService?.dispose();
    _streamingService = null;

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
