import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

enum GaslessWalletType { softwareHd, softwareIguana }

@immutable
class GaslessCapabilityIdentity {
  const GaslessCapabilityIdentity({
    required this.assetId,
    required this.platform,
    required this.contractAddress,
    required this.providerAddress,
    required this.walletPubkeyHash,
    required this.walletType,
    required this.derivationPath,
  });

  final AssetId assetId;
  final String platform;
  final String contractAddress;
  final String providerAddress;
  final String walletPubkeyHash;
  final GaslessWalletType walletType;
  final String derivationPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GaslessCapabilityIdentity &&
          assetId == other.assetId &&
          platform == other.platform &&
          contractAddress == other.contractAddress &&
          providerAddress == other.providerAddress &&
          walletPubkeyHash == other.walletPubkeyHash &&
          walletType == other.walletType &&
          derivationPath == other.derivationPath;

  @override
  int get hashCode => Object.hash(
    assetId,
    platform,
    contractAddress,
    providerAddress,
    walletPubkeyHash,
    walletType,
    derivationPath,
  );
}

class _CanonicalGaslessToken {
  const _CanonicalGaslessToken({
    required this.platform,
    required this.contract,
    required this.chainId,
  });

  final String platform;
  final String contract;
  final String chainId;
}

/// Session-scoped, fail-closed source of truth for GasFree readiness.
class GaslessCapabilityRegistry {
  GaslessCapabilityRegistry({
    required Iterable<String> configuredAssetIds,
    String? pinnedProviderAddress,
    bool allowProviderDiscovery = false,
  }) : _configuredAssetIds = Set.unmodifiable(configuredAssetIds),
       _pinnedProviderAddress = pinnedProviderAddress?.trim(),
       _allowProviderDiscovery = allowProviderDiscovery;

  static const canonicalPrimaryDerivationPath = "m/44'/195'/0'/0/0";
  static const _canonicalTokens = <String, _CanonicalGaslessToken>{
    'USDT-TRC20': _CanonicalGaslessToken(
      platform: 'TRX',
      contract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      chainId: '728126428',
    ),
    'TESTUSDT-TRC20': _CanonicalGaslessToken(
      platform: 'TRXT',
      contract: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
      chainId: '3448148188',
    ),
  };

  final Set<String> _configuredAssetIds;
  final String? _pinnedProviderAddress;
  final bool _allowProviderDiscovery;
  final Map<AssetId, GaslessCapabilityIdentity> _readyIdentities = {};
  final Map<AssetId, GaslessCapabilityIdentity> _candidateIdentities = {};
  final Map<AssetId, GaslessVerificationMode> _verificationModes = {};
  final Map<AssetId, GaslessCapability> _states = {};

  Set<String> get configuredAssetIds => _configuredAssetIds;

  bool isConfigured(Asset asset) {
    final protocol = asset.protocol;
    final canonical = _canonicalTokens[asset.id.id];
    if (protocol is! Trc20Protocol ||
        protocol.isCustomToken ||
        canonical == null) {
      return false;
    }
    final contract =
        protocol.config.valueOrNull<String>('contract_address') ??
        protocol.config.valueOrNull<String>(
          'protocol',
          'protocol_data',
          'contract_address',
        );
    return _configuredAssetIds.contains(asset.id.id) &&
        protocol.platform == canonical.platform &&
        contract == canonical.contract;
  }

  bool isConfiguredId(AssetId assetId) =>
      _configuredAssetIds.contains(assetId.id) &&
      _canonicalTokens.containsKey(assetId.id);

  bool isReady(AssetId assetId) =>
      _readyIdentities.containsKey(assetId) &&
      _states[assetId]?.state == GaslessCapabilityState.ready;

  bool isReadyFor(GaslessCapabilityIdentity identity) =>
      isReady(identity.assetId) &&
      _readyIdentities[identity.assetId] == identity;

