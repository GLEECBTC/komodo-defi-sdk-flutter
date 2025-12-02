import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/native/komodo_defi_framework_bindings_generated.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_local_executable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

IKdfOperations createLocalKdfOperations({
  required void Function(String) logCallback,
  required LocalConfig config,
}) {
  try {
    return KdfOperationsNativeLibrary.create(
      logCallback: logCallback,
      config: config,
    );
  } catch (e) {
    final executable = KdfOperationsLocalExecutable.create(
      logCallback: logCallback,
      config: config,
    );

    return executable;
  }
}

class KdfOperationsNativeLibrary implements IKdfOperations {
  KdfOperationsNativeLibrary._(
    this._bindings,
    this._logCallback,
    this._config,
    this._log,
  );
  @override
  factory KdfOperationsNativeLibrary.create({
    required void Function(String)? logCallback,
    required LocalConfig config,
  }) {
    final log = logCallback ?? print;
    final nativeLogCallback = ffi.NativeCallable<LogCallbackFunction>.listener(
      (ffi.Pointer<Utf8> messagePtr) => _logNativeLogMessage(messagePtr, log),
    );

    return KdfOperationsNativeLibrary._(
      KomodoDefiFrameworkBindings(_library),
      nativeLogCallback,
      config,
      log,
    );
  }

  /// Logs a native log message, or the raw bytes if parsing fails.
  /// Default method uses the package:ffi [Utf8] class to decode the message.
  /// If decoding fails, it tries to parse the message manually, or the raw
  /// bytes if parsing fails.
  static void _logNativeLogMessage(
    ffi.Pointer<Utf8> messagePtr,
    void Function(String) log,
  ) {
    try {
      final message = messagePtr.toDartString();
      _safeLog(message, log);
    } catch (e) {
      // Message decoding failed, try manual parsing
      final unsignedLength = _safeGetLength(messagePtr);
      _safeLog('Failed to decode log message ($unsignedLength bytes): $e', log);

      final manuallyParsedMessage = _tryParseNativeLogMessage(messagePtr, log);
      if (manuallyParsedMessage.isNotEmpty) {
        _safeLog(manuallyParsedMessage, log);
      }
    }
  }

  /// Safely gets the length of a pointer, returning -1 if it fails
  static int _safeGetLength(ffi.Pointer<Utf8> messagePtr) {
    try {
      return messagePtr.length;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get message length: $e');
      }
      return -1;
    }
  }

  /// Safely invokes the log callback with fallback to debug print
  static void _safeLog(String message, void Function(String) log) {
    try {
      log(message);
    } catch (e, stackTrace) {
      // Log callback failed - use debug print as fallback
      if (kDebugMode) {
        print('Log callback failed for message: $message');
        print('Error: $e');
        print('Stack trace: $stackTrace');
      }
    }
  }

  /// Tries to parse the native log message manually, or the raw bytes if
  /// parsing fails, by finding the null terminator (0x00) or invalid UTF-8
  /// byte (0xFF). This is a workaround for the fact that KDF terminating on
  /// exceptions can leave the log message in an invalid state.
  static String _tryParseNativeLogMessage(
    ffi.Pointer<Utf8> messagePtr,
    void Function(String) log,
  ) {
    try {
      // Calculate string length by finding the null terminator
      // (0x00) or invalid UTF-8 byte (0xFF). 0xFF encountered on iOS.
      var length = 0;
      final messagePtrAsInt = messagePtr.cast<ffi.Uint8>();
      while (messagePtrAsInt[length] != 0 && messagePtrAsInt[length] != 255) {
        length++;

        // prevent overflows & infinite loops with a reasonable limit
        if (length >= 32767) {
          _safeLog('Received log message longer than 32767 bytes.', log);
          return '';
        }
      }

      if (length == 0) {
        _safeLog('Received empty log message.', log);
        return '';
      }

      // print the raw bytes if the message is not valid UTF-8 to prevent
      // flutter devtools from crashing.
      final bytes = messagePtrAsInt.asTypedList(length);
      if (!_isValidUtf8(bytes)) {
        _safeLog('Received invalid UTF-8 log message.', log);
        final hexString = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        _safeLog('Raw bytes: $hexString', log);
        return '';
      }

      return utf8.decode(bytes);
    } catch (e) {
      _safeLog('Failed to decode log message: $e', log);
    }

    return '';
  }

  static bool _isValidUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } catch (_) {
      return false;
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
    // TODO: Implement log level

    final timer = Stopwatch()..start();
    final result = await compute(
      _kdfMainIsolate,
      _KdfMainParams(
        startParamsPtr.address,
        _logCallback.nativeFunction.address,
      ),
    ).whenComplete(() => calloc.free(startParamsPtr));

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
  final Uri _url = Uri.parse('http://127.0.0.1:7783');
  Client _client = Client();

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    if (KdfLoggingConfig.debugLogging) {
      _log('mm2 config: ${_config.toJson().censored()}');
      _log('mm2Rpc request (pre-process): ${request.censored()}');
    }

    request['userpass'] = _config.rpcPassword;
    final response = await _client.post(
      _url,
      body: json.encode(request),
      headers: {'Content-Type': 'application/json'},
    );
    return json.decode(response.body) as Map<String, dynamic>;
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
    } on Exception catch (e) {
      _log('Error getting KDF version: $e');
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
        if (kDebugMode) print('Loaded library at path: $path');
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
    return ['kdf', 'mm2', 'libkdflib.dylib', 'PROCESS', 'EXECUTABLE'];
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
    // Temporary solution to resolve the isssue where Rust libraries built for
    // Windows will crash for devices using Nvidia GPUs. When no libraries are
    // found, the SDK will attempt to use the KDF executable if present.
    return [];
  } else if (Platform.isLinux) {
    return ['libkdflib.so', 'libkdflib_static.so'];
  } else {
    throw UnsupportedError('Unsupported platform or KDF library not found');
  }
}

ffi.DynamicLibrary get _library => _loadLibrary();
