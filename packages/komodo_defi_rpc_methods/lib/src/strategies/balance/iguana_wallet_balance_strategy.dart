import 'dart:async';
import 'dart:developer' show log;
import 'dart:math' as math;

import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Balance strategy for single address assets (non-HD wallets)
class IguananaWalletBalanceStrategy extends BalanceStrategy {
  IguananaWalletBalanceStrategy();

  // Constants for retry handling
  static const Duration _initialTimeout = Duration(seconds: 15);
  static const Duration _maxTimeout = Duration(seconds: 25);
  static const int _maxRetries = 2;

  // Random generator for jittered retry
  final _random = math.Random();

  @override
  Future<BalanceInfo> getBalance(AssetId assetId, ApiClient client) async {
    var retryCount = 0;
    var timeout = _initialTimeout;

    while (true) {
      try {
        // Apply timeout to the RPC call to prevent indefinite waiting
        final response = await client.rpc.wallet
            .myBalance(coin: assetId.id)
            .timeout(
              timeout,
              onTimeout: () {
                throw TimeoutException(
                  'Balance fetch timed out after ${timeout.inSeconds}s for $assetId',
                );
              },
            );

        return response.balance;
      } catch (e) {
        if (e is TimeoutException || _isTransientError(e)) {
          // Only retry if it's a timeout or transient error
          if (retryCount < _maxRetries) {
            retryCount++;

            // Calculate jittered backoff delay - adds randomness to prevent thundering herd
            final baseDelay =
                math.min(500 * math.pow(2, retryCount), 2000).toInt();
            final jitter = _random.nextInt(baseDelay ~/ 2);
            final delay = Duration(milliseconds: baseDelay + jitter);

            // Increase timeout for next attempt
            timeout = Duration(
              milliseconds: math.min(
                timeout.inMilliseconds * 3 ~/ 2,
                _maxTimeout.inMilliseconds,
              ),
            );

            log(
              'Retrying balance fetch for $assetId after delay of ${delay.inMilliseconds}ms. '
              'Attempt ${retryCount + 1}/${_maxRetries + 1} with timeout ${timeout.inSeconds}s',
            );

            await Future<void>.delayed(delay);
            continue;
          }
        }

        // If we've exhausted retries or it's a non-retryable error, rethrow
        rethrow;
      }
    }
  }

  /// Determine if an error is likely transient and worth retrying
  bool _isTransientError(Object error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('temporary') ||
        errorString.contains('socket') ||
        errorString.contains('network') ||
        errorString.contains('unavailable');
  }

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId,
    ApiClient client, {
    Duration pollingInterval = const Duration(seconds: 1),
  }) {
    final controller = StreamController<BalanceInfo>.broadcast();

    scheduleMicrotask(() async {
      try {
        BalanceInfo? lastBalance;
        var consecutiveErrors = 0;

        while (!controller.isClosed) {
          try {
            final balance = await getBalance(assetId, client);

            // Only emit if balance changed
            if (lastBalance != balance) {
              lastBalance = balance;
              controller.add(balance);
            }

            // Reset error counter on success
            consecutiveErrors = 0;
          } catch (e, stackTrace) {
            consecutiveErrors++;

            // Log the error
            log(
              'Error fetching balance for $assetId (attempt $consecutiveErrors): $e',
            );

            // Only propagate error if it persists
            if (consecutiveErrors > 2) {
              controller.addError(e, stackTrace);
            }

            // Use longer polling interval after errors to reduce load on servers
            final errorBackoff = math.min(consecutiveErrors * 2, 10);
            await Future<void>.delayed(Duration(seconds: errorBackoff));
            continue;
          }

          await Future<void>.delayed(pollingInterval);
        }
      } catch (e, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(e, stackTrace);
          await controller.close();
        }
      }
    });

    return controller.stream;
  }

  @override
  bool protocolSupported(ProtocolClass protocol) {
    // All protocols are supported with this basic strategy
    return true;
  }
}
