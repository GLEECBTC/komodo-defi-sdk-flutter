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
          'Error in shutdown signal stream, will rely on periodic health '
          'checks',
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
          'Failed to enable shutdown signal stream, will rely on '
          'periodic health checks: '
          '${DiagnosticSanitizer.safeError(error)}',
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
      _logger.warning(
        'Could not enable shutdown signal stream: '
        '${DiagnosticSanitizer.safeError(e)}',
      );
    }
  }

  /// Handles shutdown signal events by immediately updating auth state.
  void _handleShutdownSignal(ShutdownSignalEvent event) {
    _logger.info(
      'Received shutdown signal (omitted), signing out user '
      'immediately',
    );

    beginAuthTransition();
    final generation = authGeneration;
    unawaited(
      _lockWriteOperation(() async {
        // A delayed shutdown event from the previous KDF instance must not
        // sign out a newer session.
        if (generation == _authStateGeneration && _lastEmittedUser != null) {
          await _shutdownSubscription?.cancel();
          _shutdownSubscription = null;
          _emitAuthStateChange(null);
        }
      }).whenComplete(endAuthTransition),
    );
  }

  /// Re-reads a degraded identity until KDF answers `get_public_key_hash`.
  ///
  /// A name-only user means the identity RPC failed, typically while a web
  /// login's activation fan-out saturates KDF. GasFree stays paused until an
  /// enriched identity is emitted, and the SDK managers no longer re-read the
  /// user on every poll, so nothing else would ask again promptly. The
  /// re-reads back off from [_identityRecheckDelay] and stop after
  /// [KdfAuthService._maxIdentityRechecks]; the periodic health check and any
  /// later read can still enrich the identity.
  void _trackIdentityRecovery(KdfUser? user) {
    if (user == null || user.walletId.hasFullIdentity) {
      _identityRecheckTimer?.cancel();
      _identityRecheckTimer = null;
      _identityRechecks = 0;
      return;
    }
    if (_isDisposed ||
        _identityRecheckTimer != null ||
        _identityRechecks >= KdfAuthService._maxIdentityRechecks) {
      return;
    }
    final delay = _identityRecheckDelay * (1 << _identityRechecks);
    _identityRechecks++;
    _identityRecheckTimer = Timer(delay, () {
      _identityRecheckTimer = null;
      if (_isDisposed || _lastEmittedUser == null) return;
      // The read emits what it finds, which clears or re-arms this.
      getActiveUser().ignore();
    });
  }

  Future<void> _checkKdfHealth() async {
    try {
      await _lockWriteOperation(() async {
        final isRunning = await _kdfFramework.isRunning();
        // Bypass cached user to detect external changes accurately.
        final KdfUser? currentUser;
        try {
          currentUser = await _getActiveUser();
        } on AuthException catch (error) {
          if (error.type != AuthExceptionType.internalError) {
            rethrow;
          }

          // A malformed or changed authenticated wallet identity is
          // deterministic, not a transport blip. Clear it while the same
          // auth write lock is still held so cleanup cannot race a newer
          // sign-in or restore operation.
          _logger.severe(
            'Authenticated wallet identity failed health verification',
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
    } on AuthException {
      _logger.warning('Health check failed, will retry on next interval');
    } catch (e) {
      // Log the error but don't immediately sign out on transient RPC failures.
      // The next health check (in 5 minutes) will verify if this is persistent.
      // This prevents false sign-outs during temporary network issues.
      _logger.warning('Health check failed, will retry on next interval');
      // Note: We intentionally do NOT emit null here to avoid false sign-outs
      // from transient errors. KDF may still be running and user authenticated.
    }
  }
}
