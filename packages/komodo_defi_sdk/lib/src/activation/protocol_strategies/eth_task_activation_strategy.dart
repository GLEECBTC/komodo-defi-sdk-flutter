import 'dart:convert';
import 'dart:developer' show log;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart'
    show EtherscanProtocolHelper;
import 'package:komodo_defi_types/komodo_defi_types.dart';

class EthTaskActivationStrategy extends ProtocolActivationStrategy {
  const EthTaskActivationStrategy(super.client, this.privKeyPolicy);

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
    // Use task-based activation for Trezor private key policy
    return privKeyPolicy == const PrivateKeyPolicy.trezor() &&
        super.canHandle(asset);
  }

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    final protocol = asset.protocol as Erc20Protocol;

    yield ActivationProgress(
      status: 'Starting ${asset.id.name} activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 5,
        additionalInfo: {
          'chainType': protocol.subClass.formatted,
          'contractAddress': protocol.contractAddress,
          'nodes': protocol.nodes.length,
        },
      ),
    );

    try {
      yield const ActivationProgress(
        status: 'Validating protocol configuration...',
        progressPercentage: 20,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.validation,
          stepCount: 5,
        ),
      );

      // Compute tx_history flag similar to non-task strategy
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

      // Debug logging for ETH task-based activation
      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[RPC] Activating ETH platform (task-based): ${asset.id.id}',
          name: 'EthTaskActivationStrategy',
        );
        log(
          '[RPC] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'protocol': asset.protocol.subClass.formatted, 'token_count': children?.length ?? 0, 'tokens': children?.map((e) => e.id.id).toList() ?? [], 'activation_params': activationParams.toRpcParams(), 'priv_key_policy': privKeyPolicy.toJson()})}',
          name: 'EthTaskActivationStrategy',
        );
      }

      final taskResponse = await client.rpc.erc20.enableEthInit(
        ticker: asset.id.id,
        params: activationParams,
      );

      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[RPC] Task initiated for ${asset.id.id}, task_id: ${taskResponse.taskId}',
          name: 'EthTaskActivationStrategy',
        );
      }

      yield ActivationProgress(
        status: 'Establishing network connections...',
        progressPercentage: 40,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.connection,
          stepCount: 5,
          additionalInfo: {
            'nodes': protocol.requiredServers.toJsonRequest(),
            'protocolType': protocol.subClass.formatted,
            'tokenCount': children?.length ?? 0,
          },
        ),
      );

      var isComplete = false;
      while (!isComplete) {
        final status = await client.rpc.erc20.taskEthStatus(
          taskResponse.taskId,
        );

        if (status.isCompleted) {
          if (status.status == 'Ok') {
            yield ActivationProgress.success(
              details: ActivationProgressDetails(
                currentStep: ActivationStep.complete,
                stepCount: 5,
                additionalInfo: {
                  'activatedChain': asset.id.name,
                  'activationTime': DateTime.now().toIso8601String(),
                  'childCount': children?.length ?? 0,
                },
              ),
            );
          } else {
            yield ActivationProgress(
              status: 'Activation failed: ${status.details}',
              errorMessage: status.details,
              isComplete: true,
              progressDetails: ActivationProgressDetails(
                currentStep: ActivationStep.error,
                stepCount: 5,
                errorCode: 'ETH_TASK_ACTIVATION_ERROR',
                errorDetails: status.details,
              ),
            );
          }
          isComplete = true;
        } else {
          final progress = _parseEthStatus(status.status);
          yield ActivationProgress(
            status: progress.status,
            progressPercentage: progress.percentage,
            progressDetails: ActivationProgressDetails(
              currentStep: progress.step,
              stepCount: 5,
              additionalInfo: progress.info,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e, stack) {
      yield ActivationProgress(
        status: 'Activation failed',
        errorMessage: e.toString(),
        isComplete: true,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.error,
          stepCount: 5,
          errorCode: 'ETH_TASK_ACTIVATION_ERROR',
          errorDetails: e.toString(),
          stackTrace: stack.toString(),
        ),
      );
    }
  }

  ({
    String status,
    double percentage,
    ActivationStep step,
    Map<String, dynamic> info,
  })
  _parseEthStatus(String status) {
    switch (status) {
      case 'ActivatingCoin':
        return (
          status: 'Activating platform coin...',
          percentage: 60,
          step: ActivationStep.platformActivation,
          info: {'activationType': 'platform'},
        );
      case 'RequestingWalletBalance':
        return (
          status: 'Requesting wallet balance...',
          percentage: 70,
          step: ActivationStep.verification,
          info: {'dataType': 'balance'},
        );
      case 'ActivatingTokens':
        return (
          status: 'Activating ERC20 tokens...',
          percentage: 80,
          step: ActivationStep.tokenActivation,
          info: {'activationType': 'tokens'},
        );
      case 'Finishing':
        return (
          status: 'Finalizing activation...',
          percentage: 90,
          step: ActivationStep.processing,
          info: {'stage': 'completion'},
        );
      case 'WaitingForTrezorToConnect':
        return (
          status: 'Waiting for Trezor device...',
          percentage: 50,
          step: ActivationStep.connection,
          info: {'deviceType': 'Trezor', 'action': 'connect'},
        );
      case 'FollowHwDeviceInstructions':
        return (
          status: 'Follow instructions on hardware device',
          percentage: 55,
          step: ActivationStep.connection,
          info: {'deviceType': 'Hardware', 'action': 'follow_instructions'},
        );
      default:
        return (
          status: 'Processing activation...',
          percentage: 95,
          step: ActivationStep.processing,
          info: {'status': status},
        );
    }
  }
}
