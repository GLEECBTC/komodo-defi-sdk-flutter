import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Storage for custom tokens that are not part of the official coin configuration.
/// These tokens are persisted independently from the main coin configuration
/// and are not affected by coin config updates.
class CustomTokenStorage implements CustomTokenStore {
  /// Creates a custom token storage instance.
  /// [customTokensBoxName] is the name of the Hive box for storing custom tokens.
  /// [customTokensBox] is an optional pre-opened LazyBox for testing/mocking.
  CustomTokenStorage({
    this.customTokensBoxName = 'custom_tokens',
    LazyBox<Asset>? customTokensBox,
    AssetParser assetParser = const AssetParser(),
  }) : _customTokensBox = customTokensBox,
       _assetParser = assetParser;

  static final Logger _log = Logger('CustomTokenStorage');

  /// The name of the Hive box for custom tokens.
  final String customTokensBoxName;

  /// Not final to allow for reopening if closed or in a corrupted state.
  LazyBox<Asset>? _customTokensBox;

  /// The asset parser used to rebuild parent-child relationships.
  final AssetParser _assetParser;

  @override
  Future<void> init() async {
    // Initialize by opening the box - this ensures storage is ready
    await _openCustomTokensBox();
  }

  @override
  Future<void> storeCustomToken(Asset asset) async {
    _log.fine('Storing custom token ${asset.id.id}');
    final box = await _openCustomTokensBox();
    await _validateCanStoreAsset(box, asset);
    await box.put(asset.id.id, asset);
  }

  @override
  Future<void> storeCustomTokens(List<Asset> assets) async {
    _log.fine('Storing ${assets.length} custom tokens');
    final box = await _openCustomTokensBox();
    _validateBatchCollisions(assets);
    for (final asset in assets) {
      await _validateCanStoreAsset(box, asset);
    }
    final putMap = <String, Asset>{for (final a in assets) a.id.id: a};
    await box.putAll(putMap);
  }

  @override
  Future<List<Asset>> getAllCustomTokens(Set<AssetId> knownIds) async {
    _log.fine('Retrieving all custom tokens');
    final box = await _openCustomTokensBox();
    final keys = box.keys.cast<String>();
    final values = await Future.wait(keys.map(box.get));

    return _assetParser
        .rebuildParentChildRelationshipsWithKnownParents(
          values.whereType<Asset>(),
          knownIds,
          logContext: 'for custom tokens',
        )
        .map(
          (asset) => asset.copyWith(protocol: _markCustomToken(asset.protocol)),
        )
        .toList();
  }

  @override
  Future<Asset?> getCustomToken(AssetId assetId) async {
    _log.fine('Retrieving custom token ${assetId.id}');
    final box = await _openCustomTokensBox();
    final asset = await box.get(assetId.id);
    return asset?.copyWith(protocol: _markCustomToken(asset.protocol));
  }

  @override
  Future<bool> hasCustomToken(AssetId assetId) async {
    final box = await _openCustomTokensBox();
    return box.containsKey(assetId.id);
  }

  @override
  Future<bool> deleteCustomToken(AssetId assetId) async {
    _log.fine('Deleting custom token ${assetId.id}');
    final box = await _openCustomTokensBox();
    final existed = box.containsKey(assetId.id);
    await box.delete(assetId.id);
    return existed;
  }

  @override
  Future<int> deleteCustomTokens(List<AssetId> assetIds) async {
    _log.fine('Deleting ${assetIds.length} custom tokens');
    final box = await _openCustomTokensBox();
    final keys = assetIds.map((id) => id.id).toList();

    // Count how many actually exist before deletion
    var deletedCount = 0;
    for (final key in keys) {
      if (box.containsKey(key)) {
        deletedCount++;
      }
    }

    await box.deleteAll(keys);
    return deletedCount;
  }

  @override
  Future<void> deleteAllCustomTokens() async {
    _log.fine('Deleting all custom tokens');
    final box = await _openCustomTokensBox();
    await box.clear();
  }

  @override
  Future<bool> hasCustomTokens() async {
    final exists = await Hive.boxExists(customTokensBoxName);
    if (!exists) return false;
    final box = await _openCustomTokensBox();
    return box.isNotEmpty;
  }

