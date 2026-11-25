import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/solana_activation_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Manager for cryptographic message signing and verification operations.
///
/// This class provides methods to sign messages using an asset's private key
/// and verify messages that have been signed with a private key.
class MessageSigningManager {
  /// Creates a new message signing manager.
  ///
  /// Requires an [ApiClient] to communicate with the Komodo DeFi Framework.
  MessageSigningManager(
    this._client, {
    SolanaCapabilities solanaCapabilities = const SolanaCapabilities(),
    KomodoDefiLocalAuth? auth,
  }) : _solanaCapabilities = solanaCapabilities,
       _auth = auth;

  final KomodoDefiLocalAuth? _auth;

  final SolanaCapabilities _solanaCapabilities;

  final ApiClient _client;

  /// Signs a message with the private key of the specified asset.
  ///
  /// This method creates a cryptographic signature that can be used to prove
  /// ownership of an address.
  ///
  /// Parameters:
  /// - [asset]: The asset to use for signing.
  /// - [addressInfo]: The pubkey/address info to sign with. Must be from the
  ///   asset's pubkeys.
  /// - [message]: The message to sign.
  ///
  /// Returns:
  /// A [Future] that completes with the signature as a string.
  ///
  /// Throws:
  /// - [Exception] if the signing operation fails for any reason.
  ///
  /// Example:
  /// ```dart
  /// final pubkeys = await sdk.pubkeys.getPubkeys(asset);
  /// final signature = await sdk.messageSigning.signMessage(
  ///   asset: asset,
  ///   addressInfo: pubkeys.keys.first,
  ///   message: 'Hello, world!',
  /// );
  /// ```
  Future<String> signMessage({
    required Asset asset,
    required PubkeyInfo addressInfo,
    required String message,
  }) async {
    SolanaActivationStrategy.ensureSupported(asset, _solanaCapabilities);
    final isSolana =
        asset.id.subClass == CoinSubClass.solana ||
        asset.id.subClass == CoinSubClass.solanaToken;
    AuthSessionContext? session;
    if (isSolana) {
      final auth = _auth;
      if (auth == null) {
        throw StateError(
          'Solana signing requires an authenticated SDK session',
        );
      }
      session = await auth.captureSessionContext();
      if (session.walletId.authOptions.privKeyPolicy !=
          const PrivateKeyPolicy.contextPrivKey()) {
        throw UnsupportedError('Solana signing requires an internal wallet');
      }
      auth.ensureSessionContextCurrent(session);
      final active = await _client.rpc.wallet.myBalance(coin: asset.id.id);
      auth.ensureSessionContextCurrent(session);
      if (active.coin != asset.id.id ||
          active.address.isEmpty ||
          active.address != addressInfo.address ||
          !addressInfo.balances.containsKey(asset.id.id)) {
        throw UnknownAddressException();
      }
    }
    // Convert PubkeyInfo derivation path to AddressPath if present
    AddressPath? addressPath;
    if (!isSolana && addressInfo.derivationPath != null) {
      addressPath = AddressPath.derivationPath(addressInfo.derivationPath!);
    }

    if (session != null) _auth!.ensureSessionContextCurrent(session);
    Future<SignMessageResponse> sign() => _client.rpc.utility.signMessage(
      coin: asset.id.id,
      message: message,
      addressPath: addressPath,
    );
    final signingSession = session;
    final response = await (signingSession == null
        ? sign()
        : RpcDispatchGuard.run(
            () => _auth!.ensureSessionContextCurrent(signingSession),
            () => _auth!.runWithSession(signingSession, sign),
            methods: const {'sign_message'},
          ));
    if (session != null) _auth!.ensureSessionContextCurrent(session);
    return response.signature;
  }

  /// Verifies a cryptographic signature for a message.
  ///
  /// This method checks if a signature is valid for the given message and was
  /// created by the private key corresponding to the specified address.
  ///
  /// Parameters:
  /// - [asset]: The asset to use for verification.
  /// - [message]: The original message that was signed.
  /// - [signature]: The signature to verify.
  /// - [address]: The address that supposedly signed the message.
  ///
  /// Returns:
  /// A [Future] that completes with a boolean indicating whether the signature
  /// is valid.
  ///
  /// Throws:
  /// - [Exception] if the verification operation fails for any reason.
  ///
  /// Example:
  /// ```dart
  /// final isValid = await sdk.messageSigning.verifyMessage(
  ///   asset: asset,
  ///   message: 'Hello, world!',
  ///   signature: 'H8Jk+O21IJ0ob3p...',
  ///   address: 'RXNtAyDSsY3DS3VxTpJegzoHU9bUX54j56',
  /// );
  /// ```
  Future<bool> verifyMessage({
    required Asset asset,
    required String message,
    required String signature,
    required String address,
  }) async {
    final response = await _client.rpc.utility.verifyMessage(
      coin: asset.id.id,
      message: message,
      signature: signature,
      address: address,
    );
    return response.isValid;
  }
}

/// Exception thrown when an unknown address is used for signing.
class UnknownAddressException implements Exception {
  /// Exception thrown when an unknown address is used for signing.

  UnknownAddressException([
    this.message =
        'Unknown address. The specified address is not associated with the '
        'coin. Ensure the coin is enabled and the address is generated.',
  ]);

  /// The error message associated with the exception.
  final String message;

  @override
  String toString() => 'UnknownAddressException: $message';
}
