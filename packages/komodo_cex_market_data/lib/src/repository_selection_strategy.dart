import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show RepositoryPriorityManager;
import 'package:komodo_cex_market_data/src/cex_repository.dart';
import 'package:komodo_cex_market_data/src/models/quote_currency.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart' show Logger;

/// Enum for the type of price request
///
/// This enum defines the different types of price-related requests that can be made
/// to cryptocurrency exchange repositories. Each type represents a specific kind
/// of market data that may be supported differently across various data providers.
enum PriceRequestType {
  /// Request for the current/latest price of an asset
  ///
  /// This represents the most recent price available for a given asset
  /// in a specific fiat currency.
  currentPrice,

  /// Request for price change information over a time period
  ///
  /// This includes percentage changes, absolute changes, and other
  /// price movement metrics for a given time frame.
  priceChange,

  /// Request for historical price data
  ///
  /// This includes price data points over time, such as daily, hourly,
  /// or minute-level price history for charting and analysis purposes.
  priceHistory,
}

/// Strategy interface for selecting repositories
abstract class RepositorySelectionStrategy {
  /// Ensures the cache is initialized for the given repositories
  Future<void> ensureCacheInitialized(List<CexRepository> repositories);

  /// Selects the best repository for a given asset, fiat, and request type
  Future<CexRepository?> selectRepository({
    required AssetId assetId,
    required QuoteCurrency fiatCurrency,
    required PriceRequestType requestType,
    required List<CexRepository> availableRepositories,
  });
}

/// Default strategy for selecting the best repository for a given asset
class DefaultRepositorySelectionStrategy
    implements RepositorySelectionStrategy {
  static final Logger _logger = Logger('DefaultRepositorySelectionStrategy');
  static const _supportsTimeout = Duration(seconds: 5);

  @override
  Future<void> ensureCacheInitialized(List<CexRepository> repositories) async {
    // No longer needed since we delegate to repository-specific supports() method
  }

  /// Selects the best repository for a given asset, fiat, and request type
  @override
  Future<CexRepository?> selectRepository({
    required AssetId assetId,
    required QuoteCurrency fiatCurrency,
    required PriceRequestType requestType,
    required List<CexRepository> availableRepositories,
  }) async {
    final candidates = <CexRepository>[];
    await Future.wait(
      availableRepositories.map((repo) async {
        try {
          final isSupported = await repo
              .supports(assetId, fiatCurrency, requestType)
              .timeout(_supportsTimeout, onTimeout: () => false);
          if (isSupported) {
            candidates.add(repo);
          }
        } catch (e, st) {
          // Log errors but continue with other repositories
          _logger.fine(
            'Failed to check support for ${repo.runtimeType} with asset '
            '${assetId.id} and fiat ${fiatCurrency.symbol} (requestType: $requestType)',
            e,
            st,
          );
        }
      }),
    );

    // Sort by priority
    candidates.sort(
      (a, b) => RepositoryPriorityManager.getPriority(
        a,
      ).compareTo(RepositoryPriorityManager.getPriority(b)),
    );

    return candidates.isNotEmpty ? candidates.first : null;
  }
}
