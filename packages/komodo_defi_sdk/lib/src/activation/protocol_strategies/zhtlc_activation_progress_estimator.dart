import 'dart:math' as math;

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/zhtlc_activation_progress.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// High-level phases emitted by the ZHTLC activation task engine.
enum ZhtlcActivationPhase {
  /// Initial stage where the protocol sends activation requests.
  activatingCoin,

  /// Phase in which the lightwalletd cache is updated before scanning.
  updatingBlocksCache,

  /// Phase dedicated to building the ZHTLC wallet database.
  buildingWalletDb,

  /// Waiting for a connection to an available lightwalletd server.
  waitingLightwalletd,

  /// Fetching balance information from the backend.
  requestingWalletBalance,

  /// Finalization stage reported before completion.
  finishing,

  /// Waiting for a hardware wallet (e.g. Trezor) to connect.
  waitingForTrezor,

  /// Waiting for the user to follow hardware-device instructions.
  followHardwareInstructions,

  /// Activation task reports that all work has completed successfully.
  completed,

  /// Activation task reports an unrecoverable error.
  error,

  /// State could not be classified into a known phase.
  unknown,
}

/// Tunable weights applied when converting task phases into user-facing
/// progress percentages.
class ZhtlcProgressWeights {
  /// Creates a [ZhtlcProgressWeights] instance with optional overrides for the
  /// default percentage contributions.
  const ZhtlcProgressWeights({
    this.defaultProgress = 2,
    this.activatingCoin = 1,
    this.requestingWalletBalance = 99,
    this.waitingLightwalletd = 60,
    this.waitingForTrezor = 45,
    this.followingHardwareInstructions = 55,
    this.finishing = 99,
    this.scanningBlocks = 98,
    this.updatingBlocksCacheWeight = 15,
    this.buildingWalletDbWeight = 98,
    this.minWalletDbProgress = 15,
  });

  /// Fallback percentage when no better estimate is possible.
  final double defaultProgress;

  /// Activation progress when "ActivatingCoin" is reported.
  final double activatingCoin;

  /// Activation progress when balances are being fetched.
  final double requestingWalletBalance;

  /// Activation progress when waiting for lightwalletd connection.
  final double waitingLightwalletd;

  /// Activation progress when waiting for a hardware wallet connection.
  final double waitingForTrezor;

  /// Activation progress when following hardware wallet instructions.
  final double followingHardwareInstructions;

  /// Activation progress when activation is in the finishing phase.
  final double finishing;

  /// Activation progress when scanning blocks without ratio context.
  final double scanningBlocks;

  /// Maximum contribution for the block cache warm-up stage.
  final double updatingBlocksCacheWeight;

  /// Maximum contribution for the wallet DB build stage.
  final double buildingWalletDbWeight;

  /// Minimum progress reported during wallet DB build.
  final double minWalletDbProgress;
}

/// Parsed representation of the `details` payload emitted by the task engine
/// during activation.
class ZhtlcStatusDetail {
  /// Creates a [ZhtlcStatusDetail] from the parsed activation payload.
  const ZhtlcStatusDetail({
    required this.phase,
    required this.raw,
    this.rawJson,
    this.message,
    this.error,
    this.currentScannedBlock,
    this.latestBlock,
  });

  /// Phase categorized from the raw task details.
  final ZhtlcActivationPhase phase;

  /// Raw JSON string or label reported by the task engine.
  final String raw;

  /// Parsed representation of [raw] when it contains JSON.
  final JsonMap? rawJson;

  /// Human-readable status message derived from the payload.
  final String? message;

  /// Optional error metadata returned by the task engine.
  final JsonMap? error;

  /// Current block that has been processed, if reported.
  final int? currentScannedBlock;

  /// Highest known block height at the time of reporting.
  final int? latestBlock;

  /// Whether the payload contains an explicit error description.
  bool get hasError => error != null;

  /// Ratio of processed blocks to the latest known block, if available.
  double? get progressRatio {
    final current = currentScannedBlock;
    final latest = latestBlock;
    if (current == null || latest == null || latest <= 0) {
      return null;
    }
    return current / latest;
  }
}

/// Converts ZHTLC task status updates into `ActivationProgress` snapshots using
/// heuristics derived from the legacy C++ activation flow.
class ZhtlcActivationProgressEstimator {
  /// Creates a [ZhtlcActivationProgressEstimator] that applies the provided
  /// [weights] and exposes [stepCount] steps to the UI.
  const ZhtlcActivationProgressEstimator({
    this.weights = const ZhtlcProgressWeights(),
    this.stepCount = 6,
  });

  /// Weight configuration applied when translating phases to percentages.
  final ZhtlcProgressWeights weights;

  /// Number of activation steps surfaced to the UI for progress reporting.
  final int stepCount;

