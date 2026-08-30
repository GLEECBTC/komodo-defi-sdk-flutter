import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Returns a stable, opaque persistence namespace for one wallet context.
///
/// [WalletId.compoundId] intentionally omits authentication options for
/// backwards compatibility. Persisted caches cannot do that safely: wallets
/// with the same name and public-key hash can still use different derivation
/// or signing contexts. The weak-password acceptance flag is deliberately
/// excluded because it is a mutable login policy, not wallet identity.
/// Hashing a canonical payload keeps actual signing contexts isolated without
/// exposing signing-policy details in storage keys.
///
/// Enriched identities use the normalized public-key hash so display-name
/// changes keep their cache. Name-only identities use the name and are not
/// migrated automatically after enrichment, because a reused name is
/// insufficient proof that legacy data belongs to the authenticated wallet.
String walletStorageNamespace(WalletId walletId) {
  return _walletStorageNamespace(
    walletId,
    version: 2,
    authOptions: {
      'derivation_method': walletId.authOptions.derivationMethod.toString(),
      'priv_key_policy': walletId.authOptions.privKeyPolicy.toJson(),
    },
  );
}

/// Returns namespaces emitted by the immediately preceding implementation.
///
/// Version 1 incorrectly included the mutable weak-password acceptance flag.
/// Both possible values must remain discoverable so changing that preference
/// cannot hide an unresolved GasFree reservation.
Set<String> legacyWalletStorageNamespaces(WalletId walletId) => {
  for (final allowWeakPassword in const [false, true])
    _walletStorageNamespace(
      walletId,
      version: 1,
      authOptions: AuthOptions(
        derivationMethod: walletId.authOptions.derivationMethod,
        allowWeakPassword: allowWeakPassword,
        privKeyPolicy: walletId.authOptions.privKeyPolicy,
      ).toJson(),
    ),
};

String _walletStorageNamespace(
  WalletId walletId, {
  required int version,
  required Map<String, Object?> authOptions,
}) {
  final trimmedPubkeyHash = walletId.pubkeyHash?.trim();
  final normalizedPubkeyHash =
      trimmedPubkeyHash == null || trimmedPubkeyHash.isEmpty
      ? null
      : trimmedPubkeyHash.toLowerCase();
  final canonicalPayload = _canonicalJson({
    'auth_options': authOptions,
    if (normalizedPubkeyHash == null) 'name': walletId.name,
    if (normalizedPubkeyHash != null) 'pubkey_hash': normalizedPubkeyHash,
    'version': version,
  });
  return 'v$version:${sha256.convert(utf8.encode(canonicalPayload))}';
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
