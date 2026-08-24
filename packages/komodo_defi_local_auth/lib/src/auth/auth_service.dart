import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' show ClientException;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';
import 'package:uuid/uuid.dart';

part 'auth_service_auth_extension.dart';
part 'auth_service_kdf_extension.dart';
part 'auth_service_operations_extension.dart';

abstract interface class IAuthService {
  Future<List<KdfUser>> getUsers();

  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  });

  /// Throws [AuthException] if user creation fails, the wallet already exists,
  /// or the seed phrase is not a valid BIP39 seed phrase.
  Future<KdfUser> register({
    required String walletName,
    required String password,
    required AuthOptions options,
    Mnemonic? mnemonic,
  });

  /// Waits for active operations to complete before signin the user out.
  Future<void> signOut();

  /// Returns true if KDF is running and the active wallet is registered with
  /// the auth service. Otherwise, returns false.
  Future<bool> isSignedIn();

  /// Returns the [KdfUser] associated with the active wallet if KDF is running,
  /// otherwise null.
  ///
  /// The active wallet and its stable identity are verified against KDF on
  /// every call. Identity verification and any persisted identity upgrade are
  /// serialized with authentication state transitions.
  Future<KdfUser?> getActiveUser();

  /// Returns the [Mnemonic] for the active wallet, throws an [AuthException]
  /// otherwise.
  ///
  /// If [encrypted] is true, the encrypted mnemonic is returned. Otherwise,
  /// the plaintext mnemonic is returned, which requires the [walletPassword]
  /// to be provided.
  ///
  /// The operation is serialized with authentication state transitions so a
  /// mnemonic can never be returned for a wallet that is being signed out.
  Future<Mnemonic> getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  });

  /// Changes the password for the current user.
  ///
  /// Throws [AuthException] if the current password is incorrect or if no user
  /// is signed in.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Deletes the specified wallet.
  Future<void> deleteWallet({
    required String walletName,
    required String password,
  });

  /// Method to store custom metadata for the user.
  ///
  /// Overwrites any existing metadata.
  ///
  /// This does not emit an auth state change event.
  ///
  /// NB: This is intended to only be a short-term solution until the SDK
  /// is fully integrated with KW. This may be deprecated in the future.
  Future<void> setActiveUserMetadata(JsonMap metadata);

  /// Atomically reads the current value of [key] from the active user's
  /// metadata, applies [transform] to it, and writes the result back.
  ///
  /// This is safe to call concurrently — a dedicated metadata mutex
  /// serialises all read-modify-write cycles.
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform,
  );

  /// Attempts to restore a user session without requiring password authentication
  /// Only works if the KDF API is running and the wallet exists
  Future<void> restoreSession(KdfUser user);

  /// Ensures that KDF is healthy and responsive. If KDF is not healthy,
  /// attempts to restart it with the current user's configuration.
  /// This is useful for recovering from situations where KDF has become
  /// unavailable, especially on mobile platforms after app backgrounding.
  /// Returns true if KDF is healthy or was successfully restarted, false otherwise.
  Future<bool> ensureKdfHealthy();

  Stream<KdfUser?> get authStateChanges;
  Future<void> dispose();
}

