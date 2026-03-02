import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Balance strategy for HD wallets with multiple addresses
class HDWalletBalanceStrategy extends BalanceStrategy {
  HDWalletBalanceStrategy();

  // Constants for retry handling
  static const Duration _initialTimeout = Duration(seconds: 20);
  static const Duration _maxTimeout = Duration(seconds: 30);
  static const int _maxRetries = 2;
  static const Duration _taskStatusPollingInterval = Duration(
    milliseconds: 500,
  );

  // Random generator for jittered retry
  final _random = math.Random();

  @override
  Future<BalanceInfo> getBalance(AssetId assetId, ApiClient client) async {
    var retryCount = 0;
    var timeout = _initialTimeout;

    while (true) {
      try {
        // Start balance task with timeout
        final initResponse = await client.rpc.hdWallet
            .accountBalanceInit(coin: assetId.id, accountIndex: 0)
            .timeout(
              timeout,
              onTimeout: () {
                throw TimeoutException(
                  'Balance task initialization timed out after '
                  '${timeout.inSeconds}s for $assetId',
                );
              },
            );

        // Use a more resilient task watching approach
        return await _watchBalanceTaskWithRetry(
          initResponse,
          client,
          assetId,
          timeout,
        );
      } catch (e) {
        if (e is TimeoutException || _isTransientError(e)) {
          // Only retry if it's a timeout or transient error
          if (retryCount < _maxRetries) {
            retryCount++;

            // Calculate jittered backoff delay
            final baseDelay = math
                .min(500 * math.pow(2, retryCount), 2000)
                .toInt();
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
              'Retrying HD wallet balance fetch for $assetId\n'
              'Delay: ${delay.inMilliseconds}ms\n'
              'Attempt: ${retryCount + 1}/${_maxRetries + 1}\n'
              'Timeout: ${timeout.inSeconds}s',
              name: 'HDWalletBalanceStrategy',
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

  /// More resilient version of the task watching logic
  Future<BalanceInfo> _watchBalanceTaskWithRetry(
    NewTaskResponse initResponse,
    ApiClient client,
    AssetId assetId,
    Duration timeout,
  ) async {
    final taskId = initResponse.taskId;
    final completer = Completer<AccountBalanceStatusResponse>();
    Timer? pollingTimer;
    Timer? timeoutTimer;
    var consecutiveErrorCount = 0;
    const maxConsecutiveErrors = 3;

    try {
      // Set timeout for the entire operation
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          pollingTimer?.cancel();
          completer.completeError(
            TimeoutException(
              'HD wallet balance task timed out after '
              '${timeout.inSeconds}s for $assetId',
            ),
          );

          try {
            // Try to cancel the task on timeout
            client.rpc.hdWallet.accountBalanceCancel(taskId: taskId);
          } catch (e) {
            log(
              'Error cancelling HD wallet balance task',
              name: 'HDWalletBalanceStrategy',
              error: e,
              stackTrace: StackTrace.current,
            );
          }
        }
      });

      // Poll for task status
      pollingTimer = Timer.periodic(_taskStatusPollingInterval, (timer) async {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }

        try {
          final status = await client.rpc.hdWallet.accountBalanceStatus(
            taskId: taskId,
          );

          // Reset error count on successful response
          consecutiveErrorCount = 0;

          if (status.status.isTerminal) {
            if (status.details.data != null) {
              timer.cancel();
              if (!completer.isCompleted) {
                completer.complete(status);
              }
            } else if (status.status == SyncStatusEnum.error) {
              timer.cancel();
              if (!completer.isCompleted) {
                final taskError =
                    exceptionMessage(status.details.error) ?? 'Unknown error';
                completer.completeError(
                  Exception('HD wallet balance task failed: $taskError'),
                );
              }
            }
          }
        } catch (e) {
          consecutiveErrorCount++;

          log(
            'Error checking HD wallet balance task status',
            name: 'HDWalletBalanceStrategy',
            error: e,
            stackTrace: StackTrace.current,
          );

          // If we get "No such task" error or too many consecutive errors, stop polling
          final errorString = e.toString().toLowerCase();
          if (errorString.contains('no such task') ||
              consecutiveErrorCount >= maxConsecutiveErrors) {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.completeError(
                Exception('Balance task failed or is no longer available: $e'),
              );
            }
          }
        }
      });

      final response = await completer.future;
      final balanceInfo = response.details.data!;
      return balanceInfo.totalBalance.balanceOf(assetId.id);
    } finally {
      timeoutTimer?.cancel();
      pollingTimer?.cancel();
    }
  }

  /// Determine if an error is likely transient and worth retrying
  bool _isTransientError(Object error) {
    final errorString = error.toString().toLowerCase();
    return [
      'connection',
      'timeout',
      'temporary',
      'socket',
      'network',
      'unavailable',
      // Common transient error keywords
      'no such coin',
      'coin not found',
      'not activated',
      'invalid coin',
    ].any(errorString.contains);
  }

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId,
    ApiClient client, {
    Duration pollingInterval = const Duration(seconds: 1),
  }) {
    final controller = StreamController<BalanceInfo>.broadcast();

    scheduleMicrotask(() async {
      BalanceInfo? lastBalance;
      var isClosed = false;
      var consecutiveErrors = 0;

      // Add a listener to track when the controller is closed
      controller.onCancel = () {
        isClosed = true;
      };

      try {
        while (!isClosed) {
          try {
            final balance = await getBalance(assetId, client);

            // Only emit if balance changed
            if (lastBalance != balance) {
              lastBalance = balance;
              if (!isClosed) {
                controller.add(balance);
              }
            }

            // Reset error counter on success
            consecutiveErrors = 0;
          } catch (e, stackTrace) {
            consecutiveErrors++;

            // Log the error
            log(
              'Error fetching HD wallet balance for $assetId\n'
              'Attempt: $consecutiveErrors',
              name: 'HDWalletBalanceStrategy',
              error: e,
              stackTrace: stackTrace,
            );

            // Only propagate error if it persists
            if (consecutiveErrors > 2 && !isClosed) {
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
        if (!isClosed) {
          controller.addError(e, stackTrace);
          await controller.close();
        }
      }
    });

    return controller.stream;
  }

  @override
  bool protocolSupported(ProtocolClass protocol) {
    // HD wallet balance strategy supports protocols that can handle multiple addresses
    // This includes UTXO-based protocols and EVM protocols
    // Tendermint protocols use single addresses only
    return protocol.supportsMultipleAddresses;
  }
}
