import 'package:komodo_defi_rpc_methods/src/models/error_response.dart';
import 'package:komodo_defi_rpc_methods/src/models/mm2_rpc_exceptions.dart';

/// Represents a user-friendly error message with localization support.
///
/// Contains both a locale key for translation lookup and a static English
/// fallback message for when translations are unavailable.
class KdfErrorMessage {
  const KdfErrorMessage({
    required this.localeKey,
    required this.fallbackMessage,
  });

  /// Locale key for translation lookup (e.g., 'kdfErrorNotSufficientBalance').
  ///
  /// Apps using localization can use this key to look up translated messages.
  final String localeKey;

  /// Static English message to use when translation is unavailable.
  ///
  /// This ensures users always see a human-readable message even without
  /// proper localization setup.
  final String fallbackMessage;

  @override
  String toString() => fallbackMessage;
}

/// Provides user-friendly error messages for KDF exceptions.
///
/// This class maps technical API error types to human-readable messages,
/// abstracting away API-specific knowledge from developers.
///
/// ## Usage
///
/// ```dart
/// try {
///   await withdraw(...);
/// } on MmRpcException catch (e) {
///   final msg = KdfErrorMessages.forException(e);
///   if (msg != null) {
///     // Use locale key for translation, fallback for default
///     showError(translate(msg.localeKey) ?? msg.fallbackMessage);
///   } else {
///     // Unknown error type - use technical message
///     showError(e.message ?? 'An unexpected error occurred');
///   }
/// }
/// ```
///
/// ## Simpler Usage with Extension
///
/// ```dart
/// try {
///   await withdraw(...);
/// } on MmRpcException catch (e) {
///   showError(e.displayMessage); // Always returns a user-friendly message
/// }
/// ```
abstract final class KdfErrorMessages {
  KdfErrorMessages._();

  /// Returns a user-friendly message for the given exception.
  ///
  /// Returns `null` if no mapping exists for the exception's error type.
  static KdfErrorMessage? forException(MmRpcException exception) {
    return _errorMessages[exception.errorType];
  }

  /// Returns a user-friendly message for the given error type string.
  ///
  /// This is useful when working with [GeneralErrorResponse] or raw error
  /// data. Returns `null` if no mapping exists for the error type.
  static KdfErrorMessage? forErrorType(String? errorType) {
    if (errorType == null) return null;
    return _errorMessages[errorType];
  }

  /// Returns all known error types that have user-friendly messages.
  static Iterable<String> get mappedErrorTypes => _errorMessages.keys;

  /// Default message for unknown errors.
  static const defaultError = KdfErrorMessage(
    localeKey: 'kdfErrorGeneric',
    fallbackMessage: 'An unexpected error occurred. Please try again.',
  );

  // ---------------------------------------------------------------------------
  // Error Message Mappings
  // ---------------------------------------------------------------------------
  // Organized by category for maintainability. New error types should be added
  // to the appropriate category section.

  static const _errorMessages = <String, KdfErrorMessage>{
    // -------------------------------------------------------------------------
    // Balance & Funds Errors
    // -------------------------------------------------------------------------
    'NotSufficientBalance': KdfErrorMessage(
      localeKey: 'kdfErrorNotSufficientBalance',
      fallbackMessage: 'Insufficient balance for this transaction.',
    ),
    'NotSufficientPlatformBalanceForFee': KdfErrorMessage(
      localeKey: 'kdfErrorNotSufficientPlatformBalanceForFee',
      fallbackMessage: 'Insufficient balance to pay network fees.',
    ),
    'ZeroBalanceToWithdrawMax': KdfErrorMessage(
      localeKey: 'kdfErrorZeroBalanceToWithdrawMax',
      fallbackMessage: 'Cannot withdraw: your balance is zero.',
    ),
    'AmountTooLow': KdfErrorMessage(
      localeKey: 'kdfErrorAmountTooLow',
      fallbackMessage: 'The amount is too low for this transaction.',
    ),
    'NotEnoughNftsAmount': KdfErrorMessage(
      localeKey: 'kdfErrorNotEnoughNftsAmount',
      fallbackMessage: 'You do not have enough NFTs for this transaction.',
    ),

    // -------------------------------------------------------------------------
    // Address Errors
    // -------------------------------------------------------------------------
    'InvalidAddress': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidAddress',
      fallbackMessage: 'The provided address is invalid.',
    ),
    'FromAddressNotFound': KdfErrorMessage(
      localeKey: 'kdfErrorFromAddressNotFound',
      fallbackMessage: 'Source address not found.',
    ),
    'UnexpectedFromAddress': KdfErrorMessage(
      localeKey: 'kdfErrorUnexpectedFromAddress',
      fallbackMessage: 'Unexpected source address.',
    ),
    'MyAddressNotNftOwner': KdfErrorMessage(
      localeKey: 'kdfErrorMyAddressNotNftOwner',
      fallbackMessage: 'You are not the owner of this NFT.',
    ),

