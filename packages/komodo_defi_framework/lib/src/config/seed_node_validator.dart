import 'package:flutter/foundation.dart' show debugPrint;
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_exception.dart';

/// Helper class to validate seed node configurations
class SeedNodeValidator {
  static const List<String> _defaultSeedNodes = ['seed01.kmdefi.net'];

  /// Validates the seed node configuration
  ///
  /// Throws [KdfException] if the configuration is invalid
  static void validate({
    required List<String>? seedNodes,
    required bool? disableP2p,
    required bool? iAmSeed,
    required bool? isBootstrapNode,
  }) {
    // Cannot disable P2P while seed nodes are configured
    if ((disableP2p ?? false) && seedNodes != null && seedNodes.isNotEmpty) {
      throw KdfException(
        'Cannot disable P2P while seed nodes are configured.',
        type: KdfExceptionType.seedNodeConfigError,
      );
    }

    // If P2P is disabled, no need for further validation
    if (disableP2p ?? false) {
      if (KdfLoggingConfig.verboseLogging) {
        debugPrint(
          'WARN P2P is disabled. Features that require a P2P network '
          '(like swaps, peer health checks, etc.) will not work.',
        );
      }
      return;
    }

    // Seed nodes cannot disable P2P
    if ((iAmSeed ?? false) && (disableP2p ?? false)) {
      throw KdfException(
        'Seed nodes cannot disable P2P.',
        type: KdfExceptionType.seedNodeConfigError,
      );
    }

    // Bootstrap node must also be a seed node
    if ((isBootstrapNode ?? false) && iAmSeed != true) {
      throw KdfException(
        'Bootstrap node must also be a seed node.',
        type: KdfExceptionType.seedNodeConfigError,
      );
    }

    // Non-bootstrap node must have seed nodes configured
    if (isBootstrapNode != true &&
        iAmSeed != true &&
        (seedNodes == null || seedNodes.isEmpty)) {
      throw KdfException(
        'Non-bootstrap node must have seed nodes configured to connect.',
        type: KdfExceptionType.seedNodeConfigError,
      );
    }

    // Warning about future requirements - updated to be more explicit
    if (seedNodes == null || seedNodes.isEmpty) {
      if (KdfLoggingConfig.verboseLogging) {
        debugPrint(
          'WARN From v2.5.0-beta, there will be no default seed nodes, '
          'and the seednodes parameter will be required unless '
          'disable_p2p is set to true.',
        );
      }
    }
  }

  /// Gets the emergency fallback seed nodes.
  ///
  /// The primary fallback path loads the bundled `seed_nodes.json` asset.
  /// This list is kept as a last-resort fallback when the asset cannot be
  /// loaded or does not contain any valid nodes for the current net ID.
  static List<String> getDefaultSeedNodes() => _defaultSeedNodes;
}
