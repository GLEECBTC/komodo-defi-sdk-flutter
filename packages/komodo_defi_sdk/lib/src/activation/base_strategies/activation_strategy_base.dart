import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:meta/meta.dart';

abstract class AssetActivator {
  const AssetActivator(this.client);

  final ApiClient client;

  Stream<ActivationProgress> activate(Asset asset, [List<Asset>? children]);
  bool canHandle(Asset asset);
}

/// Base for strategies that support batch operations
abstract class BatchCapableActivator extends AssetActivator {
  const BatchCapableActivator(super.client);

  bool get supportsBatchActivation;

  /// Whether the activator supports activation of custom EVM-chain
  /// tokens that are not part of the live coins configuration.
  /// Defaults to false.
  bool get supportsCustomTokenActivation => false;
}

/// Smart activator that chooses between batch/single methods
class SmartAssetActivator extends BatchCapableActivator {
  SmartAssetActivator(
    super.client,
    this._activator,
    this._activatedAssetsCache,
  );

  final CompositeAssetActivator _activator;
  final ActivatedAssetsCache _activatedAssetsCache;

  @override
  bool get supportsBatchActivation => true;

  @override
  bool canHandle(Asset asset) => _activator.canHandle(asset);

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    // Check if parent is already activated
    final parentActivated = await _isAssetActive(asset);
    final hasChildren = children?.isNotEmpty ?? false;

    yield ActivationProgress(
      status: 'Planning activation strategy...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.planning,
        stepCount: 1,
        additionalInfo: {
          'parentActivated': parentActivated,
          'hasChildren': hasChildren,
          'supportsBatch': _supportsBatchActivation(asset),
        },
      ),
    );

    if (!parentActivated && hasChildren && _supportsBatchActivation(asset)) {
      // Parent not active + has children = use batch activation
      yield* _activator.activate(asset, children);
    } else if (!parentActivated) {
      // Parent not active, no children = activate parent only
      yield* _activator.activate(asset);
    } else if (hasChildren) {
      // Parent active + has children = activate children individually
      for (final child in children!) {
        if (!await _isAssetActive(child)) {
          yield* _activator.activate(child);
        }
      }
    } else {
      // Single asset activation
      yield* _activator.activate(asset);
    }
  }

  Future<bool> _isAssetActive(Asset asset) async {
    // Use cache instead of direct RPC call to avoid excessive requests
    final enabledAssetIds = await _activatedAssetsCache.getActivatedAssetIds();
    return enabledAssetIds.contains(asset.id);
  }

  bool _supportsBatchActivation(Asset asset) {
    return _activator.supportsBatchActivationFor(asset);
  }
}

/// Composite activator that chains multiple activation strategies
class CompositeAssetActivator extends BatchCapableActivator {
  CompositeAssetActivator(
    super.client,
    List<ProtocolActivationStrategy> strategies,
  ) : _strategies = strategies;

  final List<ProtocolActivationStrategy> _strategies;

  @override
  bool get supportsBatchActivation => true;

  ProtocolActivationStrategy _findStrategy(Asset asset) {
    final strategy = _strategies.firstWhere(
      (s) => s.canHandle(asset),
      orElse: () => throw UnsupportedError(
        'No activation strategy found for ${asset.id}',
      ),
    );
    return strategy;
  }

  bool supportsBatchActivationFor(Asset asset) {
    return _findStrategy(asset).supportsBatchActivation;
  }

  @override
  bool canHandle(Asset asset) => _strategies.any((s) => s.canHandle(asset));

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    yield ActivationProgress(
      status: 'Finding appropriate activation strategy...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.strategySelection,
        stepCount: 1,
        additionalInfo: {'assetId': asset.id.id},
      ),
    );

    final strategy = _findStrategy(asset);
    yield* strategy.activate(asset, children);
  }
}

/// Base class for protocol-specific activation implementations
abstract class ProtocolActivationStrategy extends BatchCapableActivator {
  const ProtocolActivationStrategy(super.client);

  @override
  bool canHandle(Asset asset) =>
      // | isCustomToken | supportsCustomTokenActivation | result |
      // |---------------|------------------------------|--------|
      // | true          | true                         | true   |
      // | true          | false                        | false  |
      // | false         | true                         | true   |
      // | false         | false                        | false  |
      (!asset.protocol.isCustomToken || supportsCustomTokenActivation) &&
      supportedProtocols.contains(asset.protocol.subClass);

  Set<CoinSubClass> get supportedProtocols;

  @protected
  ActivationProgress buildErrorProgress({
    required Asset asset,
    required Object error,
    StackTrace? stackTrace,
    required String errorCode,
    int stepCount = 1,
    String status = 'Activation failed',
  }) {
    const mapper = SdkErrorMapper();
    final sdkError = mapper.map(
      error,
      context: SdkErrorContext(operation: 'activation', assetId: asset.id.id),
    );
    return ActivationProgress(
      status: status,
      errorMessage: sdkError.fallbackMessage,
      sdkError: sdkError,
      isComplete: true,
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.error,
        stepCount: stepCount,
        errorCode: errorCode,
        errorDetails: sdkError.fallbackMessage,
        stackTrace: stackTrace?.toString(),
      ),
    );
  }
}
