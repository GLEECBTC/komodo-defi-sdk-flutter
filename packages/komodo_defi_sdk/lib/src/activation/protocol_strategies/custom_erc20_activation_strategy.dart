import 'dart:convert';
import 'dart:developer' show log;

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Activation strategy for custom ERC20 tokens. This strategy is used to
/// activate tokens that are not part of the live coins configuration.
class CustomErc20ActivationStrategy extends ProtocolActivationStrategy {
  const CustomErc20ActivationStrategy(super.client);

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
  bool get supportsCustomTokenActivation => true;

  @override
  bool get supportsBatchActivation => true;

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    yield ActivationProgress(
      status: 'Activating ${asset.id.name}...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 2,
        additionalInfo: {
          'assetType': 'token',
          'protocol': asset.protocol.subClass.formatted,
        },
      ),
    );

    try {
      final protocolData = asset.protocol.config.valueOrNull<JsonMap>(
        'protocol',
        'protocol_data',
      );
      if (protocolData == null) {
        throw StateError('Protocol data is missing from custom token config');
      }

      final activationParams = Erc20ActivationParams.fromJsonConfig(
        asset.protocol.config,
      );
      final platform = protocolData.value<String>('platform');
      final contractAddress = protocolData.value<String>('contract_address');
      
      // Debug logging for custom ERC20 token activation
      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[RPC] Activating custom ERC20 token: ${asset.id.id}',
          name: 'CustomErc20ActivationStrategy',
        );
        log(
          '[RPC] Activation parameters: ${jsonEncode({
            'ticker': asset.id.id,
            'protocol': asset.protocol.subClass.formatted,
            'platform': platform,
            'contract_address': contractAddress,
            'activation_params': activationParams.toRpcParams(),
          })}',
          name: 'CustomErc20ActivationStrategy',
        );
      }

      await client.rpc.erc20.enableCustomErc20Token(
        ticker: asset.id.id,
        activationParams: activationParams,
        platform: platform,
        contractAddress: contractAddress,
      );
      
      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[RPC] Successfully activated custom ERC20 token: ${asset.id.id}',
          name: 'CustomErc20ActivationStrategy',
        );
      }

      yield ActivationProgress.success(
        details: ActivationProgressDetails(
          currentStep: ActivationStep.complete,
          stepCount: 2,
          additionalInfo: {
            'activatedChain': asset.id.name,
            'activationTime': DateTime.now().toIso8601String(),
            'childCount': children?.length ?? 0,
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
          stepCount: 2,
          errorCode: 'ERC20_ACTIVATION_ERROR',
          errorDetails: e.toString(),
          stackTrace: stack.toString(),
        ),
      );
    }
  }
}