  /// New custody receives require KDF-bound relay context. Legacy PR #9 can
  /// only be used to recover or send funds already held in custody.
  bool canReceiveGasless(AssetId assetId) =>
      isReady(assetId) &&
      _verificationModes[assetId] == GaslessVerificationMode.boundRelay;

  /// Verifies that signed relay metadata is still bound to the exact canonical
  /// token/network/provider identity that was authoritatively marked ready.
  ///
  /// This is intentionally stricter than [isReady]: a ready bit alone must not
  /// authorize a preview whose signed payload was replaced after capability
  /// discovery.
  bool matchesReadyAuthorizationContext(
    AssetId assetId, {
    required String chainId,
    required String tokenContract,
    required String providerAddress,
    required String walletPubkeyHash,
    required GaslessVerificationMode verificationMode,
  }) {
    final canonical = _canonicalTokens[assetId.id];
    final identity = _readyIdentities[assetId];
    return isReady(assetId) &&
        canonical != null &&
        identity != null &&
        _verificationModes[assetId] == verificationMode &&
        chainId == canonical.chainId &&
        tokenContract == canonical.contract &&
        providerAddress == identity.providerAddress &&
        walletPubkeyHash == identity.walletPubkeyHash &&
        tokenContract == identity.contractAddress;
  }

