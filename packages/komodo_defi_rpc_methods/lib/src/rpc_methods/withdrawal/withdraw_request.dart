import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Default amount value for KMD rewards when claiming
const String _kDefaultKmdRewardsAmount = '0';

bool _validatedWithdrawalMax({required Object? amount, required bool max}) {
  if (max && amount != null) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Must be omitted when max is true',
    );
  }
  if (!max && amount == null) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Must be specified when max is false',
    );
  }
  return max;
}

/// Returns KMD-specific parameters for withdrawal requests
///
/// KDF requires kmd_rewards object with claimed_by_me flag for KMD withdrawals
Map<String, dynamic> _kmdRewardsParams() => {
  'kmd_rewards': {'amount': _kDefaultKmdRewardsAmount, 'claimed_by_me': true},
};

/// Request for standard withdrawal (non-task API)
///
/// After the bug with the task-based withdrawal API was fixed, this request
/// will be deprecated in favor of the new task-based withdrawal API.
// @Deprecated('Use the new task-based withdrawal API')
class WithdrawRequest
    extends BaseRequest<WithdrawStatusResponse, GaslessWithdrawException> {
  // @Deprecated('Use the new task-based withdrawal API')
  WithdrawRequest({
    required super.rpcPass,
    required this.coin,
    required this.to,
    required this.amount,
    this.fee,
    this.from,
    this.memo,
    bool max = false,
    this.ibcSourceChannel,
    this.expirationSeconds,
    this.feeMethod,
    this.gaslessOptions,
  }) : max = _validatedWithdrawalMax(amount: amount, max: max),
       assert(
         amount != null || max,
         'Amount must be specified when max is false',
       ),
       assert(
         amount == null || !max,
         'Amount must be omitted when max is true',
       ),
       super(method: 'withdraw', mmrpc: RpcVersion.v2_0);

  final String coin;
  final String to;
  final Decimal? amount;
  final FeeInfo? fee;
  final WithdrawalSource? from;
  final String? memo;
  final bool max;
  final int? ibcSourceChannel;
  final int? expirationSeconds;
  final WithdrawalFeeMethod? feeMethod;
  final GaslessWithdrawalOptions? gaslessOptions;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {
      'coin': coin,
      'to': to,
      if (max) 'max': max,
      if (!max && amount != null) 'amount': amount?.toString(),
      if (fee != null) 'fee': fee!.toJson(),
      if (from != null) 'from': from!.toRpcParams(),
      if (memo != null) 'memo': memo,
      if (coin.toUpperCase() == 'KMD') ..._kmdRewardsParams(),
      if (ibcSourceChannel != null) 'ibc_source_channel': ibcSourceChannel,
      if (expirationSeconds != null) 'expiration_seconds': expirationSeconds,
      if (feeMethod != null) 'fee_method': feeMethod!.jsonValue,
      if (gaslessOptions != null) 'gasless': gaslessOptions!.toJson(),
    },
  };

  @override
  WithdrawStatusResponse parse(Map<String, dynamic> json) {
    // TODO: Remove work-around when legacy withdrawal is deprecated or
    // refactor to avoid shared parsing logic
    final hasDetails = json.hasNestedKey('result', 'details');
    final hasStatus = json.hasNestedKey('result', 'status');
    return WithdrawStatusResponse.parse(
      json.deepMerge(
        {
          if (!hasStatus) 'result': {'status': 'Ok'},
        }.deepMerge({
          if (!hasDetails) 'result': {'details': json['result']},
        }),
      ),
    );
  }

  @override
  GaslessWithdrawException? parseCustomErrorResponse(JsonMap json) =>
      GaslessWithdrawException.tryParse(json);
}

