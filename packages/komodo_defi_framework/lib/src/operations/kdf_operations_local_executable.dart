import 'dart:async';
import 'dart:io';

import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_exception.dart';
import 'package:komodo_defi_framework/src/native/kdf_executable_finder.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class KdfOperationsLocalExecutable implements IKdfOperations {
  KdfOperationsLocalExecutable._(
    this._logCallback,
    this._kdfRemote, {
    required Future<Directory> Function() temporaryDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
    KdfExecutableFinder? executableFinder,
    this.executableName = 'kdf',
    JsonMap Function(JsonMap params)? startParamsTransform,
  }) : _startupTimeout = startupTimeout,
       _temporaryDirectory = temporaryDirectory,
       _startParamsTransform = startParamsTransform,
       _executableFinder =
           executableFinder ?? KdfExecutableFinder(logCallback: _logCallback);

  /// Creates operations that spawn the KDF executable.
  ///
  /// [config] now decides the RPC endpoint via `LocalConfig.rpcUrl`, so a
  /// second instance on another port is a matter of constructing a second
  /// config. This used to be a `static final Uri _url` pinned to
  /// `127.0.0.1:7783`, which made the port unreachable from outside the class.
  ///
  /// The remaining parameters exist so a test harness can drive this class
  /// instead of reimplementing it:
  ///
  /// - [executableFinder] was previously only settable through the private
  ///   constructor, so a caller that knew exactly where the binary was had no
  ///   way to say so.
  /// - [temporaryDirectory] replaces a direct `getTemporaryDirectory()` call.
  ///   That reached `path_provider`, i.e. a platform channel, which under
  ///   `flutter test` resolves through whatever mock is installed - so the
  ///   coins file silently followed a harness's own redirection.
  /// - [startParamsTransform] is the one seam for adjusting startup JSON that
  ///   the caller does not otherwise control (the auth layer builds it). Used
  ///   by the harness to set `disable_p2p`; **never** use it for that in the
  ///   app, which ships a DEX.
  factory KdfOperationsLocalExecutable.create({
    required void Function(String) logCallback,
    required LocalConfig config,
    Duration startupTimeout = const Duration(seconds: 30),
    String executableName = 'kdf',
    KdfExecutableFinder? executableFinder,
    Future<Directory> Function()? temporaryDirectory,
    JsonMap Function(JsonMap params)? startParamsTransform,
  }) {
    return KdfOperationsLocalExecutable._(
      logCallback,
      KdfOperationsRemote.create(
        logCallback: logCallback,
        rpcUrl: config.rpcUrl,
        userpass: config.rpcPassword,
      ),
      startupTimeout: startupTimeout,
      executableName: executableName,
      executableFinder: executableFinder,
      temporaryDirectory: temporaryDirectory ?? getTemporaryDirectory,
      startParamsTransform: startParamsTransform,
    );
  }

  final KdfOperationsRemote _kdfRemote;
  final Duration _startupTimeout;
  final void Function(String) _logCallback;
  final KdfExecutableFinder _executableFinder;
  final String executableName;
  final Future<Directory> Function() _temporaryDirectory;
  final JsonMap Function(JsonMap params)? _startParamsTransform;

  /// The spawned process, or null when KDF is not running.
  ///
  /// Exposed so a caller that needs to guarantee the process dies - a test
  /// harness registering signal handlers, for instance - can kill it by pid
  /// rather than duplicating the whole class to get at it.
  int? get processId => _process?.pid;

  // Use nullable fields instead of late, for the process and listeners,
  // because it is not guaranteed that they will be initialized before
  // they are used. E.g. if the process fails to start, or during the
  // cleanup process.
  Process? _process;
  StreamSubscription<List<int>>? stdoutSub;
  StreamSubscription<List<int>>? stderrSub;

  @override
  String get operationsName => 'Local Executable';

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    try {
      return await _executableFinder.findExecutable(
            executableName: executableName,
          ) !=
          null;
    } catch (e) {
      _logCallback('Error checking availability: $e');
      return false;
    }
  }

  Future<Process> _startKdf(JsonMap params) async {
    final executablePath = (await _executableFinder.findExecutable(
      executableName: executableName,
    ))?.absolute.path;
    if (executablePath == null) {
      throw KdfException(
        'KDF executable not found in any of the expected locations. '
        'Please ensure KDF is properly installed or included in your bundle.',
        type: KdfExceptionType.executableNotFound,
      );
    }

    // specifically needed on linux, which currently resets the file permissions
    // on every build.
    await _tryGrantExecutablePermissions(executablePath);

    if (!params.containsKey('coins')) {
      throw ArgumentError.value(
        params['coins'],
        'params',
        'Missing coins list.',
      );
    }

    Directory? coinsTempDir;
    try {
      final coinsList = params.value<List<JsonMap>>('coins');
      var sensitiveArgs = JsonMap.of(params)..remove('coins');
      final transform = _startParamsTransform;
      if (transform != null) sensitiveArgs = transform(sensitiveArgs);

      // Store the coins list in a temp file to avoid command line argument and
      // environment variable value size limits (varies from 4-128 KB).
      // Pass the config directly to the executable as an argument.
      final tempDir = await _temporaryDirectory();
      coinsTempDir = await tempDir.createTemp('mm_coins_');
      final coinsConfigFile = File(p.join(coinsTempDir.path, 'kdf_coins.json'));
      await coinsConfigFile.writeAsString(
        coinsList.toJsonString(),
        flush: true,
      );

      final environment = Map<String, String>.of(Platform.environment)
        ..['MM_COINS_PATH'] = coinsConfigFile.path;

      final newProcess = await Process.start(executablePath, [
        sensitiveArgs.toJsonString(),
      ], environment: environment);

      _logCallback('Launched executable: $executablePath');
      _attachProcessListeners(newProcess, coinsTempDir);

      return newProcess;
    } catch (e, stackTrace) {
      // Clean up the temporary directory if an error occurs. Exceptions can
      // be thrown before process listeners are attached, so ensure that the
      // dangling resources are cleaned up.
      await coinsTempDir?.delete(recursive: true).catchError((Object error) {
        _logCallback('Failed to delete temporary directory: $error');
        return Directory('');
      });
      if (e is KdfException) {
        rethrow;
      }
      throw KdfException(
        'Failed to start KDF: $e',
        type: KdfExceptionType.startupFailed,
        stackTrace: stackTrace,
      );
    }
  }

  /// check if the executable has executable permissions on linux/macos
  /// if not, run chmod +x on it
  Future<void> _tryGrantExecutablePermissions(String executablePath) async {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['+x', executablePath]);
      if (result.exitCode != 0) {
        throw KdfException(
          'Failed to make executable executable: ${result.stderr}',
          type: KdfExceptionType.permissionError,
          stackTrace: StackTrace.current,
        );
      }
    }
  }

  void _attachProcessListeners(Process newProcess, Directory tempDir) {
    stdoutSub = newProcess.stdout.listen((event) {
      _logCallback('[INFO]: ${String.fromCharCodes(event)}');
    });

    stderrSub = newProcess.stderr.listen((event) {
      _logCallback('[ERROR]: ${String.fromCharCodes(event)}');
    });

    newProcess.exitCode
        .then((exitCode) async => _cleanUpOnProcessExit(exitCode, tempDir))
        .ignore();
  }

  Future<void> _cleanUpOnProcessExit(int exitCode, Directory tempDir) async {
    try {
      _logCallback('KDF process exited with code: $exitCode');
      await stdoutSub?.cancel();
      await stderrSub?.cancel();

      await tempDir.delete(recursive: true);
      _logCallback('Temporary directory deleted successfully.');
    } catch (error) {
      _logCallback('Failed to delete temporary directory: $error');
    } finally {
      _process = null;
    }
  }

  @override
  Future<KdfStartupResult> kdfMain(JsonMap params, {int? logLevel}) async {
    if (_process != null && _process!.pid != 0) {
      return KdfStartupResult.alreadyRunning;
    }

    final coinsCount = params.valueOrNull<List<dynamic>>('coins')?.length;
    _logCallback(
      'Starting KDF with parameters: ${{...params, 'coins': '{{OMITTED $coinsCount ITEMS}}', 'log_level': logLevel ?? 3}.censored().toJsonString()}',
    );

    try {
      _process = await _startKdf(params);

      final timer = Stopwatch()..start();

      int? exitCode;
      unawaited(_process?.exitCode.then((code) => exitCode = code));

      while (timer.elapsed < _startupTimeout) {
        if (await isRunning()) {
          break;
        }

        if (exitCode != null) {
          return KdfStartupResult.tryFromDefaultInt(exitCode!);
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (await isRunning()) {
        return KdfStartupResult.ok;
      }

      return KdfStartupResult.spawnError;
    } catch (e) {
      _logCallback('Error starting KDF: $e');
      if (e is ArgumentError) {
        return KdfStartupResult.invalidParams;
      }
      return KdfStartupResult.initError;
    }
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    if (_process != null && _process!.pid > 0 && await _kdfRemote.isRunning()) {
      return MainStatus.rpcIsUp;
    }
    return MainStatus.notRunning;
  }

  @override
  Future<StopStatus> kdfStop() async {
    var stopStatus = StopStatus.ok;
    try {
      stopStatus = await _kdfRemote.kdfStop().catchError(
        (_) => StopStatus.errorStopping,
      );

      if (_process == null || _process?.pid == 0) {
        _logCallback('Process is not running, skipping shutdown.');
        return StopStatus.notRunning;
      }

      await Future.wait([
        stdoutSub?.cancel() ?? Future<void>.value(),
        stderrSub?.cancel() ?? Future<void>.value(),
      ]);

      if (_process != null && _process!.pid != 0) {
        await _process?.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _logCallback('KDF Process did not terminate in time.');
            stopStatus = StopStatus.errorStopping;
            return -1; // not used
          },
        );
      }

      _process = null;
      _logCallback('KDF process cleanup complete');
    } catch (e, stack) {
      _logCallback('Critical error during KDF cleanup: $e\n$stack');
    }

    return stopStatus;
  }

  @override
  Future<bool> isRunning() async {
    return (await kdfMainStatus()) == MainStatus.rpcIsUp;
  }

  @override
  Future<String?> version() => _kdfRemote.version();

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) =>
      _kdfRemote.mm2Rpc(request);

  @override
  Future<void> validateSetup() async {
    if (_process == null) {
      throw KdfException(
        'KDF executable is not running. Please start it first.',
        type: KdfExceptionType.notRunning,
      );
    }
  }

  @override
  void resetHttpClient() {
    // Delegate to remote operations
    _kdfRemote.resetHttpClient();
  }

  @override
  void dispose() {
    // Cancel and clean up subscriptions
    stdoutSub?.cancel().ignore();
    stdoutSub = null;
    stderrSub?.cancel().ignore();
    stderrSub = null;

    // Gracefully stop the process if running
    final capturedProcess = _process;
    if (capturedProcess != null) {
      _kdfRemote.kdfStop().timeout(const Duration(seconds: 3)).ignore();
      unawaited(_gracefulProcessShutdown(capturedProcess));
    }

    // Clean up remote resources
    _kdfRemote.dispose();
  }

  Future<void> _gracefulProcessShutdown(Process capturedProcess) async {
    try {
      await capturedProcess.exitCode
          .timeout(const Duration(seconds: 5))
          .catchError((_) {
            capturedProcess.kill();
            return -1; // Return an int to match Future<int>
          });
    } finally {
      // Only set _process = null if it still equals the captured instance
      if (_process == capturedProcess) {
        _process = null;
      }
    }
  }
}
