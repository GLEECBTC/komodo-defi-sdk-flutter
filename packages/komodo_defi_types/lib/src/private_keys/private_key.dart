import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/src/assets/asset_id.dart' show AssetId;

class PrivateKey extends Equatable {
  const PrivateKey({
    required this.assetId,
    required this.publicKeySecp256k1,
    required this.publicKeyAddress,
    required this.privateKey,
    this.hdInfo,
    this.viewingKey,
  });

  final AssetId assetId;
  final String publicKeySecp256k1;
  final String publicKeyAddress;
  final String privateKey;
  final PrivateKeyHdInfo? hdInfo;
  final String? viewingKey;

  @override
  String toString() => 'PrivateKey(redacted)';

  JsonMap toJson() {
    return {
      'asset_id': assetId.toJson(),
      'public_key_secp256k1': publicKeySecp256k1,
      'public_key_address': publicKeyAddress,
      'private_key': privateKey,
      if (hdInfo != null) 'hd_info': hdInfo!.toJson(),
      if (viewingKey != null) 'viewing_key': viewingKey,
    };
  }

  @override
  List<Object?> get props => [
    assetId,
    publicKeySecp256k1,
    publicKeyAddress,
    privateKey,
    hdInfo,
    viewingKey,
  ];
}

class PrivateKeyHdInfo extends Equatable {
  const PrivateKeyHdInfo({required this.derivationPath, this.zDerivationPath});

  final String derivationPath;
  final String? zDerivationPath;

  JsonMap toJson() {
    return {
      'derivation_path': derivationPath,
      if (zDerivationPath != null) 'z_derivation_path': zDerivationPath,
    };
  }

  @override
  List<Object?> get props => [derivationPath, zDerivationPath];
}
