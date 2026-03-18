import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

// Init Request
class GetNewAddressTaskInitRequest
    extends BaseRequest<NewTaskResponse, GeneralErrorResponse> {
  GetNewAddressTaskInitRequest({
    required super.rpcPass,
    required this.coin,
    this.accountId,
    this.chain,
    this.gapLimit,
  }) : super(method: 'task::get_new_address::init');

  final String coin;
  final int? accountId;
  final String? chain;
  final int? gapLimit;

  @override
  JsonMap toJson() {
    return {
      ...super.toJson(),
      'userpass': rpcPass,
      'method': method,
      'mmrpc': mmrpc,
      'params': {
        'coin': coin,
        if (accountId != null) 'account_id': accountId,
        if (chain != null) 'chain': chain,
        if (gapLimit != null) 'gap_limit': gapLimit,
      },
    };
  }

  @override
  NewTaskResponse parse(JsonMap json) => NewTaskResponse.parse(json);
}

// Status Request
class GetNewAddressTaskStatusRequest
    extends BaseRequest<GetNewAddressTaskStatusResponse, GeneralErrorResponse> {
  GetNewAddressTaskStatusRequest({
    required super.rpcPass,
    required this.taskId,
    this.forgetIfFinished = true,
  }) : super(method: 'task::get_new_address::status');

  final int taskId;
  final bool forgetIfFinished;

  @override
  JsonMap toJson() {
    return {
      ...super.toJson(),
      'userpass': rpcPass,
      'method': method,
      'mmrpc': mmrpc,
      'params': {'task_id': taskId, 'forget_if_finished': forgetIfFinished},
    };
  }

  @override
  GetNewAddressTaskStatusResponse parse(JsonMap json) =>
      GetNewAddressTaskStatusResponse.parse(json);
}

SyncStatusEnum? _statusFromTaskStatus(String status) {
  switch (status) {
    case 'Ok':
      return SyncStatusEnum.success;
    case 'InProgress':
      return SyncStatusEnum.inProgress;
    case 'Error':
      return SyncStatusEnum.error;
    default:
      return null;
  }
}

// Status Response
class GetNewAddressTaskStatusResponse extends BaseResponse {
  GetNewAddressTaskStatusResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
  });

  factory GetNewAddressTaskStatusResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final statusString = result.value<String>('status');
    final status = _statusFromTaskStatus(statusString);

    if (status == null) {
      throw FormatException(
        'Unrecognized task status: "$statusString". '
        'Expected one of: Ok, InProgress, Error',
      );
    }

    final detailsJson = result['details'];
    Object? description;
    NewAddressInfo? data;
    Exception? error;

    if (status == SyncStatusEnum.success) {
      data = NewAddressInfo.fromJson(
        (detailsJson as JsonMap).value<JsonMap>('new_address'),
      );
    } else if (status == SyncStatusEnum.error) {
      error = parseTaskErrorDetails(detailsJson);
    } else if (status == SyncStatusEnum.inProgress) {
      description = TaskDescriptionParserFactory.parseDescription(detailsJson);
    }

    return GetNewAddressTaskStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: status,
      details: ResponseDetails<NewAddressInfo, Exception, Object>(
        data: data,
        error: error,
        description: description,
      ),
    );
  }

  final SyncStatusEnum status;
  final ResponseDetails<NewAddressInfo, Exception, Object> details;

  @override
  JsonMap toJson() {
    return {
      'mmrpc': mmrpc,
      'result': {'status': status, 'details': details.toJson()},
    };
  }

  /// Convert this RPC response into a [NewAddressState].
  NewAddressState toNewAddressState(int taskId, String coinTicker) {
    switch (status) {
      case SyncStatusEnum.success:
        final addr = details.data!;
        // Get the balance for the specific coin, or use the first balance if not found
        final coinBalance = addr.getBalanceForCoin(coinTicker) ?? addr.balance;
        return NewAddressState(
          status: NewAddressStatus.completed,
          address: PubkeyInfo(
            address: addr.address,
            derivationPath: addr.derivationPath,
            chain: addr.chain,
            balance: coinBalance,
            coinTicker: coinTicker,
          ),
          taskId: taskId,
        );
      case SyncStatusEnum.error:
        return NewAddressState(
          status: NewAddressStatus.error,
          error: exceptionMessage(details.error) ?? 'Unknown error',
          taskId: taskId,
        );
      case SyncStatusEnum.inProgress:
        return NewAddressState.fromInProgressDescription(
          details.description,
          taskId,
        );
      case SyncStatusEnum.notStarted:
        return NewAddressState(
          status: NewAddressStatus.error,
          error: 'Task not started',
          taskId: taskId,
        );
    }
  }
}

// Cancel Request
class GetNewAddressTaskCancelRequest
    extends BaseRequest<GetNewAddressTaskCancelResponse, GeneralErrorResponse> {
  GetNewAddressTaskCancelRequest({required super.rpcPass, required this.taskId})
    : super(method: 'task::get_new_address::cancel');

  final int taskId;

  @override
  JsonMap toJson() {
    return {
      ...super.toJson(),
      'userpass': rpcPass,
      'method': method,
      'mmrpc': mmrpc,
      'params': {'task_id': taskId},
    };
  }

  @override
  GetNewAddressTaskCancelResponse parse(JsonMap json) =>
      GetNewAddressTaskCancelResponse.parse(json);
}

// Cancel Response
class GetNewAddressTaskCancelResponse extends BaseResponse {
  GetNewAddressTaskCancelResponse({required super.mmrpc, required this.result});

  factory GetNewAddressTaskCancelResponse.parse(JsonMap json) {
    return GetNewAddressTaskCancelResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: json.value<String>('result'),
    );
  }

  final String result;

  @override
  JsonMap toJson() {
    return {'mmrpc': mmrpc, 'result': result};
  }
}
