import 'dart:convert';
import 'dart:developer' show log;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart'
    show EtherscanProtocolHelper;
import 'package:komodo_defi_types/komodo_defi_types.dart';

class EthWithTokensActivationStrategy extends ProtocolActivationStrategy {
  const EthWithTokensActivationStrategy(super.client, this.privKeyPolicy);

  /// The private key management policy to use for this strategy.
  /// Used for external wallet support.
  final PrivateKeyPolicy privKeyPolicy;

  @override
  Set<CoinSubClass> get supportedProtocols => {
    CoinSubClass.erc20,
    CoinSubClass.bep20,
    CoinSubClass.ftm20,
    CoinSubClass.matic,
    CoinSubClass.avx20,
    CoinSubClass.hrc20,
    CoinSubClass.moonbeam,
    CoinSubClass.moonriver,
    CoinSubClass.ethereumClassic,
    CoinSubClass.ubiq,
    CoinSubClass.krc20,
    CoinSubClass.ewt,
    CoinSubClass.hecoChain,
    CoinSubClass.rskSmartBitcoin,
    CoinSubClass.arbitrum,
    CoinSubClass.base,
    CoinSubClass.grc20, 
  };

  @override
  bool get supportsBatchActivation => true;

  @override
  bool canHandle(Asset asset) {
    // Use eth-with-tokens for platform assets (not trezor)
    final isPlatformAsset = asset.id.parentId == null;
    return isPlatformAsset &&
        privKeyPolicy != const PrivateKeyPolicy.trezor() &&
        super.canHandle(asset);
  }

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    if (children?.isNotEmpty == true) {
      yield ActivationProgress(
        status:
            'Activating ${asset.id.name} with ${children!.length} tokens...',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.initialization,
          stepCount: 3,
          additionalInfo: {
            'assetType': 'platform',
            'protocol': asset.protocol.subClass.formatted,
            'tokenCount': children.length,
          },
        ),
      );
    } else {
      yield ActivationProgress(
        status: 'Activating ${asset.id.name}...',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.initialization,
          stepCount: 3,
          additionalInfo: {
            'assetType': 'platform',
            'protocol': asset.protocol.subClass.formatted,
          },
        ),
      );
    }

    try {
      yield ActivationProgress(
        status: 'Configuring platform activation...',
        progressPercentage: 33,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.processing,
          stepCount: 3,
          additionalInfo: {
            'method': 'enableEthWithTokens',
            'tokenCount': children?.length ?? 0,
          },
        ),
      );

      // Compute whether to enable tx_history at activation:
      // - If tx history streaming is supported by KDF, always true.
      // - Else, only true if the chosen history strategy requires KDF tx history.
      final txHistoryFlag = asset.supportsTxHistoryStreaming
          ? true
          : const EtherscanProtocolHelper().shouldEnableTransactionHistory(
              asset,
            );

      final activationParams =
          EthWithTokensActivationParams.fromJson(
            asset.protocol.config,
          ).copyWith(
            erc20Tokens:
                children?.map((e) => TokensRequest(ticker: e.id.id)).toList() ??
                [],
            txHistory: txHistoryFlag,
            privKeyPolicy: privKeyPolicy,
          );

      // Debug logging for ETH platform activation
      if (KdfLoggingConfig.verboseLogging) {
        log(
        '[RPC] Activating ETH platform: ${asset.id.id}',
        name: 'EthWithTokensActivationStrategy',
      );
      }
      if (KdfLoggingConfig.verboseLogging) {
        log(
        '[RPC] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'protocol': asset.protocol.subClass.formatted, 'token_count': children?.length ?? 0, 'tokens': children?.map((e) => e.id.id).toList() ?? [], 'activation_params': activationParams.toRpcParams(), 'priv_key_policy': privKeyPolicy.toJson()})}',
        name: 'EthWithTokensActivationStrategy',
      );
      }

      await client.rpc.erc20.enableEthWithTokens(
        ticker: asset.id.id,
        params: activationParams,
      );

      if (KdfLoggingConfig.verboseLogging) {
        log(
        '[RPC] Successfully activated ETH platform: ${asset.id.id} with ${children?.length ?? 0} tokens',
        name: 'EthWithTokensActivationStrategy',
      );
      }

      yield const ActivationProgress(
        status: 'Finalizing activation...',
        progressPercentage: 66,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.processing,
          stepCount: 3,
        ),
      );

      yield ActivationProgress.success(
        details: ActivationProgressDetails(
          currentStep: ActivationStep.complete,
          stepCount: 3,
          additionalInfo: {
            'activatedChain': asset.id.name,
            'activationTime': DateTime.now().toIso8601String(),
            'childCount': children?.length ?? 0,
            'method': 'enableEthWithTokens',
          },
        ),
      );
    } catch (e, stack) {
      yield ActivationProgress(
        status: 'Activation failed',
        errorMessage: e.toString(),
        isComplete: true,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.error,
          stepCount: 3,
          errorCode: 'ETH_WITH_TOKENS_ACTIVATION_ERROR',
          errorDetails: e.toString(),
          stackTrace: stack.toString(),
        ),
      );
    }
  }
}
