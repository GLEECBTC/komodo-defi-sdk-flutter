import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

enum GaslessWalletType { softwareHd, softwareIguana, hardwareHd }

/// Wallet and asset identity associated with a KDF GasFree account status.
///
/// KDF derives [GaslessAccountStatusResponse.gasfreeAddress] locally and
/// validates the provider response. The SDK additionally binds the resulting
/// capability to the active wallet session and the exact activated asset.
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

  /// Empty until KDF discovers a provider, or while an unpinned provider is
  /// unreachable.
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

/// Session-scoped, typed source of truth for GasFree availability.
///
/// The registry deliberately does not implement a second GasFree protocol.
/// KDF's account-status enum is authoritative; this class adds wallet-session,
/// activated-asset, configured-provider, and stale-request guards.
class GaslessCapabilityRegistry {
  GaslessCapabilityRegistry({String? pinnedProviderAddress})
    : _pinnedProviderAddress = _nonEmpty(pinnedProviderAddress);

  final String? _pinnedProviderAddress;
  final Map<AssetId, GaslessCapabilityIdentity> _identities = {};
  final Map<AssetId, GaslessAccountStatusResponse> _statuses = {};
  final Map<AssetId, int> _accountStatusEpochs = {};
  final Map<AssetId, GaslessCapability> _states = {};
  String? _boundWalletPubkeyHash;
  int _sessionGeneration = 0;

  /// Monotonically changes whenever wallet-scoped capability state is reset.
  int get sessionGeneration => _sessionGeneration;

  /// Keeps wallet-owned capability state from crossing an auth-listener delay.
  bool ensureWalletSession(String? walletPubkeyHash) {
    final boundWallet = _boundWalletPubkeyHash;
    if (boundWallet == null) return true;
    if (_nonEmpty(walletPubkeyHash) == boundWallet) return true;
    resetSession();
    return false;
  }

  /// Whether this activated asset is opted into KDF's GasFree token config.
  ///
  /// Eligibility comes only from the concrete TRC20 asset configuration.
  /// Product-specific network and token allowlists belong above the generic
  /// SDK boundary and must amend that configuration before activation.
  bool isConfigured(Asset asset) {
    final protocol = asset.protocol;
    if (protocol is! Trc20Protocol) return false;
    final gasless = protocol.config.valueOrNull<JsonMap>('gasless');
    return gasless?.valueOrNull<bool>('enabled') == true;
  }

  bool isReady(AssetId assetId) =>
      _states[assetId]?.state == GaslessCapabilityState.ready &&
      _statuses[assetId]?.availability ==
          GaslessAccountAvailability.available &&
      _identities.containsKey(assetId);

  bool isReadyFor(GaslessCapabilityIdentity identity) =>
      isReady(identity.assetId) && _identities[identity.assetId] == identity;

  bool canSendGasless(AssetId assetId) => isReady(assetId);

  bool canReceiveGasless(AssetId assetId) => isReady(assetId);

  /// A current or retained custody identity remains visible for recovery even
  /// while provider-backed GasFree spending is unavailable.
  bool canAccessExistingCustody(AssetId assetId) =>
      _statuses.containsKey(assetId);

  /// A GasFree preview is authoritative only while the final KDF status says
  /// the rail is available.
  bool canAttemptAuthoritativePreview(AssetId assetId) => isReady(assetId);

  /// Whether KDF account status may be refreshed for this activated asset.
  ///
  /// Disabled activations require controlled reactivation, while a security
  /// mismatch stays fail-closed until the wallet/activation session is reset.
  bool canRefreshAccountStatus(Asset asset) {
    if (!isConfigured(asset)) return false;
    final state = _states[asset.id]?.state;
    return state != GaslessCapabilityState.disabled &&
        state != GaslessCapabilityState.securityMismatch;
  }

  GaslessAccountStatusResponse? statusFor(AssetId assetId) =>
      _statuses[assetId];

  String? custodyAddressFor(AssetId assetId) =>
      _statuses[assetId]?.gasfreeAddress;

  /// Starts an account-status request and supersedes older in-flight probes.
  int beginAccountStatusProbe(AssetId assetId) {
    final epoch = (_accountStatusEpochs[assetId] ?? 0) + 1;
    _accountStatusEpochs[assetId] = epoch;
    return epoch;
  }