    // -------------------------------------------------------------------------
    // Coin & Asset Errors
    // -------------------------------------------------------------------------
    'NoSuchCoin': KdfErrorMessage(
      localeKey: 'kdfErrorNoSuchCoin',
      fallbackMessage: 'Asset not found or not activated.',
    ),
    'CoinNotFound': KdfErrorMessage(
      localeKey: 'kdfErrorCoinNotFound',
      fallbackMessage: 'Asset not found.',
    ),
    'CoinNotSupported': KdfErrorMessage(
      localeKey: 'kdfErrorCoinNotSupported',
      fallbackMessage: 'This asset is not supported.',
    ),
    'CoinIsNotActive': KdfErrorMessage(
      localeKey: 'kdfErrorCoinIsNotActive',
      fallbackMessage: 'Please activate the asset first.',
    ),
    'CoinDoesntSupportInitWithdraw': KdfErrorMessage(
      localeKey: 'kdfErrorCoinDoesntSupportWithdraw',
      fallbackMessage: 'This asset does not support withdrawals.',
    ),
    'CoinDoesntSupportNftWithdraw': KdfErrorMessage(
      localeKey: 'kdfErrorCoinDoesntSupportNftWithdraw',
      fallbackMessage: 'This asset does not support NFT withdrawals.',
    ),
    'NftProtocolNotSupported': KdfErrorMessage(
      localeKey: 'kdfErrorNftProtocolNotSupported',
      fallbackMessage: 'NFT protocol is not supported for this asset.',
    ),
    'ContractTypeDoesntSupportNftWithdrawing': KdfErrorMessage(
      localeKey: 'kdfErrorContractTypeDoesntSupportNft',
      fallbackMessage: 'This contract type does not support NFT withdrawals.',
    ),

