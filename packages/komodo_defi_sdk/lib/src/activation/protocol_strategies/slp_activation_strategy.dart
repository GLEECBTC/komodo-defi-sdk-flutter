import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

@Deprecated('SLP is no longer supported it its authors')
class SlpActivationStrategy extends ProtocolActivationStrategy {
  @Deprecated('SLP is no longer supported it its authors')
  const SlpActivationStrategy(super.client);

  @override
  Set<CoinSubClass> get supportedProtocols => {CoinSubClass.slp};

  @override
  bool get supportsBatchActivation => true;

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    final isPlatformAsset = asset.id.parentId == null;
    if (!isPlatformAsset && children?.isNotEmpty == true) {
      throw StateError('Child assets cannot perform batch activation');
    }

    yield ActivationProgress(
      status: 'Starting BCH/SLP activation...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 3,
        additionalInfo: {
          'assetType': isPlatformAsset ? 'platform' : 'token',
          'protocol': 'SLP',
          'childCount': children?.length ?? 0,
        },
      ),
    );

    try {
      if (isPlatformAsset) {
        final protocol = asset.protocol as SlpProtocol;
        yield ActivationProgress(
          status: 'Configuring BCH platform...',
          progressPercentage: 33,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.platformSetup,
            stepCount: 3,
            additionalInfo: {
              'bchdServers': protocol.bchdUrls.length,
              'electrumServers': protocol.requiredServers,
            },
          ),
        );

        await client.rpc.slp.enableBchWithTokens(
          ticker: asset.id.id,
          params: BchActivationParams.fromJson(protocol.config),
          slpTokensRequests:
              children
                  ?.map((child) => TokensRequest(ticker: child.id.id))
                  .toList() ??
              [],
        );
      } else {
        yield const ActivationProgress(
          status: 'Activating SLP token...',
          progressPercentage: 66,
          progressDetails: ActivationProgressDetails(
            currentStep: ActivationStep.tokenActivation,
            stepCount: 3,
          ),
        );

        await client.rpc.slp.enableSlpToken(
          ticker: asset.id.id,
          params: SlpActivationParams(),
        );
      }
      yield ActivationProgress.success(
        details: ActivationProgressDetails(
          currentStep: ActivationStep.complete,
          stepCount: 3,
          additionalInfo: {
            'activatedChain': asset.id.name,
            'activationTime': DateTime.now().toIso8601String(),
          },
        ),
      );
    } catch (e, stack) {
      yield buildErrorProgress(
        asset: asset,
        error: e,
        stackTrace: stack,
        errorCode: 'SLP_ACTIVATION_ERROR',
        stepCount: 3,
      );
    }
  }
}
