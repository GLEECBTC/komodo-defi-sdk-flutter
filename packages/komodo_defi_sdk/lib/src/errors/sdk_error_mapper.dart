import 'dart:async';
import 'dart:developer' show log;

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

abstract class SdkErrorHandler {
  const SdkErrorHandler();

  bool canHandle(Object error);

  SdkError handle(Object error, {SdkErrorContext? context});
}

class SdkErrorMapper {
  const SdkErrorMapper({List<SdkErrorHandler>? handlers})
    : _handlers = handlers ?? _defaultHandlers;

  final List<SdkErrorHandler> _handlers;

  static const List<SdkErrorHandler> _defaultHandlers = [
    _SdkErrorPassthroughHandler(),
    _WithdrawalExceptionHandler(),
    _AuthExceptionHandler(),
    _ActivationExceptionHandler(),
    _GeneralErrorResponseHandler(),
    _MmRpcExceptionHandler(),
    _TimeoutExceptionHandler(),
    _UnsupportedErrorHandler(),
    _StringErrorHandler(),
    _FallbackHandler(),
  ];

  SdkError map(Object error, {SdkErrorContext? context}) {
    for (final handler in _handlers) {
      if (handler.canHandle(error)) {
        return handler.handle(error, context: context);
      }
    }
    return const _FallbackHandler().handle(error, context: context);
  }
}

class _SdkErrorPassthroughHandler extends SdkErrorHandler {
  const _SdkErrorPassthroughHandler();

  @override
  bool canHandle(Object error) => error is SdkError;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) =>
      error as SdkError;
}

class _GeneralErrorResponseHandler extends SdkErrorHandler {
  const _GeneralErrorResponseHandler();

  @override
  bool canHandle(Object error) => error is GeneralErrorResponse;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final response = error as GeneralErrorResponse;
    final typedException = response.toTypedException();
    if (typedException != null) {
      return const _MmRpcExceptionHandler().handle(
        typedException,
        context: context,
      );
    }

    return _build(
      code: SdkErrorCode.general,
      category: SdkErrorCategory.unknown,
      messageKey: _keyGeneral,
      fallbackMessage: _fallbackGeneral(response.error ?? response),
      detail: response.error,
      retryable: false,
      context: context,
      source: response,
    );
  }
}

class _WithdrawalExceptionHandler extends SdkErrorHandler {
  const _WithdrawalExceptionHandler();

  @override
  bool canHandle(Object error) => error is WithdrawalException;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final withdrawalError = error as WithdrawalException;
    final detail = _detailFromSimpleMessage(withdrawalError.message);
    switch (withdrawalError.code) {
      case WithdrawalErrorCode.insufficientFunds:
        return _build(
          code: SdkErrorCode.insufficientFunds,
          category: SdkErrorCategory.funds,
          messageKey: _keyInsufficientFunds,
          fallbackMessage: _fallbackInsufficientFunds,
          detail: detail,
          retryable: false,
          context: context,
          source: withdrawalError,
        );
      case WithdrawalErrorCode.invalidAddress:
        return _build(
          code: SdkErrorCode.invalidAddress,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidAddress,
          fallbackMessage: _fallbackInvalidAddress,
          detail: detail,
          retryable: false,
          context: context,
          source: withdrawalError,
        );
      case WithdrawalErrorCode.networkError:
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: withdrawalError,
        );
      case WithdrawalErrorCode.userCancelled:
        return _build(
          code: SdkErrorCode.userCancelled,
          category: SdkErrorCategory.validation,
          messageKey: _keyUserCancelled,
          fallbackMessage: _fallbackUserCancelled,
          detail: detail,
          retryable: false,
          context: context,
          source: withdrawalError,
        );
      case WithdrawalErrorCode.gasEstimateFailed:
        return _build(
          code: SdkErrorCode.insufficientGas,
          category: SdkErrorCategory.funds,
          messageKey: _keyInsufficientGas,
          fallbackMessage: _fallbackInsufficientGas,
          detail: detail,
          retryable: false,
          context: context,
          source: withdrawalError,
        );
      case WithdrawalErrorCode.transactionFailed:
      case WithdrawalErrorCode.contractError:
      case WithdrawalErrorCode.unknownError:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(withdrawalError),
          detail: detail,
          retryable: false,
          context: context,
          source: withdrawalError,
        );
    }
  }
}

class _AuthExceptionHandler extends SdkErrorHandler {
  const _AuthExceptionHandler();

