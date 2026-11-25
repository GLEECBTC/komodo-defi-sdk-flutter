import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

// TODO: Add streaming support for price updates. The challenges share a lot
// of similarities with the balance manager. Investigate if we can create a
// generic manager class for such cases. See:
// docs/tech_debt/Market_Data_Price_Streaming_Tech_Debt.md

/// Interface defining the contract for price management operations
abstract class MarketDataManager {
  Future<void> init();

  /// Gets the current fiat price for an asset
  ///
  /// Throws [ArgumentError] if asset is not found
  /// May throw [TimeoutException] if price fetch times out
  Future<Decimal> fiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  });

  /// Gets the current fiat price for an asset if the CEX data is available
  Future<Decimal?> maybeFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  });

  /// Gets the price for an asset if it's cached, returns null otherwise
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  });

  /// Gets historical fiat prices for an asset at specified dates
  ///
  /// Returns a map of dates to prices, keyed by the UTC day each date falls
  /// on. A day with no known price is absent, so check for the days you need.
  /// Throws only when a fetch failed and no price is known for any day.
  Future<Map<DateTime, Decimal>> fiatPriceHistory(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  });

  /// Gets the 24-hour price change percentage for an asset
  ///
  /// Returns the percentage change as a decimal value (e.g., 0.05 for 5% increase)
  /// Returns null if the change data is not available
  ///
  /// Note: This method will likely be deprecated in the future in favor of a
  /// more flexible method that provides data for various time periods.
  ///
  /// Throws [ArgumentError] if asset is not found
  /// May throw [TimeoutException] if price fetch times out
  Future<Decimal?> priceChange24h(
    AssetId assetId, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  });

  /// Disposes of all resources
  Future<void> dispose();
}

