import 'package:flutter/foundation.dart';

/// Minimal platform-gating interface for legacy native wallet migration.
abstract interface class LegacyWalletPlatform {
  /// Whether the current runtime can access legacy native wallet storage.
  bool get isSupportedPlatform;
}

/// Default platform implementation for the production migration service.
class DefaultLegacyWalletPlatform implements LegacyWalletPlatform {
  /// Creates the default platform detector.
  const DefaultLegacyWalletPlatform();

  @override
  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