  @override
  bool canHandle(Object error) => error is AuthException;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final authError = error as AuthException;
    final detail = _detailFromSimpleMessage(authError.message);
    switch (authError.type) {
      case AuthExceptionType.incorrectPassword:
        return _build(
          code: SdkErrorCode.authInvalidCredentials,
          category: SdkErrorCategory.auth,
          messageKey: _keyAuthInvalidCredentials,
          fallbackMessage: _fallbackAuthInvalidCredentials,
          detail: detail,
          retryable: false,
          context: context,
          source: authError,
        );
      case AuthExceptionType.walletNotFound:
        return _build(
          code: SdkErrorCode.authWalletNotFound,
          category: SdkErrorCategory.auth,
          messageKey: _keyAuthWalletNotFound,
          fallbackMessage: _fallbackAuthWalletNotFound,
          detail: detail,
          retryable: false,
          context: context,
          source: authError,
        );
      case AuthExceptionType.unauthorized:
        return _build(
          code: SdkErrorCode.authUnauthorized,
          category: SdkErrorCategory.auth,
          messageKey: _keyAuthUnauthorized,
          fallbackMessage: _fallbackAuthUnauthorized,
          detail: detail,
          retryable: false,
          context: context,
          source: authError,
        );
      case AuthExceptionType.apiConnectionError:
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: authError,
        );
      case AuthExceptionType.invalidBip39Mnemonic:
      case AuthExceptionType.walletAlreadyExists:
      case AuthExceptionType.walletAlreadyRunning:
      case AuthExceptionType.walletStartFailed:
      case AuthExceptionType.generalAuthError:
      case AuthExceptionType.alreadySignedIn:
      case AuthExceptionType.registrationNotAllowed:
      case AuthExceptionType.internalError:
      case AuthExceptionType.legacyWalletAlreadyMigrated:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.auth,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(authError),
          detail: detail,
          retryable: false,
          context: context,
          source: authError,
        );
    }
  }
}

class _ActivationExceptionHandler extends SdkErrorHandler {
  const _ActivationExceptionHandler();

  @override
  bool canHandle(Object error) => error is ActivationFailedException;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final activationError = error as ActivationFailedException;
    final detail = _detailFromSimpleMessage(activationError.message);
    if (activationError is ActivationTimeoutException) {
      return _build(
        code: SdkErrorCode.timeout,
        category: SdkErrorCategory.network,
        messageKey: _keyTimeout,
        fallbackMessage: _fallbackTimeout,
        detail: detail,
        retryable: true,
        context: context,
        source: activationError,
      );
    }

    if (activationError is ActivationNetworkException) {
      return _build(
        code: SdkErrorCode.networkUnavailable,
        category: SdkErrorCategory.network,
        messageKey: _keyNetworkUnavailable,
        fallbackMessage: _fallbackNetworkUnavailable,
        detail: detail,
        retryable: true,
        context: context,
        source: activationError,
      );
    }

    if (activationError is ActivationNotSupportedException) {
      return _build(
        code: SdkErrorCode.notSupported,
        category: SdkErrorCategory.unsupported,
        messageKey: _keyNotSupported,
        fallbackMessage: _fallbackNotSupported,
        detail: detail,
        retryable: false,
        context: context,
        source: activationError,
      );
    }

    return _build(
      code: SdkErrorCode.activationFailed,
      category: SdkErrorCategory.activation,
      messageKey: _keyActivationFailed,
      fallbackMessage: _fallbackActivationFailed,
      detail: detail,
      retryable: true,
      context: context,
      source: activationError,
    );
  }
}

class _MmRpcExceptionHandler extends SdkErrorHandler {
  const _MmRpcExceptionHandler();

  @override
  bool canHandle(Object error) => error is MmRpcException;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final rpcError = error as MmRpcException;
    final detail = _detailFromMmRpcException(rpcError, context);
    if (rpcError is WithdrawErrorException) {
      return _mapWithdrawError(rpcError, context, detail);
    }

    if (rpcError is Web3RpcErrorException) {
      return _mapWeb3Error(rpcError, context, detail);
    }

    if (rpcError is EthActivationV2ErrorException) {
      return _mapEthActivationError(rpcError, context, detail);
    }

    if (rpcError is EthTokenActivationErrorException) {
      return _mapEthTokenActivationError(rpcError, context, detail);
    }

    final fallback = _mapByTypeName(rpcError, context, detail);
    if (fallback != null) return fallback;

    log(
      'Unhandled MmRpcException type: ${rpcError.runtimeType} (${rpcError.errorType})',
      name: 'SdkErrorMapper',
    );

