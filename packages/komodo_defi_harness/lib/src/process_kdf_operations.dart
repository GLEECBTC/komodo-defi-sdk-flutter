import 'dart:async';
import 'dart:io';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_harness/src/kdf_binary.dart';
import 'package:komodo_defi_harness/src/kdf_port.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonMap;

/// Runs the real KDF binary, by **delegating to the framework's own**
/// [KdfOperationsLocalExecutable].
///
/// This used to be a reimplementation. That was a mistake, and a specific one:
/// re-deriving the lifecycle contract got it subtly wrong. `version()` must
/// return null rather than throw when KDF is not up, because
/// `KomodoDefiFramework.isRunning` calls it as a fallback probe *before*
/// `kdfMain` has ever run (`komodo_defi_framework.dart`, `isRunning`). The
/// reimplementation let the `SocketException` escape, and the symptom was an
/// `AuthException: KDF RPC did not become ready within 15 seconds` pointing at
/// KDF instead of at the caller. The framework class already handles this, and
/// every other lifecycle subtlety, correctly.
///
/// What it adds on top - and the reason it is a wrapper rather than a direct
/// use - is only what a *measurement* harness needs and an app must not have:
///
/// - **Per-method RPC counting.** Amplification is the thing being measured.
/// - **Signal handlers that kill by pid.** A `flutter test` interrupted with
///   Ctrl-C tears the isolate down without running teardown, and a leaked
///   120 MB KDF holding the port breaks every later run on the machine.
/// - **`disable_p2p`.** Passed through the framework's `startParamsTransform`
///   seam. Correct for a harness that only activates coins and reads balances;
///   **never** correct for the app, which ships a DEX.
class ProcessKdfOperations implements IKdfOperations {
  ProcessKdfOperations({
    required this.binary,
    required this.config,
    required Directory workspace,
    void Function(String)? logCallback,
    Duration startupTimeout = const Duration(seconds: 60),
    this.disableP2p = true,
  }) : _workspace = workspace,
       _log = logCallback ?? ((_) {}) {
    _delegate = KdfOperationsLocalExecutable.create(
      logCallback: _log,
      config: config,
      startupTimeout: startupTimeout,
      // The binary's location is known exactly; the framework's finder searches
      // an app bundle layout that does not exist under `flutter test`.
      executableFinder: _FixedExecutableFinder(binary, _log),
      // Keep the coins file inside the harness workspace. The default reaches
      // `path_provider`, which a harness has already redirected at its own
      // temp dir - so the file would follow that redirection implicitly.
      temporaryDirectory: () async =>
          Directory('${_workspace.path}/kdf_tmp')..createSync(recursive: true),
      startParamsTransform: _applyP2pPolicy,
    );
  }

  final KdfBinary binary;

  /// Decides the RPC endpoint, including the port. Two harnesses on different
  /// ports no longer collide.
  final LocalConfig config;

  final Directory _workspace;
  final void Function(String) _log;

  /// See the class doc: correct here, never in the app.
  final bool disableP2p;

  late final KdfOperationsLocalExecutable _delegate;

  /// Turning p2p off is not a one-flag change: KDF prechecks the combination
  /// and refuses to start with
  /// `Cannot disable P2P while seed nodes are configured.` The seed nodes are
  /// meaningless without p2p anyway - they exist to bootstrap the very network
  /// being disabled - so they go together.
  ///
  /// The auth layer builds these params and always attaches seed nodes
  /// (`auth_service_kdf_extension.dart` fetches them via `SeedNodeService`),
  /// which is why this has to be corrected here rather than upstream.
  JsonMap _applyP2pPolicy(JsonMap params) {
    final adjusted = JsonMap.of(params);
    if (!disableP2p) return adjusted;
    return adjusted
      ..['disable_p2p'] = true
      ..remove('seednodes')
      ..remove('i_am_seed')
      ..remove('is_bootstrap_node');
  }