/// Request to initialize withdrawal task
class WithdrawInitRequest
    extends BaseRequest<WithdrawInitResponse, GaslessWithdrawException> {
  WithdrawInitRequest({
    required super.rpcPass,
    required WithdrawParameters params,
  }) : coin = params.asset,
       to = params.toAddress,
       amount = params.amount?.toString(),
       fee = params.fee,
       from = params.from,
       memo = params.memo,
       max = _validatedWithdrawalMax(
         amount: params.amount,
         max: params.isMax ?? false,
       ),
       expirationSeconds = params.expirationSeconds,
       feeMethod = params.feeMethod,
       gaslessOptions = params.gaslessOptions,
       assert(
         params.amount != null || (params.isMax ?? false),
         'Amount must be specified when isMax is false',
       ),
       assert(
         params.amount == null || !(params.isMax ?? false),
         'Amount must be omitted when isMax is true',
       ),
       super(method: 'task::withdraw::init', mmrpc: RpcVersion.v2_0);

  final String coin;
  final String to;
  final String? amount;
  final FeeInfo? fee;
  final WithdrawalSource? from;
  final String? memo;
  final bool max;
  final int? expirationSeconds;
  final WithdrawalFeeMethod? feeMethod;
  final GaslessWithdrawalOptions? gaslessOptions;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {
      'coin': coin,
      'to': to,
      if (!max && amount != null) 'amount': amount,
      if (fee != null) 'fee': fee!.toJson(),
      if (from != null) 'from': from!.toRpcParams(),
      if (memo != null) 'memo': memo,
      if (max) 'max': max,
      if (expirationSeconds != null) 'expiration_seconds': expirationSeconds,
      if (feeMethod != null) 'fee_method': feeMethod!.jsonValue,
      if (gaslessOptions != null) 'gasless': gaslessOptions!.toJson(),
      if (coin.toUpperCase() == 'KMD') ..._kmdRewardsParams(),
    },
  };

  @override
  WithdrawInitResponse parse(Map<String, dynamic> json) =>
      WithdrawInitResponse.parse(json);

  @override
  GaslessWithdrawException? parseCustomErrorResponse(JsonMap json) =>
      GaslessWithdrawException.tryParse(json);
}

typedef WithdrawInitResponse = NewTaskResponse;

/// Request to check withdrawal task status
class WithdrawStatusRequest
    extends BaseRequest<WithdrawStatusResponse, GaslessWithdrawException> {
  WithdrawStatusRequest({
    required super.rpcPass,
    required this.taskId,
    this.forgetIfFinished = true,
  }) : super(method: 'task::withdraw::status', mmrpc: RpcVersion.v2_0);

  final int taskId;
  final bool forgetIfFinished;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {'task_id': taskId, 'forget_if_finished': forgetIfFinished},
  };

  @override
  WithdrawStatusResponse parse(Map<String, dynamic> json) =>
      WithdrawStatusResponse.parse(json);

  @override
  bool shouldParseErrorAsResponse(JsonMap json) =>
      json.valueOrNull<String>('result', 'status') == 'Error' &&
      json.hasNestedKey('result', 'details');

  @override
  GaslessWithdrawException? parseCustomErrorResponse(JsonMap json) =>
      GaslessWithdrawException.tryParse(json);
}

Object? _typedWithdrawTaskError(Object details) {
  final errorJson = switch (details) {
    final String value => tryParseJson(value),
    final Map<dynamic, dynamic> value => convertToJsonMap(value),
    _ => null,
  };
  if (errorJson == null) return null;

  return GaslessWithdrawException.tryParse(errorJson) ??
      KdfErrorRegistry.tryParse(
        errorJson,
        rpcMethodHint: 'task::withdraw::status',
      );
}

Object _untypedWithdrawTaskError(Object details) => switch (details) {
  final String value => value,
  final Map<dynamic, dynamic> value => convertToJsonMap(value).toJsonString(),
  _ => details.toString(),
};

class WithdrawStatusResponse extends BaseResponse {
  WithdrawStatusResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
  });

  factory WithdrawStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    final status = result.value<String>('status');
    final rawDetails = result.value<Object>('details');

    return WithdrawStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: status,
      details: status == 'Ok'
          ? WithdrawResult.fromJson(result.value<JsonMap>('details'))
          : status == 'Error'
          ? _typedWithdrawTaskError(rawDetails) ??
                _untypedWithdrawTaskError(rawDetails)
          : result.value<String>('details'),
    );
  }

  final String status;

  /// Progress text, a completed [WithdrawResult], or a typed terminal error.
  ///
  /// JSON-stringified task errors are decoded at this RPC boundary so SDK
  /// consumers never need to inspect or regex-match the raw error text.
  final Object details;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'status': status,
      'details': switch (details) {
        final WithdrawResult result => result.toJson(),
        final GaslessWithdrawException error => error.toJson().toJsonString(),
        final MmRpcException error => error.toString(),
        final Object value => value,
      },
    },
  };

  @override
  String toString() => toJson().toJsonString();
}

/// Request to cancel withdrawal task
class WithdrawCancelRequest
    extends BaseRequest<WithdrawCancelResponse, GeneralErrorResponse> {
  WithdrawCancelRequest({required super.rpcPass, required this.taskId})
    : super(method: 'task::withdraw::cancel', mmrpc: RpcVersion.v2_0);

  final int taskId;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {'task_id': taskId},
  };

  @override
  WithdrawCancelResponse parse(Map<String, dynamic> json) =>
      WithdrawCancelResponse.parse(json);
}

class WithdrawCancelResponse extends BaseResponse {
  WithdrawCancelResponse({required super.mmrpc, required this.result});

  factory WithdrawCancelResponse.parse(Map<String, dynamic> json) {
    return WithdrawCancelResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: json.value<String>('result'),
    );
  }

  final String result;

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': result};
}
