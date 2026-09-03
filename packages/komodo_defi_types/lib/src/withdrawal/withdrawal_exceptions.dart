import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Exception thrown when withdrawal operations fail
class WithdrawalException implements Exception {
  WithdrawalException(this.message, this.code);

  final String message;
  final WithdrawalErrorCode code;

  @override
  String toString() => message;

  /// Maps error messages from the API to appropriate error codes
  static WithdrawalErrorCode mapErrorToCode(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('insufficient funds') ||
        errorLower.contains('not enough funds') ||
        errorLower.contains('not sufficient balance') ||
        (errorLower.contains('not enough') &&
            (errorLower.contains('withdraw') ||
                errorLower.contains('balance')))) {
      return WithdrawalErrorCode.insufficientFunds;
    }

    if (errorLower.contains('invalid address')) {
      return WithdrawalErrorCode.invalidAddress;
    }

    if (errorLower.contains('fee')) {
      return WithdrawalErrorCode.networkError;
    }

    return WithdrawalErrorCode.unknownError;
  }
}