  bool isCurrentAccountStatusProbe(AssetId assetId, int epoch) =>
      _accountStatusEpochs[assetId] == epoch;

  /// Binds an activated TRC20 asset to this wallet session before probing KDF.
  ///
  /// This carries no custody or availability authority. It only lets a later
  /// account-status retry be validated against the activation and wallet that
  /// established the provider configuration.
  bool bindActivatedIdentity(Asset asset, GaslessCapabilityIdentity identity) {
    final pin = _pinnedProviderAddress;
    if (!_validateIdentity(asset, identity) ||
        (pin != null && identity.providerAddress != pin)) {
      markTemporarilyUnavailable(asset.id);
      return false;
    }
    final existing = _identities[asset.id];
    if (existing != null) {
      if (!_hasSameActivationIdentity(existing, identity)) {
        markSecurityMismatch(asset.id);
        return false;
      }
      if (existing.providerAddress.isNotEmpty &&
          identity.providerAddress.isNotEmpty &&
          identity.providerAddress != existing.providerAddress) {
        markSecurityMismatch(asset.id);
        return false;
      }
      // Preserve a provider discovered by an earlier status response when a
      // generic unpinned activation is re-observed without a provider echo.
      if (identity.providerAddress.isEmpty &&
          existing.providerAddress.isNotEmpty) {
        return true;
      }
    }
    _boundWalletPubkeyHash = identity.walletPubkeyHash.trim();
    _identities[asset.id] = identity;
    return true;
  }

  /// Validates and records one of KDF's four exact account-status shapes.
  ///
  /// Returns false only for a security/shape mismatch. Valid unavailable
  /// statuses are retained and represented by their corresponding capability
  /// state so the Standard TRON rail and custody recovery remain usable.
  bool recordAccountStatus(
    Asset asset,
    GaslessCapabilityIdentity identity,
    GaslessAccountStatusResponse status, {
    String? expectedGasfreeAddress,
  }) {
    if (!_validateIdentity(asset, identity)) {
      markSecurityMismatch(asset.id);
      return false;
    }
    final existing = _identities[asset.id];
    if (existing != null) {
      if (!_hasSameActivationIdentity(existing, identity)) {
        markSecurityMismatch(asset.id);
        return false;
      }
      if (existing.providerAddress.isNotEmpty &&
          identity.providerAddress.isNotEmpty &&
          identity.providerAddress != existing.providerAddress) {
        markSecurityMismatch(asset.id);
        return false;
      }
    }
    if (!_hasExactStatusShape(status)) {
      markSecurityMismatch(asset.id);
      return false;
    }
    if (!_matchesExpectedCustody(status, expectedGasfreeAddress)) {
      markSecurityMismatch(asset.id);
      return false;
    }
    final retainedIdentity =
        existing != null &&
            existing.providerAddress.isNotEmpty &&
            identity.providerAddress.isEmpty
        ? existing
        : identity;
    if (!_matchesProviderPin(retainedIdentity, status)) {
      markSecurityMismatch(asset.id);
      return false;
    }

    _boundWalletPubkeyHash = retainedIdentity.walletPubkeyHash.trim();
    _identities[asset.id] = retainedIdentity;
    _statuses[asset.id] = status;
    _applyAvailability(asset.id, status.availability);
    return true;
  }

