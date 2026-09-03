import 'package:komodo_defi_types/komodo_defi_types.dart';

class SingleAddressStrategy extends PubkeyStrategy {
  SingleAddressStrategy();

  @override
  bool get supportsMultipleAddresses => false;

  @override
  Future<AssetPubkeys> getPubkeys(AssetId assetId, ApiClient client) async {
    final balanceInfo = await client.rpc.wallet.myBalance(coin: assetId.id);

    return AssetPubkeys(
      assetId: assetId,
      keys: [
        PubkeyInfo(
          address: balanceInfo.address,
          balance: balanceInfo.balance,
          derivationPath: null,
          chain: null,
          coinTicker: assetId.id,
          gasfreeAddress: balanceInfo.gasfreeAddress,
        ),
      ],
      availableAddressesCount: 0,
      syncStatus: SyncStatusEnum.success,
    );
  }

  @override
  bool protocolSupported(ProtocolClass protocol) {
    // All protocols are supported, but coins capable of HD/multi-address
    // should use the ContextPrivKeyHDWalletStrategy or TrezorHDWalletStrategy
    // instead if launched in HD mode. This strategy has to be used for HD
    // coins if launched in non-HD mode.
    return true;
  }

  @override
  Future<PubkeyInfo> getNewAddress(AssetId _, ApiClient __) async {
    throw UnsupportedError(
      'Single address coins do not support generating new addresses',
    );
  }

  @override
  Stream<NewAddressState> getNewAddressStream(
    AssetId assetId,
    ApiClient client,
  ) async* {
    yield NewAddressState.error(
      'Single address coins do not support generating new addresses',
    );
  }

  @override
  Future<void> scanForNewAddresses(AssetId _, ApiClient __) async {
    // No-op for single address coins
  }
}
