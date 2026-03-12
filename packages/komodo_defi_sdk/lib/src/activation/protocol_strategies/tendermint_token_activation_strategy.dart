import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Activation strategy for individual Tendermint tokens.
/// Handles IBC tokens (ATOM-IBC_IRIS, IRIS-IBC_OSMO) that are activated individually
/// after their platform coin is already active.
class TendermintTokenActivationStrategy extends ProtocolActivationStrategy {
  /// Creates a new [TendermintTokenActivationStrategy] with the given client and
  /// private key policy.
  const TendermintTokenActivationStrategy(super.client, this.privKeyPolicy);

  /// The private key policy to use for activation.
  final PrivateKeyPolicy privKeyPolicy;

  @override
  Set<CoinSubClass> get supportedProtocols => {
    CoinSubClass.tendermint,
    CoinSubClass.tendermintToken,
  };

  @override
  bool get supportsBatchActivation => false;

  @override
  bool canHandle(Asset asset) {
    // Use tendermint token activation for token assets (not platform assets, not trezor)
    final isTokenAsset = asset.id.parentId != null;
    return isTokenAsset &&
        privKeyPolicy != const PrivateKeyPolicy.trezor() &&
        super.canHandle(asset);
  }

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    if (children?.isNotEmpty == true) {
      throw StateError('Token assets cannot perform batch activation');
    }

    yield ActivationProgress(
      status: 'Activating ${asset.id.name} token...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.initialization,
        stepCount: 3,
        additionalInfo: {
          'assetType': 'token',
          'protocol': asset.protocol.subClass.formatted,
          'parentCoin': asset.id.parentId,
        },
      ),
    );

    try {
      yield ActivationProgress(
        status: 'Configuring token activation...',
        progressPercentage: 33,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.processing,
          stepCount: 3,
          additionalInfo: {
            'method': 'enable_tendermint_token',
            'ticker': asset.id.id,
          },
        ),
      );

      await client.rpc.tendermint.enableTendermintToken(
        ticker: asset.id.id,
        params: TendermintTokenActivationParams(
          mode: ActivationMode(rpc: ActivationModeType.native.value),
        ).copyWith(privKeyPolicy: privKeyPolicy),
      );

      yield const ActivationProgress(
        status: 'Finalizing activation...',
        progressPercentage: 66,
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.processing,
          stepCount: 3,
        ),
      );

      yield ActivationProgress.success(
        details: ActivationProgressDetails(
          currentStep: ActivationStep.complete,
          stepCount: 3,
          additionalInfo: {
            'activatedToken': asset.id.name,
            'activationTime': DateTime.now().toIso8601String(),
            'method': 'enable_tendermint_token',
            'parentCoin': asset.id.parentId,
          },
        ),
      );
    } catch (e, stack) {
      yield buildErrorProgress(
        asset: asset,
        error: e,
        stackTrace: stack,
        errorCode: 'TENDERMINT_TOKEN_ACTIVATION_ERROR',
        stepCount: 3,
      );
    }
  }
}
