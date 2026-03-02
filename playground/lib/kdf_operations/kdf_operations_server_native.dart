import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class KdfHttpServerOperations implements IKdfOperations {
  KdfHttpServerOperations(LocalConfig _, {void Function(String)? logCallback});

  @override
  String get operationsName => 'Unsupported HTTP Server Operations';

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<StopStatus> kdfStop() async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<bool> isRunning() async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<String?> version() async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<void> validateSetup() async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    throw UnsupportedError('Unknown platforms are not supported');
  }

  @override
  void resetHttpClient() {}

  @override
  void dispose() {}
}