    // -------------------------------------------------------------------------
    // Network & Transport Errors
    // -------------------------------------------------------------------------
    'Transport': KdfErrorMessage(
      localeKey: 'kdfErrorTransport',
      fallbackMessage: 'Network error. Please check your connection.',
    ),
    'Timeout': KdfErrorMessage(
      localeKey: 'kdfErrorTimeout',
      fallbackMessage: 'Request timed out. Please try again.',
    ),
    'TaskTimedOut': KdfErrorMessage(
      localeKey: 'kdfErrorTaskTimedOut',
      fallbackMessage: 'Operation timed out. Please try again.',
    ),
    'InvalidResponse': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidResponse',
      fallbackMessage: 'Received an invalid response from the server.',
    ),
    'UnreachableNodes': KdfErrorMessage(
      localeKey: 'kdfErrorUnreachableNodes',
      fallbackMessage: 'Unable to connect to network nodes.',
    ),
    'AtLeastOneNodeRequired': KdfErrorMessage(
      localeKey: 'kdfErrorAtLeastOneNodeRequired',
      fallbackMessage: 'At least one network node is required.',
    ),
    'ClientConnectionFailed': KdfErrorMessage(
      localeKey: 'kdfErrorClientConnectionFailed',
      fallbackMessage: 'Failed to connect to the server.',
    ),
    'ConnectToNodeError': KdfErrorMessage(
      localeKey: 'kdfErrorConnectToNodeError',
      fallbackMessage: 'Failed to connect to network node.',
    ),

    // -------------------------------------------------------------------------
    // Activation Errors
    // -------------------------------------------------------------------------
    'ActivationFailed': KdfErrorMessage(
      localeKey: 'kdfErrorActivationFailed',
      fallbackMessage: 'Failed to activate the asset.',
    ),
    'CouldNotFetchBalance': KdfErrorMessage(
      localeKey: 'kdfErrorCouldNotFetchBalance',
      fallbackMessage: 'Could not fetch balance. Please try again.',
    ),
    'UnsupportedChain': KdfErrorMessage(
      localeKey: 'kdfErrorUnsupportedChain',
      fallbackMessage: 'This blockchain is not supported.',
    ),
    'ChainIdNotSet': KdfErrorMessage(
      localeKey: 'kdfErrorChainIdNotSet',
      fallbackMessage: 'Chain ID is not configured.',
    ),
    'NoChainIdSet': KdfErrorMessage(
      localeKey: 'kdfErrorNoChainIdSet',
      fallbackMessage: 'Chain ID is not set.',
    ),

    // -------------------------------------------------------------------------
    // Fee Errors
    // -------------------------------------------------------------------------
    'InvalidFeePolicy': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidFeePolicy',
      fallbackMessage: 'Invalid fee configuration.',
    ),
    'InvalidFee': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidFee',
      fallbackMessage: 'The specified fee is invalid.',
    ),
    'InvalidGasApiConfig': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidGasApiConfig',
      fallbackMessage: 'Invalid gas API configuration.',
    ),

    // -------------------------------------------------------------------------
    // Account Errors
    // -------------------------------------------------------------------------
    'NameTooLong': KdfErrorMessage(
      localeKey: 'kdfErrorNameTooLong',
      fallbackMessage: 'The name is too long.',
    ),
    'DescriptionTooLong': KdfErrorMessage(
      localeKey: 'kdfErrorDescriptionTooLong',
      fallbackMessage: 'The description is too long.',
    ),
    'NoSuchAccount': KdfErrorMessage(
      localeKey: 'kdfErrorNoSuchAccount',
      fallbackMessage: 'Account not found.',
    ),
    'NoEnabledAccount': KdfErrorMessage(
      localeKey: 'kdfErrorNoEnabledAccount',
      fallbackMessage: 'No account is enabled.',
    ),
    'AccountExistsAlready': KdfErrorMessage(
      localeKey: 'kdfErrorAccountExistsAlready',
      fallbackMessage: 'An account with this name already exists.',
    ),
    'UnknownAccount': KdfErrorMessage(
      localeKey: 'kdfErrorUnknownAccount',
      fallbackMessage: 'Unknown account.',
    ),
    'ErrorLoadingAccount': KdfErrorMessage(
      localeKey: 'kdfErrorLoadingAccount',
      fallbackMessage: 'Failed to load account.',
    ),
    'ErrorSavingAccount': KdfErrorMessage(
      localeKey: 'kdfErrorSavingAccount',
      fallbackMessage: 'Failed to save account.',
    ),

    // -------------------------------------------------------------------------
    // Hardware Wallet Errors
    // -------------------------------------------------------------------------
    'HwError': KdfErrorMessage(
      localeKey: 'kdfErrorHwError',
      fallbackMessage: 'Hardware wallet error occurred.',
    ),
    'HwContextNotInitialized': KdfErrorMessage(
      localeKey: 'kdfErrorHwContextNotInitialized',
      fallbackMessage: 'Hardware wallet is not initialized.',
    ),
    'CoinDoesntSupportTrezor': KdfErrorMessage(
      localeKey: 'kdfErrorCoinDoesntSupportTrezor',
      fallbackMessage: 'This asset is not supported on Trezor.',
    ),
    'InvalidHardwareWalletCall': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidHardwareWalletCall',
      fallbackMessage: 'Invalid hardware wallet operation.',
    ),

    // -------------------------------------------------------------------------
    // Swap & Trading Errors
    // -------------------------------------------------------------------------
    'NotSupported': KdfErrorMessage(
      localeKey: 'kdfErrorNotSupported',
      fallbackMessage: 'This operation is not supported.',
    ),
    'VolumeTooLow': KdfErrorMessage(
      localeKey: 'kdfErrorVolumeTooLow',
      fallbackMessage: 'Trade volume is too low.',
    ),
    'MyRecentSwapsError': KdfErrorMessage(
      localeKey: 'kdfErrorMyRecentSwapsError',
      fallbackMessage: 'Failed to fetch recent swaps.',
    ),
    'SwapInfoNotAvailable': KdfErrorMessage(
      localeKey: 'kdfErrorSwapInfoNotAvailable',
      fallbackMessage: 'Swap information is not available.',
    ),

    // -------------------------------------------------------------------------
    // Authentication & Wallet Errors
    // -------------------------------------------------------------------------
    'InvalidRequest': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidRequest',
      fallbackMessage: 'Invalid request.',
    ),
    'InvalidPayload': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidPayload',
      fallbackMessage: 'Invalid data provided.',
    ),
    'InvalidMemo': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidMemo',
      fallbackMessage: 'Invalid memo/tag provided.',
    ),
    'InvalidConfiguration': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidConfiguration',
      fallbackMessage: 'Invalid configuration.',
    ),
    'PrivKeyPolicyNotAllowed': KdfErrorMessage(
      localeKey: 'kdfErrorPrivKeyPolicyNotAllowed',
      fallbackMessage:
          'This operation is not allowed with the current wallet type.',
    ),
    'UnexpectedDerivationMethod': KdfErrorMessage(
      localeKey: 'kdfErrorUnexpectedDerivationMethod',
      fallbackMessage: 'Unexpected wallet derivation method.',
    ),
    'ActionNotAllowed': KdfErrorMessage(
      localeKey: 'kdfErrorActionNotAllowed',
      fallbackMessage: 'This action is not allowed.',
    ),
    'UnexpectedUserAction': KdfErrorMessage(
      localeKey: 'kdfErrorUnexpectedUserAction',
      fallbackMessage: 'Unexpected user action.',
    ),
    'BroadcastExpected': KdfErrorMessage(
      localeKey: 'kdfErrorBroadcastExpected',
      fallbackMessage: 'Transaction broadcast was expected.',
    ),

    // -------------------------------------------------------------------------
    // Database & Storage Errors
    // -------------------------------------------------------------------------
    'DbError': KdfErrorMessage(
      localeKey: 'kdfErrorDbError',
      fallbackMessage: 'Database error occurred.',
    ),
    'WalletStorageError': KdfErrorMessage(
      localeKey: 'kdfErrorWalletStorageError',
      fallbackMessage: 'Wallet storage error occurred.',
    ),
    'HDWalletStorageError': KdfErrorMessage(
      localeKey: 'kdfErrorHDWalletStorageError',
      fallbackMessage: 'HD wallet storage error occurred.',
    ),

    // -------------------------------------------------------------------------
    // Internal & System Errors
    // -------------------------------------------------------------------------
    'Internal': KdfErrorMessage(
      localeKey: 'kdfErrorInternal',
      fallbackMessage: 'An internal error occurred.',
    ),
    'InternalError': KdfErrorMessage(
      localeKey: 'kdfErrorInternalError',
      fallbackMessage: 'An internal error occurred.',
    ),
    'UnsupportedError': KdfErrorMessage(
      localeKey: 'kdfErrorUnsupportedError',
      fallbackMessage: 'Unsupported operation.',
    ),
    'SigningError': KdfErrorMessage(
      localeKey: 'kdfErrorSigningError',
      fallbackMessage: 'Failed to sign the transaction.',
    ),
    'SystemTimeError': KdfErrorMessage(
      localeKey: 'kdfErrorSystemTimeError',
      fallbackMessage: 'System time error. Please check your device time.',
    ),
    'NumConversError': KdfErrorMessage(
      localeKey: 'kdfErrorNumConversError',
      fallbackMessage: 'Number conversion error.',
    ),
    'IOError': KdfErrorMessage(
      localeKey: 'kdfErrorIOError',
      fallbackMessage: 'Input/output error occurred.',
    ),
    'RpcError': KdfErrorMessage(
      localeKey: 'kdfErrorRpcError',
      fallbackMessage: 'RPC communication error.',
    ),
    'RpcTaskError': KdfErrorMessage(
      localeKey: 'kdfErrorRpcTaskError',
      fallbackMessage: 'RPC task error.',
    ),

    // -------------------------------------------------------------------------
    // Address Derivation Errors
    // -------------------------------------------------------------------------
    'InvalidBip44Chain': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidBip44Chain',
      fallbackMessage: 'Invalid BIP44 derivation chain.',
    ),
    'Bip32Error': KdfErrorMessage(
      localeKey: 'kdfErrorBip32Error',
      fallbackMessage: 'Key derivation error.',
    ),
    'InvalidPath': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidPath',
      fallbackMessage: 'Invalid derivation path.',
    ),
    'InvalidPathToAddress': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidPathToAddress',
      fallbackMessage: 'Invalid path to address.',
    ),
    'ErrorDeserializingDerivationPath': KdfErrorMessage(
      localeKey: 'kdfErrorDeserializingDerivationPath',
      fallbackMessage: 'Failed to parse derivation path.',
    ),

    // -------------------------------------------------------------------------
    // Contract & Token Errors
    // -------------------------------------------------------------------------
    'InvalidSwapContractAddr': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidSwapContractAddr',
      fallbackMessage: 'Invalid swap contract address.',
    ),
    'InvalidFallbackSwapContract': KdfErrorMessage(
      localeKey: 'kdfErrorInvalidFallbackSwapContract',
      fallbackMessage: 'Invalid fallback swap contract.',
    ),
    'CustomTokenError': KdfErrorMessage(
      localeKey: 'kdfErrorCustomTokenError',
      fallbackMessage: 'Custom token error.',
    ),
    'GetNftInfoError': KdfErrorMessage(
      localeKey: 'kdfErrorGetNftInfoError',
      fallbackMessage: 'Failed to get NFT information.',
    ),

    // -------------------------------------------------------------------------
    // External Service Errors
    // -------------------------------------------------------------------------
    'MetamaskError': KdfErrorMessage(
      localeKey: 'kdfErrorMetamaskError',
      fallbackMessage: 'MetaMask error occurred.',
    ),
    'WalletConnectError': KdfErrorMessage(
      localeKey: 'kdfErrorWalletConnectError',
      fallbackMessage: 'WalletConnect error occurred.',
    ),
  };
}