  /// The spawned pid, remembered from `kdfMain`.
  ///
  /// Deliberately not read from the delegate at teardown time. Its `kdfStop`
  /// awaits `exitCode` with a 10s timeout and then clears its own process
  /// handle **whether or not the process actually died**
  /// (`kdf_operations_local_executable.dart`, `kdfStop`), so by the time
  /// `dispose` runs there may be nothing left to kill - and the KDF is
  /// reparented to pid 1, still holding the fixed port, on a database
  /// directory the harness is about to delete. Every subsequent run then
  /// skipped with "port already in use".
  int? _spawnedPid;

  final Map<String, int> _callCounts = <String, int>{};
  StreamSubscription<ProcessSignal>? _sigint;
  StreamSubscription<ProcessSignal>? _sigterm;

  /// Per-method RPC counts, so amplification is measurable against a real KDF
  /// and not only against the replay script.
  Map<String, int> get invocationCounts => Map.unmodifiable(_callCounts);

  int callsTo(String method) => _callCounts[method] ?? 0;

  int get totalCalls => _callCounts.values.fold(0, (sum, n) => sum + n);

  @override
  String get operationsName => 'Harness Process';

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) =>
      _delegate.isAvailable(hostConfig);

  @override
  Future<void> validateSetup() => _delegate.validateSetup();

  @override
  Future<KdfStartupResult> kdfMain(JsonMap params, {int? logLevel}) async {
    // Fail before spawning rather than after. A 120 MB process that starts and
    // then exits because the port is taken reports that in a much less obvious
    // way than this does.
    await requireFreeKdfPort(port: config.port);
    final result = await _delegate.kdfMain(params, logLevel: logLevel);
    // After the delegate has a pid, not before.
    final pid = _delegate.processId;
    if (pid != null) {
      _spawnedPid = pid;
      _registerSignalHandlers(pid);
    }
    return result;
  }

  /// Kills by pid on SIGINT/SIGTERM.
  ///
  /// `dispose` is the graceful path and the framework class already implements
  /// it. This covers the case where teardown never runs at all.
  void _registerSignalHandlers(int pid) {
    void handle(ProcessSignal signal) {
      _log('Received $signal; killing KDF pid $pid');
      Process.killPid(pid, ProcessSignal.sigkill);
      exit(signal == ProcessSignal.sigint ? 130 : 143);
    }

    _sigint ??= ProcessSignal.sigint.watch().listen(handle);
    if (!Platform.isWindows) {
      _sigterm ??= ProcessSignal.sigterm.watch().listen(handle);
    }
  }

  @override
  Future<MainStatus> kdfMainStatus() => _delegate.kdfMainStatus();

  @override
  Future<bool> isRunning() => _delegate.isRunning();

  @override
  Future<String?> version() => _delegate.version();

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) {
    final method = request['method'] as String? ?? '<unknown>';
    _callCounts[method] = (_callCounts[method] ?? 0) + 1;
    return _delegate.mm2Rpc(request);
  }

  @override
  Future<StopStatus> kdfStop() => _delegate.kdfStop();

  @override
  void resetHttpClient() => _delegate.resetHttpClient();

  @override
  void dispose() {
    _sigint?.cancel();
    _sigterm?.cancel();
    _sigint = null;
    _sigterm = null;

    // The delegate's dispose is the graceful path; this guarantees the outcome
    // it only attempts, because a survivor holds the fixed port.
    _delegate.dispose();
    final pid = _spawnedPid;
    if (pid != null) {
      Process.killPid(pid, ProcessSignal.sigkill);
      _spawnedPid = null;
    }
  }
}

/// Returns the binary the harness already located, instead of searching an app
/// bundle layout that does not exist under `flutter test`.
class _FixedExecutableFinder extends KdfExecutableFinder {
  _FixedExecutableFinder(this._binary, void Function(String) log)
    : super(logCallback: log);

  final KdfBinary _binary;

  @override
  Future<File?> findExecutable({String executableName = 'kdf'}) async {
    logCallback('Using KDF binary at ${_binary.path}');
    return _binary.file;
  }
}