  /// Refreshes status for an identity already bound in this wallet session.
  bool refreshAccountStatus(
    Asset asset,
    GaslessAccountStatusResponse status, {
    String? expectedGasfreeAddress,
  }) {
    final identity = _identities[asset.id];
    if (identity == null) {
      // No identity bound yet. That is a caller-ordering condition - the
      // session was reset while the asset stayed active - not evidence that
      // anything disagrees. `securityMismatch` is terminal
      // (`canRefreshAccountStatus` refuses it until the session is reset), so
      // latching it here permanently disables the gas-free rail for an asset
      // whose only problem is that it has not been bound yet.
      //
      // Reserve `securityMismatch` for an identity that IS bound and
      // disagrees, which `recordAccountStatus` still enforces.
      markTemporarilyUnavailable(asset.id);
      return false;
    }
    // Provider discovery is permitted once for the generic SDK. After the
    // activation/session has observed an identity, every reachable status must
    // repeat that exact provider instead of silently rebinding the capability.
    final providerAddress =
        _nonEmpty(identity.providerAddress) ??
        _pinnedProviderAddress ??
        _nonEmpty(status.serviceProvider) ??
        '';
    final retainedGasfreeAddress = _statuses[asset.id]?.gasfreeAddress;
    return recordAccountStatus(
      asset,
      GaslessCapabilityIdentity(
        assetId: identity.assetId,
        platform: identity.platform,
        contractAddress: identity.contractAddress,
        providerAddress: providerAddress,
        walletPubkeyHash: identity.walletPubkeyHash,
        walletType: identity.walletType,
        derivationPath: identity.derivationPath,
      ),
      status,
      expectedGasfreeAddress: expectedGasfreeAddress ?? retainedGasfreeAddress,
    );
  }

  /// Maps typed KDF account-status failures without parsing error messages.
  bool markAccountStatusError(AssetId assetId, Object error) {
    if (error is FormatException || error is ArgumentError) {
      markSecurityMismatch(assetId);
      return true;
    }
    if (error is! GaslessAccountStatusException) return false;

    switch (error.type) {
      case GaslessAccountStatusErrorType.providerIdentityMismatch:
      case GaslessAccountStatusErrorType.gasfreeAddressMismatch:
      case GaslessAccountStatusErrorType.tokenDecimalMismatch:
        markSecurityMismatch(assetId);
        return true;
      case GaslessAccountStatusErrorType.coinNotSupported:
      case GaslessAccountStatusErrorType.notEthCoin:
        markUnsupported(assetId);
        return true;
      case GaslessAccountStatusErrorType.gaslessNotConfigured:
      case GaslessAccountStatusErrorType.coinNotFound:
        markDisabled(assetId);
        return true;
      case GaslessAccountStatusErrorType.tronRpcUnavailable:
      case GaslessAccountStatusErrorType.providerError:
      case GaslessAccountStatusErrorType.internalError:
        markTemporarilyUnavailable(assetId);
        return true;
    }
  }

  GaslessCapability capabilityFor(Asset asset) {
    if (!isConfigured(asset)) {
      return GaslessCapability(
        assetId: asset.id,
        state: GaslessCapabilityState.disabled,
      );
    }
    return _states[asset.id] ??
        GaslessCapability(
          assetId: asset.id,
          state: GaslessCapabilityState.initial,
        );
  }

