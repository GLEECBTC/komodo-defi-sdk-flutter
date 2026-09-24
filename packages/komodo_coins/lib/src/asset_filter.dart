import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Strategy interface for filtering assets based on coin configuration.
abstract class AssetFilterStrategy extends Equatable {
  const AssetFilterStrategy(this.strategyId);

  /// A unique id for the strategy used for comparison and caching.
  final String strategyId;

  /// Returns `true` if the asset should be included.
  bool shouldInclude(Asset asset, JsonMap coinConfig);

  /// Factory method to create a strategy instance from a strategy ID.
  /// Used for reconstructing strategies from cached strategy IDs.
  static AssetFilterStrategy? fromStrategyId(String strategyId) {
    switch (strategyId) {
      case 'none':
        return const NoAssetFilterStrategy();
      case 'trezor':
        // Using default hiddenAssets - in practice, this should work for most cases
        return const TrezorAssetFilterStrategy();
      case 'utxo':
        return const UtxoAssetFilterStrategy();
      case 'evm':
        return const EvmAssetFilterStrategy();
      default:
        return null;
    }
  }

  @override
  List<Object?> get props => [strategyId];
}

/// Default strategy that includes all assets.
class NoAssetFilterStrategy extends AssetFilterStrategy {
  const NoAssetFilterStrategy() : super('none');

  @override
  bool shouldInclude(Asset asset, JsonMap coinConfig) => true;
}

/// Filters assets that are not currently supported on Trezor.
/// This includes assets that are not UTXO-based or EVM-based tokens.
/// ETH, AVAX, BNB, FTM, etc. are excluded as they currently fail to
/// activate on Trezor.
/// ERC20, Arbitrum, and MATIC explicitly do not support Trezor via KDF
/// at this time, so they are also excluded.
class TrezorAssetFilterStrategy extends AssetFilterStrategy {
  const TrezorAssetFilterStrategy({this.hiddenAssets = const {}})
    : super('trezor');

  final Set<String> hiddenAssets;

  @override
  bool shouldInclude(Asset asset, JsonMap coinConfig) {
    final subClass = asset.protocol.subClass;

    // AVAX, BNB, ETH, FTM, etc. currently fail to activate on Trezor,
    // so we exclude them from the Trezor asset list.
    final isProtocolSupported =
        subClass == CoinSubClass.utxo ||
        subClass == CoinSubClass.smartChain ||
        subClass == CoinSubClass.qrc20;

    final hasTrezorCoinField =
        coinConfig['trezor_coin'] is String &&
        (coinConfig['trezor_coin'] as String).isNotEmpty;
    final isExcludedAsset = hiddenAssets.contains(asset.id.id);

    return isProtocolSupported && hasTrezorCoinField && !isExcludedAsset;
  }
}

/// Filters out assets that are not UTXO-based chains.
class UtxoAssetFilterStrategy extends AssetFilterStrategy {
  const UtxoAssetFilterStrategy() : super('utxo');

  @override
  bool shouldInclude(Asset asset, JsonMap coinConfig) {
    final subClass = asset.protocol.subClass;
    return subClass == CoinSubClass.utxo || subClass == CoinSubClass.smartChain;
  }
}

/// Filters assets that are EVM-based tokens.
/// This includes various EVM-compatible chains like Ethereum, Binance, etc.
/// This strategy is necessary for external wallets like Metamask or
/// WalletConnect.
class EvmAssetFilterStrategy extends AssetFilterStrategy {
  const EvmAssetFilterStrategy() : super('evm');

  @override
  bool shouldInclude(Asset asset, JsonMap coinConfig) =>
      evmCoinSubClasses.contains(asset.protocol.subClass);
}
