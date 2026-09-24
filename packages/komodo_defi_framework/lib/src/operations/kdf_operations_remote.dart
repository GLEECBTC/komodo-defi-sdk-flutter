import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class KdfOperationsRemote implements IKdfOperations {
  // TODO! Add wallet password and name or add the config object
  factory KdfOperationsRemote.create({
    required void Function(String) logCallback,
    // required String ipAddress,
    // required int port,
    required Uri rpcUrl,
    required String userpass,
  }) {
    return KdfOperationsRemote._(logCallback, rpcUrl, userpass);
  }

  KdfOperationsRemote._(this._logCallback, this._rpcUrl, this._userpass);
  final void Function(String) _logCallback;
  final String _userpass;

  final Uri _rpcUrl;

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

  @override
  Future<StopStatus> kdfStop() async {
    try {
      final stopResultResponse = await mm2Rpc({'method': 'stop'});

      _log('stopResultResponse: $stopResultResponse');

      return _parseStopResult(stopResultResponse);
    } on Exception catch (e) {
      _log('Error stopping KDF: $e');
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
      _logCallback('mm2Rpc request: ${json.encode(request.censored())}');
    }

    late final http.Response response;

    try {
      response = await http.post(_baseUrl, body: json.encode(request));
    } on http.ClientException {
      // ClientException can include a credential-bearing URL. Keep the public
      // failure stable and free of transport internals.
      return ConnectionError('Remote KDF request failed');
    }

    if (response.statusCode != 200) {
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
      final decoded = json.decode(response.body);
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

  @override
  void resetHttpClient() {
    // No-op for remote operations - HTTP client is managed by http package
    _log('resetHttpClient called on remote operations (no-op)');
  }

  @override
  void dispose() {
    // No-op for remote operations - HTTP client is managed externally
  }
}
