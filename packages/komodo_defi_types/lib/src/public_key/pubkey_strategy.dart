import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

// TODO: Refactor strategy consumption so that API client does not need to be
// passed in. See the activation strategy for an example of how this can
// be done.
/// Abstract interface for pubkey strategies
abstract class PubkeyStrategy {
  /// Get all pubkeys for an asset
  Future<AssetPubkeys> getPubkeys(AssetId assetId, ApiClient client);

  /// Get a new address for an asset if supported
  Future<PubkeyInfo> getNewAddress(AssetId assetId, ApiClient client);

  /// Streamed version of [getNewAddress] that emits progress updates
  Stream<NewAddressState> getNewAddressStream(
    AssetId assetId,
    ApiClient client,
  );

  /// Scan for any new addresses
  Future<void> scanForNewAddresses(AssetId assetId, ApiClient client);

  /// Check if this strategy supports the given protocol
  bool protocolSupported(ProtocolClass protocol);

  /// Whether this strategy supports multiple addresses per asset
  bool get supportsMultipleAddresses;
}

/// Factory to create appropriate strategy based on protocol and KDF user
class PubkeyStrategyFactory {
  /// [scanGapLimit] bounds `task::scan_for_new_addresses` only - not address
  /// creation. Omit it and the full BIP-44 gap is used. See [HdGapLimit].
  static PubkeyStrategy createStrategy(
    ProtocolClass protocol, {
    required KdfUser kdfUser,
    int? scanGapLimit,
  }) {
    final isHdWallet = kdfUser.isHd;

    if (!isHdWallet && protocol.requiresHdWallet) {
      throw UnsupportedProtocolException(
        'Protocol ${protocol.runtimeType} '
        'requires HD wallet but wallet is not in HD mode',
      );
    }

    if (isHdWallet && protocol.supportsMultipleAddresses) {
      // Select specific HD wallet strategy based on private key policy
      final privKeyPolicy = kdfUser.walletId.authOptions.privKeyPolicy;

      switch (privKeyPolicy) {
        case const PrivateKeyPolicy.trezor():
          return TrezorHDWalletStrategy(kdfUser: kdfUser);
        case const PrivateKeyPolicy.contextPrivKey():
          return ContextPrivKeyHDWalletStrategy(
            kdfUser: kdfUser,
            scanGapLimit: scanGapLimit ?? HdGapLimit.hardware,
          );
      }
    }

    return SingleAddressStrategy();
  }
}

extension AssetPubkeyStrategy on Asset {
  PubkeyStrategy pubkeyStrategy({required KdfUser kdfUser, int? scanGapLimit}) {
    return PubkeyStrategyFactory.createStrategy(
      protocol,
      scanGapLimit: scanGapLimit,
      kdfUser: kdfUser,
    );
  }
}