/// Implementation of the [MarketDataManager] interface for managing asset prices
class CexMarketDataManager
    with RepositoryFallbackMixin
    implements MarketDataManager {
  /// Creates a new instance of [CexMarketDataManager]
  CexMarketDataManager({
    required List<CexRepository> priceRepositories,
    RepositorySelectionStrategy? selectionStrategy,
    Duration cacheClearInterval = _defaultCacheClearInterval,
    DateTime Function() clock = DateTime.now,
  }) : assert(
         cacheClearInterval > Duration.zero,
         'cacheClearInterval must be greater than zero',
       ),
       _cacheClearInterval = cacheClearInterval,
       _priceRepositories = priceRepositories,
       _selectionStrategy =
           selectionStrategy ?? DefaultRepositorySelectionStrategy(),
       _clock = clock;

  static final _logger = Logger('CexMarketDataManager');
  static const _defaultCacheClearInterval = Duration(minutes: 5);
  final Duration _cacheClearInterval;
  final DateTime Function() _clock;
  Timer? _cacheTimer;

  @override
  Future<void> init() async {
    // Start the cache clearing timer and report ready immediately.
    _cacheTimer = Timer.periodic(_cacheClearInterval, (_) => _clearCaches());
    _logger.finer(
      'Started cache clearing timer with interval $_cacheClearInterval',
    );

    _isInitialized = true;

    // Coin-list loading is a cache warm-up, not a precondition: every
    // repository fetches on demand, and each failure here was already
    // swallowed and stepped over. Awaiting it made four remote downloads -
    // Komodo, Binance, CoinPaprika, CoinGecko - run *serially* inside a
    // `registerSingletonAsync`, so `container.allReady()` and therefore the
    // whole SDK bootstrap (and `runApp` behind it) waited on them.
    unawaited(_warmCoinLists());
  }

  Future<void> _warmCoinLists() async {
    // Independent endpoints: warm them concurrently rather than one by one.
    await Future.wait(
      _priceRepositories.map((repo) async {
        try {
          final coins = await repo.getCoinList();
          _logger.finer(
            'Loaded ${coins.length} coins from repository: ${repo.runtimeType}',
          );
        } catch (e, s) {
          // Log error but continue with other repositories
          _logger
            ..info('Failed to get coin list from repository: $e')
            ..finest('Stack trace: $s');
        }
      }),
    );
  }

  final List<CexRepository> _priceRepositories;
  final RepositorySelectionStrategy _selectionStrategy;
  bool _isDisposed = false;
  bool _isInitialized = false;

  // Required by RepositoryFallbackMixin
  @override
  List<CexRepository> get priceRepositories => _priceRepositories;

  @override
  RepositorySelectionStrategy get selectionStrategy => _selectionStrategy;

  // Cache to store asset prices
  final Map<String, Decimal> _priceCache = {};

  // Cache to keep last-known current prices (without historical date).
  // This intentionally survives periodic live cache rotations to avoid
  // transient null windows for read-only cache consumers.
  final Map<String, Decimal> _lastKnownCurrentPriceCache = {};

  // Cache to store 24h price changes
  final Map<String, Decimal> _priceChangeCache = {};

  /// Prices of days before today, which no longer change. They outlive the
  /// live cache rotation, so repeated history lookups don't refetch them.
  final Map<String, Decimal> _pastDayPriceCache = {};

  /// Bounds [_pastDayPriceCache]; the oldest insertion is evicted first.
  static const _maxPastDayPrices = 25000;

  /// Past days no repository priced, and when that was learnt. A plan's
  /// history window or a delisting leaves the same gaps on every lookup.
  final Map<String, DateTime> _unpricedPastDays = {};
  static const _unpricedPastDayRetryInterval = Duration(hours: 1);

  /// The day in progress, when neither a current price nor history priced it.
  /// Kept briefly: a price for today can appear at any moment.
  final Map<String, DateTime> _unpricedCurrentDays = {};
  static const _unpricedCurrentDayRetryInterval = Duration(minutes: 5);

  /// Clears all cached data to ensure fresh values are fetched
  void _clearCaches() {
    if (_isDisposed) return;
    _logger.finer('Clearing price and price change caches');
    _priceCache.clear();
    _priceChangeCache.clear();
    _unpricedPastDays.removeWhere(
      (_, learntAt) => !_isWithin(learntAt, _unpricedPastDayRetryInterval),
    );
    _unpricedCurrentDays.removeWhere(
      (_, learntAt) => !_isWithin(learntAt, _unpricedCurrentDayRetryInterval),
    );
  }

  /// A clock that moved backwards counts as expired rather than fresh.
  bool _isWithin(DateTime at, Duration window) {
    final age = _clock().difference(at);
    return !age.isNegative && age < window;
  }

  /// The UTC day [date] falls on, at midnight. Prices are daily in UTC, so a
  /// local time's own calendar date would file it under the wrong day for the
  /// hours the device's clock is on a different date than UTC.
  DateTime _normalizeDate(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  DateTime _utcToday() => _normalizeDate(_clock());

  /// [normalizedDate] decides the cache: a past day's price never changes.
  void _cacheDatedPrice(
    String cacheKey,
    DateTime normalizedDate,
    Decimal price, {
    required DateTime requestDay,
  }) {
    if (!normalizedDate.isBefore(requestDay)) {
      _priceCache[cacheKey] = price;
      _unpricedCurrentDays.remove(cacheKey);
      return;
    }
    _pastDayPriceCache[cacheKey] = price;
    _unpricedPastDays.remove(cacheKey);
    if (_pastDayPriceCache.length > _maxPastDayPrices) {
      _pastDayPriceCache.remove(_pastDayPriceCache.keys.first);
    }
  }

  bool _isKnownUnpriced(String cacheKey) {
    final learntAt = _unpricedPastDays[cacheKey];
    return learntAt != null &&
        _isWithin(learntAt, _unpricedPastDayRetryInterval);
  }

  bool _isKnownUnpricedToday(String cacheKey) {
    final learntAt = _unpricedCurrentDays[cacheKey];
    return learntAt != null &&
        _isWithin(learntAt, _unpricedCurrentDayRetryInterval);
  }

  // Helper method to generate canonical string cache keys
  String _getCacheKey(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) {
    final basePrefix = assetId.baseCacheKeyPrefix;
    final normalizedDate = priceDate != null ? _normalizeDate(priceDate) : null;
    return canonicalCacheKeyFromBasePrefix(basePrefix, {
      'quote': quoteCurrency.symbol,
      'kind': 'price',
      if (normalizedDate != null) 'ts': normalizedDate.millisecondsSinceEpoch,
    });
  }

  // Helper method to generate change cache keys
  String _getChangeCacheKey(
    AssetId assetId, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) {
    final basePrefix = assetId.baseCacheKeyPrefix;
    return canonicalCacheKeyFromBasePrefix(basePrefix, {
      'quote': quoteCurrency.symbol,
      'kind': 'change24h',
    });
  }

  /// Validates that the manager hasn't been disposed
  void _checkNotDisposed() {
    if (_isDisposed) {
      _logger.warning('Attempted to use manager after dispose');
      throw StateError('PriceManager has been disposed');
    }
  }

  /// Validates that the manager has been initialized
  void _assertInitialized() {
    if (!_isInitialized) {
      _logger.warning('Attempted to use manager before initialization');
      throw StateError('MarketDataManager must be initialized before use');
    }
  }

  /// Gets cached price if available, returns null otherwise
  Decimal? _getCachedPrice(String cacheKey) {
    final cachedPrice = _priceCache[cacheKey] ?? _pastDayPriceCache[cacheKey];
    if (cachedPrice != null) {
      _logger.finer('Cache hit for $cacheKey');
    }
    return cachedPrice;
  }

  /// Fetches price from repository and caches the result
  Future<Decimal> _fetchAndCachePrice(
    CexRepository repo,
    AssetId assetId,
    String cacheKey, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    final requestDay = _utcToday();
    final price = await repo.getCoinFiatPrice(
      assetId,
      priceDate: priceDate,
      fiatCurrency: quoteCurrency,
    );
    if (priceDate == null) {
      _priceCache[cacheKey] = price;
      _lastKnownCurrentPriceCache[cacheKey] = price;
    } else {
      _cacheDatedPrice(
        cacheKey,
        _normalizeDate(priceDate),
        price,
        requestDay: requestDay,
      );
    }
    _logger.finer(
      'Fetched price from ${repo.runtimeType} for '
      '${assetId.symbol.assetConfigId}: $price',
    );
    return price;
  }

  /// A dated price must come from a repository that can serve a past date;
  /// the Komodo feed, for one, answers with today's price whatever the date.
  PriceRequestType _priceRequestType(DateTime? priceDate) => priceDate == null
      ? PriceRequestType.currentPrice
      : PriceRequestType.priceHistory;

  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) {
    _checkNotDisposed();

    final cacheKey = _getCacheKey(
      assetId,
      priceDate: priceDate,
      quoteCurrency: quoteCurrency,
    );

    final cachedPrice = _getCachedPrice(cacheKey);
    if (cachedPrice != null) {
      return cachedPrice;
    }

    // Only current prices have a last-known fallback.
    if (priceDate != null) {
      return null;
    }

    final lastKnownCurrentPrice = _lastKnownCurrentPriceCache[cacheKey];
    if (lastKnownCurrentPrice != null) {
      _logger.finer('Last-known current price cache hit for $cacheKey');
    }
    return lastKnownCurrentPrice;
  }

  @override
  Future<Decimal> fiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    _checkNotDisposed();
    _assertInitialized();

    final cacheKey = _getCacheKey(
      assetId,
      priceDate: priceDate,
      quoteCurrency: quoteCurrency,
    );

    // Check cache first
    final cachedPrice = _getCachedPrice(cacheKey);
    if (cachedPrice != null) {
      return cachedPrice;
    }

    // Use mixin method with minimal changes
    return tryRepositoriesInOrder(
      assetId,
      quoteCurrency,
      _priceRequestType(priceDate),
      (repo) => _fetchAndCachePrice(
        repo,
        assetId,
        cacheKey,
        priceDate: priceDate,
        quoteCurrency: quoteCurrency,
      ),
      'fiatPrice',
    );
  }

  @override
  Future<Decimal?> maybeFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    _assertInitialized();

    final cacheKey = _getCacheKey(
      assetId,
      priceDate: priceDate,
      quoteCurrency: quoteCurrency,
    );

    // Check cache first
    final cachedPrice = _getCachedPrice(cacheKey);
    if (cachedPrice != null) {
      return cachedPrice;
    }

    // Use mixin method - returns null on failure
    return tryRepositoriesInOrderMaybe(
      assetId,
      quoteCurrency,
      _priceRequestType(priceDate),
      (repo) => _fetchAndCachePrice(
        repo,
        assetId,
        cacheKey,
        priceDate: priceDate,
        quoteCurrency: quoteCurrency,
      ),
      'maybeFiatPrice',
    );
  }

  @override
  Future<Decimal?> priceChange24h(
    AssetId assetId, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    _checkNotDisposed();
    _assertInitialized();

    final cacheKey = _getChangeCacheKey(assetId, quoteCurrency: quoteCurrency);
    final cached = _priceChangeCache[cacheKey];
    if (cached != null) {
      _logger.finer('Cache hit for $cacheKey');
      return cached;
    }

    // Use mixin method
    return tryRepositoriesInOrderMaybe(
      assetId,
      quoteCurrency,
      PriceRequestType.priceChange,
      (repo) async {
        final priceChange = await repo.getCoin24hrPriceChange(
          assetId,
          fiatCurrency: quoteCurrency,
        );
        _priceChangeCache[cacheKey] = priceChange;
        _logger.finer(
          'Fetched 24h price change from ${repo.runtimeType} for '
          '${assetId.symbol.assetConfigId}: $priceChange',
        );
        return priceChange;
      },
      'priceChange24h',
    );
  }

  @override
  Future<Map<DateTime, Decimal>> fiatPriceHistory(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    _checkNotDisposed();
    _assertInitialized();

    String cacheKeyFor(DateTime date) =>
        _getCacheKey(assetId, priceDate: date, quoteCurrency: quoteCurrency);

    final today = _utcToday();
    final prices = <DateTime, Decimal>{};
    final currentDays = <DateTime>[];
    final missingDates = <DateTime>[];

    for (final date in {for (final date in dates) _normalizeDate(date)}) {
      if (date.isAfter(today)) continue;
      final cacheKey = cacheKeyFor(date);
      final cachedPrice = _getCachedPrice(cacheKey);
      if (cachedPrice != null) {
        prices[date] = cachedPrice;
      } else if (date == today) {
        currentDays.add(date);
      } else if (!_isKnownUnpriced(cacheKey)) {
        missingDates.add(date);
      }
    }

    // Daily history may not include the day in progress (CoinPaprika never
    // does), while the current price always describes it.
    if (currentDays.isNotEmpty) {
      final currentPrice = await maybeFiatPrice(
        assetId,
        quoteCurrency: quoteCurrency,
      );
      if (currentPrice == null) {
        missingDates.addAll(
          currentDays.where(
            (date) => !_isKnownUnpricedToday(cacheKeyFor(date)),
          ),
        );
      } else {
        for (final date in currentDays) {
          prices[date] = currentPrice;
        }
      }
    }

    if (missingDates.isNotEmpty) {
      final accumulated = <DateTime, Decimal>{};
      var hadFailure = false;
      Map<DateTime, Decimal> fetched;
      try {
        fetched = await tryRepositoriesInOrder(
          assetId,
          quoteCurrency,
          PriceRequestType.priceHistory,
          (repo) async {
            final remaining = missingDates
                .where((date) => !accumulated.containsKey(date))
                .toList();
            final remainingSet = remaining.toSet();
            try {
              final result = await repo.getCoinFiatPrices(
                assetId,
                remaining,
                fiatCurrency: quoteCurrency,
              );
              for (final entry in result.entries) {
                final date = _normalizeDate(entry.key);
                if (remainingSet.contains(date)) {
                  accumulated[date] = entry.value;
                }
              }
            } catch (_) {
              hadFailure = true;
              rethrow;
            }
            return accumulated;
          },
          'fiatPriceHistory',
          maxTotalAttempts: priceRepositories.length > 3
              ? priceRepositories.length
              : 3,
          isComplete: (result) => missingDates.every(result.containsKey),
        );
      } catch (e) {
        // The days already priced (cache hits, today's price) are still
        // right. The rest stay unknown, not unpriced, so they are asked for
        // again next time.
        if (prices.isEmpty && accumulated.isEmpty) rethrow;
        _logger.fine(
          'Returning the ${prices.length + accumulated.length} known prices '
          'for ${assetId.symbol.assetConfigId}; the rest failed: $e',
        );
        hadFailure = true;
        fetched = accumulated;
      }

      fetched.forEach((date, price) {
        final normalizedDate = _normalizeDate(date);
        _cacheDatedPrice(
          cacheKeyFor(normalizedDate),
          normalizedDate,
          price,
          requestDay: today,
        );
        prices[normalizedDate] = price;
      });
      final unpriced = missingDates.where((date) => !prices.containsKey(date));
      if (!hadFailure &&
          unpriced.isNotEmpty &&
          !await hasUnavailableRepositoriesFor(
            assetId,
            quoteCurrency,
            PriceRequestType.priceHistory,
          )) {
        final learntAt = _clock();
        for (final date in unpriced) {
          final memo = date.isBefore(today)
              ? _unpricedPastDays
              : _unpricedCurrentDays;
          memo[cacheKeyFor(date)] = learntAt;
        }
      }
    }

    final sortedDates = prices.keys.toList()..sort();
    return {for (final date in sortedDates) date: prices[date]!};
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _isInitialized = false;
    _cacheTimer?.cancel();
    _cacheTimer = null;
    _priceCache.clear();
    _pastDayPriceCache.clear();
    _unpricedPastDays.clear();
    _unpricedCurrentDays.clear();
    _lastKnownCurrentPriceCache.clear();
    _priceChangeCache.clear();
    clearRepositoryHealthData(); // Clear mixin data
    _logger.fine('Disposed CexMarketDataManager');
  }
}
