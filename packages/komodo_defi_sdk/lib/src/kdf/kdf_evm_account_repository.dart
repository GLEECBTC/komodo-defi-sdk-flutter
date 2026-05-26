// ignore_for_file: document_ignores, public_member_api_docs

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const int kdfGnosisChainId = 100;
const String kdfGnosisGasAssetId = 'XDAI';

enum KdfEvmSigningPolicy { software, trezor, walletConnect, metamask }

final class KdfEvmAccount {
  const KdfEvmAccount({
    required this.walletRef,
    required this.addressRef,
    required this.address,
    required this.chainId,
    required this.assetId,
    required this.label,
    required this.signingPolicy,
    this.derivationPath,
  });

  final String walletRef;
  final String addressRef;
  final String address;
  final int chainId;
  final String assetId;
  final String label;
  final KdfEvmSigningPolicy signingPolicy;
  final String? derivationPath;
}

final class KdfEvmPrivateKey {
  const KdfEvmPrivateKey({
    required this.privateKeyHex,
    required this.address,
    required this.assetId,
    this.derivationPath,
  });

  final String privateKeyHex;
  final String address;
  final String assetId;
  final String? derivationPath;

  @override
  String toString() {
    return 'KdfEvmPrivateKey(assetId: $assetId, address: $address, '
        'derivationPath: $derivationPath, privateKeyHex: <redacted>)';
  }
}

final class KdfEvmAccountRepository {
  KdfEvmAccountRepository({required KomodoDefiSdk sdk}) : _sdk = sdk;

  final KomodoDefiSdk _sdk;

  Future<List<KdfEvmAccount>> listAccounts({
    String assetId = kdfGnosisGasAssetId,
    int chainId = kdfGnosisChainId,
    bool activeForSwapOnly = true,
  }) async {
    await _sdk.ensureInitialized();
    final user = await _requireCurrentUser();
    final asset = await _requireAsset(assetId);
    final activation = await _sdk.ensureAssetActivated(asset);
    if (!activation) {
      throw StateError('KDF asset $assetId could not be activated.');
    }

    final pubkeys = await _sdk.pubkeys.getPubkeys(asset);
    final policy = _signingPolicy(user.walletId.authOptions.privKeyPolicy);

    return [
      for (final key in pubkeys.keys)
        if (!activeForSwapOnly || key.isActiveForSwap)
          KdfEvmAccount(
            walletRef: user.walletId.compoundId,
            addressRef: _addressRef(assetId, key),
            address: key.address,
            chainId: chainId,
            assetId: assetId,
            label: key.name ?? 'Gnosis account',
            signingPolicy: policy,
            derivationPath: key.derivationPath,
          ),
    ];
  }

  Future<KdfEvmPrivateKey> exportPrivateKey({
    required KdfEvmAccount account,
    KeyExportMode? mode,
  }) async {
    await _sdk.ensureInitialized();
    await _requireCurrentUser();
    final asset = await _requireAsset(account.assetId);
    final keys = await _sdk.security.getPrivateKey(
      asset.id,
      mode: mode,
      startIndex: _addressIndex(account.derivationPath),
      endIndex: _addressIndex(account.derivationPath),
    );
    final exported = keys[asset.id] ?? const <PrivateKey>[];
    final matches = exported.where((key) {
      final sameAddress =
          key.publicKeyAddress.trim().toLowerCase() ==
          account.address.trim().toLowerCase();
      final samePath =
          account.derivationPath == null ||
          key.hdInfo?.derivationPath == account.derivationPath;
      return sameAddress && samePath;
    }).toList();
    final match = matches.length == 1 ? matches.single : null;
    if (match == null) {
      throw StateError('No exported KDF key matched ${account.address}.');
    }
    return KdfEvmPrivateKey(
      privateKeyHex: match.privateKey,
      address: match.publicKeyAddress,
      assetId: account.assetId,
      derivationPath: match.hdInfo?.derivationPath,
    );
  }

  Future<KdfUser> _requireCurrentUser() async {
    final user = await _sdk.auth.currentUser;
    if (user == null) {
      throw AuthException.notSignedIn();
    }
    return user;
  }

  Future<Asset> _requireAsset(String assetId) async {
    final matches = _sdk.assets.findAssetsByConfigId(assetId);
    if (matches.isEmpty) {
      throw StateError('KDF asset $assetId is not configured.');
    }
    return matches.single;
  }
}

String _addressRef(String assetId, PubkeyInfo key) {
  return [assetId, key.derivationPath ?? key.address].join(':');
}

int? _addressIndex(String? derivationPath) {
  if (derivationPath == null) return null;
  final last = derivationPath.split('/').last;
  return int.tryParse(last.replaceAll("'", ''));
}

KdfEvmSigningPolicy _signingPolicy(PrivateKeyPolicy policy) {
  return switch (policy.pascalCaseName) {
    'Trezor' => KdfEvmSigningPolicy.trezor,
    'Metamask' => KdfEvmSigningPolicy.metamask,
    'WalletConnect' => KdfEvmSigningPolicy.walletConnect,
    _ => KdfEvmSigningPolicy.software,
  };
}
