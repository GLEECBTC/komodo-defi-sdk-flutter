import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonMap;

/// An [IKdfOperations] backed by a [KdfScript] instead of a real KDF.
///
/// `KomodoDefiFramework.executeRpc` funnels every RPC through `mm2Rpc`, so this
/// single seam replaces the entire backend while leaving the SDK's own
/// orchestration - auth, activation, pubkeys, balances - completely real. That
/// is what makes it useful for measuring: the numbers it produces are the
/// SDK's own overhead with backend latency held at zero (or at a latency the
/// script chooses), rather than a blend of the two.
class ReplayKdfOperations implements IKdfOperations {
  ReplayKdfOperations(this.script, {this.rpcLatency = Duration.zero});

  final KdfScript script;

  /// Injected per-RPC delay. Zero by default so timings isolate SDK overhead;
  /// set it to model a saturated single-threaded KDF.
  final Duration rpcLatency;

  bool _running = false;

  /// Every request seen, for assertions about volume and ordering.
  final List<Map<String, dynamic>> requests = [];

  @override
  String get operationsName => 'Replay';

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    _running = true;
    startParams_ = Map<String, dynamic>.from(startParams);
    script.onKdfStart?.call(startParams_);
    return KdfStartupResult.ok;
  }

  /// The parameters KDF was last started with.
  ///
  /// Exposed because `enable_hd` lives here, which is the only observable
  /// difference between an HD and an iguana sign-in at the KDF boundary.
  Map<String, dynamic> startParams_ = const {};

  @override
  Future<MainStatus> kdfMainStatus() async =>
      _running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    _running = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<String?> version() async => 'harness-replay';

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() {
    _running = false;
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    requests.add(Map<String, dynamic>.from(request));

    if (rpcLatency > Duration.zero) {
      await Future<void>.delayed(rpcLatency);
    }

    final response = script.respondTo(request);
    if (response == null) {
      // Loud by design. A silent default would let an unscripted method look
      // like a legitimate empty result, and the SDK would then fail somewhere
      // far away from the actual gap in the script.
      final method = request['method'];
      throw StateError(
        'KdfScript has no response for "$method". Add one with '
        'script.reply("$method", {...}) or script.hang("$method").',
      );
    }
    return response;
  }
}
