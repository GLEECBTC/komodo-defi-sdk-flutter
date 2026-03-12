import 'dart:convert';
import 'dart:developer' show log;

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const _deprecatedMessage =
    'BCH is now handled by UtxoActivationStrategy as its authors no longer '
    'support SLP';

/// Special case strategy for BCH which is UTXO-based but handles SLP children differently
@Deprecated(_deprecatedMessage)
class BchActivationStrategy extends ProtocolActivationStrategy {
  @Deprecated(_deprecatedMessage)
  const BchActivationStrategy(super.client);

  @override
  Set<CoinSubClass> get supportedProtocols => {
    CoinSubClass.utxo,
    CoinSubClass.slp,
  };

  @override
  bool get supportsBatchActivation => true;

  @override
  bool canHandle(Asset asset) {
    // Only handle BCH and its SLP children
    if (asset.id.id == 'BCH') return true;
    return asset.id.parentId?.id == 'BCH' &&
        asset.protocol.subClass == CoinSubClass.slp;

    // return false;
  }

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    final isBch = asset.id.id == 'BCH';

    if (!isBch && (children?.isNotEmpty ?? false)) {
      throw StateError('SLP tokens cannot perform batch activation');
    }

    yield ActivationProgress(
      status: 'Starting BCH/SLP activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 4,
        additionalInfo: {
          'assetType': isBch ? 'BCH' : 'SLP',
          'childCount': children?.length ?? 0,
        },
      ),
    );

    try {
      if (isBch) {
        // BCH activation with optional SLP tokens
        final protocol = asset.protocol as UtxoProtocol;
        yield ActivationProgress(
          status: 'Configuring BCH platform...',
          progressPercentage: 25,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.platformSetup,
            stepCount: 4,
            additionalInfo: {
              'electrumServers': protocol.requiredServers.toJsonRequest(),
            },
          ),
        );

        // Get BCH configuration
        final bchConfig = BchActivationParams.fromJson(protocol.config);

        yield const ActivationProgress(
          status: 'Activating BCH with SLP support...',
          progressPercentage: 50,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.activation,
            stepCount: 4,
          ),
        );

        final slpTokensRequests =
            children
                ?.map((child) => TokensRequest(ticker: child.id.id))
                .toList() ??
            [];

        // Debug logging for BCH activation
        if (KdfLoggingConfig.verboseLogging) {
          log(
            '[RPC] Activating BCH platform: ${asset.id.id}',
            name: 'BchActivationStrategy',
          );
          log(
            '[RPC] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'protocol': asset.protocol.subClass.formatted, 'slp_token_count': children?.length ?? 0, 'slp_tokens': children?.map((e) => e.id.id).toList() ?? [], 'activation_params': bchConfig.toRpcParams()})}',
            name: 'BchActivationStrategy',
          );
        }

        // Enable BCH with SLP support
        final response = await client.rpc.slp.enableBchWithTokens(
          ticker: asset.id.id,
          params: bchConfig,
          slpTokensRequests: slpTokensRequests,
        );

        if (KdfLoggingConfig.verboseLogging) {
          log(
            '[RPC] Successfully activated BCH with ${children?.length ?? 0} SLP tokens',
            name: 'BchActivationStrategy',
          );
        }

        yield ActivationProgress(
          status: 'Verifying activation...',
          progressPercentage: 75,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.verification,
            stepCount: 4,
            additionalInfo: {
              'currentBlock': response.currentBlock,
              'addresses': response.bchAddressesInfos.length,
            },
          ),
        );

        yield ActivationProgress.success(
          details: ActivationProgressDetails(
            currentStep: ActivationStep.complete,
            stepCount: 4,
            additionalInfo: {
              'activatedChain': 'BCH',
              'slpTokenCount': children?.length ?? 0,
              'activationTime': DateTime.now().toIso8601String(),
            },
          ),
        );
      } else {
        // Individual SLP token activation
        yield const ActivationProgress(
          status: 'Activating SLP token...',
          progressPercentage: 50,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.tokenActivation,
            stepCount: 2,
          ),
        );

        // Debug logging for SLP token activation
        if (KdfLoggingConfig.verboseLogging) {
          log(
            '[RPC] Activating SLP token: ${asset.id.id}',
            name: 'BchActivationStrategy',
          );
          log(
            '[RPC] Activation parameters: ${jsonEncode({'ticker': asset.id.id, 'protocol': asset.protocol.subClass.formatted, 'parent_id': asset.id.parentId?.id})}',
            name: 'BchActivationStrategy',
          );
        }

        await client.rpc.slp.enableSlpToken(
          ticker: asset.id.id,
          params: SlpActivationParams(),
        );

        if (KdfLoggingConfig.verboseLogging) {
          log(
            '[RPC] Successfully activated SLP token: ${asset.id.id}',
            name: 'BchActivationStrategy',
          );
        }

        yield ActivationProgress.success(
          details: ActivationProgressDetails(
            currentStep: ActivationStep.complete,
            stepCount: 2,
            additionalInfo: {
              'activatedToken': asset.id.name,
              'activationTime': DateTime.now().toIso8601String(),
            },
          ),
        );
      }
    } catch (e, stack) {
      yield buildErrorProgress(
        asset: asset,
        error: e,
        stackTrace: stack,
        errorCode: isBch ? 'BCH_ACTIVATION_ERROR' : 'SLP_ACTIVATION_ERROR',
        stepCount: 4,
      );
    }
  }
}
