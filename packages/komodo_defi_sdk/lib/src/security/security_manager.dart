import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/security/private_key_conversion_extension.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A manager for security-sensitive wallet operations.
///
/// This manager handles operations that involve private keys or other
/// sensitive cryptographic material. All operations require proper
/// authentication and should be used with caution.
///
/// **Security Note**: Private key operations are extremely sensitive.
/// Ensure proper authentication before calling these methods and
/// handle returned private keys securely.
class SecurityManager {
  /// Creates a new [SecurityManager] instance.
  SecurityManager(
    this._client,
    this._auth,
    this._assetProvider,
    this._activationCoordinator,
  );

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;

  /// Gets private keys for the specified assets.
  ///
  /// This method exports private keys for assets, supporting both HD wallet
  /// and Iguana (standard) modes. The exported keys can be used to recover
  /// funds or import into other wallets.
  ///
  /// **⚠️ SECURITY WARNING**: This method exposes private keys which provide
  /// full control over the associated funds. Use with extreme caution:
  /// - Only call this method when absolutely necessary
  /// - Ensure secure handling of returned private keys
  /// - Never log or store private keys in plain text
  /// - Clear private key data from memory when no longer needed
  ///
  /// Parameters:
  /// - [assets]: List of asset IDs to export keys for. If null, will use all
  ///   assets that have been successfully activated, are pending activation,
  ///   or have failed activation
  /// - [mode]: Export mode (HD or Iguana). If null, defaults based on wallet
  ///   type
  /// - [startIndex]: Starting address index for HD mode (default: 0)
  /// - [endIndex]: Ending address index for HD mode (default: startIndex + 10)
  /// - [accountIndex]: Account index for HD mode (default: 0)
  ///
  /// Returns a map where:
  /// - Keys are [AssetId] objects
  /// - Values are lists of [PrivateKey] objects containing the private key data
  ///
  /// For HD wallets, each address becomes a separate [PrivateKey] with
  /// [PrivateKeyHdInfo] containing the derivation path.
  ///
  /// For standard wallets, there's typically one [PrivateKey] per asset.
  ///
  /// Throws:
  /// - [StateError] if user is not authenticated
  /// - [GeneralErrorResponse] if the RPC call fails
  /// - [ArgumentError] if invalid parameters are provided
  ///
  /// Example:
  /// ```dart
  /// // Check if authenticated first
  /// if (await securityManager.isAuthenticated) {
  ///   // Get private keys for all assets (activated, pending, or failed)
  ///   final privateKeyMap = await securityManager.getPrivateKeys();
  ///
  ///   // Get private keys for specific assets
  ///   final btcAsset = assetManager.findAssetsByTicker('BTC').first;
  ///   final privateKeyMap = await securityManager.getPrivateKeys(
  ///     assets: [btcAsset.id],
  ///     mode: KeyExportMode.iguana,
  ///   );
  ///
  ///   for (final entry in privateKeyMap.entries) {
  ///     final assetId = entry.key;
  ///     final privateKeys = entry.value;
  ///
  ///     for (final privateKey in privateKeys) {
  ///       print('Asset: ${assetId.id}');
  ///       print('Public Key (secp256k1): ${privateKey.publicKeySecp256k1}');
  ///       print('Public Key Address: ${privateKey.publicKeyAddress}');
  ///       print('Derivation Path: ${privateKey.hdInfo?.derivationPath ?? 'N/A'}');
  ///       // Handle private key securely: privateKey.privateKey
  ///     }
  ///   }
  /// }
  /// ```
  Future<Map<AssetId, List<PrivateKey>>> getPrivateKeys({
    List<AssetId>? assets,
    KeyExportMode? mode,
    int? startIndex,
    int? endIndex,
    int? accountIndex,
  }) async {
    // Ensure user is authenticated before proceeding with sensitive operation
    final currentUser = await _auth.currentUser;
    if (currentUser == null) {
      throw AuthException.notSignedIn();
    }

    // If no assets specified, use all assets for which their activation is
    // successful, pending, or failed.
    final targetAssets =
        assets != null
            ? assets.toSet()
            : {
              ...(await _assetProvider.getActivatedAssets()).map((a) => a.id),
              ..._activationCoordinator.pendingActivations,
              ..._activationCoordinator.failedActivations,
            };

    // Filter out coins whose RPCs don't implement get_private_keys / show_priv_key.
    // Currently, SIA-based assets would throw "Unsupported" errors if included.
    final filteredTargetAssets =
        targetAssets
            .where((assetId) => assetId.subClass != CoinSubClass.sia)
            .toSet();

    // Validate parameters
    if (filteredTargetAssets.isEmpty) {
      return {};
    }

    // Convert AssetId objects to coin ticker strings for the RPC call
    final coinTickers =
        filteredTargetAssets.map((assetId) => assetId.id).toList();

    // Create a map from coin ticker to AssetId for conversion
    final assetMap = <String, AssetId>{
      for (final assetId in filteredTargetAssets) assetId.id: assetId,
    };

    // If HD mode parameters are provided, ensure they're valid
    if (mode == KeyExportMode.hd) {
      final start = startIndex;
      final end = endIndex;

      if (start != null && start < 0) {
        throw ArgumentError('startIndex must be non-negative');
      }

      if (end != null && start != null) {
        if (end < start) {
          throw ArgumentError(
            'endIndex must be greater than or equal to startIndex',
          );
        }

        if (end - start > 100) {
          throw ArgumentError('Index range cannot exceed 100 addresses');
        }
      }

      if (accountIndex != null && accountIndex < 0) {
        throw ArgumentError('accountIndex must be non-negative');
      }
    } else if (mode == KeyExportMode.iguana) {
      // Validate that HD-specific parameters are not provided for Iguana mode
      if (startIndex != null || endIndex != null || accountIndex != null) {
        throw ArgumentError(
          'startIndex, endIndex, and accountIndex are only valid for HD mode',
        );
      }
    }

    final response = await _client.rpc.wallet.getPrivateKeys(
      coins: coinTickers,
      mode: mode,
      startIndex: startIndex,
      endIndex: endIndex,
      accountIndex: accountIndex,
    );

    return response.toPrivateKeyInfoMap(assetMap);
  }

  /// Convenience method to get private keys for a single asset.
  ///
  /// This is a wrapper around [getPrivateKeys] for the common case of
  /// exporting keys for a single asset.
  ///
  /// **⚠️ SECURITY WARNING**: Same security considerations as [getPrivateKeys]
  /// apply.
  ///
  /// Parameters:
  /// - [asset]: The asset ID to export keys for
  /// - [mode]: Export mode (HD or Iguana). If null, defaults based on
  ///   authenticated wallet type.
  /// - [startIndex]: Starting address index for HD mode (default: 0)
  /// - [endIndex]: Ending address index for HD mode (default: startIndex + 10)
  /// - [accountIndex]: Account index for HD mode (default: 0)
  ///
  /// Returns a map containing the private key information for the single asset.
  Future<Map<AssetId, List<PrivateKey>>> getPrivateKey(
    AssetId asset, {
    KeyExportMode? mode,
    int? startIndex,
    int? endIndex,
    int? accountIndex,
  }) {
    return getPrivateKeys(
      assets: [asset],
      mode: mode,
      startIndex: startIndex,
      endIndex: endIndex,
      accountIndex: accountIndex,
    );
  }

  /// Dispose of any resources
  Future<void> dispose() async {
    // No cleanup needed currently
  }
}
