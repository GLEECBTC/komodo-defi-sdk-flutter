import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart'
    if (dart.library.io) 'package:komodo_defi_framework/src/operations/kdf_operations_native.dart'
    if (dart.library.js_interop) 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart'
    as local;

IKdfOperations createKdfOperations({
  required void Function(String)? logCallback,
  required IKdfHostConfig hostConfig,
}) {
  return _selectKdfImplementation(
    logCallback: logCallback,
    hostConfig: hostConfig,
  );
}

Future<IKdfOperations> createKdfOperationsAsync({
  required void Function(String)? logCallback,
  required IKdfHostConfig hostConfig,
}) async {
  final implementation = await _selectKdfImplementationAsync(
    logCallback: logCallback,
    hostConfig: hostConfig,
  );
  if (await implementation.isAvailable(hostConfig)) {
    return implementation;
  }
  throw ArgumentError(
    'No available KDF operations found for ${hostConfig.runtimeType}',
  );
}

IKdfOperations _selectKdfImplementation({
  required void Function(String)? logCallback,
  required IKdfHostConfig hostConfig,
}) {
  switch (hostConfig.runtimeType) {
    case LocalConfig:
      return local.createLocalKdfOperations(
        logCallback: logCallback ?? print,
        config: hostConfig as LocalConfig,
      );
    case RemoteConfig:
      return KdfOperationsRemote.create(
        logCallback: logCallback ?? print,
        rpcUrl: (hostConfig as RemoteConfig).rpcUrl,
        userpass: hostConfig.rpcPassword,
      );
    default:
      throw ArgumentError('Unsupported host type: ${hostConfig.runtimeType}');
  }
}

Future<IKdfOperations> _selectKdfImplementationAsync({
  required void Function(String)? logCallback,
  required IKdfHostConfig hostConfig,
}) async {
  switch (hostConfig.runtimeType) {
    case LocalConfig:
      return local.createLocalKdfOperations(
        logCallback: logCallback ?? print,
        config: hostConfig as LocalConfig,
      );

    case RemoteConfig:
      return KdfOperationsRemote.create(
        logCallback: logCallback ?? print,
        rpcUrl: Uri.parse(
          '${(hostConfig as RemoteConfig).https == true ? 'https' : 'http'}://${hostConfig.ipAddress}:${hostConfig.port}',
        ),
        userpass: hostConfig.rpcPassword,
      );

    // TOOD: Other implementations (AWS, DigitalOcean)

    default:
      throw ArgumentError('Unsupported host type: ${hostConfig.runtimeType}');
  }
}
