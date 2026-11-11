import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_response_body.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show RpcDispatchGuard;

class KdfOperationsRemote implements IKdfOperations {
  // TODO! Add wallet password and name or add the config object
  factory KdfOperationsRemote.create({
    required void Function(String) logCallback,
    // required String ipAddress,
    // required int port,
    required Uri rpcUrl,
    required String userpass,
    Duration stopTimeout = const Duration(seconds: 5),
  }) {
    return KdfOperationsRemote._(logCallback, rpcUrl, userpass, stopTimeout);
  }

  KdfOperationsRemote._(
    this._logCallback,
    this._rpcUrl,
    this._userpass,
    this._stopTimeout,
  );
  final void Function(String) _logCallback;
  final String _userpass;

  final Uri _rpcUrl;

  /// How long [kdfStop] waits for the engine to answer `stop`. A stop runs
  /// while the auth service holds the engine, so it must not wait for good.
  final Duration _stopTimeout;

  /// Clients of the requests still awaiting an answer.
  ///
  /// Each request keeps its own client, as `http.post` does, so connections
  /// are never reused. [resetHttpClient] closes them all.
  final Set<http.Client> _inFlight = {};

  Uri get _baseUrl => _safeRpcUrl(_rpcUrl);

  static const String _forwardProxy =
      'https://proxy-se-push.go-away-bugs.co.za/?target=';

  static const bool _proxyRequests = false;

  Uri _safeRpcUrl(Uri rpcUrl) {
    var url = rpcUrl;
    // If the scheme is not provided, default to http
    url = url.scheme.isEmpty ? url.replace(scheme: 'http') : url;

    // Normalize localhost to 127.0.0.1 to avoid DNS resolution issues on Android
    if (url.host == 'localhost') {
      return url.replace(host: '127.0.0.1');
    }
    if (url.host == '127.0.0.1') {
      return url;
    }

    // if (!kIsWeb) {
    //   return url;
    // }

    // NB: The code below is for a workaround to avoid CORS issues when
    // running in the browser. This is needed at least until the time when
    // the KDF releases the CORS failing OPTIONS preflight requests available
    // on `fix-allow-options-req` branch.
    // However, this may be needed long-term if we want to cater for users who
    // don't have CORS configured on their KDF servers.

    // If on the web, check if the cors preflight succeeds
    // TODO:

    // If the cors preflight fails, return a url that will be proxied by the
    // forward proxy 134.122.60.102
    // TODO:

    return Uri.parse('${_proxyRequests ? _forwardProxy : ''}$url');
  }

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    // Check if the remote server is reachable
    try {
      final uri = Uri.parse(
        'http://${(hostConfig as RemoteConfig).ipAddress}:${hostConfig.port}',
      );
      final response = await http.get(uri);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _log(String message) => _logCallback(message);

  @override
  String operationsName = 'Remote RPC Server';

  @override
  Future<bool> isRunning() async {
    return await kdfMainStatus() == MainStatus.rpcIsUp;
  }

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    const message =
        'KDF cannot be started using Remote client. '
        'Please start the KDF on the remote server manually.';
    _log(message);

    // return KdfStartupResult.invalidParams;
    throw UnimplementedError(message);
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    final versionResult = await version();
    return versionResult != null ? MainStatus.rpcIsUp : MainStatus.noRpc;
  }

  /// Asks the engine to stop. An engine that takes the request and never
  /// answers fails it after the stop timeout; the next transport reset aborts
  /// the request itself.
  @override
  Future<StopStatus> kdfStop() async {
    try {
      final stopResultResponse = await mm2Rpc({
        'method': 'stop',
      }).timeout(_stopTimeout);

      _log('KDF stop response received');

      return _parseStopResult(stopResultResponse);
    } on Exception {
      _log('KDF stop failed');
      return StopStatus.errorStopping;
    }
  }

  // Could be shared with other implementations?
  StopStatus _parseStopResult(dynamic stopResponse) {
    if (stopResponse['error'] != null) {
      return StopStatus.errorStopping;
    }

    switch (stopResponse['result']) {
      case 'already_stopped':
        return StopStatus.stoppingAlready;
      case 'success':
        return StopStatus.ok;
      default:
        final maybeResultCode = stopResponse is int?
            ? stopResponse
            : int.tryParse(stopResponse.toString());

        return maybeResultCode != null
            ? StopStatus.fromDefaultInt(maybeResultCode)
            : StopStatus.errorStopping;
    }
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    if (request['userpass'] == null) {
      request['userpass'] = _userpass;
    }

    if (KdfLoggingConfig.verboseLogging) {
      _logCallback('KDF remote RPC request dispatched');
    }

    late final http.Response response;

    final client = http.Client();
    _inFlight.add(client);
    try {
      if (request['method'] case final String method) {
        RpcDispatchGuard.ensureCurrent(method);
      }
      response = await client.post(_baseUrl, body: json.encode(request));
    } on http.ClientException {
      // ClientException can include a credential-bearing URL. Keep the public
      // failure stable and free of transport internals.
      return ConnectionError('Remote KDF request failed');
    } finally {
      _inFlight.remove(client);
      client.close();
    }

    final body = kdfResponseBody(response);

    if (response.statusCode != 200) {
      // KDF answers errors with a non-200 status: typed MMRPC 2.0 errors
      // (400-502) and legacy methods' `{"error": ...}` (404, 500). Callers
      // branch on the error_type or match the legacy text (`No swap with
      // uuid`), and the FFI and WASM transports already pass both through.
      // Anything else stays opaque.
      final kdfError = _kdfError(body);
      if (kdfError != null) return kdfError;
      return JsonRpcErrorResponse(
        code: response.statusCode,
        error: {
          'error': 'HTTP Error',
          'status': response.statusCode,
        }.toJsonString(),
        message: 'Remote KDF returned HTTP ${response.statusCode}',
      );
    }

    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Do not surface FormatException.source: it contains the upstream body.
    }
    return JsonRpcErrorResponse(
      code: response.statusCode,
      error: 'InvalidKdfResponse',
      message: 'Remote KDF returned a malformed JSON response',
    );
  }

  @override
  Future<void> validateSetup() async {
    final version = await this.version();
    if (version == null) {
      throw Exception('Failed to validate remote KDF setup');
    }
  }

  @override
  Future<String?> version() async {
    try {
      final response = await mm2Rpc({'method': 'version'});

      final maybeError = response.valueOrNull<String>('error');

      if (maybeError != null) {
        _log('Error getting remote KDF version');
        return null;
      }

      return response.valueOrNull<String?>('result');
    } on http.ClientException {
      return null;
    }
  }

  /// Aborts every request still awaiting an answer, including one still
  /// connecting, so none of them can reach an engine started afterwards.
  /// Each aborted request answers [ConnectionError].
  @override
  void resetHttpClient() {
    final aborted = _inFlight.toList();
    _inFlight.clear();
    for (final client in aborted) {
      client.close();
    }
    _log('Remote KDF transport reset');
  }

  @override
  void dispose() {
    // Requests in flight settle on their own. Aborting them here would also
    // abort the stop request the local executable sends while disposing.
  }

  /// Returns [body] decoded when it is one of KDF's error envelopes: a typed
  /// MMRPC 2.0 error, or a legacy method's `{"error": "..."}`.
  static Map<String, dynamic>? _kdfError(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final typed =
          decoded['mmrpc'] == '2.0' && decoded['error_type'] is String;
      final legacy = decoded.length == 1 && decoded['error'] is String;
      if (typed || legacy) return decoded;
    } catch (_) {
      // Not an envelope; handled as an opaque HTTP error.
    }
    return null;
  }
}
