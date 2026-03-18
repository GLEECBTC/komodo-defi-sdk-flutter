// lib/src/rpc_methods/base_method_namespace.dart

import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

abstract class BaseRpcMethodNamespace {
  const BaseRpcMethodNamespace(this._client);

  final ApiClient? _client;

  String? get rpcPass => null;

  Future<T> execute<T extends BaseResponse>(
    BaseRequest<T, Exception> request,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'ApiClient is not set. Use this method through an ApiClient instance.',
      );
    }
    return client.post(request);
  }
}