  /// Estimates the activation progress for a given ZHTLC task status.
  ActivationProgress estimate({
    required TaskStatusResponse status,
    required Asset asset,
    ZhtlcStatusDetail? detail,
    int? currentBlock,
  }) {
    const mapper = SdkErrorMapper();
    final context = SdkErrorContext(
      operation: 'activation',
      assetId: asset.id.id,
    );
    final parsedDetail = detail ?? parse(status.details);
    final baseInfo = _buildAdditionalInfo(
      asset,
      status,
      parsedDetail,
      currentBlock,
    );

    if (status.status == 'Ok') {
      if (parsedDetail.hasError) {
        final message =
            _extractErrorMessage(parsedDetail.error) ?? 'Unknown error';
        final sdkError = mapper.map(message, context: context);
        return ActivationProgress(
          status: 'Activation failed',
          errorMessage: sdkError.fallbackMessage,
          isComplete: true,
          sdkError: sdkError,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.error,
            stepCount: stepCount,
            errorCode: ZhtlcActivationProgress.errorCode,
            errorDetails: sdkError.fallbackMessage,
            additionalInfo: baseInfo,
          ),
        );
      }

      return ActivationProgress.success(
        details: ActivationProgressDetails(
          currentStep: ActivationStep.complete,
          stepCount: stepCount,
          additionalInfo: {...baseInfo, 'activatedChain': asset.id.name},
        ),
      );
    }

