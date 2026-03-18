import 'dart:async';
import 'dart:js_interop' as js_interop;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:http/http.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/js/js_error_utils.dart';
import 'package:komodo_defi_framework/src/js/js_interop_utils.dart';
import 'package:komodo_defi_framework/src/js/js_result_mappers.dart' as js_maps;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:mutex/mutex.dart';

const _kdfAsstsPath = 'kdf';
const _kdfJsBootstrapperPath = '$_kdfAsstsPath/res/kdflib_bootstrapper.js';

@js_interop.JS()
extension type _KdfBootstrapperModule._(js_interop.JSObject _)
    implements js_interop.JSObject {
  @js_interop.JS('default')
  external _KdfWasmBindings? get defaultBinding;

  external _KdfWasmBindings? get kdf;
}

@js_interop.JS()
extension type _KdfWasmBindings._(js_interop.JSObject _)
    implements js_interop.JSObject {
  external js_interop.JSBoolean get isInitialized;

  @js_interop.JS('init_wasm')
  external js_interop.JSPromise<js_interop.JSAny?>? initWasm();

  @js_interop.JS('mm2_main')
  external js_interop.JSAny? mm2Main(
    js_interop.JSAny? config,
    js_interop.JSFunction logHandler,
  );

  @js_interop.JS('mm2_main_status')
  external js_interop.JSNumber? mm2MainStatus();

  @js_interop.JS('mm2_stop')
  external js_interop.JSAny? mm2Stop();

  @js_interop.JS('mm2_rpc')
  external js_interop.JSPromise<js_interop.JSAny?>? mm2Rpc(
    js_interop.JSAny? request,
  );
}

@js_interop.JS()
extension type _KdfErrorWithCode._(js_interop.JSAny _)
    implements js_interop.JSAny {
  external js_interop.JSAny? get code;
}

IKdfOperations createLocalKdfOperations({
  required void Function(String)? logCallback,
  required LocalConfig config,
}) {
  return KdfOperationsWasm.create(
    logCallback: logCallback ?? print,
    config: config,
  );
}

class KdfOperationsWasm implements IKdfOperations {
  @override
  factory KdfOperationsWasm.create({
    required LocalConfig config,
    void Function(String)? logCallback,
  }) {
    return KdfOperationsWasm._(config).._logger = logCallback;
  }

  KdfOperationsWasm._(this._config);
  final _startupLock = Mutex();

  final LocalConfig _config;
  bool _libraryLoaded = false;
  _KdfWasmBindings? _kdfModule;
  void Function(String)? _logger;

  void _log(String message) => (_logger ?? print).call(message);

