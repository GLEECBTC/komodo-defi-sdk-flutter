import 'dart:collection';

import 'package:komodo_defi_types/komodo_defi_types.dart';

final assetTickersWithFaucet = UnmodifiableListView([
  'RICK',
  'MORTY',
  'DOC',
  'MARTY',
  'IRISTEST',
  'NUCLEUSTEST',
]);

extension AssetFaucetExtension on Asset {
  // TODO: Implement faucet functionality in SDK - using the faucet endpoint with hardcoded tickers as a fallback
  // https://faucet.komodo.earth/faucet_coins
  bool get hasFaucet => assetTickersWithFaucet.contains(id.symbol.configSymbol);
}

extension AssetIdFaucetExtension on AssetId {
  bool get hasFaucet => assetTickersWithFaucet.contains(symbol.configSymbol);
}

/// Core extension providing asset validation and compatibility checks
extension AssetValidation on Asset {
  /// Checks if this asset is valid for use.
  /// A valid asset has all required protocol fields and configuration.
  bool get isValid {
    try {
      // For SLP tokens, we don't require a derivation path
      if (protocol is SlpProtocol) {
        return true;
      }

      // Other protocols require derivation paths for multiple addresses
      if (protocol.supportsMultipleAddresses) {
        final derivationPath = id.derivationPath ?? protocol.derivationPath;
        if (derivationPath == null) {
          return false;
        }
      }

      // Ensure required servers are available
      if (protocol.requiredServers.isEmpty) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // /// Checks if the asset is compatible with the current wallet mode.
  // ///
  // /// This performs a full compatibility check including:
  // /// - Basic validity
  // /// - HD wallet compatibility
  // /// - Protocol requirements
  // Future<bool> get isCompatible async {
  //   if (!isValid) return false;

  //   final authOptions =
  //       await KomodoDefiSdk.global.auth.currentUsersAuthOptions();
  //   if (authOptions == null) return false;

  //   return _checkWalletCompatibility(authOptions);
  // }

  /// Check compatibility with specific wallet options.
  /// Useful for pre-checking compatibility before wallet mode changes.
  bool isCompatibleWith(AuthOptions options) {
    if (!isValid) return false;
    return _checkWalletCompatibility(options);
  }

  /// Core compatibility logic checking if the asset works with given wallet mode
  bool _checkWalletCompatibility(AuthOptions options) {
    final isHdWallet = options.derivationMethod == DerivationMethod.hdWallet;

    // SLP tokens always use single address mode regardless of wallet mode
    if (protocol is SlpProtocol) {
      return true;
    }

    // Check if protocol requires HD wallet
    if (protocol.requiresHdWallet && !isHdWallet) {
      return false;
    }

    // For HD wallets, check derivation path requirements for multi-address protocols
    if (isHdWallet && protocol.supportsMultipleAddresses) {
      final derivationPath = id.derivationPath ?? protocol.derivationPath;
      if (derivationPath == null) {
        return false;
      }
    }

    return true;
  }

  /// Get derivation path from either the asset ID or protocol
  String? get derivationPath => id.derivationPath ?? protocol.derivationPath;

  /// Whether this asset supports multiple addresses
  bool get supportsMultipleAddresses => protocol.supportsMultipleAddresses;

  /// Whether this asset requires HD wallet mode
  bool get requiresHdWallet => protocol.requiresHdWallet;

  /// Returns a set of reasons why this asset might be unavailable for use
  /// session.
  ///
  /// Returns null if the asset is available.
  Set<AssetUnavailableErrorReason>? getUnavailableReasons(
    AuthOptions authOptions,
  ) {
    final status = <AssetUnavailableErrorReason>{};

    if (!isValid) {
      status.add(AssetUnavailableErrorReason.invalidConfiguration);
    }

    if (protocol.requiredServers.isEmpty) {
      status.add(AssetUnavailableErrorReason.missingServers);
    }

    final isHdWallet =
        authOptions.derivationMethod == DerivationMethod.hdWallet;

    if (protocol.requiresHdWallet && !isHdWallet) {
      status.add(AssetUnavailableErrorReason.notSupportedInHdWallet);
    }

    if (isHdWallet &&
        protocol.supportsMultipleAddresses &&
        derivationPath == null) {
      status.add(AssetUnavailableErrorReason.missingDerivationPath);
    }

    return status.isEmpty ? null : status;
  }

  /// Get human-readable reason why an asset might be disabled
  @Deprecated(
    'This method does not consider localised strings and will be removed in '
    'the future because it concerns only the UI. Use getValidationStatus().',
  )
  String? getDisabledReason(AuthOptions options) {
    if (!isValid) {
      if (protocol.supportsMultipleAddresses && derivationPath == null) {
        return 'Missing derivation path required for multiple addresses';
      }
      if (protocol.requiredServers.isEmpty) {
        return 'No servers configured';
      }
      return 'Invalid configuration';
    }

    final isHdWallet = options.derivationMethod == DerivationMethod.hdWallet;

    if (protocol.requiresHdWallet && !isHdWallet) {
      return 'Requires HD wallet mode';
    }

    if (isHdWallet &&
        protocol.supportsMultipleAddresses &&
        derivationPath == null) {
      return 'Missing derivation path for HD wallet';
    }

    return null;
  }
}

enum AssetUnavailableErrorReason {
  missingDerivationPath,

  missingServers,

  notSupportedInIguana,

  notSupportedInHdWallet,

  invalidConfiguration,
}

// TODO! Localise
extension AssetUnavailableErrorReasonExtension on AssetUnavailableErrorReason {
  String get message {
    switch (this) {
      case AssetUnavailableErrorReason.missingDerivationPath:
        return 'Missing derivation path required for multiple addresses';
      case AssetUnavailableErrorReason.missingServers:
        return 'No servers configured';
      case AssetUnavailableErrorReason.notSupportedInIguana:
        return 'Not supported in Iguana wallet';
      case AssetUnavailableErrorReason.notSupportedInHdWallet:
        return 'Requires HD wallet mode';
      case AssetUnavailableErrorReason.invalidConfiguration:
        return 'Invalid configuration';
    }
  }
}
