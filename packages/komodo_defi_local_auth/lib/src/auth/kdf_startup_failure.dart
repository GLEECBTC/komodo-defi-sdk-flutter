import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The [AuthException] for a KDF start that returned [result].
///
/// KDF reports a wallet password that cannot decrypt the stored seed only as a
/// generic [KdfStartupResult.initError]
/// (https://github.com/GLEECBTC/komodo-defi-framework/issues/2383), so that
/// result means an incorrect password only when one was sent.
AuthException authExceptionForKdfStartup(
  KdfStartupResult result, {
  required bool walletPasswordSent,
}) => switch (result) {
  KdfStartupResult.initError when walletPasswordSent => AuthException(
    'Incorrect password or invalid seed',
    type: AuthExceptionType.incorrectPassword,
  ),
  KdfStartupResult.initError => AuthException(
    'Wallet process failed to initialize',
    type: AuthExceptionType.walletStartFailed,
    details: {'kdf_error': result.name},
  ),
  KdfStartupResult.alreadyRunning => AuthException(
    'Wallet is already running',
    type: AuthExceptionType.walletAlreadyRunning,
  ),
  KdfStartupResult.configError => AuthException(
    'Invalid wallet configuration',
    type: AuthExceptionType.walletStartFailed,
    details: {'kdf_error': result.name},
  ),
  KdfStartupResult.invalidParams => AuthException(
    'Invalid parameters provided to wallet',
    type: AuthExceptionType.walletStartFailed,
    details: {'kdf_error': result.name},
  ),
  KdfStartupResult.spawnError => AuthException(
    'Failed to start wallet process',
    type: AuthExceptionType.walletStartFailed,
    details: {'kdf_error': result.name},
  ),
  KdfStartupResult.unknownError => AuthException(
    'Wallet process failed to start for an unknown reason',
    type: AuthExceptionType.walletStartFailed,
    details: {'kdf_error': result.name},
  ),
  KdfStartupResult.ok => throw ArgumentError.value(
    result,
    'result',
    'Not a startup failure',
  ),
};

/// Whether [KdfStartupConfig.encodeStartParams] sends [config]'s wallet
/// password to KDF.
bool sendsWalletPassword(KdfStartupConfig config) =>
    config.walletPassword?.isNotEmpty ?? false;
