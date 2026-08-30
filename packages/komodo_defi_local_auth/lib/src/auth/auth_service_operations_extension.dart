part of 'auth_service.dart';

extension KdfAuthServiceOperationsExtension on KdfAuthService {
  Future<T> _lockWriteOperation<T>(Future<T> Function() operation) async {
    return _authMutex.protectWrite(operation);
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    // With shutdown signal streaming in place, health checks serve primarily
    // as a backup for edge cases where the event stream might miss a shutdown.
    // Reduced from 5 minutes to 30 minutes to minimize RPC spam while
    // maintaining a safety net for detecting stale KDF instances.
    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkKdfHealth(),
    );
  }

  /// Subscribes to shutdown signal events from KDF to immediately detect
  /// when KDF is shutting down, eliminating the need for frequent polling.
  ///
  /// This provides near-instant detection of KDF shutdown (< 1 second) compared
  /// to the periodic health check (up to 30 minutes delay).
  Future<void> _subscribeToShutdownSignals() async {
    await _shutdownSubscription?.cancel();
    _shutdownSubscription = null;

    // Enable shutdown signal streaming via RPC and subscribe to events
    _shutdownSubscription = _kdfFramework.streaming.shutdownSignals.listen(
      _handleShutdownSignal,
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Error in shutdown signal stream, '
          'will rely on periodic health checks',
          error,
          stackTrace,
        );
      },
      cancelOnError: false,
    );

    // Stream registration is an availability optimization, not an
    // authentication dependency. Keep startup non-blocking and bound a KDF
    // endpoint that does not answer; the periodic health check remains the
    // fallback.
    unawaited(
      _enableShutdownStream().timeout(const Duration(seconds: 2)).catchError((
        Object error,
      ) {
        _logger.warning(
          'Failed to enable shutdown signal stream, '
          'will rely on periodic health checks: $error',
        );
      }),
    );
  }

  /// Enables the shutdown signal stream on KDF.
  Future<void> _enableShutdownStream() async {
    // TODO: Remove if/when shutdown signal stream is supported on Web
    // and Windows
    if (kIsWeb || Platform.isWindows) {
      _logger.info('Shutdown signal stream not supported on Web');
      return;
    }
    try {
      if (!await _kdfFramework.isRunning()) {
        return;
      }

      await _client.rpc.streaming.enableShutdownSignal();
      _logger.info(
        '[EVENT STREAM] Shutdown signal stream enabled successfully',
      );
    } catch (e) {
      // Log but don't throw - streaming is a nice-to-have optimization
      _logger.warning('Could not enable shutdown signal stream: $e');
    }
  }

  /// Handles shutdown signal events by immediately updating auth state.
  void _handleShutdownSignal(ShutdownSignalEvent event) {
    _logger.info(
      'Received shutdown signal (${event.signalName}), '
      'signing out user immediately',
    );

    final generation = _authStateGeneration;
    unawaited(
      _lockWriteOperation(() async {
        // A delayed shutdown event from the previous KDF instance must not
        // sign out a newer session.
        if (generation == _authStateGeneration && _lastEmittedUser != null) {
          await _shutdownSubscription?.cancel();
          _shutdownSubscription = null;
          _emitAuthStateChange(null);
        }
      }),
    );
  }

  Future<void> _checkKdfHealth() async {
    try {
      await _lockWriteOperation(() async {
        final isRunning = await _kdfFramework.isRunning();
        // Bypass cached user to detect external changes accurately.
        final KdfUser? currentUser;
        try {
          currentUser = await _getActiveUser();
        } on AuthException catch (error, stackTrace) {
          if (error.type != AuthExceptionType.internalError) {
            rethrow;
          }

          // A malformed or changed authenticated wallet identity is
          // deterministic, not a transport blip. Clear it while the same
          // auth write lock is still held so cleanup cannot race a newer
          // sign-in or restore operation.
          _logger.severe(
            'Authenticated wallet identity failed health verification',
            error,
            stackTrace,
          );
          await _clearFailedAuthenticatedKdfWithinWriteLock();
          return;
        }

        // If KDF is not running or we're in no-auth mode but previously had a
        // user, emit signed out state.
        if ((!isRunning || currentUser == null) && _lastEmittedUser != null) {
          _emitAuthStateChange(null);
        } else if (currentUser != null &&
            currentUser.walletId != _lastEmittedUser?.walletId) {
          // User state changed.
          _emitAuthStateChange(currentUser);
        }
      });
    } on AuthException catch (e, s) {
      _logger.warning('Health check failed, will retry on next interval', e, s);
    } catch (e, s) {
      // Log the error but don't immediately sign out on transient RPC failures.
      // The next health check (in 5 minutes) will verify if this is persistent.
      // This prevents false sign-outs during temporary network issues.
      _logger.warning('Health check failed, will retry on next interval', e, s);
      // Note: We intentionally do NOT emit null here to avoid false sign-outs
      // from transient errors. KDF may still be running and user authenticated.
    }
  }
}
