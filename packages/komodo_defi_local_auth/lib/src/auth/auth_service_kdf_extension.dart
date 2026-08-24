part of 'auth_service.dart';

extension KdfExtensions on KdfAuthService {
  Future<bool> _walletExists(String walletName) async {
    if (!await _kdfFramework.isRunning()) return false;

    // The caller owns the auth write lock. Avoid re-entering the public
    // lock-protected API from the registration transaction.
    final users = await _getUsersWithinAuthLock();
    return users.any((user) => user.walletId.name == walletName);
  }

  Future<KdfUser?> _getActiveUser() async {
    if (!await _kdfFramework.isRunning()) {
      return null;
    }

    final activeWallet = (await _runStartupSensitiveRpc(
      phase: 'active wallet read',
      operation: () => _client.rpc.wallet.getWalletNames(),
    )).activatedWallet;
    if (activeWallet == null) {
      return null;
    }

    final user = await _secureStorage.getUser(activeWallet);
    if (user == null) return null;

    return _ensureAuthenticatedWalletIdentity(user);
  }

  Future<KdfUser> _ensureAuthenticatedWalletIdentity(
    KdfUser user, {
    bool persist = true,
  }) async {
    final GetPublicKeyHashResponse response;
    try {
      response = await _runStartupSensitiveRpc(
        phase: 'authenticated wallet identity read',
        operation: () => _client.rpc.wallet.getPublicKeyHash(),
      );
    } catch (error, stackTrace) {
      final identityRpcIsUnavailable =
          error is GeneralErrorResponse ||
          (error is AuthException &&
              error.type == AuthExceptionType.apiConnectionError);
      if (!identityRpcIsUnavailable) {
        // The exception deliberately carries only the cause's *type*: this
        // message reaches the UI, and a cause like JsonUnsupportedObjectError
        // stringifies the offending object, which here is a wallet identity
        // response.
        //
        // That left nothing at all to debug with, though - a bare
        // "causeType: JsonUnsupportedObjectError" says the response could not
        // be re-encoded and not one thing about why. So log the full cause and
        // stack at severe, where it reaches the log file the user can export
        // and the redaction in the framework's log sink still applies.
        _logger.severe(
          '[$_sessionId] Authenticated wallet identity read failed',
          error,
          stackTrace,
        );
        throw AuthException(
          'KDF returned a malformed authenticated wallet identity response',
          type: AuthExceptionType.internalError,
          details: {'causeType': error.runtimeType.toString()},
        );
      }
      // A temporarily unavailable identity RPC must not lock users out of
      // Standard wallet access. Never retain a previously persisted identity
      // in the runtime user, though: GasFree may only unlock its wallet-scoped
      // journal after the active KDF identity has been verified in this
      // session. The stored user remains untouched so a later successful RPC
      // can recover the same journal.
      _logger.warning(
        'Authenticated wallet identity is unavailable '
        '(${error.runtimeType})',
        null,
        stackTrace,
      );
      return user.copyWith(
        walletId: WalletId.fromName(
          user.walletId.name,
          user.walletId.authOptions,
        ),
      );
    }
    final resolvedIdentity = response.publicKeyHash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(resolvedIdentity)) {
      throw AuthException(
        'KDF returned an invalid authenticated wallet identity',
        type: AuthExceptionType.internalError,
      );
    }

    final storedIdentity = user.walletId.pubkeyHash?.trim().toLowerCase();
    if (storedIdentity != null &&
        storedIdentity.isNotEmpty &&
        storedIdentity != resolvedIdentity) {
      throw AuthException(
        'Stored wallet identity does not match the active KDF wallet',
        type: AuthExceptionType.internalError,
      );
    }
    if (storedIdentity == resolvedIdentity &&
        (user.walletId.pubkeyHash?.trim().isNotEmpty ?? false)) {
      // Preserve an already-authenticated identity byte-for-byte. Earlier
      // preview builds could have stored uppercase hex and used those bytes
      // when deriving the encrypted journal key; canonicalizing it here would
      // orphan that journal even though it represents the same H160.
      return user;
    }

