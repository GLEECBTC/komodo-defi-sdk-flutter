import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Extension on [GetPrivateKeysResponse] to convert the response to a map
/// of asset IDs to lists of private keys.
extension PrivateKeyConversionExtension on GetPrivateKeysResponse {
  /// Converts the private keys response to a map of [AssetId] to
  /// [List<PrivateKey>].
  ///
  /// This method handles both standard and HD wallet responses, creating
  /// [PrivateKey] instances with appropriate HD information when available.
  ///
  /// The [assetMap] parameter is used to map coin ticker strings from the
  /// response to their corresponding [AssetId] objects. This is necessary
  /// because the RPC response only contains coin tickers, not full AssetId
  /// information.
  ///
  /// Parameters:
  /// - [assetMap]: A map from coin ticker strings to [AssetId] objects
  ///
  /// Returns a map where:
  /// - Keys are [AssetId] objects from the provided asset map
  /// - Values are lists of [PrivateKey] objects containing the private key data
  ///
  /// For HD wallets, each address in the HD response becomes a separate
  /// [PrivateKey] with [PrivateKeyHdInfo] containing the derivation path.
  ///
  /// For standard wallets, there's typically one [PrivateKey] per asset.
  ///
  /// Throws [StateError] if a coin ticker from the response is not found in
  /// the asset map.
  Map<AssetId, List<PrivateKey>> toPrivateKeyInfoMap(
    Map<String, AssetId> assetMap,
  ) {
    final result = <AssetId, List<PrivateKey>>{};

    if (isStandardResponse) {
      // Handle standard (non-HD) keys
      for (final coinKeyInfo in standardKeys!) {
        final assetId = assetMap[coinKeyInfo.coin];
        if (assetId == null) {
          throw StateError(
            'Asset ID not found for coin ticker: ${coinKeyInfo.coin}',
          );
        }

        final privateKey = PrivateKey(
          assetId: assetId,
          publicKeySecp256k1: coinKeyInfo.publicKeySecp256k1,
          publicKeyAddress: coinKeyInfo.publicKeyAddress,
          privateKey: coinKeyInfo.privKey,
          // No HD info for standard keys
        );

        result[assetId] = [privateKey];
      }
    } else if (isHdResponse) {
      // Handle HD wallet keys
      for (final hdCoinInfo in hdKeys!) {
        final assetId = assetMap[hdCoinInfo.coin];
        if (assetId == null) {
          throw StateError(
            'Asset ID not found for coin ticker: ${hdCoinInfo.coin}',
          );
        }

        final privateKeys = <PrivateKey>[];

        for (final addressInfo in hdCoinInfo.addresses) {
          final privateKey = PrivateKey(
            assetId: assetId,
            publicKeySecp256k1: addressInfo.publicKeySecp256k1,
            publicKeyAddress: addressInfo.publicKeyAddress,
            privateKey: addressInfo.privKey,
            hdInfo: PrivateKeyHdInfo(
              derivationPath: addressInfo.derivationPath,
            ),
          );
          privateKeys.add(privateKey);
        }

        result[assetId] = privateKeys;
      }
    }

    return result;
  }
}
