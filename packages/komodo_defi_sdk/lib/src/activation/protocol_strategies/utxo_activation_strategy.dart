import 'dart:convert';
import 'dart:developer' show log;

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class UtxoActivationStrategy extends ProtocolActivationStrategy {
  const UtxoActivationStrategy(super.client, this.privKeyPolicy);

  /// The private key management policy to use for this strategy.
  /// Used for external wallet support.
  final PrivateKeyPolicy privKeyPolicy;

  @override
  Set<CoinSubClass> get supportedProtocols => {
    CoinSubClass.utxo,
    CoinSubClass.smartChain,
    // CoinSubClass.smartBch,
  };

  @override
  bool get supportsBatchActivation => false;

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    if (children?.isNotEmpty == true) {
      throw UnsupportedError('UTXO protocol does not support batch activation');
    }

    final protocol = asset.protocol as UtxoProtocol;

    yield ActivationProgress(
      status: 'Starting ${asset.id.name} activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 5,
        additionalInfo: {
          'chainType': protocol.subClass.formatted,
          'mode': protocol
              .defaultActivationParams(privKeyPolicy: privKeyPolicy)
              .mode
              ?.rpc,
          'txVersion': protocol.txVersion,
          'pubtype': protocol.pubtype,
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

      final activationParams = protocol.defaultActivationParams(
        privKeyPolicy: privKeyPolicy,
      );

      // Debug logging for UTXO/Electrum activation
      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[ELECTRUM] Activating UTXO coin: ${asset.id.id}',
          name: 'UtxoActivationStrategy',
        );
        log(
          '[ELECTRUM] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'mode': activationParams.mode?.rpc, 'utxo_params': activationParams.toRpcParams(), 'protocol_type': protocol.subClass.formatted, 'tx_version': protocol.txVersion, 'pubtype': protocol.pubtype, 'p2shtype': protocol.p2shtype, 'wiftype': protocol.wiftype, 'electrum_servers': protocol.requiredServers.toJsonRequest(), 'priv_key_policy': privKeyPolicy.toJson()})}',
          name: 'UtxoActivationStrategy',
        );
      }

      final taskResponse = await client.rpc.utxo.enableUtxoInit(
        ticker: asset.id.id,
        params: activationParams,
      );

      if (KdfLoggingConfig.verboseLogging) {
        log(
          '[ELECTRUM] Task initiated for ${asset.id.id}, task_id: ${taskResponse.taskId}',
          name: 'UtxoActivationStrategy',
        );
      }

      yield ActivationProgress(
        status: 'Establishing network connections...',
        progressPercentage: 40,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.connection,
          stepCount: 5,
          additionalInfo: {
            'electrumServers': protocol.requiredServers.toJsonRequest(),
            'protocolType': protocol.subClass.formatted,
          },
        ),
      );

      var isComplete = false;
      while (!isComplete) {
        final status = await client.rpc.utxo.taskEnableStatus(
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
                  'txFee': protocol.txFee,
                  'overwintered': protocol.overwintered,
                },
              ),
            );
          } else {
            yield buildErrorProgress(
              asset: asset,
              error: status.details,
              errorCode: 'UTXO_ACTIVATION_ERROR',
              stepCount: 5,
            );
          }
          isComplete = true;
        } else {
          final progress = _parseUtxoStatus(status.status);
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
        errorCode: 'UTXO_ACTIVATION_ERROR',
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
  _parseUtxoStatus(String status) {
    switch (status) {
      case 'ConnectingElectrum':
        return (
          status: 'Connecting to Electrum servers...',
          percentage: 60,
          step: ActivationStep.electrumConnection,
          info: {'connectionType': 'Electrum'},
        );
      case 'LoadingBlockchain':
        return (
          status: 'Loading blockchain data...',
          percentage: 80,
          step: ActivationStep.blockchainSync,
          info: {'dataType': 'blockchain'},
        );
      case 'ScanningTransactions':
        return (
          status: 'Scanning transaction history...',
          percentage: 90,
          step: ActivationStep.txScan,
          info: {'dataType': 'transactions'},
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