    final identifiedUser = user.copyWith(
      walletId: user.walletId.copyWith(pubkeyHash: resolvedIdentity),
    );
    if (persist) {
      try {
        await _secureStorage.saveUser(identifiedUser);
        _invalidateUsersCache();
      } catch (error, stackTrace) {
        // Identity persistence is required for GasFree journal access, but a
        // local secure-storage write failure must not stop an otherwise
        // authenticated KDF session or remove Standard wallet access. Return
        // a name-only runtime identity so GasFree remains locked until a later
        // verified call can persist the stable identity.
        _logger.warning(
          'Unable to persist the authenticated wallet identity '
          '(${error.runtimeType})',
          null,
          stackTrace,
        );
        return user.copyWith(
          walletId: WalletId.fromName(
            user.walletId.name,
            user.walletId.authOptions,
          ),
        );
      }
    }
    return identifiedUser;
  }

  /// Returns the mnenomic for the active wallet in the requested format, if
  /// it exists and KDF is running, otherwise throws [AuthException].
  /// NOTE: this function does not check if there is an active user, so only
  /// use it if you know there is one.
  /// There are no read/write locks used internally by this function, so it is
  /// safe to call within mutex locks.
  Future<Mnemonic> _getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  }) async {
    if (!await _kdfFramework.isRunning()) {
      throw AuthException(
        'KDF is not running',
        type: AuthExceptionType.generalAuthError,
      );
    }

    final response = await _runStartupSensitiveRpc<JsonMap>(
      phase: 'get_mnemonic',
      operation: () async {
        return _kdfFramework.client.executeRpc({
          'mmrpc': '2.0',
          'method': 'get_mnemonic',
          'params': {
            'format': encrypted ? 'encrypted' : 'plaintext',
            if (!encrypted) 'password': walletPassword,
          },
        });
      },
    );

    if (response is JsonRpcErrorResponse) {
      throw AuthException(
        response.error,
        type: AuthExceptionType.generalAuthError,
      );
    }

    return Mnemonic.fromRpcJson(response.value<JsonMap>('result'));
  }

  Future<void> _stopKdf() async {
    await _shutdownSubscription?.cancel();
    _shutdownSubscription = null;
    await _kdfFramework.kdfStop();
    _kdfFramework.resetHttpClient();
    _emitAuthStateChange(null);
  }

  Future<void> _clearFailedAuthenticatedKdfWithinWriteLock() async {
    try {
      await _stopKdf();
    } catch (error, stackTrace) {
      // Authentication must remain cleared even if the native runtime cannot
      // be stopped cleanly. Managers observe this transition and revoke every
      // wallet-scoped cache and operation.
      _emitAuthStateChange(null);
      _logger.warning(
        'Failed to stop KDF after authentication failure '
        '(${error.runtimeType})',
        null,
        stackTrace,
      );
    }
  }

  /// Ensures that KDF is running with a write lock.
  /// NOTE: do not use within a read or write lock.
  Future<void> _ensureKdfRunning() async {
    if (!await _kdfFramework.isRunning()) {
      await _lockWriteOperation(() async {
        if (await _kdfFramework.isRunning()) return;

        final startStopwatch = Stopwatch()..start();
        final kdfResult = await _kdfFramework.startKdf(await _noAuthConfig);
        startStopwatch.stop();
        _logger.info(
          '[$_sessionId] _ensureKdfRunning: startKdf(no-auth) returned '
          '${kdfResult.name} in ${startStopwatch.elapsedMilliseconds}ms',
        );

        if (!kdfResult.isStartingOrAlreadyRunning()) {
          throw _mapStartupErrorToAuthException(kdfResult);
        }

        _kdfFramework.resetHttpClient();
        await _waitUntilKdfRpcReady();
        await _subscribeToShutdownSignals();
      });
    }
  }

  // consider moving to kdf api
  Future<void> _restartKdf(KdfStartupConfig config) async {
    final stopStopwatch = Stopwatch()..start();
    await _stopKdf();
    stopStopwatch.stop();
    _logger.info(
      '[$_sessionId] _restartKdf: stop phase completed in '
      '${stopStopwatch.elapsedMilliseconds}ms',
    );

    final startStopwatch = Stopwatch()..start();
    final kdfResult = await _kdfFramework.startKdf(config);
    startStopwatch.stop();
    _logger.info(
      '[$_sessionId] _restartKdf: auth start returned ${kdfResult.name} in '
      '${startStopwatch.elapsedMilliseconds}ms',
    );

    if (!kdfResult.isStartingOrAlreadyRunning()) {
      throw _mapStartupErrorToAuthException(kdfResult);
    }

    _kdfFramework.resetHttpClient();
    final readyStopwatch = Stopwatch()..start();
    await _waitUntilKdfRpcReady();
    await _subscribeToShutdownSignals();
    readyStopwatch.stop();
    _logger.info(
      '[$_sessionId] _restartKdf: readiness verify completed in '
      '${readyStopwatch.elapsedMilliseconds}ms',
    );
  }

  static AuthException _mapStartupErrorToAuthException(
    KdfStartupResult result,
  ) {
    switch (result) {
      // TODO! NB: The only user-caused reason for this is if the user
      // enters the wrong password. However (!!) we must migrate soon to a
      // more robust error handling system. Either log scanning, or a more
      // reliable solution as detailed in:
      // https://github.com/GLEECBTC/komodo-defi-framework/issues/2383
      // TODO(takenagain): Integrate the log scanning if KDF team does not
      // implement the proposal in the GH Issue above.
      case KdfStartupResult.initError:
        // This is typically caused by an incorrect password. As a temporary
        // solution, this can be narrowed down to incorrect password by
        // validating the mnemonic. See the note above.
        throw AuthException(
          'Incorrect password or invalid seed',
          type: AuthExceptionType.incorrectPassword,
        );

      case KdfStartupResult.alreadyRunning:
        // This should not be reached due to isStartingOrAlreadyRunning check
        throw AuthException(
          'Wallet is already running',
          type: AuthExceptionType.walletAlreadyRunning,
        );

      case KdfStartupResult.configError:
        throw AuthException(
          'Invalid wallet configuration',
          type: AuthExceptionType.walletStartFailed,
          details: {'kdf_error': result.name},
        );

      case KdfStartupResult.invalidParams:
        throw AuthException(
          'Invalid parameters provided to wallet',
          type: AuthExceptionType.walletStartFailed,
          details: {'kdf_error': result.name},
        );

      case KdfStartupResult.spawnError:
        throw AuthException(
          'Failed to start wallet process',
          type: AuthExceptionType.walletStartFailed,
          details: {'kdf_errosr': result.name},
        );

      case KdfStartupResult.unknownError:
      case KdfStartupResult.ok:
        throw ArgumentError('Unexpected startup result: $result');
    }
  }

  Future<void> _waitUntilKdfRpcReady({
    Duration timeout = KdfAuthService._kdfRpcReadyTimeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      final status = await _kdfFramework.kdfMainStatus().timeout(
        KdfAuthService._kdfRpcProbeTimeout,
        onTimeout: () => MainStatus.notRunning,
      );
      if (status == MainStatus.rpcIsUp) {
        try {
          final version = await _kdfFramework.version().timeout(
            KdfAuthService._kdfRpcProbeTimeout,
            onTimeout: () => null,
          );
          if (version != null) {
            _logger.info(
              '[$_sessionId] _waitUntilKdfRpcReady: RPC ready in '
              '${stopwatch.elapsedMilliseconds}ms',
            );
            return;
          }
        } on SocketException catch (e) {
          _logger.fine(
            '[$_sessionId] _waitUntilKdfRpcReady: version probe transport '
            'error (will retry): $e',
          );
        } on HttpException catch (e) {
          _logger.fine(
            '[$_sessionId] _waitUntilKdfRpcReady: version probe transport '
            'error (will retry): $e',
          );
        } on HandshakeException catch (e) {
          _logger.fine(
            '[$_sessionId] _waitUntilKdfRpcReady: version probe transport '
            'error (will retry): $e',
          );
        }
      }

      await Future<void>.delayed(KdfAuthService._kdfRpcPollInterval);
    }

    throw AuthException(
      'KDF RPC did not become ready within ${timeout.inSeconds} seconds',
      type: AuthExceptionType.apiConnectionError,
    );
  }

  Future<T> _runStartupSensitiveRpc<T>({
    required String phase,
    required Future<T> Function() operation,
  }) async {
    Future<T> runAttempt() =>
        operation().timeout(KdfAuthService._startupSensitiveRpcTimeout);

    try {
      return await runAttempt();
    } catch (error, stackTrace) {
      if (!_shouldRecoverStartupSensitiveRpc(error)) {
        rethrow;
      }

      _logger.warning(
        '[$_sessionId] _runStartupSensitiveRpc: $phase failed on first '
        'attempt, resetting HTTP client and retrying',
        error,
        stackTrace,
      );
      _kdfFramework.resetHttpClient();
      await _waitUntilKdfRpcReady();

      try {
        return await runAttempt();
      } catch (retryError, retryStackTrace) {
        if (!_shouldRecoverStartupSensitiveRpc(retryError)) {
          rethrow;
        }

        _logger.severe(
          '[$_sessionId] _runStartupSensitiveRpc: $phase failed after retry',
          retryError,
          retryStackTrace,
        );
        throw AuthException(
          'KDF RPC unavailable during $phase',
          type: AuthExceptionType.apiConnectionError,
          details: {'phase': phase, 'cause': retryError.toString()},
        );
      }
    }
  }

  /// Whether [error] means KDF could not be *reached*, in either the raw or the
  /// already-wrapped form.
  ///
  /// Deliberately narrower than [_shouldRecoverStartupSensitiveRpc], and
  /// deliberately not delegating to it: that one also retries a non-permanent
  /// `GeneralErrorResponse`, which means KDF answered. This decides whether to
  /// tear down the runtime and sign the user out, so it must mean transport
  /// only.
  ///
  /// The wrapped form is the one that fires in practice.
  /// [_runStartupSensitiveRpc] retries the raw types and then gives up by
  /// throwing `AuthException(apiConnectionError)`, so a caller matching only
  /// the raw types would silently never fire.
  /// [_ensureAuthenticatedWalletIdentity] keys off the same pair.
  bool _isKdfUnreachable(Object error) {
    if (error is AuthException) {
      return error.type == AuthExceptionType.apiConnectionError;
    }
    return error is TimeoutException ||
        error is ClientException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException;
  }

  /// Whether a startup-sensitive RPC failure is worth one retry.
  ///
  /// The transport faults below, plus KDF answering *with* an error while it is
  /// still coming up or is saturated - on web a single-threaded WASM instance
  /// sharing the Flutter isolate with a login's activation fan-out. Without
  /// that last clause, one such response on the very first attempt makes
  /// [_ensureAuthenticatedWalletIdentity] fall straight through to a name-only
  /// identity with no retry, and that downgrade is emitted on the auth stream
  /// to every wallet-scoped consumer.
  ///
  /// `ClientException` is the transport type that actually fires: the RPC path
  /// runs through `package:http` (`kdf_operations_native.dart`) and
  /// `http_extensions.dart` raises it directly, so a loopback failure arrives
  /// as that rather than as the `dart:io` types. Those are kept for the paths
  /// that bypass `package:http`.
  bool _shouldRecoverStartupSensitiveRpc(Object error) {
    return error is TimeoutException ||
        error is ClientException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        (error is GeneralErrorResponse && !_isPermanentStartupRpcError(error));
  }

  /// Errors KDF has explicitly classified as terminal.
  ///
  /// A deny-list, not an allow-list: the saturation responses this retry exists
  /// for often carry no `error_type` at all, so anything unrecognised must stay
  /// retryable. Retrying a *modelled* failure only delays the real message and
  /// re-labels it `apiConnectionError`.
  bool _isPermanentStartupRpcError(GeneralErrorResponse error) {
    if (_isIncorrectPasswordRpcError(error) ||
        _isWalletNotFoundRpcError(error)) {
      return true;
    }
    final errorType = _extractRpcErrorType(error);
    return _isInternalWalletError(errorType) ||
        (errorType ?? '').toLowerCase() == 'invalidrequest';
  }

  Future<KdfStartupConfig> _generateStartupConfig({
    required String walletName,
    required String walletPassword,
    required bool allowRegistrations,
    required bool hdEnabled,
    String? plaintextMnemonic,
    String? encryptedMnemonic,
    bool allowWeakPassword = false,
  }) async {
    if (plaintextMnemonic != null && encryptedMnemonic != null) {
      throw AuthException(
        'Both plaintext and encrypted mnemonics provided.',
        type: AuthExceptionType.generalAuthError,
      );
    }

    // Fetch seed nodes using the dedicated service
    final (seedNodes: seedNodes, netId: netId) =
        await SeedNodeService.fetchSeedNodes();

    return KdfStartupConfig.generateWithDefaults(
      walletName: walletName,
      walletPassword: walletPassword,
      seed: plaintextMnemonic ?? encryptedMnemonic,
      rpcPassword: _hostConfig.rpcPassword,
      // Without this the `rpcPort = 7783` default won unconditionally, so the
      // KDF this service started never listened anywhere else - no matter what
      // the host config said. That is what made the port effectively fixed
      // rather than merely defaulted.
      rpcPort: _hostConfig.port,
      allowRegistrations: allowRegistrations,
      enableHd: hdEnabled,
      allowWeakPassword: allowWeakPassword,
      seedNodes: seedNodes,
      netid: netId,
    );
  }
}
