import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_exception.dart';
import 'package:komodo_defi_framework/src/native/komodo_defi_framework_bindings_generated.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_response_body.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show RpcDispatchGuard;
import 'package:path/path.dart' as path;

IKdfOperations createLocalKdfOperations({
  required void Function(String) logCallback,
  required LocalConfig config,
}) {
  try {
    return KdfOperationsNativeLibrary.create(
      logCallback: logCallback,
      config: config,
    );
  } catch (_) {
    // The executable transport places startup parameters in process arguments.
    // Never silently move production credentials to that transport when a
    // native library is missing or incompatible.
    throw KdfException(
      'The bundled wallet engine could not be loaded. '
      'Reinstall or update the app.',
      type: KdfExceptionType.configurationError,
    );
  }
}

class KdfOperationsNativeLibrary implements IKdfOperations {
  KdfOperationsNativeLibrary._(
    this._bindings,
    this._logCallback,
    this._config,
    this._log,
  );
  factory KdfOperationsNativeLibrary.create({
    required void Function(String)? logCallback,
    required LocalConfig config,
  }) {
    final log = logCallback ?? print;
    // Resolve the library before allocating a callback that keeps its isolate
    // alive. A missing bundled library must fail without leaking that callback.
    final bindings = KomodoDefiFrameworkBindings(_library);
    final nativeLogCallback = ffi.NativeCallable<LogCallbackFunction>.listener(
      (ffi.Pointer<Utf8> messagePtr) => _logNativeLogMessage(messagePtr, log),
    );

    return KdfOperationsNativeLibrary._(
      bindings,
      nativeLogCallback,
      config,
      log,
    );
  }

  /// Native free-form diagnostics have no stable privacy schema. Do not decode
  /// or forward their contents, including malformed UTF-8 and fallback bytes.
  static void _logNativeLogMessage(
    ffi.Pointer<Utf8> messagePtr,
    void Function(String) log,
  ) {
    if (!KdfLoggingConfig.verboseLogging) return;
    try {
      log('KDF native diagnostic event received');
    } catch (_) {
      if (kDebugMode) print('KDF diagnostic callback failed');
    }
  }

  void Function(String) _log;
  final KomodoDefiFrameworkBindings _bindings;
  final ffi.NativeCallable<LogCallbackFunction> _logCallback;
  LocalConfig _config;

  @override
  String operationsName = 'Local Native Library';

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    // Check if the native dynamic library is available on the device.
    try {
      final dylib = _library;
      assert(
        dylib.providesSymbol('mm2_main'),
        'Symbol mm2_main not found in library',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    final startParamsPtr = startParams
        .toJsonString()
        .toNativeUtf8()
        .cast<Utf8>();
    final startParamsBytes = startParamsPtr.length + 1;
    // TODO: Implement log level

    final timer = Stopwatch()..start();
    final result =
        await compute(
          _kdfMainIsolate,
          _KdfMainParams(
            startParamsPtr.address,
            _logCallback.nativeFunction.address,
          ),
        ).whenComplete(() {
          // mm2_main consumed this owned startup allocation before returning.
          // This clears our native copy; it cannot erase Dart strings or KDF's
          // own live signing material.
          startParamsPtr
              .cast<ffi.Uint8>()
              .asTypedList(startParamsBytes)
              .fillRange(0, startParamsBytes, 0);
          calloc.free(startParamsPtr);
        });

    if (kDebugMode) _log('KDF started in ${timer.elapsedMilliseconds}ms');

    // Wait for RPC to be fully up instead of just a fixed delay
    // This is a workaround for the race condition where KDF is started but
    // the RPC server is not yet ready to accept requests.
    bool isRpcReady = false;
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_kdfMainStatus() == MainStatus.rpcIsUp) {
        isRpcReady = true;
        if (kDebugMode) {
          _log('RPC server ready after ${timer.elapsedMilliseconds}ms');
        }
        break;
      }
    }

    if (!isRpcReady && kDebugMode) {
      _log(
        'Warning: RPC server not ready after ${timer.elapsedMilliseconds}ms',
      );
    }

    if (kDebugMode) {
      _log('KDF started with result: $result');
      _log('Status after starting KDF: ${_kdfMainStatus()}');
    }