  void markChecking(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.checking,
    );
  }

  void markUnconfirmed(AssetId assetId) {
    markTemporarilyUnavailable(assetId);
  }

  void markTemporarilyUnavailable(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.temporarilyUnavailable,
    );
  }

  void markUnsupported(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.unsupported,
    );
  }

  void markDisabled(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.disabled,
    );
  }

  void markSecurityMismatch(AssetId assetId) {
    _states[assetId] = GaslessCapability(
      assetId: assetId,
      state: GaslessCapabilityState.securityMismatch,
    );
  }

  void resetSession() {
    _sessionGeneration++;
    _identities.clear();
    _statuses.clear();
    _accountStatusEpochs.clear();
    _states.clear();
    _boundWalletPubkeyHash = null;
  }

  void _applyAvailability(
    AssetId assetId,
    GaslessAccountAvailability availability,
  ) {
    _states[assetId] = switch (availability) {
      GaslessAccountAvailability.available => GaslessCapability(
        assetId: assetId,
        state: GaslessCapabilityState.ready,
      ),
      GaslessAccountAvailability.pendingTransfer => GaslessCapability(
        assetId: assetId,
        state: GaslessCapabilityState.temporarilyUnavailable,
      ),
      GaslessAccountAvailability.tokenUnsupported => GaslessCapability(
        assetId: assetId,
        state: GaslessCapabilityState.unsupported,
      ),
      GaslessAccountAvailability.providerUnreachable => GaslessCapability(
        assetId: assetId,
        state: GaslessCapabilityState.temporarilyUnavailable,
      ),
    };
  }

  bool _validateIdentity(Asset asset, GaslessCapabilityIdentity identity) {
    final protocol = asset.protocol;
    if (protocol is! Trc20Protocol || !isConfigured(asset)) return false;
    final contract =
        protocol.config.valueOrNull<String>('contract_address') ??
        protocol.config.valueOrNull<String>(
          'protocol',
          'protocol_data',
          'contract_address',
        );
    final supportedWallet = switch (identity.walletType) {
      // Retain the activated asset's configured HD base path verbatim. The
      // concrete withdrawal source is selected later and may use any KDF HD
      // selector; the generic SDK must not resolve it to an app-specific path.
      GaslessWalletType.softwareHd => identity.derivationPath.trim().isNotEmpty,
      GaslessWalletType.softwareIguana => identity.derivationPath.isEmpty,
      GaslessWalletType.hardwareHd => identity.derivationPath.trim().isNotEmpty,
    };
    return identity.assetId == asset.id &&
        identity.platform == protocol.platform &&
        identity.contractAddress == contract &&
        identity.walletPubkeyHash.trim().isNotEmpty &&
        (_boundWalletPubkeyHash == null ||
            identity.walletPubkeyHash.trim() == _boundWalletPubkeyHash) &&
        supportedWallet;
  }

  bool _hasSameActivationIdentity(
    GaslessCapabilityIdentity existing,
    GaslessCapabilityIdentity candidate,
  ) =>
      existing.assetId == candidate.assetId &&
      existing.platform == candidate.platform &&
      existing.contractAddress == candidate.contractAddress &&
      existing.walletPubkeyHash == candidate.walletPubkeyHash &&
      existing.walletType == candidate.walletType &&
      existing.derivationPath == candidate.derivationPath;

  bool _matchesProviderPin(
    GaslessCapabilityIdentity identity,
    GaslessAccountStatusResponse status,
  ) {
    final rawProvider = status.serviceProvider;
    final provider = _nonEmpty(rawProvider);
    if (rawProvider != null && rawProvider != provider) return false;
    final providerReachable =
        status.availability != GaslessAccountAvailability.providerUnreachable;
    if (providerReachable && provider == null) return false;
    if (provider != null && identity.providerAddress != provider) return false;
    final pin = _pinnedProviderAddress;
    return pin == null || provider == null || provider == pin;
  }

  bool _matchesExpectedCustody(
    GaslessAccountStatusResponse status,
    String? expectedGasfreeAddress,
  ) {
    final expected = _nonEmpty(expectedGasfreeAddress);
    return expected == null || expected == status.gasfreeAddress;
  }

  bool _hasExactStatusShape(GaslessAccountStatusResponse status) {
    final provider = _nonEmpty(status.serviceProvider);
    final providerAmounts = [
      status.frozenBalance,
      status.spendableBalance,
      status.transferFee,
      status.activationFee,
      status.maxWithdrawable,
    ];
    if (_nonEmpty(status.gasfreeAddress) != status.gasfreeAddress ||
        status.onChainBalance < Decimal.zero ||
        providerAmounts.whereType<Decimal>().any(
          (amount) => amount < Decimal.zero,
        )) {
      return false;
    }

    return switch (status.availability) {
      GaslessAccountAvailability.available =>
        provider != null &&
            status.active != null &&
            status.frozenBalance != null &&
            status.spendableBalance != null &&
            status.transferFee != null &&
            status.maxWithdrawable != null,
      GaslessAccountAvailability.pendingTransfer =>
        provider != null &&
            status.active != null &&
            status.frozenBalance != null &&
            status.spendableBalance != null &&
            status.transferFee != null &&
            status.maxWithdrawable == null,
      GaslessAccountAvailability.tokenUnsupported =>
        provider != null &&
            status.active == null &&
            status.frozenBalance == null &&
            status.spendableBalance == null &&
            status.transferFee == null &&
            status.activationFee == null &&
            status.maxWithdrawable == null,
      GaslessAccountAvailability.providerUnreachable =>
        provider == null &&
            status.active == null &&
            status.frozenBalance == null &&
            status.spendableBalance == null &&
            status.transferFee == null &&
            status.activationFee == null &&
            status.maxWithdrawable == null,
    };
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
