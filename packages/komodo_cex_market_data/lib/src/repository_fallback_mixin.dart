import 'dart:async';

import 'package:komodo_cex_market_data/src/cex_repository.dart';
import 'package:komodo_cex_market_data/src/common/api_error_parser.dart';
import 'package:komodo_cex_market_data/src/models/quote_currency.dart';
import 'package:komodo_cex_market_data/src/repository_selection_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Mixin that provides repository fallback functionality for market data managers
///
/// This mixin handles intelligent fallback between multiple CEX repositories when
/// one becomes unavailable or returns errors. It includes special handling for
/// HTTP 429 (Too Many Requests) responses to prevent rate limiting issues.
///
/// Key features:
/// - Health tracking for repositories with automatic backoff periods
/// - Special 429 rate limit detection and immediate backoff (5 minutes)
/// - Smart retry logic across multiple repositories
/// - Repository prioritization based on health status
///
/// Rate Limit Handling:
/// When a repository returns a 429 response (or similar rate limiting error),
/// it is immediately marked as unhealthy and excluded from requests for the
/// configured backoff period. This prevents cascading rate limit violations
/// and allows the repository time to recover.
///
/// The mixin detects rate limiting errors by checking for:
/// - HTTP status code 429 in exception messages
/// - Text patterns like "too many requests" or "rate limit"
mixin RepositoryFallbackMixin {
  static final _logger = Logger('RepositoryFallbackMixin');

  // Repository health tracking
  final Map<Type, DateTime> _repositoryFailures = {};
  final Map<Type, int> _repositoryFailureCounts = {};
  final Map<Type, DateTime> _rateLimitedRepositories = {};
  static const _repositoryBackoffDuration = Duration(minutes: 5);
  static const _maxFailureCount = 3;

  // Conservative backoff strategy for fallback operations
  static final _fallbackBackoffStrategy = ExponentialBackoff(
    initialDelay: const Duration(milliseconds: 300),
    withJitter: true,
  );

  /// Must be implemented by the mixing class
  List<CexRepository> get priceRepositories;

  /// Must be implemented by the mixing class
  RepositorySelectionStrategy get selectionStrategy;

  /// Checks if a repository is healthy (not in backoff period)
  bool _isRepositoryHealthy(CexRepository repo) {
    final repoType = repo.runtimeType;

    // Check if repository is rate limited
    final rateLimitEnd = _rateLimitedRepositories[repoType];
    if (rateLimitEnd != null) {
      final isRateLimitExpired = DateTime.now().isAfter(rateLimitEnd);
      if (!isRateLimitExpired) {
        return false;
      } else {
        // Rate limit period expired, remove from rate limited list
        _rateLimitedRepositories.remove(repoType);
      }
    }

    final lastFailure = _repositoryFailures[repoType];
    final failureCount = _repositoryFailureCounts[repoType] ?? 0;

    if (lastFailure == null || failureCount < _maxFailureCount) {
      return true;
    }

    final backoffEnd = lastFailure.add(_repositoryBackoffDuration);
    final isHealthy = DateTime.now().isAfter(backoffEnd);

    if (isHealthy) {
      // Reset failure count after backoff period
      _repositoryFailureCounts[repoType] = 0;
      _repositoryFailures.remove(repoType);
    }

    return isHealthy;
  }

  /// Checks if an exception indicates a 429 (Too Many Requests) response
  bool _isRateLimitError(Exception exception) {
    if (exception is MarketDataApiException) return exception.isRateLimited;

    final exceptionString = exception.toString().toLowerCase();

    // Check for HTTP 429 status code in various exception formats
    return exceptionString.contains('429') ||
        exceptionString.contains('too many requests') ||
        exceptionString.contains('rate limit');
  }

  /// Records a repository failure
  void _recordRepositoryFailure(CexRepository repo, Exception exception) {
    final repoType = repo.runtimeType;

    // Check if this is a rate limiting error
    if (_isRateLimitError(exception)) {
      _recordRateLimitFailure(repo);
      return;
    }

    _repositoryFailures[repoType] = DateTime.now();
    _repositoryFailureCounts[repoType] =
        (_repositoryFailureCounts[repoType] ?? 0) + 1;

    _logger.fine(
      'Repository ${repo.runtimeType} failure recorded '
      '(count: ${_repositoryFailureCounts[repoType]})',
    );
  }

  /// Records a rate limit failure and immediately applies backoff
  void _recordRateLimitFailure(CexRepository repo) {
    final repoType = repo.runtimeType;
    final backoffEnd = DateTime.now().add(_repositoryBackoffDuration);

    _rateLimitedRepositories[repoType] = backoffEnd;

    _logger.warning(
      'Repository ${repo.runtimeType} hit rate limit (429). '
      'Applying immediate ${_repositoryBackoffDuration.inMinutes}-minute backoff '
      'until ${backoffEnd.toIso8601String()}',
    );
  }

  /// Records a repository success
  void _recordRepositorySuccess(CexRepository repo) {
    final repoType = repo.runtimeType;
    if (_repositoryFailureCounts.containsKey(repoType)) {
      _repositoryFailureCounts[repoType] = 0;
      _repositoryFailures.remove(repoType);
    }
    // Also clear any rate limit status on success
    _rateLimitedRepositories.remove(repoType);
  }

  /// Gets repositories ordered by health and preference
  Future<List<CexRepository>> _getHealthyRepositoriesInOrder(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    PriceRequestType requestType,
  ) async {
    // Filter healthy repositories
    final healthyRepos = priceRepositories.where(_isRepositoryHealthy).toList();

    if (healthyRepos.isEmpty) {
      _logger.fine('No healthy repositories available, using all repositories');
      // Even when no healthy repos, still filter by support
      final supportingRepos = <CexRepository>[];
      for (final repo in priceRepositories) {
        try {
          if (await repo.supports(assetId, quoteCurrency, requestType)) {
            supportingRepos.add(repo);
          }
        } catch (e, s) {
          _logger.fine(
            'Error checking support for repository ${repo.runtimeType}',
            e,
            s,
          );
          // Skip repositories that error on supports check
        }
      }
      return supportingRepos;
    }

    // Get primary repository from healthy ones
    final primaryRepo = await selectionStrategy.selectRepository(
      assetId: assetId,
      fiatCurrency: quoteCurrency,
      requestType: requestType,
      availableRepositories: healthyRepos,
    );

    if (primaryRepo == null) {
      // No repository supports this asset/currency combination
      return <CexRepository>[];
    }

    // Order: primary first, then other healthy repos that support the asset,
    // then unhealthy repos that support the asset
    final orderedRepos = <CexRepository>[primaryRepo];

    // Add other healthy repositories that support the asset
    for (final repo in healthyRepos) {
      if (repo != primaryRepo) {
        try {
          if (await repo.supports(assetId, quoteCurrency, requestType)) {
            orderedRepos.add(repo);
          }
        } catch (e, s) {
          _logger.fine(
            'Error checking support for healthy repository ${repo.runtimeType}',
            e,
            s,
          );
          // Skip repositories that error on supports check
        }
      }
    }

    // Add unhealthy repositories that support the asset as last resort
    for (final repo in priceRepositories) {
      if (!_isRepositoryHealthy(repo)) {
        try {
          if (await repo.supports(assetId, quoteCurrency, requestType)) {
            orderedRepos.add(repo);
          }
        } catch (e, s) {
          _logger.fine(
            'Error checking support for unhealthy repository '
            '${repo.runtimeType}',
            e,
            s,
          );
          // Skip repositories that error on supports check
        }
      }
    }

    return orderedRepos;
  }

  /// Generic method to try repositories in order until one succeeds
  /// Uses smart retry logic with maximum 3 total attempts across
  /// all repositories
  Future<T> tryRepositoriesInOrder<T>(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    PriceRequestType requestType,
    Future<T> Function(CexRepository repo) operation,
    String operationName, {
    int maxTotalAttempts = 3,
  }) async {
    var repositories = await _getHealthyRepositoriesInOrder(
      assetId,
      quoteCurrency,
      requestType,
    );

    if (repositories.isEmpty) {
      throw StateError(
        'No repository supports ${assetId.symbol.assetConfigId}/$quoteCurrency '
        'for $operationName',
      );
    }

    Exception? lastException;
    var attemptCount = 0;

    // Smart retry logic: try each repository in order first, then retry
    // if needed, but re-evaluate health after rate limit errors
    for (var attempt = 0; attempt < maxTotalAttempts; attempt++) {
      // Re-evaluate repository health if we've had failures
      if (attempt > 0) {
        repositories = await _getHealthyRepositoriesInOrder(
          assetId,
          quoteCurrency,
          requestType,
        );
        if (repositories.isEmpty) {
          break; // No healthy repositories left
        }
      }

      final repositoryIndex = attempt % repositories.length;
      final repo = repositories[repositoryIndex];

      // Double-check repository health before attempting
      if (!_isRepositoryHealthy(repo)) {
        _logger.fine(
          'Skipping unhealthy repository ${repo.runtimeType} for $operationName',
        );
        continue;
      }

      try {
        attemptCount++;
        _logger.finer(
          'Attempting $operationName for ${assetId.symbol.assetConfigId} '
          'with repository ${repo.runtimeType} '
          '(attempt $attemptCount/$maxTotalAttempts)',
        );

        final result = await retry(
          () => operation(repo),
          maxAttempts: 1, // Single attempt per call, we handle retries here
          backoffStrategy: _fallbackBackoffStrategy,
        );

        _recordRepositorySuccess(repo);

        if (attemptCount > 1) {
          _logger.fine(
            'Successfully fetched $operationName for '
            '${assetId.symbol.assetConfigId} '
            'using repository ${repo.runtimeType} on attempt $attemptCount',
          );
        }

        return result;
      } catch (e, s) {
        lastException = e is Exception ? e : Exception(e.toString());
        _recordRepositoryFailure(repo, lastException);

        // If this was a rate limit error, immediately refresh the repository list
        // to exclude the now-unhealthy repository from future attempts
        if (_isRateLimitError(lastException)) {
          _logger.fine(
            'Rate limit detected for ${repo.runtimeType}, refreshing repository list',
          );
          repositories = await _getHealthyRepositoriesInOrder(
            assetId,
            quoteCurrency,
            requestType,
          );
        }

        _logger
          ..fine(
            'Repository ${repo.runtimeType} failed for $operationName '
            '${assetId.symbol.assetConfigId} (attempt $attemptCount): $e',
          )
          ..finest('Stack trace: $s');
      }
    }

    _logger.warning(
      'All $attemptCount attempts failed for $operationName '
      '${assetId.symbol.assetConfigId}',
    );
    throw lastException ??
        Exception('All $maxTotalAttempts attempts failed for $operationName');
  }

  /// Tries repositories in order but returns null instead of
  /// throwing on failure
  Future<T?> tryRepositoriesInOrderMaybe<T>(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    PriceRequestType requestType,
    Future<T> Function(CexRepository repo) operation,
    String operationName, {
    int maxTotalAttempts = 3,
  }) async {
    try {
      return await tryRepositoriesInOrder(
        assetId,
        quoteCurrency,
        requestType,
        operation,
        operationName,
        maxTotalAttempts: maxTotalAttempts,
      );
    } catch (e, s) {
      _logger.finest('Stack trace: $s');
      return null;
    }
  }

  /// Clears repository health tracking data
  void clearRepositoryHealthData() {
    _repositoryFailures.clear();
    _repositoryFailureCounts.clear();
    _rateLimitedRepositories.clear();
  }
}
