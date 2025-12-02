import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Factory for creating the complete activation strategy stack
class ActivationStrategyFactory {
  /// Creates a complete activation strategy stack with all protocols
  /// and returns a [SmartAssetActivator] instance.
  /// [client] The [ApiClient] to use for RPC calls.
  /// [privKeyPolicy] The [PrivateKeyPolicy] to use for private key management.
  /// This is used for external wallet support. E.g. trezor, wallet connect, etc
  /// [configService] The [ActivationConfigService] for resolving activation configuration.
  /// [activatedAssetsCache] The [ActivatedAssetsCache] to use for checking activation status.
  static SmartAssetActivator createStrategy(
    ApiClient client,
    PrivateKeyPolicy privKeyPolicy,
    ActivationConfigService configService,
    ActivatedAssetsCache activatedAssetsCache,
  ) {
    return SmartAssetActivator(
      client,
      CompositeAssetActivator(client, [
        // BCH strategy needs to be before UTXO strategy to handle the special case
        // BchActivationStrategy(client),
        UtxoActivationStrategy(client, privKeyPolicy),
        EthTaskActivationStrategy(client, privKeyPolicy),
        EthWithTokensActivationStrategy(client, privKeyPolicy),
        Erc20ActivationStrategy(client, privKeyPolicy),
        // SlpActivationStrategy(client),
        // Tendermint strategies follow same pattern as ETH: task -> platform -> tokens
        TendermintTaskActivationStrategy(client, privKeyPolicy),
        TendermintWithTokensActivationStrategy(client, privKeyPolicy),
        TendermintTokenActivationStrategy(client, privKeyPolicy),
        QtumActivationStrategy(client, privKeyPolicy),
        SiaActivationStrategy(client),
        ZhtlcActivationStrategy(client, privKeyPolicy, configService),
        CustomErc20ActivationStrategy(client),
      ]),
      activatedAssetsCache,
    );
  }
}
