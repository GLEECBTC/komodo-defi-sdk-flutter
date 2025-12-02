import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class SiaActivationStrategy extends ProtocolActivationStrategy {
  SiaActivationStrategy(super.client);

  static const Duration kPollInterval = Duration(milliseconds: 500);

  @override
  Set<CoinSubClass> get supportedProtocols => {CoinSubClass.sia};

  @override
  bool get supportsBatchActivation => false;

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    final protocol = asset.protocol as SiaProtocol;
    final serverUrl = protocol.serverUrl;
    if (serverUrl == null) {
      throw StateError(
        'Missing SIA server_url/nodes in coins configuration for ${asset.id.id}',
      );
    }
    final params = SiaActivationParams(
      serverUrl: serverUrl,
      requiredConfirmations: protocol.requiredConfirmations,
    );

    yield ActivationProgress(
      status: 'Starting SIA activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 3,
        additionalInfo: {
          'assetType': 'platform',
          'protocol': 'SIA',
        },
      ),
    );

    try {
      final init = await KomodoDefiRpcMethods(client).sia.enableSiaInit(
            ticker: asset.id.id,
            params: params,
          );

      final taskId = init.taskId;
      yield ActivationProgress(
        status: 'SIA activation task started',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.initialization,
          stepCount: 3,
          additionalInfo: {'taskId': taskId},
        ),
      );

      while (true) {
        final status =
            await KomodoDefiRpcMethods(client).sia.enableSiaStatus(taskId);

        yield ActivationProgress(
          status: 'SIA activation in progress',
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.processing,
            stepCount: 3,
            additionalInfo: {'status': status.status},
          ),
        );

        // Stop polling on any terminal state
        if (status.status != 'InProgress') {
          if (status.status == 'Ok') {
            yield ActivationProgress(
              status: 'SIA activation complete',
              isComplete: true,
              progressDetails: ActivationProgressDetails(
                currentStep: ActivationStep.complete,
                stepCount: 3,
                additionalInfo: {'taskId': taskId},
              ),
            );
          } else {
            yield ActivationProgress(
              status: 'SIA activation failed',
              isComplete: true,
              progressDetails: ActivationProgressDetails(
                currentStep: ActivationStep.error,
                stepCount: 3,
                additionalInfo: {
                  'taskId': taskId,
                  'status': status.status,
                  'details': status.details,
                },
              ),
            );
          }
          yield ActivationProgress(
            status: 'SIA activation concluded',
            isComplete: true,
            progressDetails: ActivationProgressDetails(
              currentStep: status.status == 'Ok'
                  ? ActivationStep.complete
                  : ActivationStep.error,
              stepCount: 3,
            ),
          );
          break;
        }

        await Future<void>.delayed(kPollInterval);
      }
    } on Exception catch (e) {
      yield ActivationProgress(
        status: 'SIA activation failed',
        isComplete: true,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.error,
          stepCount: 3,
          additionalInfo: {'error': e.toString()},
        ),
      );
      rethrow;
    }
  }
}

