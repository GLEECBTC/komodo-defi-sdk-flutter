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
        additionalInfo: {'assetType': 'platform', 'protocol': 'SIA'},
      ),
    );

    try {
      final init = await KomodoDefiRpcMethods(
        client,
      ).sia.enableSiaInit(ticker: asset.id.id, params: params);

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
        final status = await KomodoDefiRpcMethods(
          client,
        ).sia.enableSiaStatus(taskId);
        if (status.status == 'InProgress') {
          yield ActivationProgress(
            status: 'SIA activation in progress',
            progressDetails: ActivationProgressDetails(
              currentStep: ActivationStep.processing,
              stepCount: 3,
              additionalInfo: {'status': status.status},
            ),
          );
          await Future<void>.delayed(kPollInterval);
          continue;
        }

        if (status.status == 'Ok') {
          yield ActivationProgress.success(
            details: ActivationProgressDetails(
              currentStep: ActivationStep.complete,
              stepCount: 3,
              additionalInfo: {'taskId': taskId, 'status': status.status},
            ),
          );
          break;
        }

        final errorDetails = (status.detailsAsString ?? '').trim().isEmpty
            ? 'SIA activation failed'
            : status.detailsAsString!;
        final errorProgress = buildErrorProgress(
          asset: asset,
          error: errorDetails,
          errorCode: 'SIA_ACTIVATION_ERROR',
          stepCount: 3,
          status: 'SIA activation failed',
        );
        yield errorProgress.copyWith(
          progressDetails: errorProgress.progressDetails?.copyWith(
            additionalInfo: {
              'taskId': taskId,
              'status': status.status,
              'details': status.details,
            },
          ),
        );
        break;
      }
    } on Exception catch (e, stack) {
      final errorProgress = buildErrorProgress(
        asset: asset,
        error: e,
        stackTrace: stack,
        errorCode: 'SIA_ACTIVATION_ERROR',
        stepCount: 3,
        status: 'SIA activation failed',
      );
      yield errorProgress.copyWith(
        progressDetails: errorProgress.progressDetails?.copyWith(
          additionalInfo: {'error': e.toString()},
        ),
      );
    }
  }
}
