import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class WithdrawMethodsNamespace extends BaseRpcMethodNamespace {
  WithdrawMethodsNamespace(super.client);

  /// Soon to be deprecated. After the bug with the task-based withdrawal API
  /// is fixed, this method will be deprecated in favor of the new task-based
  /// withdrawal API.
  Future<WithdrawStatusResponse> withdraw(WithdrawParameters params) {
    return execute(
      WithdrawRequest(
        rpcPass: rpcPass ?? '',
        coin: params.asset,
        to: params.toAddress,
        amount: params.amount,
        fee: params.fee,
        from: params.from,
        memo: params.memo,
        max: params.isMax ?? false,
        ibcSourceChannel: params.ibcSourceChannel,
      ),
    );
  }

  /// Convenience wrapper for SIA withdrawals with SIA-specific response parsing.
  ///
  /// Uses the v2 `withdraw` RPC but parses the result into [SiaWithdrawResponse],
  /// exposing the SIA `tx_json` payload that should later be passed to
  /// [sendRawTransactionSia].
  Future<SiaWithdrawResponse> withdrawSia({
    required String coin,
    required String to,
    Decimal? amount,
    FeeInfo? fee,
    WithdrawalSource? from,
    bool max = false,
  }) {
    return execute(
      SiaWithdrawRequest(
        rpcPass: rpcPass ?? '',
        coin: coin,
        to: to,
        amount: amount,
        fee: fee,
        from: from,
        max: max,
      ),
    );
  }

  /// Initialize a new withdrawal task
  // TODO: Consider refactoring to use individual parameters instead of a single
  // object for the request parameters for the sake of consistency with other
  // requests and since the objective for the RPC methods is to be as close to
  // the API as possible.
  Future<WithdrawInitResponse> init(WithdrawParameters params) {
    return execute(WithdrawInitRequest(rpcPass: rpcPass ?? '', params: params));
  }

  /// Get status of a withdrawal task
  Future<WithdrawStatusResponse> status(
    int taskId, {
    bool forgetIfFinished = true,
  }) {
    return execute(
      WithdrawStatusRequest(
        rpcPass: rpcPass ?? '',
        taskId: taskId,
        forgetIfFinished: forgetIfFinished,
      ),
    );
  }

  /// Cancel a withdrawal task
  Future<WithdrawCancelResponse> cancel(int taskId) {
    return execute(
      WithdrawCancelRequest(rpcPass: rpcPass ?? '', taskId: taskId),
    );
  }

  Future<SendRawTransactionResponse> sendRawTransaction({
    required String coin,
    String? txHex,
    JsonMap? txJson,
    WithdrawalSource? from,
  }) {
    return execute(
      SendRawTransactionLegacyRequest(
        rpcPass: rpcPass ?? '',
        coin: coin,
        txHex: txHex,
        txJson: txJson,
      ),
    );
  }

  /// SIA-specific `send_raw_transaction` using a `tx_json` payload.
  ///
  /// This should be used together with [withdrawSia], passing the
  /// [SiaWithdrawResponse.txJson] value as [txJson].
  Future<SendRawTransactionResponse> sendRawTransactionSia({
    required String coin,
    required JsonMap txJson,
  }) {
    return execute(
      SiaSendRawTransactionRequest(
        rpcPass: rpcPass ?? '',
        coin: coin,
        txJson: txJson,
      ),
    );
  }
}