    return KdfStartupResult.fromDefaultInt(result);
  }

  // Since KDF main status is sync in this implementation, we can use it
  // internally to check if KDF is running..

  MainStatus _kdfMainStatus() {
    final status = _bindings.mm2_main_status();
    return MainStatus.fromDefaultInt(status);
  }

  @override
  Future<MainStatus> kdfMainStatus() => Future.sync(_kdfMainStatus);

  @override
  Future<StopStatus> kdfStop() async {
    final result = await compute(_kdfStopIsolate, null);
    return StopStatus.fromDefaultInt(result);
  }

  @override
  Future<bool> isRunning() =>
      Future.sync(() => _kdfMainStatus() == MainStatus.rpcIsUp);

  // Use 127.0.0.1 instead of localhost to avoid DNS resolution issues on mobile
  // platforms, especially after app backgrounding. See:
  // https://github.com/GLEECBTC/gleec-wallet/issues/3213
  /// Derived from the host config rather than pinned to 127.0.0.1:7783, so a
  /// second instance on another port reaches its own KDF.
  Uri get _url => _config.rpcUrl;
  Client _client = Client();

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    if (KdfLoggingConfig.debugLogging) {
      _log('KDF native RPC request dispatched');
    }

    request['userpass'] = _config.rpcPassword;
    final method = request['method'];
    if (method is String) RpcDispatchGuard.ensureCurrent(method);
    final response = await _client.post(
      _url,
      body: json.encode(request),
      headers: {'Content-Type': 'application/json'},
    );
    try {
      final decoded = json.decode(kdfResponseBody(response));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Never propagate FormatException.source because it contains the raw KDF
      // response body and may echo credentials or a signed relay payload.
    }
    return JsonRpcErrorResponse(
      code: response.statusCode,
      error: 'InvalidKdfResponse',
      message: 'KDF returned a malformed JSON response',
    );
  }

  @override
  Future<void> validateSetup() async {
    try {
      _bindings.mm2_main_status();
    } catch (e) {
      throw Exception('Failed to validate KDF setup: $e');
    }
  }

  @override
  Future<String?> version() async {
    try {
      final response = await mm2Rpc({'method': 'version'});
      return response['result'] as String?;
    } on Exception {
      _log('KDF version probe failed');
      return null;
    }
  }

  @override
  void resetHttpClient() {
    _log('Resetting HTTP client to drop stale keep-alive connections');
    _client.close();
    _client = Client();
  }

  static int _kdfMainIsolate(_KdfMainParams params) {
    final dylib = _library;
    assert(
      dylib.providesSymbol('mm2_main'),
      'Symbol mm2_main not found in library',
    );
    final bindings = KomodoDefiFrameworkBindings(dylib);
    final startParamsPtr = ffi.Pointer<Utf8>.fromAddress(
      params.startParamsPtrAddress,
    );
    final logCallback =
        ffi.Pointer<ffi.NativeFunction<LogCallbackFunction>>.fromAddress(
          params.logCallbackAddress,
        );
    return bindings.mm2_main(startParamsPtr, logCallback);
  }

  static int _kdfStopIsolate(_) {
    final dylib = _library;
    assert(
      dylib.providesSymbol('mm2_stop'),
      'Symbol mm2_stop not found in library',
    );
    final bindings = KomodoDefiFrameworkBindings(dylib);
    return bindings.mm2_stop();
  }

  @override
  void dispose() {
    _client.close();
    _logCallback.close(); // Ensure the NativeCallable is properly closed
  }
}

class _KdfMainParams {
  _KdfMainParams(this.startParamsPtrAddress, this.logCallbackAddress);
  final int startParamsPtrAddress;
  final int logCallbackAddress;
}

ffi.DynamicLibrary _loadLibrary() {
  final paths = _getLibraryPaths();
  for (final path in paths) {
    try {
      final lib = path == 'PROCESS'
          ? ffi.DynamicLibrary.process()
          : path == 'EXECUTABLE'
          ? ffi.DynamicLibrary.executable()
          : ffi.DynamicLibrary.open(path);
      if (lib.providesSymbol('mm2_main')) {
        if (kDebugMode) print('KDF native library loaded');
        return lib;
      }
    } catch (_) {
      // Continue to the next path if this one fails
    }
  }
  throw UnsupportedError('No valid library path found');
}

List<String> _getLibraryPaths() {
  if (Platform.isMacOS) {
    return macOsKdfLibraryPaths(Platform.resolvedExecutable);
  } else if (Platform.isIOS) {
    return ['libkdflib.dylib', 'PROCESS', 'EXECUTABLE'];
  } else if (Platform.isAndroid) {
    return [
      'libkomodo_defi_framework.so',
      'komodo_defi_framework.so',
      'komodo_defi_framework_plugin.so',
      'libkomodo_defi_framework_plugin.so',
      'libkdflib.so',
      'libkdflib_static.so',
      'EXECUTABLE',
      'PROCESS',
    ];
  } else if (Platform.isWindows) {
    return windowsKdfLibraryPaths(Platform.resolvedExecutable);
  } else if (Platform.isLinux) {
    return ['libkdflib.so', 'libkdflib_static.so'];
  } else {
    throw UnsupportedError('Unsupported platform or KDF library not found');
  }
}

/// The verified Windows archive bundles kdflib.dll next to the application.
/// Resolve it from that directory, never the working directory or DLL search
/// path. Incompatible/missing libraries fail without executable transport.
@visibleForTesting
List<String> windowsKdfLibraryPaths(String executablePath) => [
  path.windows.join(path.windows.dirname(executablePath), 'kdflib.dll'),
];

/// CocoaPods embeds the verified library in the application's Frameworks
/// directory. Process symbols support builds that explicitly link KDF in;
/// Mach-O executables from the old subprocess backend are not dylibs.
@visibleForTesting
List<String> macOsKdfLibraryPaths(String executablePath) => [
  path.posix.join(
    path.posix.dirname(path.posix.dirname(executablePath)),
    'Frameworks',
    'libkdflib.dylib',
  ),
  'PROCESS',
  'EXECUTABLE',
];

ffi.DynamicLibrary get _library => _loadLibrary();
