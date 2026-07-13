import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
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
  final Map<AssetId, GaslessReceiveEvidence> _receiveEvidence = {};
  final Map<AssetId, String> _attestedReceiveAddresses = {};
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

  /// Returns the receive-address evidence retained for this wallet session.
  GaslessReceiveEvidence receiveEvidenceFor(AssetId assetId) =>
      _receiveEvidence[assetId] ?? GaslessReceiveEvidence.none;

  /// Wallet-only V1 receive permission. Bound-only integrations must continue
  /// to use [canReceiveGasless].
  bool canReceiveGaslessFromStatus(AssetId assetId) =>
      _candidateIdentities.containsKey(assetId) &&
      receiveEvidenceFor(assetId) == GaslessReceiveEvidence.statusAttestedV1;

  /// Whether a canonical legacy candidate may make a read-only status probe.
  bool canAttemptStatusReceiveAttestation(AssetId assetId) =>
      _candidateIdentities.containsKey(assetId) &&
      _verificationModes[assetId] == GaslessVerificationMode.legacyOnChain;

  /// Revokes V1 receive permission while retaining custody recovery metadata.
  void invalidateStatusReceiveEvidence(
    AssetId assetId, {
    required String reasonCode,
  }) {
    if (_receiveEvidence[assetId] == GaslessReceiveEvidence.statusAttestedV1) {
      _receiveEvidence[assetId] = GaslessReceiveEvidence.none;
    }
    markStale(assetId, reasonCode: reasonCode);
  }

  /// Maps typed KDF account-status failures without inspecting error messages.
  bool markAccountStatusError(AssetId assetId, Object error) {
    if (error is FormatException || error is ArgumentError) {
      _receiveEvidence[assetId] = GaslessReceiveEvidence.none;
      markSecurityMismatch(assetId, reasonCode: 'invalid_account_status');
      return true;
    }
    if (error is! GeneralErrorResponse) return false;
    final reason = switch (error.errorType) {
      'TokenDecimalsMismatch' => 'token_decimals_mismatch',
      'CustodyAddressMismatch' => 'custody_address_mismatch',
      'ProviderIdentityMismatch' => 'provider_identity_mismatch',
      _ => null,
    };
    if (reason != null) {
      _receiveEvidence[assetId] = GaslessReceiveEvidence.none;
      markSecurityMismatch(assetId, reasonCode: reason);
      return true;
    }
    switch (error.errorType) {
      case 'GaslessNotConfigured':
        invalidateStatusReceiveEvidence(
          assetId,
          reasonCode: 'runtime_restart_required',
        );
        return true;
      case 'CoinNotSupported':
        _receiveEvidence[assetId] = GaslessReceiveEvidence.none;
        markUnsupported(assetId);
        return true;
      case 'ProviderError' || 'TronRpcUnavailable':
        invalidateStatusReceiveEvidence(
          assetId,
          reasonCode: 'provider_unreachable',
        );
        return true;
      default:
        return false;
    }
  }

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
    _receiveEvidence[asset.id] = GaslessReceiveEvidence.boundRelayV2;
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
    _receiveEvidence[asset.id] = GaslessReceiveEvidence.none;
    _attestedReceiveAddresses.remove(asset.id);
    _states[asset.id] = GaslessCapability(
      assetId: asset.id,
      state: GaslessCapabilityState.temporarilyUnavailable,
      reasonCode: 'provider_pin_preview_required',
    );
    return true;
  }

  /// Records V1 receive evidence without granting transfer readiness.
  bool markStatusAttestedFor(
    Asset asset,
    GaslessCapabilityIdentity identity,
    GaslessAccountStatusResponse status,
  ) {
    if (!markProvisionalFor(asset, identity)) return false;
    return _applyStatusAttestation(asset.id, status);
  }

  /// Revalidates a previously attested V1 address for a sensitive UI action.
  bool refreshStatusAttestation(
    AssetId assetId,
    GaslessAccountStatusResponse status, {
    required String expectedGasfreeAddress,
  }) {
    if (!canAttemptStatusReceiveAttestation(assetId)) return false;
    return _applyStatusAttestation(
      assetId,
      status,
      expectedGasfreeAddress: expectedGasfreeAddress,
    );
  }

  bool _applyStatusAttestation(
    AssetId assetId,
    GaslessAccountStatusResponse status, {
    String? expectedGasfreeAddress,
  }) {
    _receiveEvidence[assetId] = GaslessReceiveEvidence.none;
    final identity = _candidateIdentities[assetId]!;
    if (!status.hasExplicitAvailability) {
      markStale(assetId, reasonCode: 'availability_unattested');
      return false;
    }
    if (status.availability != GaslessAccountAvailability.available) {
      switch (status.availability) {
        case GaslessAccountAvailability.pendingTransfer:
          markStale(assetId, reasonCode: 'pending_transfer');
        case GaslessAccountAvailability.tokenUnsupported:
          markUnsupported(assetId);
        case GaslessAccountAvailability.providerUnreachable:
          markStale(assetId, reasonCode: 'provider_unreachable');
        case GaslessAccountAvailability.available:
          throw StateError('Unreachable GasFree availability branch');
      }
      return false;
    }
    if (status.serviceProvider != identity.providerAddress) {
      markSecurityMismatch(assetId, reasonCode: 'provider_identity_mismatch');
      return false;
    }
    final previousAddress = _attestedReceiveAddresses[assetId];
    if (status.gasfreeAddress.isEmpty ||
        (expectedGasfreeAddress != null &&
            status.gasfreeAddress != expectedGasfreeAddress) ||
        (previousAddress != null && status.gasfreeAddress != previousAddress)) {
      markSecurityMismatch(assetId, reasonCode: 'custody_address_mismatch');
      return false;
    }
    if (status.reasonCode != null) {
      markSecurityMismatch(assetId, reasonCode: 'unexpected_ready_reason');
      return false;
    }
    if (status.active == null ||
        status.frozenBalance == null ||
        status.spendableBalance == null ||
        status.transferFee == null ||
        status.maxWithdrawable == null) {
      markUnconfirmed(assetId);
      return false;
    }
    _attestedReceiveAddresses[assetId] = status.gasfreeAddress;
    _receiveEvidence[assetId] = GaslessReceiveEvidence.statusAttestedV1;
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.temporarilyUnavailable,
      reasonCode: 'legacy_status_attested_receive_only',
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
    _receiveEvidence.clear();
    _attestedReceiveAddresses.clear();
    _states.clear();
  }
}
