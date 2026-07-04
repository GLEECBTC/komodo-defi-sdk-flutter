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
      const error = GaslessWithdrawErrorInsufficientGasFreeBalanceException(
        coin: 'USDT-TRC20',
        gasfreeAddress: '',
        available: BigDecimal('0'),
        required: BigDecimal('8'),
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
      // Empty address must not leave a dangling 'address ' in the fallback.
      expect(sdkError.fallbackMessage, contains('Your GasFree address has'));
    });

    test('maps GasFree activation shortfall with the activation fee', () {
      const error =
          GaslessWithdrawErrorInsufficientGasFreeBalanceForActivationException(
            coin: 'USDT-TRC20',
            gasfreeAddress: 'TPRN9HuCCTUuEsw5DsPBM8CQGRq77Aey5g',
            available: BigDecimal('2'),
            required: BigDecimal('8'),
            activationFee: BigDecimal('1.5'),
          );
      final sdkError = mapper.map(error);

      expect(sdkError.code, SdkErrorCode.insufficientFunds);
      expect(sdkError.category, SdkErrorCategory.funds);
      expect(
        sdkError.messageKey,
        'withdrawGaslessInsufficientGasFreeBalanceForActivation',
      );
      expect(sdkError.messageArgs, [
        'TPRN9HuCCTUuEsw5DsPBM8CQGRq77Aey5g',
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
      // address and the activation fee.
      expect(sdkError.fallbackMessage, contains('activation fee 1.5'));
      expect(
        sdkError.fallbackMessage,
        contains('TPRN9HuCCTUuEsw5DsPBM8CQGRq77Aey5g'),
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