  void _debugLog(String message) {
    if (KdfLoggingConfig.debugLogging) {
      _log(message);
    }
  }

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    try {
      await _ensureLoaded();
      return _areFunctionsLoaded();
    } catch (_) {
      return false;
    }
  }

  bool get _isWasmInitialized {
    return _kdfModule?.isInitialized.toDart ?? false;
  }

  @override
  String operationsName = 'Local WASM JS Library';

  @override
  Future<bool> isRunning() async =>
      (await kdfMainStatus()) == MainStatus.rpcIsUp;

  @override
  Future<KdfStartupResult> kdfMain(JsonMap config, {int? logLevel}) async {
    return _startupLock.protect(() async {
      await _ensureLoaded();

      final jsConfig = {'conf': config, 'log_level': logLevel ?? 3}.jsify();

      try {
        return await _executeKdfMain(jsConfig);
      } on int catch (errorCode) {
        return KdfStartupResult.fromDefaultInt(errorCode);
      } on js_interop.JSAny catch (jsError) {
        return _handleStartupJsError(jsError);
      } catch (e) {
        _log('Unknown error starting KDF: [${e.runtimeType}] $e');

        if (e.toString().contains('error')) {
          throw ClientException('Failed to call KDF main: $e');
        }
        return KdfStartupResult.invalidParams;
      }
    });
  }

  Future<KdfStartupResult> _executeKdfMain(js_interop.JSAny? jsConfig) async {
    final jsMethod = _kdfModule!.mm2Main(
      jsConfig,
      (int level, String message) {
        _log('[$level] KDF: $message');
      }.toJS,
    );

    final result = await parseJsInteropMaybePromise<int>(jsMethod);
    _log('mm2_main called: $result');

    return KdfStartupResult.fromDefaultInt(result);
  }

  KdfStartupResult _handleStartupJsError(js_interop.JSAny jsError) {
    try {
      _debugLog('Handling JSAny error: [${jsError.runtimeType}] $jsError');

      final dynamic error = jsError.dartify();
      _debugLog('Dartified error type: ${error.runtimeType}, value: $error');

      final code = extractNumericCodeFromDartError(error);
      if (code != null) return KdfStartupResult.fromDefaultInt(code);

      final msg = extractMessageFromDartError(error);
      if (msg != null && messageIndicatesAlreadyRunning(msg)) {
        return KdfStartupResult.alreadyRunning;
      }

      final codeValue = _KdfErrorWithCode._(jsError).code?.dartify();
      final codeFromProperty = extractNumericCodeFromDartError(codeValue);
      if (codeFromProperty != null) {
        return KdfStartupResult.fromDefaultInt(codeFromProperty);
      }

      _log('Could not extract error code from JSAny: $error');
    } catch (conversionError) {
      _log('Error during JSAny conversion: $conversionError');
    }

    return KdfStartupResult.unknownError;
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    await _ensureLoaded();
    final status = _kdfModule!.mm2MainStatus()?.toDartInt;
    return MainStatus.fromDefaultInt(status!);
  }

  @override
  Future<StopStatus> kdfStop() async {
    await _ensureLoaded();

    try {
      // Call mm2_stop which may return a Promise or a direct value
      final jsAny = _kdfModule!.mm2Stop();
      final status = await parseJsInteropMaybePromise(
        jsAny,
        js_maps.mapJsStopResult,
      );

      // Ensure the node actually stops when we expect success or an
      // already-stopped result.
      if (status == StopStatus.ok || status == StopStatus.stoppingAlready) {
        await Future.doWhile(() async {
          final isStopped = (await kdfMainStatus()) == MainStatus.notRunning;
          if (!isStopped) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          return !isStopped;
        }).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('KDF stop timed out'),
        );
      }

      return status;
    } on int catch (e) {
      return StopStatus.fromDefaultInt(e);
    } catch (e) {
      _log('Error stopping KDF: $e');
      return StopStatus.errorStopping;
    }
  }

  @override
  Future<JsonMap> mm2Rpc(JsonMap request) async {
    await _ensureLoaded();

    final jsResponse = await _makeJsCall(request);
    final dartResponse = parseJsInteropJson(jsResponse);
    _validateResponse(dartResponse, request, jsResponse);

    return JsonMap.from(dartResponse);
  }

  /// Makes the JavaScript RPC call and returns the raw JS response
  Future<js_interop.JSAny?> _makeJsCall(JsonMap request) async {
    _debugLog('mm2Rpc request: ${request.censored()}');
    request['userpass'] = _config.rpcPassword;

    final jsRequest = request.jsify();
    final jsPromise = _kdfModule!.mm2Rpc(jsRequest);

    if (jsPromise == null || jsPromise.isUndefinedOrNull) {
      throw Exception(
        'mm2_rpc call returned null for method: ${request['method']}'
        '\nRequest: $request',
      );
    }

    final jsResponse = await jsPromise.toDart.then((value) => value).catchError(
      (Object error) {
        if (error.toString().contains('RethrownDartError')) {
          final errorMessage = error.toString().split('\n')[0];
          throw Exception(
            'JavaScript error for method ${request['method']}: $errorMessage'
            '\nRequest: $request',
          );
        }
        throw Exception(
          'Unknown error for method ${request['method']}: $error'
          '\nRequest: $request',
        );
      },
    );

    if (jsResponse == null || jsResponse.isUndefinedOrNull) {
      throw Exception(
        'mm2_rpc response was null for method: ${request['method']}'
        '\nRequest: $request',
      );
    }

    try {
      _debugLog('Raw JS response: ${jsResponse.dartify()}');
    } catch (e) {
      _debugLog('Raw JS response: $jsResponse (stringify failed: $e)');
    }
    return jsResponse;
  }

  /// Validates the response structure
  void _validateResponse(
    JsonMap dartResponse,
    JsonMap request,
    js_interop.JSAny? jsResponse,
  ) {
    // Legacy RPCs have no standard response format to validate
    if (request.valueOrNull<String>('mmrpc') != '2.0') return;

    if (!dartResponse.containsKey('result') &&
        !dartResponse.containsKey('error')) {
      throw Exception(
        'Invalid response format for method ${request['method']}\nResponse: '
        '$dartResponse\nRaw JS Response: $jsResponse\nRequest: $request',
      );
    }

    _debugLog('JS response validated: $dartResponse');
  }

  @override
  Future<void> validateSetup() async {
    await _ensureLoaded();
  }

  @override
  Future<String?> version() async {
    await _ensureLoaded();

    try {
      final response = await mm2Rpc({
        'userpass': _config.rpcPassword,
        'method': 'version',
      });

      return response['result'] as String?;
    } catch (e) {
      _log("Couldn't get KDF version: $e");
      return null;
    }
  }

  bool _areFunctionsLoaded() {
    return _kdfModule != null;
  }

  Future<void> _ensureLoaded() async {
    if (_libraryLoaded && _kdfModule != null) {
      return;
    }

    if (!_areFunctionsLoaded()) {
      await _injectLibrary();
    }

    if (!_isWasmInitialized) {
      await _initWasm();
    }

    _libraryLoaded = _areFunctionsLoaded()
        ? true
        : throw Exception('Failed to load KDF library: functions not found');
  }

  Future<void> _initWasm() async {
    final initWasmPromise = _kdfModule?.initWasm();
    if (initWasmPromise != null) {
      await initWasmPromise.toDart;
    }
  }

  Future<void> _injectLibrary() async {
    try {
      final module = _KdfBootstrapperModule._(
        await js_interop.importModule('./$_kdfJsBootstrapperPath'.toJS).toDart,
      );
      _kdfModule = module.kdf ?? module.defaultBinding;

      if (_kdfModule == null) {
        throw StateError('Imported KDF module did not expose a kdf binding.');
      }

      _log('KDF library loaded successfully');
    } catch (e) {
      final message =
          'Failed to load and import script $_kdfJsBootstrapperPath\n$e';
      _log(message);

      throw Exception(message);
    }
  }

  @override
  void resetHttpClient() {
    // No-op for WASM operations - HTTP client is managed by browser
    _log('resetHttpClient called on WASM operations (no-op)');
  }

  @override
  void dispose() {
    // Clean up any resources used by the WASM operations
    _kdfModule = null;
    _libraryLoaded = false;
  }
}

class KdfPluginWeb {
  static void registerWith(Registrar registrar) {
    MethodChannel(
      'komodo_defi_framework',
      const StandardMethodCodec(),
      registrar,
    ).setMethodCallHandler((call) async {
      // Handle method calls here if needed.
    });

    registrar.registerMessageHandler();
  }
}