  @override
  Future<bool> upsertCustomToken(Asset asset) async {
    final box = await _openCustomTokensBox();
    final existingAsset = await box.get(asset.id.id);
    final existed = existingAsset != null;
    _assertNoConflict(existingAsset, asset);
    await box.put(asset.id.id, asset);

    if (existed) {
      _log.fine('Updated existing custom token ${asset.id.id}');
    } else {
      _log.fine('Stored new custom token ${asset.id.id}');
    }

    return existed;
  }

  @override
  Future<bool> addCustomTokenIfNotExists(Asset asset) async {
    final box = await _openCustomTokensBox();
    final existingAsset = await box.get(asset.id.id);
    if (existingAsset != null) {
      _assertNoConflict(existingAsset, asset);
      _log.fine('Custom token ${asset.id.id} already exists, skipping');
      return false;
    }

    await box.put(asset.id.id, asset);
    _log.fine('Added new custom token ${asset.id.id}');
    return true;
  }

  @override
  Future<int> getCustomTokenCount() async {
    final box = await _openCustomTokensBox();
    return box.length;
  }

  @override
  Future<void> dispose() async {
    if (_customTokensBox != null) {
      _log.fine('Closing custom tokens box');
      await _customTokensBox!.close();
      _customTokensBox = null;
    }
  }

  Future<LazyBox<Asset>> _openCustomTokensBox() async {
    if (_customTokensBox == null || !_customTokensBox!.isOpen) {
      _log.fine('Opening custom tokens box "$customTokensBoxName"');
      try {
        _customTokensBox = await Hive.openLazyBox<Asset>(customTokensBoxName);
      } catch (e) {
        _log.warning('Failed to open custom tokens box, retrying: $e');
        // If the box is in a corrupted state, try to delete and recreate
        if (await Hive.boxExists(customTokensBoxName)) {
          await _customTokensBox?.close();
        }
        _customTokensBox = await Hive.openLazyBox<Asset>(customTokensBoxName);
      }
    }

    return _customTokensBox!;
  }

  Future<void> _validateCanStoreAsset(LazyBox<Asset> box, Asset asset) async {
    final existingAsset = await box.get(asset.id.id);
    _assertNoConflict(existingAsset, asset);
  }

  void _validateBatchCollisions(List<Asset> assets) {
    final assetsById = <String, Asset>{};
    for (final asset in assets) {
      final existingAsset = assetsById[asset.id.id];
      _assertNoConflict(existingAsset, asset);
      assetsById[asset.id.id] = asset;
    }
  }

  void _assertNoConflict(Asset? existingAsset, Asset requestedAsset) {
    if (existingAsset == null) {
      return;
    }

    if (_hasMatchingContract(existingAsset, requestedAsset)) {
      return;
    }

    throw CustomTokenConflictException(
      assetId: requestedAsset.id.id,
      network: requestedAsset.id.subClass,
      existingContractAddress: existingAsset.protocol.contractAddress ?? '',
      requestedContractAddress: requestedAsset.protocol.contractAddress ?? '',
    );
  }

  bool _hasMatchingContract(Asset existingAsset, Asset requestedAsset) {
    final hasMatchingIdentity =
        existingAsset.id.subClass == requestedAsset.id.subClass &&
        existingAsset.id.chainId.formattedChainId ==
            requestedAsset.id.chainId.formattedChainId &&
        existingAsset.id.parentId == requestedAsset.id.parentId;
    if (!hasMatchingIdentity) {
      return false;
    }

    final existingContractAddress = existingAsset.protocol.contractAddress;
    final requestedContractAddress = requestedAsset.protocol.contractAddress;
    if (existingContractAddress == null || requestedContractAddress == null) {
      return false;
    }

    return _normalizeContractAddress(
          existingAsset.id.subClass,
          existingContractAddress,
        ) ==
        _normalizeContractAddress(
          requestedAsset.id.subClass,
          requestedContractAddress,
        );
  }

  String _normalizeContractAddress(
    CoinSubClass network,
    String contractAddress,
  ) {
    return network == CoinSubClass.trc20
        ? contractAddress
        : contractAddress.toLowerCase();
  }
  ProtocolClass _markCustomToken(ProtocolClass protocol) {
    return switch (protocol) {
      final Erc20Protocol p => p.copyWith(isCustomToken: true),
      final Trc20Protocol p => p.copyWith(isCustomToken: true),
      _ => throw UnsupportedError(
        'Unsupported custom token protocol: ${protocol.runtimeType}',
      ),
    };
  }
}