/// Extension on [MmRpcException] providing convenient access to user-friendly
/// error messages.
///
/// This allows developers to get user-friendly messages without needing to
/// understand the underlying error type system.
///
/// ## Example
///
/// ```dart
/// try {
///   await withdraw(...);
/// } on MmRpcException catch (e) {
///   // Always returns a human-readable message
///   showErrorDialog(e.displayMessage);
///
///   // Access structured message info if needed
///   final msg = e.userMessage;
///   if (msg != null) {
///     analytics.logError(msg.localeKey);
///   }
/// }
/// ```
extension MmRpcExceptionUserMessage on MmRpcException {
  /// Returns user-friendly message info for this exception.
  ///
  /// Returns `null` if no mapping exists for this error type. In that case,
  /// use [displayMessage] which always returns a usable message.
  KdfErrorMessage? get userMessage => KdfErrorMessages.forException(this);

  /// Returns a user-friendly display message for this exception.
  ///
  /// This method always returns a usable message:
  /// 1. If a user-friendly mapping exists, returns the fallback message
  /// 2. Otherwise, returns the technical error message
  /// 3. As a last resort, returns a generic error message
  String get displayMessage =>
      userMessage?.fallbackMessage ??
      message ??
      KdfErrorMessages.defaultError.fallbackMessage;

  /// Returns the locale key for this exception if a mapping exists.
  ///
  /// Returns `null` if no mapping exists. Apps can use this to look up
  /// translated messages in their localization system.
  String? get localeKey => userMessage?.localeKey;
}
