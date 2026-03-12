import 'dart:async';
import 'dart:convert';
import 'dart:io';

// this warning is pointless, since `web` and `js_interop` fail to compile on
// native platforms, so they aren't safe to import without conditional
// imports either (yet)
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';

class KdfHttpServerOperations implements IKdfOperations {
  late HeadlessInAppWebView _webView;
  late HttpServer _server;
  bool _isInitialized = false;
  final void Function(String)? _logger;

  KdfHttpServerOperations(
    LocalConfig config, {
    void Function(String)? logCallback,
  }) : _logger = logCallback;

  @override
  String get operationsName => 'WASM HTTP Server Operations';

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller == null) {
      throw Exception('WebView controller is not available.');
    }

    final jsConfig = {'conf': startParams, 'log_level': logLevel ?? 3};

    try {
      // The mm2_main function now returns a Promise that resolves to a result code
      // or rejects with a structured error. We need to handle both cases.
      final resultStr = await controller.evaluateJavascript(
        source:
            '''
          (async function() {
            try {
              const result = await kdf.mm2_main(${jsonEncode(jsConfig)});
              return { success: true, code: result };
            } catch (error) {
              return { 
                success: false, 
                code: error.code || 1,
                message: error.message || String(error) 
              };
            }
          })();
        ''',
      );

      final resultMap = jsonDecode(resultStr.toString());
      _logger?.call('kdfMain result: $resultMap');

      if (resultMap['success'] == true) {
        final code = resultMap['code'] as int;
        return KdfStartupResult.fromDefaultInt(code);
      } else {
        _logger?.call(
          'Error starting KDF: ${resultMap['message']} (code: ${resultMap['code']})',
        );
        return KdfStartupResult.fromDefaultInt(resultMap['code'] as int);
      }
    } catch (e) {
      _logger?.call('Error starting KDF: $e');
      // return KdfStartupResult.initError;
      throw Exception('Error starting KDF: $e');
    }
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller == null) {
      throw Exception('WebView controller is not available.');
    }

    final status = await controller.evaluateJavascript(
      source: 'kdf.mm2_main_status();',
    );
    return MainStatus.fromDefaultInt(int.parse(status.toString()));
  }

  @override
  Future<StopStatus> kdfStop() async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller == null) {
      throw Exception('WebView controller is not available.');
    }

    try {
      final resultStr = await controller.evaluateJavascript(
        source: '''
          (async function() {
            try {
              const result = await kdf.mm2_stop();
              return { success: true, code: result };
            } catch (error) {
              return { 
                success: false, 
                code: error.code || 2,
                message: error.message || String(error) 
              };
            }
          })();
        ''',
      );

      final resultMap = jsonDecode(resultStr.toString());
      _logger?.call('kdfStop result: $resultMap');

      if (resultMap['success'] == true) {
        final code = resultMap['code'] as int;
        return StopStatus.fromDefaultInt(code);
      } else {
        _logger?.call(
          'Error stopping KDF: ${resultMap['message']} (code: ${resultMap['code']})',
        );
        return StopStatus.fromDefaultInt(resultMap['code'] as int);
      }
    } catch (e) {
      _logger?.call('Error stopping KDF: $e');
      return StopStatus.errorStopping;
    }
  }

  @override
  Future<bool> isRunning() async {
    final status = await kdfMainStatus();
    return status == MainStatus.rpcIsUp;
  }

  @override
  Future<String?> version() async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller == null) {
      throw Exception('WebView controller is not available.');
    }

    final version = await controller.evaluateJavascript(
      source: 'kdf.version();',
    );
    return version?.toString();
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller == null) {
      throw Exception('WebView controller is not available.');
    }

    try {
      final responseStr = await controller.evaluateJavascript(
        source:
            '''
          (async function() {
            try {
              const result = await kdf.mm2_rpc(${jsonEncode(request)});
              return JSON.stringify(result);
            } catch (error) {
              return JSON.stringify({
                error: error.message || String(error)
              });
            }
          })();
        ''',
      );

      final response = jsonDecode(responseStr.toString());
      if (response is Map && response.containsKey('error')) {
        throw Exception('RPC error: ${response['error']}');
      }
      return response;
    } catch (e) {
      _logger?.call('Error calling mm2Rpc: $e');
      throw Exception('Error calling mm2Rpc: $e');
    }
  }

  @override
  Future<void> validateSetup() async {
    await _ensureWebViewInitialized();
    final controller = _webView.webViewController;
    if (controller != null) {
      await controller.evaluateJavascript(source: 'kdf.validateSetup();');
    } else {
      throw Exception('WebView controller is not available.');
    }
  }

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    try {
      await _ensureWebViewInitialized();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void resetHttpClient() {}

  Future<void> _ensureWebViewInitialized() async {
    if (_isInitialized) return;

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: null),
      onWebViewCreated: (controller) async {
        await _injectLibrary(controller);
      },
    );

    await _webView.run();
    _isInitialized = true;
    await _startProxyServer();
  }

  Future<void> _injectLibrary(InAppWebViewController controller) async {
    try {
      // Load the JS file from assets
      String jsCode = await rootBundle.loadString(
        'kdf/res/kdflib_bootstrapper.js',
      );
      await controller.evaluateJavascript(source: jsCode);

      _logger?.call('KDF library injected successfully');
    } catch (e) {
      _logger?.call('Failed to inject the KDF library: $e');
      throw Exception('Failed to inject the KDF library: $e');
    }
  }

  Future<void> _startProxyServer() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
    final handler = proxyHandler(Uri.parse('http://localhost:8080'));

    shelf_io.serve(handler, 'localhost', 8080);
    _logger?.call('HTTP server running at http://localhost:8080');
  }

  @override
  void dispose() {
    _webView.dispose();
    _server.close();
  }
}