class KdfAuthService implements IAuthService {
  KdfAuthService(
    this._kdfFramework,
    this._hostConfig, {
    SecureLocalStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureLocalStorage(),
       _sessionId = const Uuid().v4() {
    _logger.info('[$_sessionId] KdfAuthService initialized');
    _startHealthCheck();
    unawaited(_lockWriteOperation(_subscribeToShutdownSignals));
  }

  final KomodoDefiFramework _kdfFramework;
  final IKdfHostConfig _hostConfig;
  final StreamController<KdfUser?> _authStateController =
      StreamController.broadcast();
  final SecureLocalStorage _secureStorage;
  final ReadWriteMutex _authMutex = ReadWriteMutex();
  final Mutex _metadataMutex = Mutex();
  final Logger _logger = Logger('KdfAuthService');
  final String _sessionId;

  KdfUser? _lastEmittedUser;
  int _authStateGeneration = 0;
  Timer? _healthCheckTimer;

  /// Compound ids of wallets this session created without an imported mnemonic.
  ///
  /// Never persisted: the whole meaning is "first sign-in", and a value that
  /// outlived the session would keep telling the address scan there is nothing
  /// to find long after the wallet could have received funds.
  final Set<String> _walletsGeneratedThisSession = <String>{};

  /// Rolling cost of [getActiveUser]; see [_recordActiveUserCall].
  int _activeUserCalls = 0;
  int _activeUserQueuedMs = 0;
  int _activeUserHeldMs = 0;
  DateTime? _activeUserWindowStart;

  /// Short enough to resolve a login burst into several windows, long enough
  /// that a steady-state app logs roughly nothing.
  static const Duration _activeUserReportInterval = Duration(seconds: 5);

  // Single-flight guard for ensureKdfHealthy to prevent concurrent restarts
  Future<bool>? _ongoingHealthCheck;
  DateTime? _lastHealthCheckAttempt;
  DateTime? _lastHealthCheckCompleted;
  bool? _lastHealthCheckResult;
  StreamSubscription<ShutdownSignalEvent>? _shutdownSubscription;

  // Cache for wallet users list to avoid spamming get_wallet_names
  List<KdfUser>? _usersCache;
  DateTime? _usersCacheTimestamp;
  final Duration _usersCacheTtl = const Duration(minutes: 5);
  static const Duration _kdfRpcReadyTimeout = Duration(seconds: 15);
  static const Duration _kdfRpcProbeTimeout = Duration(seconds: 2);
  static const Duration _kdfRpcPollInterval = Duration(milliseconds: 250);
  static const Duration _startupSensitiveRpcTimeout = Duration(seconds: 10);

  ApiClient get _client => _kdfFramework.client;
  late final methods = KomodoDefiRpcMethods(_client);

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  }) async {
    _logger.info(
      '[$_sessionId] signIn: Starting login for wallet: $walletName',
    );

    // Proactively ensure KDF is healthy before attempting login
    // This prevents login attempts while KDF is down or restarting
    final isHealthy = await ensureKdfHealthy().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _logger.warning(
          '[$_sessionId] signIn: Health check timed out after 3s',
        );
        return false;
      },
    );

    if (!isHealthy) {
      _logger.warning(
        '[$_sessionId] signIn: KDF not healthy, retrying after 1s',
      );
      // Wait and retry once
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final retryHealthy = await ensureKdfHealthy().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (!retryHealthy) {
        _logger.severe(
          '[$_sessionId] signIn: KDF still not healthy after retry',
        );
        throw AuthException(
          'KDF is not available. Please try again.',
          type: AuthExceptionType.apiConnectionError,
        );
      }
    }

    _logger.info('[$_sessionId] signIn: KDF healthy, proceeding with login');

    final user = await _lockWriteOperation<KdfUser>(() async {
      // Check if already signed in first
      if (await _kdfFramework.isRunning()) {
        final KdfUser? activeUser;
        try {
          activeUser = await _resolveActiveUserWithinWriteLock();
        } catch (_) {
          await _clearFailedAuthenticatedKdfWithinWriteLock();
          rethrow;
        }
        if (activeUser?.walletId.name == walletName) {
          return activeUser!;
        }
        // If running but wrong user, stop KDF
        await _stopKdf();
      }

      final storedUser = await _secureStorage.getUser(walletName);
      if (storedUser == null) {
        throw AuthException.notFound();
      }

      // If we know this is not a BIP39 seed, don't allow HD mode
      if (!storedUser.isBip39Seed &&
          options.derivationMethod == DerivationMethod.hdWallet) {
        throw AuthException(
          'Cannot use HD mode with non-BIP39 seed',
          type: AuthExceptionType.generalAuthError,
        );
      }

      final config = await _generateStartupConfig(
        walletName: walletName,
        walletPassword: password,
        allowRegistrations: false,
        hdEnabled: options.derivationMethod == DerivationMethod.hdWallet,
        allowWeakPassword: options.allowWeakPassword,
      );

      try {
        final user = await _authenticateUser(config);
        _emitAuthStateChange(user);
        return user;
      } catch (_) {
        await _clearFailedAuthenticatedKdfWithinWriteLock();
        rethrow;
      }
    });

    return user;
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
  }) async {
    _logger.info(
      '[$_sessionId] register: Starting registration for wallet: $walletName',
    );
    final registerStopwatch = Stopwatch()..start();

    try {
      final ensureStartStopwatch = Stopwatch()..start();
      await _ensureKdfRunning();
      ensureStartStopwatch.stop();
      _logger.info(
        '[$_sessionId] register: ensure no-auth start completed in '
        '${ensureStartStopwatch.elapsedMilliseconds}ms',
      );

      final walletExistsStopwatch = Stopwatch()..start();
      await _lockWriteOperation(() async {
        final walletExists = await _walletExists(walletName);
        if (walletExists) {
          throw AuthException(
            'Wallet already exists',
            type: AuthExceptionType.generalAuthError,
          );
        }
      });
      walletExistsStopwatch.stop();
      _logger.info(
        '[$_sessionId] register: wallet existence read completed in '
        '${walletExistsStopwatch.elapsedMilliseconds}ms',
      );

      // replaces the __assertWalletOrStop method - wait for read/write locks to
      // be released here.
      // can be used outside of a lock, since both functions are public-facing
      // and manage their own read/write locks
      final stopStopwatch = Stopwatch()..start();
      if (await isSignedIn()) {
        await signOut();
        stopStopwatch.stop();
        _logger.info(
          '[$_sessionId] register: stop phase completed in '
          '${stopStopwatch.elapsedMilliseconds}ms',
        );
      } else {
        stopStopwatch.stop();
        _logger.info(
          '[$_sessionId] register: no active session to stop '
          '(${stopStopwatch.elapsedMilliseconds}ms)',
        );
      }

      final config = await _generateStartupConfig(
        walletName: walletName,
        walletPassword: password,
        allowRegistrations: true,
        plaintextMnemonic: mnemonic?.plaintextMnemonic,
        hdEnabled: options.derivationMethod == DerivationMethod.hdWallet,
        allowWeakPassword: options.allowWeakPassword,
      );

      return _lockWriteOperation(() async {
        final writePathStopwatch = Stopwatch()..start();
        final isImported = mnemonic != null;
        late final KdfUser currentUser;
        try {
          currentUser = await _registerNewUser(config, options, isImported);
          if (!isImported) {
            // A wallet created here has no on-chain history by construction:
            // the seed did not exist a moment ago. Recorded per session so the
            // HD gap scan can be told so on this sign-in only.
            _walletsGeneratedThisSession.add(
              currentUser.walletId.compoundId,
            );
          }
        } catch (_) {
          await _clearFailedAuthenticatedKdfWithinWriteLock();
          rethrow;
        }
        writePathStopwatch.stop();
        _logger.info(
          '[$_sessionId] register: registration write path completed in '
          '${writePathStopwatch.elapsedMilliseconds}ms',
        );
        final sessionUser = _stampSessionFlags(currentUser)!;
        _emitAuthStateChange(sessionUser);
        _invalidateUsersCache();
        return sessionUser;
      });
    } finally {
      registerStopwatch.stop();
      _logger.info(
        '[$_sessionId] register: Finished in '
        '${registerStopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  @override
  Future<List<KdfUser>> getUsers() async {
    await _ensureKdfRunning();

    return _lockWriteOperation(_getUsersWithinAuthLock);
  }

  Future<List<KdfUser>> _getUsersWithinAuthLock() async {
    // Serve from cache if fresh.
    if (_usersCache != null &&
        _usersCacheTimestamp != null &&
        DateTime.now().difference(_usersCacheTimestamp!) < _usersCacheTtl) {
      return _usersCache!;
    }

    final walletNames = await _runStartupSensitiveRpc(
      phase: 'get_wallet_names',
      operation: () => _client.rpc.wallet.getWalletNames(),
    );

    final users = await Future.wait(
      walletNames.walletNames.map((name) async {
        final user = await _secureStorage.getUser(name);
        if (user != null) return user;

        // Create a user record for a KDF wallet discovered before local auth
        // metadata was persisted.
        final newUser = KdfUser(
          walletId: WalletId.fromName(name, _fallbackAuthOptions),
          isBip39Seed: true,
        );
        await _secureStorage.saveUser(newUser);
        return newUser;
      }),
    );

    _usersCache = users;
    _usersCacheTimestamp = DateTime.now();
    return users;
  }

  Future<void> updateUserBip39Status(String walletName, bool isBip39) async {
    await _lockWriteOperation(() async {
      final existingUser = await _secureStorage.getUser(walletName);
      if (existingUser == null) return;

      // Don't allow switching to HD if not BIP39
      if (!isBip39 && existingUser.isHd) {
        throw AuthException(
          'Cannot use non-BIP39 seed with HD wallet',
          type: AuthExceptionType.generalAuthError,
        );
      }

      final updatedUser = existingUser.copyWith(isBip39Seed: isBip39);
      await _secureStorage.saveUser(updatedUser);
      _invalidateUsersCache();
    });
  }

  @override
  Future<void> signOut() async {
    await _lockWriteOperation(() async {
      await _stopKdf();
      _emitAuthStateChange(null);
    });
  }

  @override
  Future<bool> isSignedIn() async {
    return await getActiveUser() != null;
  }

  @override
  Future<KdfUser?> getActiveUser() async {
    // `getActiveUser` is the hottest thing on the login path and the reason it
    // is hot is invisible from any single call site: it is invoked from the
    // auth write lock by nearly every SDK subsystem, and each invocation costs
    // two RPCs (`get_wallet_names` then `get_public_key_hash`). Field logs
    // showed ~480 identity RPCs for one login, and nothing in either repo
    // could say where they came from.
    //
    // Three numbers make that legible: how many calls, how long they queued
    // for the write lock, and how long they held it. Queue time is the one
    // that matters most - it is serialised, so N callers pay for each other.
    //
    // Deliberately NOT a cache. `protectRead` was removed here as a GasFree
    // security fix (see the note at [_resolveActiveUserWithinWriteLock]) and
    // caching `currentUser` per auth generation would reintroduce exactly what
    // that removal prevents. This measures the cost; it does not avoid it.
    final queued = Stopwatch()..start();
    return _lockWriteOperation(() async {
      queued.stop();
      final held = Stopwatch()..start();
      try {
        return _stampSessionFlags(await _resolveActiveUserWithinWriteLock());
      } catch (error) {
        // Clearing authentication here is the right response to an identity we
        // cannot trust - KDF answering with a different wallet, or a malformed
        // identity. It is the wrong response to not having been able to ask.
        //
        // This is a read-shaped accessor: `isSignedIn()` and six managers call
        // it, some on a poll. Treating a dropped socket or a timeout as proof
        // of a bad identity turns one transient blip on the loopback RPC into
        // `kdfStop()` plus a forced sign-out, losing the whole session.
        if (_isKdfUnreachable(error)) rethrow;
        await _clearFailedAuthenticatedKdfWithinWriteLock();
        rethrow;
      } finally {
        held.stop();
        _recordActiveUserCall(
          queued.elapsedMilliseconds,
          held.elapsedMilliseconds,
        );
      }
    });
  }

  /// Re-applies session-scoped facts that are not persisted with the user.
  ///
  /// [KdfUser.isGeneratedThisSession] lives only in [_walletsGeneratedThisSession],
  /// so a user read back from secure storage has it false. Stamped on the way
  /// out of [getActiveUser] rather than written into storage, because the whole
  /// meaning is "this session created it": a persisted value would keep telling
  /// the HD address scan there is nothing to find long after the wallet could
  /// have received funds.
  KdfUser? _stampSessionFlags(KdfUser? user) {
    if (user == null) return null;
    if (!_walletsGeneratedThisSession.contains(user.walletId.compoundId)) {
      return user;
    }
    return user.copyWith(isGeneratedThisSession: true);
  }

  /// Accumulates [getActiveUser] cost and reports it at INFO, rate-limited.
  ///
  /// Rate-limited rather than one line per call: a login issues hundreds of
  /// these, and per-call logging would itself become a cost. Rate-limited
  /// rather than a single end-of-login summary, because there is no clean
  /// "login finished" moment - the amplification continues through activation,
  /// and watching the count decay across successive windows is what tells you
  /// whether the burst is login or something that never settles.
  void _recordActiveUserCall(int queuedMs, int heldMs) {
    _activeUserCalls++;
    _activeUserQueuedMs += queuedMs;
    _activeUserHeldMs += heldMs;

    final now = DateTime.now();
    final since = _activeUserWindowStart ??= now;
    if (now.difference(since) < _activeUserReportInterval) return;

    _logger.info(
      '[$_sessionId] getActiveUser: $_activeUserCalls calls in '
      '${now.difference(since).inMilliseconds}ms '
      '(${_activeUserCalls * 2} identity RPCs), '
      'lock queue ${_activeUserQueuedMs}ms, lock held ${_activeUserHeldMs}ms',
    );
    _activeUserCalls = 0;
    _activeUserQueuedMs = 0;
    _activeUserHeldMs = 0;
    _activeUserWindowStart = now;
  }

  Future<KdfUser?> _resolveActiveUserWithinWriteLock() async {
    // A cached identity is not authentication proof: KDF may have restarted
    // in no-auth mode or switched wallets outside this service. Always bind
    // security-sensitive wallet storage to a fresh active-wallet and
    // public-key-hash response from the running KDF instance.
    final user = await _getActiveUser();
    _emitAuthStateChange(user);
    return user;
  }

  Future<T> _runAuthenticatedWriteOperation<T>(
    Future<T> Function(KdfUser activeUser) operation,
  ) async {
    return _lockWriteOperation(() async {
      var activeUserResolutionCompleted = false;
      try {
        final activeUser = await _resolveActiveUserWithinWriteLock();
        activeUserResolutionCompleted = true;
        if (activeUser == null) throw AuthException.notSignedIn();
        return operation(activeUser);
      } catch (_) {
        if (!activeUserResolutionCompleted) {
          await _clearFailedAuthenticatedKdfWithinWriteLock();
        }
        rethrow;
      }
    });
  }

  AuthOptions get _fallbackAuthOptions =>
      const AuthOptions(derivationMethod: DerivationMethod.hdWallet);

  @override
  Future<Mnemonic> getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  }) async {
    assert(
      encrypted || walletPassword != null,
      'walletPassword is required to retrieve plaintext mnemonic.',
    );
    return _runAuthenticatedWriteOperation((_) {
      return _getMnemonic(encrypted: encrypted, walletPassword: walletPassword);
    });
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _runAuthenticatedWriteOperation((_) async {
      try {
        await _client.rpc.wallet.changeMnemonicPassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      } on MmRpcException catch (e) {
        if (_isIncorrectPasswordRpcError(e)) {
          throw AuthException(
            'Incorrect current password',
            type: AuthExceptionType.incorrectPassword,
            details: {
              'error': _extractRpcErrorMessage(e),
              'errorType': e.errorType,
            },
          );
        }

        final knownExceptions = _findKnownAuthExceptions(e);
        if (knownExceptions.isNotEmpty) {
          throw knownExceptions.first;
        }

        throw AuthException(
          'Failed to change password: ${_extractRpcErrorMessage(e) ?? e}',
          type: AuthExceptionType.generalAuthError,
          details: {'errorType': e.errorType},
        );
      } on GeneralErrorResponse catch (e) {
        if (_isIncorrectPasswordRpcError(e)) {
          throw AuthException(
            'Incorrect current password',
            type: AuthExceptionType.incorrectPassword,
            details: {'error': e.error, 'errorType': e.errorType},
          );
        }

        final knownExceptions = _findKnownAuthExceptions(e);
        if (knownExceptions.isNotEmpty) {
          throw knownExceptions.first;
        }

        throw AuthException(
          'Failed to change password: ${e.error ?? e}',
          type: AuthExceptionType.generalAuthError,
          details: {'errorType': e.errorType},
        );
      } catch (e) {
        final knownExceptions = _findKnownAuthExceptions(e);
        if (knownExceptions.isNotEmpty) {
          throw knownExceptions.first;
        }

        throw AuthException(
          'Failed to change password: $e',
          type: AuthExceptionType.generalAuthError,
        );
      }
    });
  }

  @override
  Future<void> deleteWallet({
    required String walletName,
    required String password,
  }) async {
    await _ensureKdfRunning();
    return _lockWriteOperation(() async {
      try {
        await _client.rpc.wallet.deleteWallet(
          walletName: walletName,
          password: password,
        );
        await _secureStorage.deleteUser(walletName);
        _invalidateUsersCache();
      } on MmRpcException catch (e) {
        throw _mapDeleteWalletRpcError(e);
      } on GeneralErrorResponse catch (e) {
        throw _mapDeleteWalletRpcError(e);
      } catch (e) {
        final knownExceptions = _findKnownAuthExceptions(e);
        if (knownExceptions.isNotEmpty) {
          throw knownExceptions.first;
        }
        throw AuthException(
          'Failed to delete wallet: $e',
          type: AuthExceptionType.generalAuthError,
        );
      }
    });
  }

  AuthException _mapDeleteWalletRpcError(Object error) {
    final message = _extractRpcErrorMessage(error);
    final errorType = _extractRpcErrorType(error);

    if (_isIncorrectPasswordRpcError(error)) {
      return AuthException(
        message ?? 'Invalid password',
        type: AuthExceptionType.incorrectPassword,
        details: {if (errorType != null) 'errorType': errorType},
      );
    }

    if (_isWalletNotFoundRpcError(error)) {
      return AuthException.notFound();
    }

    if (_isCannotDeleteActiveWalletError(errorType, message)) {
      return AuthException(
        message ?? 'Cannot delete active wallet',
        type: AuthExceptionType.generalAuthError,
        details: {if (errorType != null) 'errorType': errorType},
      );
    }

    if (_isInternalWalletError(errorType) ||
        error is MnemonicRpcErrorWalletsStorageErrorException ||
        error is MnemonicRpcErrorInternalException) {
      return AuthException(
        message ?? 'Internal error',
        type: AuthExceptionType.internalError,
        details: {if (errorType != null) 'errorType': errorType},
      );
    }

    if ((errorType ?? '').toLowerCase() == 'invalidrequest') {
      return AuthException(
        message ?? 'Invalid request',
        type: AuthExceptionType.internalError,
        details: {if (errorType != null) 'errorType': errorType},
      );
    }

    return AuthException(
      'Failed to delete wallet: ${message ?? error}',
      type: AuthExceptionType.generalAuthError,
      details: {if (errorType != null) 'errorType': errorType},
    );
  }

  bool _isIncorrectPasswordRpcError(Object error) {
    if (error is MnemonicRpcErrorInvalidPasswordException) {
      return true;
    }

    final errorType = _extractRpcErrorType(error)?.toLowerCase();
    if (errorType == 'invalidpassword') {
      return true;
    }

    final message = _extractRpcErrorMessage(error);
    if (message == null || message.isEmpty) {
      return false;
    }

    return AuthException.findExceptionsInLog(
      message,
      firstOnly: true,
    ).any((item) => item.type == AuthExceptionType.incorrectPassword);
  }

  bool _isWalletNotFoundRpcError(Object error) {
    final errorType = _extractRpcErrorType(error)?.toLowerCase();
    if (errorType == 'walletnotfound') {
      return true;
    }

    final message = _extractRpcErrorMessage(error)?.toLowerCase() ?? '';
    if (message.contains('wallet not found') ||
        message.contains('wallet does not exist') ||
        message.contains('no wallet found')) {
      return true;
    }

    return AuthException.findExceptionsInLog(
      message,
      firstOnly: true,
    ).any((item) => item.type == AuthExceptionType.walletNotFound);
  }

  bool _isCannotDeleteActiveWalletError(String? errorType, String? message) {
    if ((errorType ?? '').toLowerCase() == 'cannotdeleteactivewallet') {
      return true;
    }

    final lowerMessage = (message ?? '').toLowerCase();
    return lowerMessage.contains('cannot delete active wallet');
  }

  bool _isInternalWalletError(String? errorType) {
    switch ((errorType ?? '').toLowerCase()) {
      case 'walletsstorageerror':
      case 'walletstorageerror':
      case 'internal':
      case 'internalerror':
        return true;
      default:
        return false;
    }
  }

  String? _extractRpcErrorType(Object error) {
    if (error is MmRpcException) {
      return error.errorType;
    }
    if (error is GeneralErrorResponse) {
      return error.errorType;
    }
    return null;
  }

  String? _extractRpcErrorMessage(Object error) {
    if (error is MnemonicRpcErrorInvalidPasswordException) {
      return error.value;
    }
    if (error is MnemonicRpcErrorInvalidRequestException) {
      return error.value;
    }
    if (error is MnemonicRpcErrorWalletsStorageErrorException) {
      return error.value;
    }
    if (error is MnemonicRpcErrorInternalException) {
      return error.value;
    }
    if (error is MmRpcException) {
      return error.message;
    }
    if (error is GeneralErrorResponse) {
      return error.error;
    }
    return null;
  }

  List<AuthException> _findKnownAuthExceptions(Object error) {
    final details = _extractRpcErrorMessage(error);
    final errorText = [
      if (details != null) details,
      error.toString(),
    ].join('\n');
    return AuthException.findExceptionsInLog(errorText.toLowerCase());
  }

  void _invalidateUsersCache() {
    _usersCache = null;
    _usersCacheTimestamp = null;
  }

  @override
  Stream<KdfUser?> get authStateChanges => _authStateController.stream;

  @override
  Future<void> dispose() async {
    // Wait for running operations to complete before disposing. Write lock can
    // only be acquired once the active read/write operations complete.
    await _lockWriteOperation(() async {
      _healthCheckTimer?.cancel();
      await _shutdownSubscription?.cancel();
      _shutdownSubscription = null;
      await _stopKdf();
      await _authStateController.close();
      _lastEmittedUser = null;
    });
  }

  late final Future<KdfStartupConfig> _noAuthConfig =
      KdfStartupConfig.noAuthStartup(
        rpcPassword: _hostConfig.rpcPassword,
        rpcPort: _hostConfig.port,
      );

  Future<bool> verifyEncryptedSeedBip39Compatibility(String password) async {
    final mnemonic = await getMnemonic(
      encrypted: false,
      walletPassword: password,
    );

    if (mnemonic.plaintextMnemonic == null) {
      throw AuthException(
        'Failed to decrypt seed for verification',
        type: AuthExceptionType.generalAuthError,
      );
    }

    return MnemonicValidator().init().then((_) {
      final result = MnemonicValidator().validateMnemonic(
        mnemonic.plaintextMnemonic!,
        isHd: false,
        allowCustomSeed: true,
      );

      return result == null;
    });
  }

  @override
  Future<void> setActiveUserMetadata(Map<String, dynamic> metadata) async {
    await _runAuthenticatedWriteOperation(
      (activeUser) => _metadataMutex.protect(() async {
        final user = await _secureStorage.getUser(activeUser.walletId.name);
        if (user == null) throw AuthException.notFound();

        final persistedUser = user.copyWith(metadata: metadata);
        await _secureStorage.saveUser(persistedUser);

        // Update cache silently without triggering auth state change. Updating
        // the storage and cache at the same time emulates the same behaviour as
        // before. Update user metadata for any subsequent access without
        // emitting auth state changes, as the metadata field is currently used
        // for events like coin activation, wallet type (derivation), and seed
        // backup status.
        //
        // Keep the wallet identity from the current runtime session. In
        // particular, an identity RPC outage intentionally produces a
        // name-only runtime user so the encrypted GasFree journal remains
        // locked. Reloading the stored identity into this cache would bypass
        // that verification boundary after an otherwise unrelated metadata
        // write.
        _lastEmittedUser = activeUser.copyWith(metadata: metadata);
      }),
    );
  }

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) async {
    await _runAuthenticatedWriteOperation(
      (activeUser) => _metadataMutex.protect(() async {
        final user = await _secureStorage.getUser(activeUser.walletId.name);
        if (user == null) throw AuthException.notFound();

        final metadata = JsonMap.from(user.metadata);
        final transformed = transform(metadata[key]);
        if (transformed == null) {
          metadata.remove(key);
        } else {
          metadata[key] = transformed;
        }

        final persistedUser = user.copyWith(metadata: metadata);
        await _secureStorage.saveUser(persistedUser);
        _lastEmittedUser = activeUser.copyWith(metadata: metadata);
      }),
    );
  }

  @override
  Future<void> restoreSession(KdfUser user) async {
    return _lockWriteOperation(() async {
      try {
        // Only attempt to restore the session if KDF is running.
        // Check if KDF is running
        if (!await _kdfFramework.isRunning()) {
          throw AuthException(
            'KDF API is not running, cannot restore session',
            type: AuthExceptionType.apiConnectionError,
          );
        }

        // Verify the wallet exists in KDF
        final wallets = await _getUsersWithinAuthLock();
        final walletExists = wallets.any(
          (wallet) => wallet.walletId.name == user.walletId.name,
        );

        if (!walletExists) {
          throw AuthException(
            'Wallet not found: ${user.walletId.name}',
            type: AuthExceptionType.walletNotFound,
          );
        }

        final activeUser = await _getActiveUser();
        if (activeUser == null ||
            activeUser.walletId.name != user.walletId.name) {
          throw AuthException(
            'Active KDF wallet does not match the restored session',
            type: AuthExceptionType.unauthorized,
          );
        }

        // Update internal state and emit auth state change.
        _emitAuthStateChange(activeUser);
      } catch (error) {
        await _clearFailedAuthenticatedKdfWithinWriteLock();
        throw AuthException(
          'Failed to restore session: $error',
          type: AuthExceptionType.generalAuthError,
        );
      }
    });
  }

  @override
  Future<bool> ensureKdfHealthy() async {
    // Single-flight guard: if a health check is already in progress, return that future
    if (_ongoingHealthCheck != null) {
      _logger.info(
        '[$_sessionId] ensureKdfHealthy: Health check already in progress, awaiting result',
      );
      return _ongoingHealthCheck!;
    }

    // Cooldown mechanism: prevent rapid successive health checks
    // Only apply cooldown if a previous check has completed
    final now = DateTime.now();
    if (_lastHealthCheckCompleted != null) {
      final timeSinceLastCheck = now.difference(_lastHealthCheckCompleted!);
      if (timeSinceLastCheck.inSeconds < 2) {
        _logger.info(
          '[$_sessionId] ensureKdfHealthy: In cooldown period (${timeSinceLastCheck.inSeconds}s since last check)',
        );
        return _lastHealthCheckResult ?? false;
      }
    }

    // Start the health check and store the future
    _lastHealthCheckAttempt = now;
    _ongoingHealthCheck = _performHealthCheck();

    try {
      final result = await _ongoingHealthCheck!;
      _lastHealthCheckCompleted = DateTime.now();
      _lastHealthCheckResult = result;
      final elapsed = _lastHealthCheckCompleted!.difference(
        _lastHealthCheckAttempt!,
      );
      _logger.info(
        '[$_sessionId] ensureKdfHealthy: Completed in ${elapsed.inMilliseconds}ms, result=$result',
      );
      return result;
    } finally {
      // Clear the ongoing check flag when done
      _ongoingHealthCheck = null;
    }
  }

  Future<bool> _performHealthCheck() =>
      _lockWriteOperation(_performHealthCheckWithinWriteLock);

  Future<bool> _performHealthCheckWithinWriteLock() async {
    _logger.info('[$_sessionId] _performHealthCheck: Starting health check');
    final stopwatch = Stopwatch()..start();

    try {
      // First check if KDF is healthy with a short timeout
      final isHealthy = await _kdfFramework.isHealthy().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.warning(
            '[$_sessionId] _performHealthCheck: isHealthy() timed out after 2s',
          );
          return false;
        },
      );

      if (isHealthy) {
        // Double verification: even if isHealthy() returns true, verify with version() RPC
        // This prevents false positives where native status reports "running" but HTTP is down
        _logger.info(
          '[$_sessionId] _performHealthCheck: Initial check passed, performing double verification',
        );
        final doubleCheck = await _verifyKdfHealthy().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _logger.warning(
              '[$_sessionId] _performHealthCheck: Double verification timed out',
            );
            return false;
          },
        );

        if (doubleCheck) {
          stopwatch.stop();
          _logger.info(
            '[$_sessionId] _performHealthCheck: KDF is healthy (double verified) in ${stopwatch.elapsedMilliseconds}ms',
          );
          return true;
        }

        _logger.warning(
          '[$_sessionId] _performHealthCheck: Double verification failed, KDF not actually healthy',
        );
      }

      _logger.warning(
        '[$_sessionId] _performHealthCheck: KDF is not healthy, forcing full restart',
      );

      // Use _lastEmittedUser instead of calling _getActiveUser() RPC when KDF is down
      // This avoids blocking on a dead KDF
      final hadAuthenticatedUser = _lastEmittedUser != null;
      _logger.info(
        '[$_sessionId] _performHealthCheck: hadAuthenticatedUser=$hadAuthenticatedUser',
      );

      // FORCE a full stop->start cycle when we've determined KDF is unhealthy
      // Don't trust isRunning() as it can be stale after iOS backgrounding
      _logger.info(
        '[$_sessionId] _performHealthCheck: Forcing clean shutdown (ignoring isRunning status)',
      );
      try {
        await _stopKdf().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _logger.warning(
              '[$_sessionId] _performHealthCheck: kdfStop() timed out',
            );
          },
        );
      } catch (e) {
        _logger.warning(
          '[$_sessionId] _performHealthCheck: Error during shutdown: $e (continuing with restart)',
        );
        // KDF might already be dead, continue with restart
      }

      // Reset HTTP client unconditionally to drop stale keep-alive connections
      _logger.info('[$_sessionId] _performHealthCheck: Resetting HTTP client');
      _kdfFramework.resetHttpClient();

      // Force restart KDF in no-auth mode (we don't have the password)
      // Use _forceStartKdf instead of _ensureKdfRunning to bypass isRunning check
      _logger.info('[$_sessionId] _performHealthCheck: Force starting KDF');
      final restartStopwatch = Stopwatch()..start();
      await _forceStartKdfWithinWriteLock();
      restartStopwatch.stop();
      _logger.info(
        '[$_sessionId] _performHealthCheck: KDF force start completed in ${restartStopwatch.elapsedMilliseconds}ms',
      );

      // Reset HTTP client again after restart to ensure no stale sockets
      _logger.info(
        '[$_sessionId] _performHealthCheck: Resetting HTTP client again after restart',
      );
      _kdfFramework.resetHttpClient();

      // Add 200ms delay after restart before verification to avoid race where
      // native status reports "up" but HTTP listener hasn't bound yet
      _logger.info(
        '[$_sessionId] _performHealthCheck: Waiting 200ms for HTTP listener to bind',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Check if restart was successful with a strong health check (version RPC)
      _logger.info(
        '[$_sessionId] _performHealthCheck: Verifying KDF health with version check',
      );
      final verifyStopwatch = Stopwatch()..start();
      final isHealthyAfterRestart = await _verifyKdfHealthy().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.warning(
            '[$_sessionId] _performHealthCheck: Health verification timed out',
          );
          return false;
        },
      );
      verifyStopwatch.stop();
      _logger.info(
        '[$_sessionId] _performHealthCheck: Health verification took ${verifyStopwatch.elapsedMilliseconds}ms, result=$isHealthyAfterRestart',
      );

      // If we had an authenticated user, emit logged-out state
      // This will trigger the UI to show re-authentication prompt
      if (hadAuthenticatedUser && _lastEmittedUser != null) {
        _logger.info(
          '[$_sessionId] _performHealthCheck: Emitting logged-out state',
        );
        _emitAuthStateChange(null);
      }

      stopwatch.stop();
      _logger.info(
        '[$_sessionId] _performHealthCheck: Health check completed in ${stopwatch.elapsedMilliseconds}ms, result=$isHealthyAfterRestart',
      );
      return isHealthyAfterRestart;
    } catch (e) {
      stopwatch.stop();
      _logger.severe(
        '[$_sessionId] _performHealthCheck: Error during health check after ${stopwatch.elapsedMilliseconds}ms: $e',
      );
      // If we can't restart KDF and had an authenticated user, emit logged-out state
      if (_lastEmittedUser != null) {
        _logger.info(
          '[$_sessionId] _performHealthCheck: Emitting logged-out state due to error',
        );
        _emitAuthStateChange(null);
      }
      // Log the error but don't throw - return false to indicate failure
      return false;
    }
  }

  /// Force starts KDF without checking isRunning() status
  /// This is needed when we've determined KDF is unhealthy but isRunning() returns stale true
  Future<void> _forceStartKdfWithinWriteLock() async {
    _logger.info(
      '[$_sessionId] _forceStartKdf: Starting KDF (bypassing isRunning check)',
    );
    final startStopwatch = Stopwatch()..start();
    final result = await _kdfFramework.startKdf(await _noAuthConfig);
    startStopwatch.stop();
    _logger.info(
      '[$_sessionId] _forceStartKdf: startKdf() returned ${result.name} in '
      '${startStopwatch.elapsedMilliseconds}ms',
    );

    if (!result.isStartingOrAlreadyRunning()) {
      _logger.severe(
        '[$_sessionId] _forceStartKdf: Failed to start KDF: ${result.name}',
      );
      throw KdfExtensions._mapStartupErrorToAuthException(result);
    }

    _kdfFramework.resetHttpClient();
    _logger.info('[$_sessionId] _forceStartKdf: Waiting for RPC to be ready');
    final waitStopwatch = Stopwatch()..start();
    await _waitUntilKdfRpcReady();
    await _subscribeToShutdownSignals();
    waitStopwatch.stop();
    _logger.info(
      '[$_sessionId] _forceStartKdf: RPC ready after '
      '${waitStopwatch.elapsedMilliseconds}ms',
    );
  }

  /// Verifies KDF is healthy by checking if it responds to a version RPC
  /// This is a stronger check than just checking if the socket is open
  Future<bool> _verifyKdfHealthy() async {
    try {
      // Try to get KDF version - this confirms KDF is actually responding to RPCs
      await _kdfFramework.version();
      return true;
    } catch (e) {
      _logger.warning(
        '[$_sessionId] _verifyKdfHealthy: Version check failed: $e',
      );
      return false;
    }
  }
}
