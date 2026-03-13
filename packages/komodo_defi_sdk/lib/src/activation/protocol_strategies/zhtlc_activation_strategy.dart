// Start sync mode can be passed via one-shot sync params through
// ActivationConfigService.setOneShotSyncParams() before activation.
// See zhtlc_config_dialog.dart for UI implementation.

import 'dart:convert';
import 'dart:developer' show log;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/zhtlc_activation_progress.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/zhtlc_activation_progress_estimator.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Activation strategy for ZHTLC-based assets that translates task updates into
/// user-facing progress events.
class ZhtlcActivationStrategy extends ProtocolActivationStrategy {
  /// Creates a strategy that activates ZHTLC assets using the provided
  /// services.
  const ZhtlcActivationStrategy(
    super.client,
    this.privKeyPolicy,
    this.configService, {
    this.pollingInterval = const Duration(milliseconds: 500),
    ZhtlcActivationProgressEstimator? progressEstimator,
  }) : progressEstimator =
           progressEstimator ?? const ZhtlcActivationProgressEstimator();

  /// Policy used when deriving private keys during activation.
  final PrivateKeyPolicy privKeyPolicy;

  /// Service that provides user-configured activation parameters.
  final ActivationConfigService configService;

  /// Progress estimator that maps task status updates to activation progress.
  final ZhtlcActivationProgressEstimator progressEstimator;

  /// Interval between TaskShepherd status polls when monitoring activation.
  final Duration pollingInterval;

  @override
  Set<CoinSubClass> get supportedProtocols => {CoinSubClass.zhtlc};

  @override
  bool get supportsBatchActivation => false;

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    if (children?.isNotEmpty ?? false) {
      throw UnsupportedError(
        'ZHTLC protocol does not support batch activation',
      );
    }

    yield ZhtlcActivationProgress.starting(asset);

    try {
      final protocol = asset.protocol as ZhtlcProtocol;
      final userConfig = await configService.getZhtlcOrRequest(asset.id);

      if (userConfig == null || userConfig.zcashParamsPath.trim().isEmpty) {
        yield ActivationProgressZhtlc.missingZcashParams();
        return;
      }

      final effectivePollingInterval =
          userConfig.taskStatusPollingIntervalMs != null &&
              userConfig.taskStatusPollingIntervalMs! > 0
          ? Duration(milliseconds: userConfig.taskStatusPollingIntervalMs!)
          : pollingInterval;

      var params = ZhtlcActivationParams.fromConfigJson(protocol.config)
          .copyWith(
            scanBlocksPerIteration: userConfig.scanBlocksPerIteration,
            scanIntervalMs: userConfig.scanIntervalMs,
            zcashParamsPath: userConfig.zcashParamsPath,
            privKeyPolicy: privKeyPolicy,
          );

      // Apply one-shot sync_params only when explicitly provided via config form
      // right before activation. This avoids caching and unintended rewinds.
      if (params.mode?.rpcData != null) {
        final oneShotSync = await configService.takeOneShotSyncParams(asset.id);
        if (oneShotSync != null) {
          final rpcData = params.mode!.rpcData!;
          final updatedRpcData = ActivationRpcData(
            lightWalletDServers: rpcData.lightWalletDServers,
            electrum: rpcData.electrum,
            syncParams: oneShotSync,
          );
          params = params.copyWith(
            mode: ActivationMode(
              rpc: params.mode!.rpc,
              rpcData: updatedRpcData,
            ),
          );
        }
      }

      yield ZhtlcActivationProgress.validation(protocol);

      // Debug logging for ZHTLC activation
      if (KdfLoggingConfig.verboseLogging) {
        log(
        '[RPC] Activating ZHTLC coin: ${asset.id.id}',
        name: 'ZhtlcActivationStrategy',
      );
      }
      if (KdfLoggingConfig.verboseLogging) {
        log(
        '[RPC] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'protocol': asset.protocol.subClass.formatted, 'activation_params': params.toRpcParams(), 'zcash_params_path': userConfig.zcashParamsPath, 'scan_blocks_per_iteration': userConfig.scanBlocksPerIteration, 'scan_interval_ms': userConfig.scanIntervalMs, 'polling_interval_ms': effectivePollingInterval.inMilliseconds, 'priv_key_policy': privKeyPolicy.toJson()})}',
        name: 'ZhtlcActivationStrategy',
      );
      }

      // Initialize task and watch via TaskShepherd
      final stream = client.rpc.zhtlc
          .enableZhtlcInit(ticker: asset.id.id, params: params)
          .watch<TaskStatusResponse>(
            getTaskStatus: (int taskId) => client.rpc.zhtlc.enableZhtlcStatus(
              taskId,
              forgetIfFinished: false,
            ),
            isTaskComplete: (TaskStatusResponse s) =>
                s.status == 'Ok' || s.status == 'Error',
            pollingInterval: effectivePollingInterval,
            pollingIntervalForStatus: (TaskStatusResponse s) {
              final parsed = progressEstimator.parse(s.details);
              // Back off to 5s until requesting balance; then use the effective (fast) interval.
              return parsed.phase == ZhtlcActivationPhase.requestingWalletBalance
                  ? effectivePollingInterval
                  : const Duration(seconds: 5);
            },
            // cancelTask intentionally omitted, as it is not used in this
            // context and leaving it enabled lead to uncaught exceptions
            // when taskId was already finished.
            // TODO(gui-team): investigate why this is the case.
          );

      var emittedCompletion = false;
      TaskStatusResponse? lastStatus;

      await for (final status in stream) {
        lastStatus = status;
        final detail = progressEstimator.parse(status.details);

        final progress = progressEstimator.estimate(
          status: status,
          asset: asset,
          detail: detail,
        );

        yield progress;

        if (progress.isComplete) {
          emittedCompletion = true;
          return;
        }
      }

      // If the task ended with an error status but without emitting a specific
      // error detail case, emit a failure result now.
      if (!emittedCompletion &&
          lastStatus != null &&
          lastStatus.status == 'Error') {
        final detail = progressEstimator.parse(lastStatus.details);
        yield progressEstimator.estimate(
          status: lastStatus,
          asset: asset,
          detail: detail,
        );
      }
    } catch (e, stack) {
      yield ActivationProgressZhtlc.failure(e, stack);
    }
  }
}
