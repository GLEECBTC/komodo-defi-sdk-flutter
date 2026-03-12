import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Task-based activation strategy for Tendermint with Trezor hardware wallets.
/// Uses task::enable_tendermint::init for both platform and token assets when using Trezor.
class TendermintTaskActivationStrategy extends ProtocolActivationStrategy {
  /// Creates a new [TendermintTaskActivationStrategy] with the given client and
  /// private key policy.
  const TendermintTaskActivationStrategy(super.client, this.privKeyPolicy);

  /// The private key policy to use for activation.
  final PrivateKeyPolicy privKeyPolicy;

  @override
  Set<CoinSubClass> get supportedProtocols => {
    CoinSubClass.tendermint,
    CoinSubClass.tendermintToken,
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
    final protocol = asset.protocol as TendermintProtocol;

    yield ActivationProgress(
      status: 'Starting ${asset.id.name} activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 5,
        additionalInfo: {
          'chainType': protocol.subClass.formatted,
          'chainId': protocol.chainId,
          'accountPrefix': protocol.accountPrefix,
          'tokenCount': children?.length ?? 0,
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

      final taskResponse = await client.rpc.tendermint.taskEnableTendermintInit(
        ticker: asset.id.id,
        tokensParams:
            children
                ?.map((child) => TendermintTokenParams(ticker: child.id.id))
                .toList() ??
            [],
        nodes: protocol.rpcUrlsMap.map(TendermintNode.fromJson).toList(),
      );

      yield ActivationProgress(
        status: 'Establishing network connections...',
        progressPercentage: 40,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.connection,
          stepCount: 5,
          additionalInfo: {
            'nodes': protocol.rpcUrlsMap.length,
            'protocolType': protocol.subClass.formatted,
            'tokenCount': children?.length ?? 0,
            'taskId': taskResponse.taskId,
          },
        ),
      );

      var isComplete = false;
      while (!isComplete) {
        final status = await client.rpc.tendermint.taskEnableTendermintStatus(
          taskId: taskResponse.taskId,
        );

        status.details.throwIfError();

        if (status.status == SyncStatusEnum.success) {
          yield ActivationProgress.success(
            details: ActivationProgressDetails(
              currentStep: ActivationStep.complete,
              stepCount: 5,
              additionalInfo: {
                'activatedChain': asset.id.name,
                'activationTime': DateTime.now().toIso8601String(),
                'address': status.details.data?.address,
                'currentBlock': status.details.data?.currentBlock,
                'childCount': children?.length ?? 0,
                'method': 'task::enable_tendermint',
              },
            ),
          );
          isComplete = true;
        } else if (status.status == SyncStatusEnum.error) {
          yield buildErrorProgress(
            asset: asset,
            error: status.details.error ?? 'Unknown error',
            errorCode: 'TENDERMINT_TASK_ACTIVATION_ERROR',
            stepCount: 5,
          );
          isComplete = true;
        } else {
          final progress = _parseTendermintStatus(status.status);
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
      yield buildErrorProgress(
        asset: asset,
        error: e,
        stackTrace: stack,
        errorCode: 'TENDERMINT_TASK_ACTIVATION_ERROR',
        stepCount: 5,
      );
    }
  }

  ({
    String status,
    double percentage,
    ActivationStep step,
    Map<String, dynamic> info,
  })
  _parseTendermintStatus(SyncStatusEnum status) {
    switch (status) {
      case SyncStatusEnum.notStarted:
        return (
          status: 'Initializing Tendermint activation...',
          percentage: 50,
          step: ActivationStep.initialization,
          info: {'stage': 'init', 'type': 'tendermint'},
        );
      case SyncStatusEnum.inProgress:
        return (
          status: 'Synchronizing with Tendermint network...',
          percentage: 75,
          step: ActivationStep.blockchainSync,
          info: {'stage': 'sync', 'type': 'tendermint'},
        );
      case SyncStatusEnum.success:
      case SyncStatusEnum.error:
        // These cases should never be reached as they are handled in the main loop
        // before calling this method. Including them for exhaustive enumeration.
        throw StateError(
          'Unexpected status $status in _parseTendermintStatus. '
          'Success and error cases should be handled in the main activation loop.',
        );
    }
  }
}
