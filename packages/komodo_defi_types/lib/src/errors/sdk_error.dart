import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// High-level error categories for SDK consumers.
enum SdkErrorCategory {
  network,
  validation,
  funds,
  auth,
  activation,
  hardware,
  unsupported,
  unknown,
}

/// Stable error codes for SDK consumers.
enum SdkErrorCode {
  networkUnavailable,
  timeout,
  transport,
  invalidResponse,
  insufficientFunds,
  insufficientGas,
  insufficientFeeBalance,
  zeroBalance,
  amountTooLow,
  invalidAddress,
  invalidFee,
  invalidMemo,
  assetNotActivated,
  assetNotFound,
  activationFailed,
  userCancelled,
  hardwareFailure,
  notSupported,
  authInvalidCredentials,
  authUnauthorized,
  authWalletNotFound,
  general,
}

/// Optional context describing where the error occurred.
class SdkErrorContext extends Equatable {
  const SdkErrorContext({
    this.operation,
    this.assetId,
    this.rpcMethod,
    this.extra = const {},
  });

  final String? operation;
  final String? assetId;
  final String? rpcMethod;
  final JsonMap extra;

  JsonMap toJson() => {
    if (operation != null) 'operation': operation,
    if (assetId != null) 'assetId': assetId,
    if (rpcMethod != null) 'rpcMethod': rpcMethod,
    if (extra.isNotEmpty) 'extra': extra,
  };

  @override
  List<Object?> get props => [operation, assetId, rpcMethod, extra];
}

/// Structured SDK error wrapper for user-facing messaging.
class SdkError extends Equatable implements Exception {
  const SdkError({
    required this.code,
    required this.category,
    required this.messageKey,
    required this.fallbackMessage,
    this.messageArgs = const [],
    this.retryable = false,
    this.context,
    this.source,
  });

  final SdkErrorCode code;
  final SdkErrorCategory category;
  final String messageKey;
  final String fallbackMessage;
  final List<String> messageArgs;
  final bool retryable;
  final SdkErrorContext? context;

  /// Original error for debugging/telemetry.
  final Object? source;

  SdkError copyWith({
    SdkErrorCode? code,
    SdkErrorCategory? category,
    String? messageKey,
    String? fallbackMessage,
    List<String>? messageArgs,
    bool? retryable,
    SdkErrorContext? context,
    Object? source,
  }) {
    return SdkError(
      code: code ?? this.code,
      category: category ?? this.category,
      messageKey: messageKey ?? this.messageKey,
      fallbackMessage: fallbackMessage ?? this.fallbackMessage,
      messageArgs: messageArgs ?? this.messageArgs,
      retryable: retryable ?? this.retryable,
      context: context ?? this.context,
      source: source ?? this.source,
    );
  }

  JsonMap toJson() => {
    'code': code.name,
    'category': category.name,
    'messageKey': messageKey,
    'fallbackMessage': fallbackMessage,
    if (messageArgs.isNotEmpty) 'messageArgs': messageArgs,
    'retryable': retryable,
    if (context != null) 'context': context!.toJson(),
  };

  @override
  String toString() => fallbackMessage;

  @override
  List<Object?> get props => [
    code,
    category,
    messageKey,
    fallbackMessage,
    messageArgs,
    retryable,
    context,
  ];
}
