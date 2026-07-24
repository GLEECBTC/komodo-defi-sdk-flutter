import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('SdkErrorMapper', () {
    const mapper = SdkErrorMapper();

    test('maps withdraw insufficient balance to insufficient funds', () {
      const error = WithdrawErrorNotSufficientBalanceException(
        coin: 'KMD',
        available: BigDecimal('1'),
        required: BigDecimal('2'),
      );
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.insufficientFunds);
      expect(sdkError.category, SdkErrorCategory.funds);
      expect(sdkError.messageKey, 'withdrawNotSufficientBalanceError');
      expect(sdkError.messageArgs, ['KMD', '1', '2']);
    });

    test('maps GasFree custody shortfall to insufficient funds', () {
      const error = GaslessWithdrawException(
        type: GaslessWithdrawErrorType.insufficientGasFreeBalance,
        errorData: {'coin': 'USDT-TRC20', 'available': '0', 'required': '8'},
      );
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.insufficientFunds);
      expect(sdkError.category, SdkErrorCategory.funds);
      expect(sdkError.messageKey, 'withdrawGaslessInsufficientGasFreeBalance');
      expect(sdkError.messageArgs, [
        '',
        '0',
        'USDT-TRC20',
        '8',
        'USDT-TRC20',
        'USDT-TRC20',
      ]);
      expect(sdkError.retryable, isFalse);
      // Never the native-gas diagnosis: gasless fees are paid in the token.
      expect(sdkError.code, isNot(SdkErrorCode.insufficientGas));
      expect(sdkError.fallbackMessage, contains('custody balance has'));
    });

    test('maps GasFree activation shortfall with the activation fee', () {
      const error = GaslessWithdrawException(
        type: GaslessWithdrawErrorType.insufficientGasFreeBalanceForActivation,
        errorData: {
          'coin': 'USDT-TRC20',
          'available': '2',
          'required': '8',
          'activation_fee': '1.5',
        },
      );
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.insufficientFunds);
      expect(sdkError.category, SdkErrorCategory.funds);
      expect(
        sdkError.messageKey,
        'withdrawGaslessInsufficientGasFreeBalanceForActivation',
      );
      expect(sdkError.messageArgs, [
        '',
        '2',
        'USDT-TRC20',
        '8',
        'USDT-TRC20',
        '1.5',
        'USDT-TRC20',
        'USDT-TRC20',
      ]);
      expect(sdkError.retryable, isFalse);
      // The technical detail (folded into the fallback) keeps the full
      // activation fee without inventing a provider-address echo.
      expect(sdkError.fallbackMessage, contains('activation fee 1.5'));
      expect(sdkError.fallbackMessage, isNot(contains('TPRN')));
    });

    for (final entry in const {
      GaslessWithdrawErrorType.unavailable: (
        GaslessTransferErrorCode.providerUnavailable,
        true,
      ),
      GaslessWithdrawErrorType.pendingTransfer: (
        GaslessTransferErrorCode.pendingTransfer,
        true,
      ),
      GaslessWithdrawErrorType.maxFeeExceeded: (
        GaslessTransferErrorCode.maxFeeExceeded,
        true,
      ),
      GaslessWithdrawErrorType.providerRejected: (
        GaslessTransferErrorCode.relayRejected,
        false,
      ),
      GaslessWithdrawErrorType.invalidProviderResponse: (
        GaslessTransferErrorCode.responseMismatch,
        false,
      ),
      GaslessWithdrawErrorType.traceNotFound: (
        GaslessTransferErrorCode.traceInvalid,
        false,
      ),
      GaslessWithdrawErrorType.quoteExpired: (
        GaslessTransferErrorCode.authorizationExpired,
        true,
      ),
      GaslessWithdrawErrorType.insufficientGasFreeBalance: (
        GaslessTransferErrorCode.relayRejected,
        false,
      ),
      GaslessWithdrawErrorType.insufficientGasFreeBalanceForActivation: (
        GaslessTransferErrorCode.relayRejected,
        false,
      ),
    }.entries) {
      test('maps exact GasFree endpoint ${entry.key.wireValue}', () {
        final sdkError = mapper.map(
          GaslessWithdrawException(
            type: entry.key,
            errorData: const {
              'coin': 'USDT-TRC20',
              'available': '1',
              'required': '2',
              'activation_fee': '0.5',
            },
          ),
        );

        expect(sdkError.context?.extra['gaslessCode'], entry.value.$1.name);
        expect(sdkError.retryable, entry.value.$2);
        expect(
          sdkError.source,
          isA<GaslessTransferException>()
              .having((error) => error.code, 'code', entry.value.$1)
              .having(
                (error) => error.stage,
                'stage',
                GaslessTransferStage.preview,
              ),
        );
      });
    }

    test('maps GasFree maximum-fee failures to dedicated copy', () {
      final sdkError = mapper.map(
        const GaslessWithdrawException(
          type: GaslessWithdrawErrorType.maxFeeExceeded,
        ),
      );

      expect(sdkError.messageKey, 'sdk_errors.gasless_max_fee_exceeded');
      expect(
        sdkError.fallbackMessage,
        'The GasFree quote exceeds the requested maximum fee',
      );
    });

    test('maps web3 timeout to network timeout', () {
      const error = Web3RpcErrorTimeoutException('timeout');
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.timeout);
      expect(sdkError.category, SdkErrorCategory.network);
      expect(sdkError.messageKey, 'sdk_errors.timeout');
    });

    test('maps withdraw no such coin with coin arg', () {
      const error = WithdrawErrorNoSuchCoinException(coin: 'KMD');
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.assetNotActivated);
      expect(sdkError.category, SdkErrorCategory.activation);
      expect(sdkError.messageKey, 'withdrawNoSuchCoinError');
      expect(sdkError.messageArgs, ['KMD']);
    });

    test('maps unsupported errors by exception class name heuristics', () {
      const error = GetFeeEstimationRequestErrorCoinNotSupportedException();
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.notSupported);
      expect(sdkError.category, SdkErrorCategory.unsupported);
      expect(sdkError.messageKey, 'sdk_errors.not_supported');
    });

    test('maps auth incorrect password to invalid credentials', () {
      final error = AuthException(
        'Incorrect wallet password',
        type: AuthExceptionType.incorrectPassword,
      );
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.authInvalidCredentials);
      expect(sdkError.category, SdkErrorCategory.auth);
      expect(sdkError.messageKey, 'sdk_errors.auth_invalid_credentials');
    });
  });
}
