import 'dart:async';
import 'dart:convert';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

class SiaActivationStrategy extends ProtocolActivationStrategy {
  SiaActivationStrategy(super.client);

  static const Duration kPollInterval = Duration(milliseconds: 500);
  static final Logger _log = Logger('SiaActivationStrategy');

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

    yield const ActivationProgress(
      status: 'Starting SIA activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 3,
        additionalInfo: {'assetType': 'platform', 'protocol': 'SIA'},
      ),
    );

    try {
      // Debug logging for SIA activation
      if (KdfLoggingConfig.verboseLogging) {
        _log
          ..info('[SIA] Activating SIA coin: ${asset.id.id}')
          ..info(
            '[SIA] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'server_url': serverUrl, 'required_confirmations': protocol.requiredConfirmations})}',
          );
      }

      final init = await KomodoDefiRpcMethods(
        client,
      ).sia.enableSiaInit(ticker: asset.id.id, params: params);

      final taskId = init.taskId;

      if (KdfLoggingConfig.verboseLogging) {
        _log.info('[SIA] Task initiated for ${asset.id.id}, task_id: $taskId');
      }

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
            if (KdfLoggingConfig.verboseLogging) {
              _log.info('[SIA] Activation completed for ${asset.id.id}');
            }

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
            if (KdfLoggingConfig.verboseLogging) {
              _log.warning(
                '[SIA] Activation failed for ${asset.id.id}: ${status.status} - ${status.details}',
              );
            }

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
      if (KdfLoggingConfig.verboseLogging) {
        _log.severe('[SIA] Activation exception for ${asset.id.id}: $e');
      }

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