  /// Promotes a legacy candidate only after a signed preview proves the exact
  /// configured provider and wallet identity. This never enables receives.
  bool proveLegacyReadyFromSignedPreview(
    AssetId assetId, {
    required String chainId,
    required String tokenContract,
    required String providerAddress,
    required String walletPubkeyHash,
  }) {
    final valid = matchesProvisionalAuthorizationContext(
      assetId,
      chainId: chainId,
      tokenContract: tokenContract,
      providerAddress: providerAddress,
      walletPubkeyHash: walletPubkeyHash,
    );
    if (!valid) {
      markSecurityMismatch(assetId, reasonCode: 'signed_preview_mismatch');
      return false;
    }
    _readyIdentities[assetId] = _candidateIdentities[assetId]!;
    _verificationModes[assetId] = GaslessVerificationMode.legacyOnChain;
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.ready,
      reasonCode: 'legacy_recovery_ready',
    );
    return true;
  }

  bool matchesProvisionalAuthorizationContext(
    AssetId assetId, {
    required String chainId,
    required String tokenContract,
    required String providerAddress,
    required String walletPubkeyHash,
  }) {
    final canonical = _canonicalTokens[assetId.id];
    final identity = _candidateIdentities[assetId];
    return canonical != null &&
        identity != null &&
        _verificationModes[assetId] == GaslessVerificationMode.legacyOnChain &&
        chainId == canonical.chainId &&
        tokenContract == canonical.contract &&
        tokenContract == identity.contractAddress &&
        providerAddress == identity.providerAddress &&
        walletPubkeyHash == identity.walletPubkeyHash;
  }

  /// Whether a previously verified wallet/provider identity may make a
  /// read-only authoritative preview attempt while status is stale.
  bool canAttemptAuthoritativePreview(AssetId assetId) {
    if (!_readyIdentities.containsKey(assetId) &&
        !_candidateIdentities.containsKey(assetId)) {
      return false;
    }
    return switch (_states[assetId]?.state) {
      GaslessCapabilityState.ready ||
      GaslessCapabilityState.stale ||
      GaslessCapabilityState.temporarilyUnavailable => true,
      _ => false,
    };
  }

  /// Existing custody data remains addressable after a transient outage.
  bool canAccessExistingCustody(AssetId assetId) =>
      _readyIdentities.containsKey(assetId) ||
      _candidateIdentities.containsKey(assetId);

  /// Reinstates a previously verified identity after a fresh authoritative
  /// account-status response. Never creates readiness for a new identity.
  bool restoreReadyAfterAuthoritativeStatus(AssetId assetId) {
    if (!_readyIdentities.containsKey(assetId) ||
        _verificationModes[assetId] != GaslessVerificationMode.boundRelay) {
      return false;
    }
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.ready,
    );
    return true;
  }

  GaslessCapability capabilityFor(Asset asset) {
    if (!isConfigured(asset)) {
      return GaslessCapability(
        assetId: asset.id,
        state: GaslessCapabilityState.disabled,
        reasonCode: 'not_canonical_or_configured',
      );
    }
    final state = _states[asset.id];
    if (state != null) return state;
    return GaslessCapability(
      assetId: asset.id,
      state: GaslessCapabilityState.initial,
      reasonCode: 'awaiting_account_status',
    );
  }

  bool markReadyFor(Asset asset, GaslessCapabilityIdentity identity) {
    if (!_validateIdentity(asset, identity)) return false;
    _candidateIdentities[asset.id] = identity;
    _readyIdentities[asset.id] = identity;
    _verificationModes[asset.id] = GaslessVerificationMode.boundRelay;
    _states[asset.id] = GaslessCapability(
      assetId: asset.id,
      state: GaslessCapabilityState.ready,
    );
    return true;
  }

  /// Retains an exact legacy identity for custody recovery and signed-preview
  /// proof, without enabling sends or new receives yet.
  bool markProvisionalFor(Asset asset, GaslessCapabilityIdentity identity) {
    if (!_validateIdentity(asset, identity)) return false;
    _candidateIdentities[asset.id] = identity;
    _readyIdentities.remove(asset.id);
    _verificationModes[asset.id] = GaslessVerificationMode.legacyOnChain;
    _states[asset.id] = GaslessCapability(
      assetId: asset.id,
      state: GaslessCapabilityState.temporarilyUnavailable,
      reasonCode: 'provider_pin_preview_required',
    );
    return true;
  }

  bool _validateIdentity(Asset asset, GaslessCapabilityIdentity identity) {
    final canonical = _canonicalTokens[asset.id.id];
    final pinnedProvider = _pinnedProviderAddress;
    final providerMatches = pinnedProvider != null && pinnedProvider.isNotEmpty
        ? identity.providerAddress == pinnedProvider
        : _allowProviderDiscovery && identity.providerAddress.trim().isNotEmpty;
    final canonicalWallet = switch (identity.walletType) {
      GaslessWalletType.softwareHd =>
        identity.derivationPath == canonicalPrimaryDerivationPath,
      GaslessWalletType.softwareIguana => identity.derivationPath.isEmpty,
    };
    final valid =
        isConfigured(asset) &&
        identity.assetId == asset.id &&
        canonical != null &&
        identity.platform == canonical.platform &&
        identity.contractAddress == canonical.contract &&
        providerMatches &&
        identity.walletPubkeyHash.trim().isNotEmpty &&
        canonicalWallet;
    if (!valid) {
      markSecurityMismatch(
        asset.id,
        reasonCode: 'capability_identity_mismatch',
      );
      return false;
    }
    return true;
  }

  void markUnconfirmed(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.temporarilyUnavailable,
      reasonCode: 'account_status_unconfirmed',
    );
  }

  void markChecking(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.checking,
      reasonCode: 'checking_account_status',
    );
  }

  void markStale(AssetId assetId, {String reasonCode = 'status_stale'}) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.stale,
      reasonCode: reasonCode,
    );
  }

  void markUnsupported(
    AssetId assetId, {
    String reasonCode = 'token_unsupported',
  }) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.unsupported,
      reasonCode: reasonCode,
    );
  }

  void markDisabled(AssetId assetId, {String reasonCode = 'gasless_disabled'}) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.disabled,
      reasonCode: reasonCode,
    );
  }

  void markSecurityMismatch(
    AssetId assetId, {
    String reasonCode = 'provider_security_mismatch',
  }) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.securityMismatch,
      reasonCode: reasonCode,
    );
  }

  void resetSession() {
    _readyIdentities.clear();
    _candidateIdentities.clear();
    _verificationModes.clear();
    _states.clear();
  }
}
