import 'dart:async';

import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/operations/electrum/native_wss_electrum_routing.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Whether native builds reach `WSS` Electrum servers through the loopback
/// bridge. Build with `--dart-define=KDF_ELECTRUM_WS_BRIDGE=false` to fall back
/// to the SSL servers alone.
const bool kElectrumWebSocketBridgeEnabled = bool.fromEnvironment(
  'KDF_ELECTRUM_WS_BRIDGE',
  defaultValue: true,
);

/// Adapts every request for a native KDF that cannot dial `WSS` Electrum
/// servers itself, by routing those entries through [NativeWssElectrumRouting].
final class ElectrumBridgingKdfOperations implements IKdfOperations {
  ElectrumBridgingKdfOperations(this._inner, {required this.routing});

  final IKdfOperations _inner;
  final NativeWssElectrumRouting routing;

  @override
  String get operationsName => _inner.operationsName;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async =>
      _inner.mm2Rpc(await routeWssElectrumServers(request, routing));

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) =>
      _inner.kdfMain(startParams, logLevel: logLevel);

  @override
  Future<MainStatus> kdfMainStatus() => _inner.kdfMainStatus();

  @override
  Future<StopStatus> kdfStop() => _inner.kdfStop();

  @override
  Future<bool> isRunning() => _inner.isRunning();

  @override
  Future<String?> version() => _inner.version();

  @override
  Future<void> validateSetup() => _inner.validateSetup();

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) =>
      _inner.isAvailable(hostConfig);

  @override
  void resetHttpClient() => _inner.resetHttpClient();

  @override
  void dispose() {
    unawaited(routing.close());
    _inner.dispose();
  }
}
