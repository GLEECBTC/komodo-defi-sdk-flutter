part of 'auth_service.dart';

extension KdfExtensions on KdfAuthService {
  Future<bool> _walletExists(String walletName) async {
    if (!await _kdfFramework.isRunning()) return false;

    final users = await getUsers();
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

    return _secureStorage.getUser(activeWallet);
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
    await _kdfFramework.kdfStop();
    _kdfFramework.resetHttpClient();
    _authStateController.add(null);
  }

  /// Ensures that KDF is running with a write lock.
  /// NOTE: do not use within a read or write lock.
  Future<void> _ensureKdfRunning() async {
    if (!await _kdfFramework.isRunning()) {
      await _lockWriteOperation(() async {
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

  bool _shouldRecoverStartupSensitiveRpc(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException;
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
      allowRegistrations: allowRegistrations,
      enableHd: hdEnabled,
      allowWeakPassword: allowWeakPassword,
      seedNodes: seedNodes,
      netid: netId,
    );
  }
}