    return _build(
      code: SdkErrorCode.general,
      category: SdkErrorCategory.unknown,
      messageKey: _keyGeneral,
      fallbackMessage: _fallbackGeneral(rpcError),
      detail: detail,
      retryable: false,
      context: context,
      source: rpcError,
    );
  }

  SdkError _mapWithdrawError(
    WithdrawErrorException error,
    SdkErrorContext? context,
    String? detail,
  ) {
    final assetId = context?.assetId ?? '';
    switch (error) {
      case WithdrawErrorNotSufficientBalanceException():
        return _build(
          code: SdkErrorCode.insufficientFunds,
          category: SdkErrorCategory.funds,
          messageKey: _keyWithdrawNotSufficientBalance,
          messageArgs: [
            error.coin,
            error.available.value,
            error.required.value,
          ],
          fallbackMessage: _fallbackInsufficientFunds,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorNotSufficientPlatformBalanceForFeeException():
        return _build(
          code: SdkErrorCode.insufficientGas,
          category: SdkErrorCategory.funds,
          messageKey: _keyWithdrawNotEnoughBalanceForGas,
          messageArgs: [error.coin],
          fallbackMessage: _fallbackInsufficientGas,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorZeroBalanceToWithdrawMaxException():
        return _build(
          code: SdkErrorCode.zeroBalance,
          category: SdkErrorCategory.funds,
          messageKey: _keyWithdrawZeroBalance,
          messageArgs: [assetId],
          fallbackMessage: _fallbackZeroBalance,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorAmountTooLowException():
        return _build(
          code: SdkErrorCode.amountTooLow,
          category: SdkErrorCategory.validation,
          messageKey: _keyWithdrawAmountTooLow,
          messageArgs: [
            error.amount.value,
            assetId,
            error.threshold.value,
            assetId,
          ],
          fallbackMessage: _fallbackAmountTooLow,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorInvalidAddressException():
        return _build(
          code: SdkErrorCode.invalidAddress,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidAddressApp,
          messageArgs: [assetId],
          fallbackMessage: _fallbackInvalidAddress,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorInvalidFeePolicyException():
      case WithdrawErrorInvalidFeeException():
        return _build(
          code: SdkErrorCode.invalidFee,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidFee,
          fallbackMessage: _fallbackInvalidFee,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorInvalidMemoException():
        return _build(
          code: SdkErrorCode.invalidMemo,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidMemo,
          fallbackMessage: _fallbackInvalidMemo,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorNoSuchCoinException():
        return _build(
          code: SdkErrorCode.assetNotActivated,
          category: SdkErrorCategory.activation,
          messageKey: _keyWithdrawNoSuchCoin,
          messageArgs: [error.coin],
          fallbackMessage: _fallbackAssetNotActivated,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case WithdrawErrorTimeoutException():
        return _build(
          code: SdkErrorCode.timeout,
          category: SdkErrorCategory.network,
          messageKey: _keyTimeout,
          fallbackMessage: _fallbackTimeout,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case WithdrawErrorTransportException():
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case WithdrawErrorUnexpectedUserActionException():
        return _build(
          code: SdkErrorCode.userCancelled,
          category: SdkErrorCategory.validation,
          messageKey: _keyUserCancelled,
          fallbackMessage: _fallbackUserCancelled,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case WithdrawErrorHwErrorException():
        return _build(
          code: SdkErrorCode.hardwareFailure,
          category: SdkErrorCategory.hardware,
          messageKey: _keyHardwareFailure,
          fallbackMessage: _fallbackHardwareFailure,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case WithdrawErrorCoinDoesntSupportInitWithdrawException():
      case WithdrawErrorCoinDoesntSupportNftWithdrawException():
      case WithdrawErrorContractTypeDoesntSupportNftWithdrawingException():
      case WithdrawErrorNftProtocolNotSupportedException():
      case WithdrawErrorTxTypeNotSupportedException():
      case WithdrawErrorUnsupportedErrorException():
        return _build(
          code: SdkErrorCode.notSupported,
          category: SdkErrorCategory.unsupported,
          messageKey: _keyNotSupported,
          fallbackMessage: _fallbackNotSupported,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      default:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(error),
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
    }
  }

  SdkError _mapWeb3Error(
    Web3RpcErrorException error,
    SdkErrorContext? context,
    String? detail,
  ) {
    switch (error) {
      case Web3RpcErrorTimeoutException():
        return _build(
          code: SdkErrorCode.timeout,
          category: SdkErrorCategory.network,
          messageKey: _keyTimeout,
          fallbackMessage: _fallbackTimeout,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case Web3RpcErrorTransportException():
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case Web3RpcErrorInvalidResponseException():
        return _build(
          code: SdkErrorCode.invalidResponse,
          category: SdkErrorCategory.network,
          messageKey: _keyInvalidResponse,
          fallbackMessage: _fallbackInvalidResponse,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      default:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(error),
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
    }
  }

  SdkError _mapEthActivationError(
    EthActivationV2ErrorException error,
    SdkErrorContext? context,
    String? detail,
  ) {
    switch (error) {
      case EthActivationV2ErrorUnreachableNodesException():
      case EthActivationV2ErrorAtLeastOneNodeRequiredException():
      case EthActivationV2ErrorTransportException():
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorTaskTimedOutException():
        return _build(
          code: SdkErrorCode.timeout,
          category: SdkErrorCategory.network,
          messageKey: _keyTimeout,
          fallbackMessage: _fallbackTimeout,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorUnsupportedChainException():
      case EthActivationV2ErrorCoinDoesntSupportTrezorException():
        return _build(
          code: SdkErrorCode.notSupported,
          category: SdkErrorCategory.unsupported,
          messageKey: _keyNotSupported,
          fallbackMessage: _fallbackNotSupported,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorHwErrorException():
      case EthActivationV2ErrorInvalidHardwareWalletCallException():
      case EthActivationV2ErrorHwContextNotInitializedException():
        return _build(
          code: SdkErrorCode.hardwareFailure,
          category: SdkErrorCategory.hardware,
          messageKey: _keyHardwareFailure,
          fallbackMessage: _fallbackHardwareFailure,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorPrivKeyPolicyNotAllowedException():
        return _build(
          code: SdkErrorCode.authUnauthorized,
          category: SdkErrorCategory.auth,
          messageKey: _keyAuthUnauthorized,
          fallbackMessage: _fallbackAuthUnauthorized,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorActivationFailedException():
      case EthActivationV2ErrorCouldNotFetchBalanceException():
      case EthActivationV2ErrorFailedSpawningBalanceEventsException():
        return _build(
          code: SdkErrorCode.activationFailed,
          category: SdkErrorCategory.activation,
          messageKey: _keyActivationFailed,
          fallbackMessage: _fallbackActivationFailed,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthActivationV2ErrorInvalidPayloadException():
      case EthActivationV2ErrorInvalidSwapContractAddrException():
      case EthActivationV2ErrorInvalidFallbackSwapContractException():
      case EthActivationV2ErrorInvalidPathToAddressException():
      case EthActivationV2ErrorErrorDeserializingDerivationPathException():
      case EthActivationV2ErrorUnexpectedDerivationMethodException():
      case EthActivationV2ErrorChainIdNotSetException():
        return _build(
          code: SdkErrorCode.invalidResponse,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidResponse,
          fallbackMessage: _fallbackInvalidResponse,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      default:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(error),
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
    }
  }

  SdkError _mapEthTokenActivationError(
    EthTokenActivationErrorException error,
    SdkErrorContext? context,
    String? detail,
  ) {
    switch (error) {
      case EthTokenActivationErrorClientConnectionFailedException():
      case EthTokenActivationErrorTransportException():
        return _build(
          code: SdkErrorCode.networkUnavailable,
          category: SdkErrorCategory.network,
          messageKey: _keyNetworkUnavailable,
          fallbackMessage: _fallbackNetworkUnavailable,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthTokenActivationErrorCouldNotFetchBalanceException():
        return _build(
          code: SdkErrorCode.activationFailed,
          category: SdkErrorCategory.activation,
          messageKey: _keyActivationFailed,
          fallbackMessage: _fallbackActivationFailed,
          detail: detail,
          retryable: true,
          context: context,
          source: error,
        );
      case EthTokenActivationErrorInvalidPayloadException():
        return _build(
          code: SdkErrorCode.invalidResponse,
          category: SdkErrorCategory.validation,
          messageKey: _keyInvalidResponse,
          fallbackMessage: _fallbackInvalidResponse,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      case EthTokenActivationErrorPrivKeyPolicyNotAllowedException():
      case EthTokenActivationErrorUnexpectedDerivationMethodException():
        return _build(
          code: SdkErrorCode.authUnauthorized,
          category: SdkErrorCategory.auth,
          messageKey: _keyAuthUnauthorized,
          fallbackMessage: _fallbackAuthUnauthorized,
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
      default:
        return _build(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: _keyGeneral,
          fallbackMessage: _fallbackGeneral(error),
          detail: detail,
          retryable: false,
          context: context,
          source: error,
        );
    }
  }

  SdkError? _mapByTypeName(
    MmRpcException error,
    SdkErrorContext? context,
    String? detail,
  ) {
    final typeName =
        '${error.runtimeType} ${error.errorType} ${error.message ?? ''}'
            .toLowerCase();
    if (_containsAny(typeName, ['timeout', 'timedout'])) {
      return _build(
        code: SdkErrorCode.timeout,
        category: SdkErrorCategory.network,
        messageKey: _keyTimeout,
        fallbackMessage: _fallbackTimeout,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['transport', 'unreachable', 'connection'])) {
      return _build(
        code: SdkErrorCode.networkUnavailable,
        category: SdkErrorCategory.network,
        messageKey: _keyNetworkUnavailable,
        fallbackMessage: _fallbackNetworkUnavailable,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['insufficient', 'notsufficient'])) {
      return _build(
        code: _containsAny(typeName, ['fee', 'gas'])
            ? SdkErrorCode.insufficientGas
            : SdkErrorCode.insufficientFunds,
        category: SdkErrorCategory.funds,
        messageKey: _containsAny(typeName, ['fee', 'gas'])
            ? _keyInsufficientGas
            : _keyInsufficientFunds,
        fallbackMessage: _containsAny(typeName, ['fee', 'gas'])
            ? _fallbackInsufficientGas
            : _fallbackInsufficientFunds,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (typeName.contains('invalidaddress')) {
      return _build(
        code: SdkErrorCode.invalidAddress,
        category: SdkErrorCategory.validation,
        messageKey: _keyInvalidAddress,
        fallbackMessage: _fallbackInvalidAddress,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['invalidfee', 'invalidfeepolicy'])) {
      return _build(
        code: SdkErrorCode.invalidFee,
        category: SdkErrorCategory.validation,
        messageKey: _keyInvalidFee,
        fallbackMessage: _fallbackInvalidFee,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (typeName.contains('invalidmemo')) {
      return _build(
        code: SdkErrorCode.invalidMemo,
        category: SdkErrorCategory.validation,
        messageKey: _keyInvalidMemo,
        fallbackMessage: _fallbackInvalidMemo,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['amounttoolow', 'dust'])) {
      return _build(
        code: SdkErrorCode.amountTooLow,
        category: SdkErrorCategory.validation,
        messageKey: _keyAmountTooLow,
        fallbackMessage: _fallbackAmountTooLow,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (typeName.contains('zerobalance')) {
      return _build(
        code: SdkErrorCode.zeroBalance,
        category: SdkErrorCategory.funds,
        messageKey: _keyZeroBalance,
        fallbackMessage: _fallbackZeroBalance,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['nosuchcoin', 'coinisnotfound'])) {
      return _build(
        code: SdkErrorCode.assetNotActivated,
        category: SdkErrorCategory.activation,
        messageKey: _keyAssetNotActivated,
        fallbackMessage: _fallbackAssetNotActivated,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, [
      'notsupported',
      'doesntsupport',
      'unsupported',
    ])) {
      return _build(
        code: SdkErrorCode.notSupported,
        category: SdkErrorCategory.unsupported,
        messageKey: _keyNotSupported,
        fallbackMessage: _fallbackNotSupported,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (typeName.contains('activationfailed')) {
      return _build(
        code: SdkErrorCode.activationFailed,
        category: SdkErrorCategory.activation,
        messageKey: _keyActivationFailed,
        fallbackMessage: _fallbackActivationFailed,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['useraction', 'cancelled', 'canceled'])) {
      return _build(
        code: SdkErrorCode.userCancelled,
        category: SdkErrorCategory.validation,
        messageKey: _keyUserCancelled,
        fallbackMessage: _fallbackUserCancelled,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['hw', 'hardware', 'trezor'])) {
      return _build(
        code: SdkErrorCode.hardwareFailure,
        category: SdkErrorCategory.hardware,
        messageKey: _keyHardwareFailure,
        fallbackMessage: _fallbackHardwareFailure,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(typeName, ['unauthorized', 'privkeypolicynotallowed'])) {
      return _build(
        code: SdkErrorCode.authUnauthorized,
        category: SdkErrorCategory.auth,
        messageKey: _keyAuthUnauthorized,
        fallbackMessage: _fallbackAuthUnauthorized,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    return null;
  }
}

class _TimeoutExceptionHandler extends SdkErrorHandler {
  const _TimeoutExceptionHandler();

  @override
  bool canHandle(Object error) => error is TimeoutException;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final detail = _detailFromSimpleMessage(error.toString());
    return _build(
      code: SdkErrorCode.timeout,
      category: SdkErrorCategory.network,
      messageKey: _keyTimeout,
      fallbackMessage: _fallbackTimeout,
      detail: detail,
      retryable: true,
      context: context,
      source: error,
    );
  }
}

class _UnsupportedErrorHandler extends SdkErrorHandler {
  const _UnsupportedErrorHandler();

  @override
  bool canHandle(Object error) => error is UnsupportedError;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final detail = _detailFromSimpleMessage(error.toString());
    return _build(
      code: SdkErrorCode.notSupported,
      category: SdkErrorCategory.unsupported,
      messageKey: _keyNotSupported,
      fallbackMessage: _fallbackNotSupported,
      detail: detail,
      retryable: false,
      context: context,
      source: error,
    );
  }
}

class _StringErrorHandler extends SdkErrorHandler {
  const _StringErrorHandler();

  @override
  bool canHandle(Object error) => error is String;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final message = error as String;
    final detail = _detailFromSimpleMessage(message);
    final lower = message.toLowerCase();
    if (lower.contains('timeout')) {
      return _build(
        code: SdkErrorCode.timeout,
        category: SdkErrorCategory.network,
        messageKey: _keyTimeout,
        fallbackMessage: _fallbackTimeout,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(lower, ['transport', 'unreachable', 'connection'])) {
      return _build(
        code: SdkErrorCode.networkUnavailable,
        category: SdkErrorCategory.network,
        messageKey: _keyNetworkUnavailable,
        fallbackMessage: _fallbackNetworkUnavailable,
        detail: detail,
        retryable: true,
        context: context,
        source: error,
      );
    }

    if (_containsAny(lower, ['insufficient', 'not enough funds'])) {
      return _build(
        code: SdkErrorCode.insufficientFunds,
        category: SdkErrorCategory.funds,
        messageKey: _keyInsufficientFunds,
        fallbackMessage: _fallbackInsufficientFunds,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (lower.contains('invalid address')) {
      return _build(
        code: SdkErrorCode.invalidAddress,
        category: SdkErrorCategory.validation,
        messageKey: _keyInvalidAddress,
        fallbackMessage: _fallbackInvalidAddress,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (lower.contains('fee')) {
      return _build(
        code: SdkErrorCode.invalidFee,
        category: SdkErrorCategory.validation,
        messageKey: _keyInvalidFee,
        fallbackMessage: _fallbackInvalidFee,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    if (_containsAny(lower, ['user cancelled', 'user canceled'])) {
      return _build(
        code: SdkErrorCode.userCancelled,
        category: SdkErrorCategory.validation,
        messageKey: _keyUserCancelled,
        fallbackMessage: _fallbackUserCancelled,
        detail: detail,
        retryable: false,
        context: context,
        source: error,
      );
    }

    return const _FallbackHandler().handle(error, context: context);
  }
}

class _FallbackHandler extends SdkErrorHandler {
  const _FallbackHandler();

  @override
  bool canHandle(Object error) => true;

  @override
  SdkError handle(Object error, {SdkErrorContext? context}) {
    final detail = _detailFromSimpleMessage(error.toString());
    return _build(
      code: SdkErrorCode.general,
      category: SdkErrorCategory.unknown,
      messageKey: _keyGeneral,
      fallbackMessage: _fallbackGeneral(error),
      detail: detail,
      retryable: false,
      context: context,
      source: error,
    );
  }
}

SdkError _build({
  required SdkErrorCode code,
  required SdkErrorCategory category,
  required String messageKey,
  required String fallbackMessage,
  String? detail,
  List<String> messageArgs = const [],
  required bool retryable,
  SdkErrorContext? context,
  Object? source,
}) {
  final detailSuffix = _detailSuffix(detail);
  final resolvedArgs = messageArgs.isNotEmpty
      ? messageArgs
      : [detailSuffix ?? ''];
  final detailValue = detail?.trim();
  final shouldAppendDetail =
      detailSuffix != null &&
      detailValue != null &&
      detailValue.isNotEmpty &&
      !fallbackMessage.contains(detailValue);
  final resolvedFallback = shouldAppendDetail
      ? '$fallbackMessage$detailSuffix'
      : fallbackMessage;
  return SdkError(
    code: code,
    category: category,
    messageKey: messageKey,
    fallbackMessage: resolvedFallback,
    messageArgs: resolvedArgs,
    retryable: retryable,
    context: context,
    source: source,
  );
}

String? _detailFromMmRpcException(
  MmRpcException error,
  SdkErrorContext? context,
) {
  switch (error) {
    case WithdrawErrorNotSufficientBalanceException():
      final coin = error.coin;
      return 'available ${_formatAmount(error.available.value, coin)}, '
          'required ${_formatAmount(error.required.value, coin)}';
    case WithdrawErrorCoinDoesntSupportInitWithdrawException():
      return _detailFromSimpleMessage(error.coin);
    case WithdrawErrorCoinDoesntSupportNftWithdrawException():
      return _detailFromSimpleMessage(error.coin);
    case WithdrawErrorNotSufficientPlatformBalanceForFeeException():
      final coin = error.coin;
      return 'available ${_formatAmount(error.available.value, coin)}, '
          'required ${_formatAmount(error.required.value, coin)}';
    case WithdrawErrorAmountTooLowException():
      final coin = context?.assetId;
      return 'amount ${_formatAmount(error.amount.value, coin)}, '
          'min ${_formatAmount(error.threshold.value, coin)}';
    case WithdrawErrorUnexpectedFromAddressException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorUnknownAccountException():
      return _detailFromSimpleMessage('account ${error.accountId}');
    case WithdrawErrorUnexpectedUserActionException():
      return _detailFromSimpleMessage('expected ${error.expected}');
    case WithdrawErrorInvalidAddressException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorInvalidFeePolicyException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorInvalidFeeException():
      final detail = <String>[
        error.reason,
        if (error.details?.value != null) error.details!.value.toString(),
      ].where((item) => item.trim().isNotEmpty).join(': ');
      return _detailFromSimpleMessage(detail);
    case WithdrawErrorInvalidMemoException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorNoSuchCoinException():
      return _detailFromSimpleMessage(error.coin);
    case WithdrawErrorBroadcastExpectedException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorTransportException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorInternalErrorException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorUnsupportedErrorException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorContractTypeDoesntSupportNftWithdrawingException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorActionNotAllowedException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorGetNftInfoErrorException():
      return _detailFromSimpleMessage(error.value.toString());
    case WithdrawErrorNotEnoughNftsAmountException():
      return _detailFromSimpleMessage(
        'token ${error.tokenAddress} #${error.tokenId}, '
        'available ${error.available.value}, required ${error.required.value}',
      );
    case WithdrawErrorDbErrorException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorMyAddressNotNftOwnerException():
      return _detailFromSimpleMessage(
        'owner ${error.tokenOwner}, yours ${error.myAddress}',
      );
    case WithdrawErrorNoChainIdSetException():
      return _detailFromSimpleMessage(error.coin);
    case WithdrawErrorSigningErrorException():
      return _detailFromSimpleMessage(error.value);
    case WithdrawErrorIBCErrorException():
      return _detailFromSimpleMessage(error.value.toString());
    case WithdrawErrorZeroBalanceToWithdrawMaxException():
      return _detailFromSimpleMessage(context?.assetId);
    case WithdrawErrorTimeoutException():
      return _detailFromSimpleMessage(_formatDuration(error.value.value));
    case Web3RpcErrorTimeoutException():
      return _detailFromSimpleMessage(error.value);
    case Web3RpcErrorTransportException():
      return _detailFromSimpleMessage(error.value);
    case Web3RpcErrorInvalidResponseException():
      return _detailFromSimpleMessage(error.value);
    case Web3RpcErrorInvalidGasApiConfigException():
      return _detailFromSimpleMessage(error.value);
    case Web3RpcErrorNumConversErrorException():
      return _detailFromSimpleMessage(error.value);
    case EthActivationV2ErrorActivationFailedException():
      return _detailFromSimpleMessage('${error.ticker}: ${error.error}');
    case EthActivationV2ErrorUnsupportedChainException():
      return _detailFromSimpleMessage('${error.chain} (${error.feature})');
    case EthActivationV2ErrorTaskTimedOutException():
      return _detailFromSimpleMessage(_formatDuration(error.duration.value));
    case EthActivationV2ErrorInvalidPayloadException():
    case EthActivationV2ErrorInvalidSwapContractAddrException():
    case EthActivationV2ErrorInvalidFallbackSwapContractException():
    case EthActivationV2ErrorInvalidPathToAddressException():
    case EthActivationV2ErrorCouldNotFetchBalanceException():
    case EthActivationV2ErrorUnreachableNodesException():
    case EthActivationV2ErrorErrorDeserializingDerivationPathException():
    case EthActivationV2ErrorPrivKeyPolicyNotAllowedException():
    case EthActivationV2ErrorFailedSpawningBalanceEventsException():
    case EthActivationV2ErrorHDWalletStorageErrorException():
    case EthActivationV2ErrorInternalErrorException():
    case EthActivationV2ErrorTransportException():
    case EthActivationV2ErrorUnexpectedDerivationMethodException():
    case EthActivationV2ErrorWalletConnectErrorException():
      // All of these error types carry a "value" string in the generated class.
      // ignore: avoid_dynamic_calls
      return _detailFromSimpleMessage((error as dynamic).value?.toString());
    case EthActivationV2ErrorMetamaskErrorException():
    case EthActivationV2ErrorHwErrorException():
    case EthActivationV2ErrorCustomTokenErrorException():
      // These errors carry structured values; stringify for display.
      // ignore: avoid_dynamic_calls
      return _detailFromSimpleMessage((error as dynamic).value?.toString());
    case EthTokenActivationErrorInternalErrorException():
    case EthTokenActivationErrorClientConnectionFailedException():
    case EthTokenActivationErrorCouldNotFetchBalanceException():
    case EthTokenActivationErrorInvalidPayloadException():
    case EthTokenActivationErrorTransportException():
      // ignore: avoid_dynamic_calls
      return _detailFromSimpleMessage((error as dynamic).value?.toString());
    case EthTokenActivationErrorUnexpectedDerivationMethodException():
    case EthTokenActivationErrorPrivKeyPolicyNotAllowedException():
    case EthTokenActivationErrorCustomTokenErrorException():
      // ignore: avoid_dynamic_calls
      return _detailFromSimpleMessage((error as dynamic).value?.toString());
    case AddressDerivingErrorInvalidBip44ChainException():
      return _detailFromSimpleMessage(error.chain.toJson());
    case AddressDerivingErrorBip32ErrorException():
    case AddressDerivingErrorInternalException():
      // ignore: avoid_dynamic_calls
      return _detailFromSimpleMessage((error as dynamic).value?.toString());
    default:
      final message = _detailFromSimpleMessage(error.message);
      if (message != null) return message;
      try {
        // Some generated error types expose a `value` field instead of `message`.
        // ignore: avoid_dynamic_calls
        return _detailFromSimpleMessage((error as dynamic).value?.toString());
      } catch (_) {
        return null;
      }
  }
}

String? _detailFromSimpleMessage(String? message) {
  if (message == null) return null;
  final trimmed = message.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _detailSuffix(String? detail) {
  if (detail == null) return null;
  final trimmed = detail.trim();
  if (trimmed.isEmpty) return null;
  return ' ($trimmed)';
}

String _formatAmount(String value, String? coin) {
  if (coin == null || coin.trim().isEmpty) {
    return value;
  }
  return '$value $coin';
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds > 0) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMilliseconds}ms';
}

bool _containsAny(String source, List<String> needles) =>
    needles.any(source.contains);

const String _keyNetworkUnavailable = 'sdk_errors.network_unavailable';
const String _keyTimeout = 'sdk_errors.timeout';
const String _keyInvalidResponse = 'sdk_errors.invalid_response';
const String _keyInsufficientFunds = 'sdk_errors.insufficient_funds';
const String _keyInsufficientGas = 'sdk_errors.insufficient_gas';
const String _keyZeroBalance = 'sdk_errors.zero_balance';
const String _keyAmountTooLow = 'sdk_errors.amount_too_low';
const String _keyInvalidAddress = 'sdk_errors.invalid_address';
const String _keyInvalidAddressApp = 'invalidAddress';
const String _keyWithdrawNotSufficientBalance =
    'withdrawNotSufficientBalanceError';
const String _keyWithdrawNotEnoughBalanceForGas =
    'withdrawNotEnoughBalanceForGasError';
const String _keyWithdrawZeroBalance = 'withdrawZeroBalanceError';
const String _keyWithdrawAmountTooLow = 'withdrawAmountTooLowError';
const String _keyWithdrawNoSuchCoin = 'withdrawNoSuchCoinError';
const String _keyInvalidFee = 'sdk_errors.invalid_fee';
const String _keyInvalidMemo = 'sdk_errors.invalid_memo';
const String _keyAssetNotActivated = 'sdk_errors.asset_not_activated';
const String _keyActivationFailed = 'sdk_errors.activation_failed';
const String _keyUserCancelled = 'sdk_errors.user_cancelled';
const String _keyHardwareFailure = 'sdk_errors.hardware_failure';
const String _keyNotSupported = 'sdk_errors.not_supported';
const String _keyAuthInvalidCredentials = 'sdk_errors.auth_invalid_credentials';
const String _keyAuthUnauthorized = 'sdk_errors.auth_unauthorized';
const String _keyAuthWalletNotFound = 'sdk_errors.auth_wallet_not_found';
const String _keyGeneral = 'sdk_errors.general';

const String _fallbackNetworkUnavailable =
    'Network error. Please check your connection and try again.';
const String _fallbackTimeout = 'The request timed out. Please try again.';
const String _fallbackInvalidResponse =
    'Unexpected response from the network. Please try again.';
const String _fallbackInsufficientFunds =
    'Insufficient balance to complete this action.';
const String _fallbackInsufficientGas =
    'Insufficient balance to pay network fees.';
const String _fallbackZeroBalance =
    'Your balance is zero. Please deposit funds and try again.';
const String _fallbackAmountTooLow =
    'The amount is too low. Please increase the amount and try again.';
const String _fallbackInvalidAddress =
    'The address is invalid. Please check and try again.';
const String _fallbackInvalidFee =
    'The fee value is invalid. Please review and try again.';
const String _fallbackInvalidMemo =
    'The memo is invalid. Please review and try again.';
const String _fallbackAssetNotActivated =
    'The asset is not activated or is unavailable. Please enable it and try again.';
const String _fallbackActivationFailed = 'Activation failed. Please try again.';
const String _fallbackUserCancelled = 'Action cancelled by user.';
const String _fallbackHardwareFailure =
    'Hardware wallet operation failed. Please try again.';
const String _fallbackNotSupported =
    'This action is not supported for the selected asset.';
const String _fallbackAuthInvalidCredentials =
    'Invalid credentials. Please check your password.';
const String _fallbackAuthUnauthorized =
    'Authorization failed. Please sign in again.';
const String _fallbackAuthWalletNotFound =
    'Wallet not found. Please verify the wallet name.';

String _fallbackGeneral(Object error) =>
    'Something went wrong. Please try again. ($error)';