    if (status.status == 'Error' ||
        parsedDetail.phase == ZhtlcActivationPhase.error) {
      final message = parsedDetail.message ?? status.details;
      final sdkError = mapper.map(message, context: context);
      return ActivationProgress(
        status: 'Activation failed',
        errorMessage: sdkError.fallbackMessage,
        isComplete: true,
        sdkError: sdkError,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.error,
          stepCount: stepCount,
          errorCode: ZhtlcActivationProgress.errorCode,
          errorDetails: parsedDetail.error != null
              ? jsonToString(parsedDetail.error)
              : sdkError.fallbackMessage,
          additionalInfo: baseInfo,
        ),
      );
    }

    final progress = _estimateProgress(parsedDetail).clamp(0, 100).toDouble();
    final statusMessage = parsedDetail.message ?? status.details;
    final awaitingUserAction =
        status.status == 'UserActionRequired' ||
        parsedDetail.phase == ZhtlcActivationPhase.waitingForTrezor ||
        parsedDetail.phase == ZhtlcActivationPhase.followHardwareInstructions;

    return ActivationProgress(
      status: statusMessage,
      progressPercentage: progress,
      progressDetails: ActivationProgressDetails(
        currentStep: _mapPhaseToStep(parsedDetail.phase),
        stepCount: stepCount,
        additionalInfo: baseInfo,
        uiSignal: awaitingUserAction
            ? ActivationUiSignal.awaitingUserInput
            : null,
      ),
    );
  }

  /// Parses the raw task details payload into a structured representation.
  ZhtlcStatusDetail parse(String rawDetails) {
    final trimmed = rawDetails.trim();
    if (trimmed.isEmpty) {
      return ZhtlcStatusDetail(
        phase: ZhtlcActivationPhase.unknown,
        raw: rawDetails,
        message: 'Awaiting activation status...',
      );
    }

    final json = tryParseJson(trimmed);
    if (json != null && json.isNotEmpty) {
      if (json.containsKey('error')) {
        return ZhtlcStatusDetail(
          phase: ZhtlcActivationPhase.error,
          raw: rawDetails,
          rawJson: json,
          message: _extractErrorMessage(json['error']) ?? 'Activation error',
          error: json['error'] is JsonMap
              ? Map<String, dynamic>.from(json['error'] as Map)
              : {'message': json['error']},
        );
      }

      if (json.containsKey('wallet_balance') ||
          json.containsKey('current_block') ||
          json.containsKey('ticker')) {
        return ZhtlcStatusDetail(
          phase: ZhtlcActivationPhase.completed,
          raw: rawDetails,
          rawJson: json,
          message: 'Activation completed successfully',
        );
      }

      for (final key in json.keys) {
        final normalizedKey = key.trim();
        final payload = json[key];
        switch (_phaseFromKey(normalizedKey)) {
          case ZhtlcActivationPhase.updatingBlocksCache:
            final data = _asJsonMap(payload);
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.updatingBlocksCache,
              raw: rawDetails,
              rawJson: json,
              message: 'Updating ZHTLC blocks cache...',
              currentScannedBlock: _asInt(data['current_scanned_block']),
              latestBlock: _asInt(data['latest_block']),
            );
          case ZhtlcActivationPhase.buildingWalletDb:
            final data = _asJsonMap(payload);
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.buildingWalletDb,
              raw: rawDetails,
              rawJson: json,
              message: 'Building wallet database...',
              currentScannedBlock: _asInt(data['current_scanned_block']),
              latestBlock: _asInt(data['latest_block']),
            );
          case ZhtlcActivationPhase.requestingWalletBalance:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.requestingWalletBalance,
              raw: rawDetails,
              rawJson: json,
              message: 'Requesting wallet balance...',
            );
          case ZhtlcActivationPhase.finishing:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.finishing,
              raw: rawDetails,
              rawJson: json,
              message: 'Finalizing activation...',
            );
          case ZhtlcActivationPhase.waitingForTrezor:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.waitingForTrezor,
              raw: rawDetails,
              rawJson: json,
              message: 'Waiting for Trezor device...',
            );
          case ZhtlcActivationPhase.followHardwareInstructions:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.followHardwareInstructions,
              raw: rawDetails,
              rawJson: json,
              message: 'Follow instructions on hardware device...',
            );
          case ZhtlcActivationPhase.activatingCoin:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.activatingCoin,
              raw: rawDetails,
              rawJson: json,
              message: 'Activating coin...',
            );
          case ZhtlcActivationPhase.waitingLightwalletd:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.waitingLightwalletd,
              raw: rawDetails,
              rawJson: json,
              message: 'Connecting to Lightwalletd server...',
            );
          case ZhtlcActivationPhase.completed:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.completed,
              raw: rawDetails,
              rawJson: json,
              message: 'Activation completed successfully',
            );
          case ZhtlcActivationPhase.error:
            return ZhtlcStatusDetail(
              phase: ZhtlcActivationPhase.error,
              raw: rawDetails,
              rawJson: json,
              message: _extractErrorMessage(payload) ?? 'Activation error',
              error: _asJsonMap(payload),
            );
          case ZhtlcActivationPhase.unknown:
            continue;
        }
      }
    }

    final phase = _phaseFromKey(trimmed);
    switch (phase) {
      case ZhtlcActivationPhase.updatingBlocksCache:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Updating ZHTLC blocks cache...',
        );
      case ZhtlcActivationPhase.buildingWalletDb:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Building wallet database...',
        );
      case ZhtlcActivationPhase.waitingLightwalletd:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Connecting to Lightwalletd server...',
        );
      case ZhtlcActivationPhase.requestingWalletBalance:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Requesting wallet balance...',
        );
      case ZhtlcActivationPhase.finishing:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Finalizing activation...',
        );
      case ZhtlcActivationPhase.waitingForTrezor:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Waiting for Trezor device...',
        );
      case ZhtlcActivationPhase.followHardwareInstructions:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Follow instructions on hardware device...',
        );
      case ZhtlcActivationPhase.activatingCoin:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Activating coin...',
        );
      case ZhtlcActivationPhase.completed:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Activation completed successfully',
        );
      case ZhtlcActivationPhase.error:
        return ZhtlcStatusDetail(
          phase: phase,
          raw: rawDetails,
          message: 'Activation error',
        );
      case ZhtlcActivationPhase.unknown:
        return ZhtlcStatusDetail(
          phase: ZhtlcActivationPhase.unknown,
          raw: rawDetails,
          message: rawDetails,
        );
    }
  }

  double _estimateProgress(ZhtlcStatusDetail detail) {
    switch (detail.phase) {
      case ZhtlcActivationPhase.activatingCoin:
        return weights.activatingCoin;
      case ZhtlcActivationPhase.updatingBlocksCache:
        final ratio = detail.progressRatio;
        if (ratio == null) {
          return weights.defaultProgress;
        }
        return math.min(
          weights.updatingBlocksCacheWeight,
          ratio * weights.updatingBlocksCacheWeight,
        );
      case ZhtlcActivationPhase.buildingWalletDb:
        final ratio = detail.progressRatio;
        if (ratio == null) {
          return weights.minWalletDbProgress;
        }
        final computed = ratio * weights.buildingWalletDbWeight;
        return math.max(
          weights.minWalletDbProgress,
          math.min(weights.buildingWalletDbWeight, computed),
        );
      case ZhtlcActivationPhase.waitingLightwalletd:
        return weights.waitingLightwalletd;
      case ZhtlcActivationPhase.finishing:
        return weights.finishing;
      case ZhtlcActivationPhase.waitingForTrezor:
        return weights.waitingForTrezor;
      case ZhtlcActivationPhase.followHardwareInstructions:
        return weights.followingHardwareInstructions;
      case ZhtlcActivationPhase.requestingWalletBalance:
        return weights.requestingWalletBalance;
      case ZhtlcActivationPhase.completed:
        return 100;
      case ZhtlcActivationPhase.error:
        return 0;
      case ZhtlcActivationPhase.unknown:
        return weights.defaultProgress;
    }
  }

  ActivationStep _mapPhaseToStep(ZhtlcActivationPhase phase) {
    switch (phase) {
      case ZhtlcActivationPhase.activatingCoin:
        return ActivationStep.initialization;
      case ZhtlcActivationPhase.updatingBlocksCache:
        return ActivationStep.blockchainSync;
      case ZhtlcActivationPhase.buildingWalletDb:
        return ActivationStep.database;
      case ZhtlcActivationPhase.waitingLightwalletd:
        return ActivationStep.connection;
      case ZhtlcActivationPhase.requestingWalletBalance:
        return ActivationStep.processing;
      case ZhtlcActivationPhase.finishing:
        return ActivationStep.processing;
      case ZhtlcActivationPhase.waitingForTrezor:
        return ActivationStep.connection;
      case ZhtlcActivationPhase.followHardwareInstructions:
        return ActivationStep.connection;
      case ZhtlcActivationPhase.completed:
        return ActivationStep.complete;
      case ZhtlcActivationPhase.error:
        return ActivationStep.error;
      case ZhtlcActivationPhase.unknown:
        return ActivationStep.processing;
    }
  }

  Map<String, dynamic> _buildAdditionalInfo(
    Asset asset,
    TaskStatusResponse status,
    ZhtlcStatusDetail detail,
    int? currentBlock,
  ) {
    final info = <String, dynamic>{
      'asset': asset.id.name,
      'phase': detail.phase.name,
      'taskStatus': status.status,
    };

    if (detail.currentScannedBlock != null) {
      info['currentScannedBlock'] = detail.currentScannedBlock;
    }
    if (detail.latestBlock != null) {
      info['latestBlock'] = detail.latestBlock;
    }
    final ratio = detail.progressRatio;
    if (ratio != null) {
      info['progressRatio'] = ratio;
    }
    if (currentBlock != null) {
      info['currentWalletBlock'] = currentBlock;
    }

    if (status.status == 'UserActionRequired') {
      info['awaitingUserAction'] = true;
    }

    switch (detail.phase) {
      case ZhtlcActivationPhase.waitingForTrezor:
        info['userActionType'] = 'connect_trezor';
        break;
      case ZhtlcActivationPhase.followHardwareInstructions:
        info['userActionType'] = 'hardware_instructions';
        break;
      case ZhtlcActivationPhase.finishing:
        info['stage'] = 'finishing';
        break;
      default:
        break;
    }

    if (detail.rawJson != null && detail.rawJson!.isNotEmpty) {
      info['rawDetails'] = detail.rawJson;
    } else {
      info['rawDetails'] = detail.raw;
    }

    if (detail.error != null && detail.error!.isNotEmpty) {
      info['error'] = detail.error;
    }

    return info;
  }

  static ZhtlcActivationPhase _phaseFromKey(String key) {
    final normalized = key.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.contains('updatingblockscache')) {
      return ZhtlcActivationPhase.updatingBlocksCache;
    }
    if (normalized.contains('buildingwalletdb')) {
      return ZhtlcActivationPhase.buildingWalletDb;
    }
    if (normalized.contains('waitinglightwalletd')) {
      return ZhtlcActivationPhase.waitingLightwalletd;
    }
    if (normalized.contains('requestingwalletbalance')) {
      return ZhtlcActivationPhase.requestingWalletBalance;
    }
    if (normalized.contains('finishing')) {
      return ZhtlcActivationPhase.finishing;
    }
    if (normalized.contains('waitingfortrezor')) {
      return ZhtlcActivationPhase.waitingForTrezor;
    }
    if (normalized.contains('followhwdeviceinstructions')) {
      return ZhtlcActivationPhase.followHardwareInstructions;
    }
    if (normalized.contains('activatingcoin')) {
      return ZhtlcActivationPhase.activatingCoin;
    }
    if (normalized.contains('completed') || normalized.contains('finished')) {
      return ZhtlcActivationPhase.completed;
    }
    if (normalized.contains('error') || normalized.contains('failed')) {
      return ZhtlcActivationPhase.error;
    }
    return ZhtlcActivationPhase.unknown;
  }

  static JsonMap _asJsonMap(dynamic value) {
    if (value is JsonMap) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    if (value is String) {
      return tryParseJson(value) ?? <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _extractErrorMessage(dynamic error) {
    if (error is String) {
      return error;
    }
    if (error is Map) {
      final map = error.map(
        (key, dynamic value) => MapEntry(key.toString(), value),
      );
      if (map['message'] is String) {
        return map['message'] as String;
      }
      if (map['reason'] is String) {
        return map['reason'] as String;
      }
      if (map['details'] is String) {
        return map['details'] as String;
      }
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }
    return null;
  }
}
