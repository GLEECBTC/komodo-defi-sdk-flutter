import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' show ClientException;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_local_auth/src/auth/wallet_catalog_lock.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart' show ReadWriteMutex;
import 'package:uuid/uuid.dart';

part 'auth_service_auth_extension.dart';
part 'auth_service_kdf_extension.dart';
part 'auth_service_operations_extension.dart';

abstract interface class IAuthService {
  Future<AuthSessionContext> captureSessionContext();
  bool isSessionContextCurrent(AuthSessionContext context);
  void ensureSessionContextCurrent(AuthSessionContext context);
  Stream<AuthSessionContext?> watchSessionContext();
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  );

  /// Synchronous revision of the authentication session.
  ///
  /// Capture before asynchronous sensitive work and compare before using its
  /// result. A changed revision invalidates that work, even for the same
  /// wallet.
  int get authGeneration;

  /// Synchronously reports revisions before asynchronous transitions continue.
  Stream<int> get authGenerationChanges;

  /// Whether an authentication transition is pending or this service is
  /// disposed. Either condition prevents starting sensitive operations.
  bool get isAuthTransitionInProgress;

  /// Revokes work tied to the previous authentication revision.
  void invalidateAuthSession();

  /// Starts a nested transition and synchronously revokes the previous
  /// revision.
  void beginAuthTransition();

  /// Completes one transition started by [beginAuthTransition].
  void endAuthTransition();

  Future<List<KdfUser>> getUsers();

  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  });

  /// Throws [AuthException] if user creation fails, the wallet already exists,
  /// or the seed phrase is not a valid BIP39 seed phrase. [initialMetadata]
  /// is saved with the first user record before the authenticated user is
  /// published. A collision never signs into the existing wallet.
  Future<KdfUser> register({
    required String walletName,
    required String password,
    required AuthOptions options,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
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

  /// Deletes the wallet while holding the shared catalog lock.
  /// [beforeDelete] checks the fresh record inside the auth write lock.
  /// [afterDelete] runs after that lock is released, but before catalog
  /// ownership is released. Neither callback may enter catalog operations.
  Future<void> deleteWallet({
    required String walletName,
    required String password,
    Future<void> Function(KdfUser target)? beforeDelete,
    Future<void> Function()? afterDelete,
  });

  /// Method to store custom metadata for the user.
  ///
  /// Overwrites any existing metadata. Prefer [updateActiveUserMetadataKey]
  /// when changing individual keys to avoid overwriting concurrent updates.
  ///
  /// [expectedWalletId] must be the verified identity captured when the
  /// operation began. An unavailable or different active identity throws
  /// [WalletChangedDisconnectException] under the authentication write lock.
  ///
  /// This does not emit an auth state change event.
  ///
  /// NB: This is intended to only be a short-term solution until the SDK
  /// is fully integrated with KW. This may be deprecated in the future.
  Future<void> setActiveUserMetadata(
    JsonMap metadata, {
    required WalletId expectedWalletId,
  });

  /// Atomically reads the current value of [key] from the active user's
  /// metadata, applies [transform] to it, and writes the result back.
  ///
  /// This is safe to call concurrently — a dedicated metadata mutex
  /// serialises all read-modify-write cycles.
  /// [expectedWalletId] must be the verified identity captured when the
  /// operation began. An unavailable or different active identity throws
  /// [WalletChangedDisconnectException] under the authentication write lock
  /// before [transform] runs or metadata can be changed.
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform, {
    required WalletId expectedWalletId,
  });

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
  }) : _secureStorage = secureStorage ?? SecureLocalStorage() {
    _logger.info('KdfAuthService initialized');
    _startHealthCheck();
    unawaited(_lockWriteOperation(_subscribeToShutdownSignals));
  }

  final KomodoDefiFramework _kdfFramework;
  final IKdfHostConfig _hostConfig;
  final StreamController<KdfUser?> _authStateController =
      StreamController.broadcast();
  final SecureLocalStorage _secureStorage;
  final ReadWriteMutex _authMutex = ReadWriteMutex();
  final Logger _logger = Logger('KdfAuthService');

  final _sessions = AuthSessionTracker();

  KdfUser? _lastEmittedUser;
  int _authStateGeneration = 0;
  int _authTransitionDepth = 0;
  bool _isDisposed = false;
  final _authGenerationController = StreamController<int>.broadcast(sync: true);

  @override
  int get authGeneration => _authStateGeneration;

  @override
  Stream<int> get authGenerationChanges => _authGenerationController.stream;

  @override
  bool get isAuthTransitionInProgress =>
      _isDisposed || _authTransitionDepth > 0;

  @override
  void invalidateAuthSession() {
    _authStateGeneration++;
    if (!_authGenerationController.isClosed) {
      _authGenerationController.add(_authStateGeneration);
    }
  }

  @override
  void beginAuthTransition() {
    // Subscribers must see the busy state when the synchronous epoch arrives.
    if (_authTransitionDepth == 0) _sessions.invalidate();
    _authTransitionDepth++;
    invalidateAuthSession();
  }

  @override
  void endAuthTransition() {
    if (_authTransitionDepth <= 0) {
      throw StateError('No authentication transition is in progress');
    }
    _authTransitionDepth--;
    if (_authTransitionDepth == 0 && !_isDisposed) {
      _sessions.observe(_lastEmittedUser);
    }
  }

  Future<T> _runAuthTransition<T>(Future<T> Function() operation) async {
    beginAuthTransition();
    try {
      return await operation();
    } finally {
      endAuthTransition();
    }
  }

  @override
  Future<AuthSessionContext> captureSessionContext() async {
    if (isAuthTransitionInProgress) throw const AuthSessionChangedException();
    final existing = _sessions.current;
    if (existing != null) return existing;
    final epoch = _sessions.epoch;
    await getActiveUser();
    final context = _sessions.current;
    if (context == null || epoch != _sessions.epoch) {
      throw const AuthSessionChangedException();
    }
    ensureSessionContextCurrent(context);
    return context;
  }

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      !isAuthTransitionInProgress && _sessions.isCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!isSessionContextCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() => Stream.multi((sink) {
    final subscription = _sessions.changes.listen(
      sink.addSync,
      onError: sink.addErrorSync,
      onDone: sink.closeSync,
    );
    sink
      ..addSync(_sessions.current)
      ..onCancel = subscription.cancel;
  });

  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey(walletEntryIdMetadataKey)) {
      throw ArgumentError('Wallet entry identity is SDK-owned');
    }
    ensureSessionContextCurrent(context);
    try {
      return await _runAuthenticatedWriteOperation((activeUser) async {
        ensureSessionContextCurrent(context);
        if (!(activeUser.walletId.pubkeyHash?.trim().isNotEmpty ?? false)) {
          throw const AuthIdentityUnavailableException();
        }
        final persisted = await _secureStorage.updateUser(
          activeUser.walletId.name,
          (stored) {
            if (stored == null) throw AuthException.notFound();
            _ensureMetadataWalletIdentity(activeUser.walletId, stored.walletId);
            _sessions.observe(stored);
            ensureSessionContextCurrent(context);
            final metadata = JsonMap.from(stored.metadata);
            for (final entry in updates.entries) {
              if (entry.value == null) {
                metadata.remove(entry.key);
              } else {
                metadata[entry.key] = entry.value;
              }
            }
            return stored.copyWith(metadata: metadata);
          },
        );
        final updated = activeUser.copyWith(metadata: persisted!.metadata);
        ensureSessionContextCurrent(context);
        _emitAuthStateChange(updated);
        return updated;
      });
    } catch (_) {
      // Fresh resolution may discover logout/replacement before entering the
      // metadata callback. Preserve a typed session change in that case.
      ensureSessionContextCurrent(context);
      rethrow;
    }
  }

  Timer? _healthCheckTimer;

  /// Compound ids of wallets this session created without an imported mnemonic.
  ///
  /// Never persisted, and consumed when the wallet's first authenticated
  /// session ends ([_stopKdf]) or the wallet is deleted ([deleteWallet]): the
  /// whole meaning is "first sign-in", and a value that outlived it would keep
  /// telling the address scan there is nothing to find long after the wallet
  /// could have received funds - including on a re-import under the same name.
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
  }) => _runAuthTransition(
    () => _signIn(walletName: walletName, password: password, options: options),
  );

  Future<KdfUser> _signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  }) async {
    invalidateAuthSession();
    _logger.info('signIn: Starting login for wallet: omitted');

    // Proactively ensure KDF is healthy before attempting login
    // This prevents login attempts while KDF is down or restarting
    final isHealthy = await ensureKdfHealthy().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _logger.warning('signIn: Health check timed out after 3s');
        return false;
      },
    );

    if (!isHealthy) {
      _logger.warning('signIn: KDF not healthy, retrying after 1s');
      // Wait and retry once
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final retryHealthy = await ensureKdfHealthy().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (!retryHealthy) {
        _logger.severe('signIn: KDF still not healthy after retry');
        throw AuthException(
          'KDF is not available. Please try again.',
          type: AuthExceptionType.apiConnectionError,
        );
      }
    }

    _logger.info('signIn: KDF healthy, proceeding with login');

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
    Map<String, dynamic> initialMetadata = const {},
  }) => _runAuthTransition(
    () => withWalletCatalogLock(
      () => _register(
        walletName: walletName,
        password: password,
        options: options,
        mnemonic: mnemonic,
        initialMetadata: initialMetadata,
      ),
    ),
  );

  Future<KdfUser> _register({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
  }) async {
    invalidateAuthSession();
    _logger.info('register: Starting registration for wallet: omitted');
    final registerStopwatch = Stopwatch()..start();

    try {
      final ensureStartStopwatch = Stopwatch()..start();
      await _ensureKdfRunning();
      ensureStartStopwatch.stop();
      _logger.info(
        'register: ensure no-auth start completed in '
        '${ensureStartStopwatch.elapsedMilliseconds}ms',
      );

      return _lockWriteOperation(() async {
        // A fresh existence check and creation share the auth write lock.
        // UI validation and cached wallet lists cannot enforce uniqueness.
        _invalidateUsersCache();
        if (await _walletExists(walletName)) {
          throw AuthException(
            'Wallet already exists',
            type: AuthExceptionType.walletAlreadyExists,
            details: {'walletName': walletName},
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

        final writePathStopwatch = Stopwatch()..start();
        final isImported = mnemonic != null;
        late final KdfUser currentUser;
        try {
          currentUser = await _registerNewUser(
            config,
            options,
            isImported,
            initialMetadata,
          );
          if (!isImported) {
            // A wallet created here has no on-chain history by construction:
            // the seed did not exist a moment ago. Recorded per session so the
            // HD gap scan can be told so on this sign-in only.
            _walletsGeneratedThisSession.add(currentUser.walletId.compoundId);
          }
        } catch (_) {
          await _clearFailedAuthenticatedKdfWithinWriteLock();
          rethrow;
        }
        writePathStopwatch.stop();
        _logger.info(
          'register: registration write path completed in '
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
        'register: Finished in '
        '${registerStopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  @override
  Future<List<KdfUser>> getUsers() => withWalletCatalogLock(() async {
    await _ensureKdfRunning();
    return _lockWriteOperation(() async {
      _invalidateUsersCache();
      return _getUsersWithinAuthLock();
    });
  });

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
        final updated = await _secureStorage.updateUser(name, (current) {
          final user =
              current ??
              KdfUser(
                walletId: WalletId.fromName(name, _fallbackAuthOptions),
                isBip39Seed: true,
              );
          final entryId = user.metadata[walletEntryIdMetadataKey];
          if (entryId is String && entryId.isNotEmpty) return user;
          return user.copyWith(
            metadata: {
              ...user.metadata,
              walletEntryIdMetadataKey: const Uuid().v4(),
            },
          );
        });
        return updated!;
      }),
    );

    _usersCache = users;
    _usersCacheTimestamp = DateTime.now();
    return users;
  }

  Future<void> updateUserBip39Status(String walletName, bool isBip39) async {
    await _lockWriteOperation(() async {
      await _secureStorage.updateUser(walletName, (existingUser) {
        if (existingUser == null) return null;
        if (!isBip39 && existingUser.isHd) {
          throw AuthException(
            'Cannot use non-BIP39 seed with HD wallet',
            type: AuthExceptionType.generalAuthError,
          );
        }
        return existingUser.copyWith(isBip39Seed: isBip39);
      });
      _invalidateUsersCache();
    });
  }

  @override
  Future<void> signOut() => _runAuthTransition(_signOut);

  Future<void> _signOut() async {
    // Revoke pending results before waiting for authentication operations or
    // the runtime to stop. Stream delivery alone is asynchronous and too late.
    invalidateAuthSession();
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
      'getActiveUser: ${_activeUserCalls} calls in omittedms '
      '(omitted identity RPCs), lock queue ${_activeUserQueuedMs}ms, '
      'lock held ${_activeUserHeldMs}ms',
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
    Future<void> Function(KdfUser target)? beforeDelete,
    Future<void> Function()? afterDelete,
  }) => withWalletCatalogLock(() async {
    await _ensureKdfRunning();
    await _lockWriteOperation(() async {
      if (beforeDelete != null) {
        _invalidateUsersCache();
        final users = await _getUsersWithinAuthLock();
        final target = users
            .where((user) => user.walletId.name == walletName)
            .firstOrNull;
        if (target == null) throw AuthException.notFound();
        await beforeDelete(target);
      }
      try {
        await _client.rpc.wallet.deleteWallet(
          walletName: walletName,
          password: password,
        );
        await _secureStorage.deleteUser(walletName);
        // A wallet re-imported under this name is not the wallet this session
        // generated - it may have any amount of history - so the marker must
        // not outlive the deletion. Compound ids are `name` or `name:<hash>`.
        _walletsGeneratedThisSession.removeWhere(
          (id) => id == walletName || id.startsWith('$walletName:'),
        );
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
    // Keep catalog ownership through cache cleanup, while releasing the auth
    // lock so hooks may perform ordinary identity reads without deadlocking.
    await afterDelete?.call();
  });

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
    if (error is JsonRpcErrorResponse) {
      return error.error;
    }
    if (error is MmRpcException) {
      return error.errorType;
    }
    if (error is GeneralErrorResponse) {
      return error.errorType;
    }
    return null;
  }

  String? _extractRpcErrorMessage(Object error) {
    if (error is JsonRpcErrorResponse) {
      return error.message;
    }
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
  Future<void> dispose() => _runAuthTransition(() async {
    try {
      await _dispose();
    } finally {
      await _authGenerationController.close();
      await _sessions.dispose();
    }
  });

  Future<void> _dispose() async {
    _isDisposed = true;
    invalidateAuthSession();
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
  Future<void> setActiveUserMetadata(
    Map<String, dynamic> metadata, {
    required WalletId expectedWalletId,
  }) async {
    await _runAuthenticatedWriteOperation((activeUser) async {
      _ensureMetadataWalletIdentity(expectedWalletId, activeUser.walletId);
      final persistedUser = await _secureStorage.updateUser(
        activeUser.walletId.name,
        (user) {
          if (user == null) throw AuthException.notFound();
          _ensureMetadataWalletIdentity(activeUser.walletId, user.walletId);
          return user.copyWith(
            metadata: {
              ...metadata,
              if (user.metadata[walletEntryIdMetadataKey] != null)
                walletEntryIdMetadataKey:
                    user.metadata[walletEntryIdMetadataKey],
            },
          );
        },
      );
      final persistedMetadata = persistedUser!.metadata;

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
      _lastEmittedUser = activeUser.copyWith(metadata: persistedMetadata);
    });
  }

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform, {
    required WalletId expectedWalletId,
  }) async {
    if (key == walletEntryIdMetadataKey) {
      throw ArgumentError('Wallet entry identity is SDK-owned');
    }
    await _runAuthenticatedWriteOperation((activeUser) async {
      _ensureMetadataWalletIdentity(expectedWalletId, activeUser.walletId);
      final persisted = await _secureStorage.updateUser(
        activeUser.walletId.name,
        (user) {
          if (user == null) throw AuthException.notFound();
          _ensureMetadataWalletIdentity(activeUser.walletId, user.walletId);
          final metadata = JsonMap.from(user.metadata);
          final transformed = transform(metadata[key]);
          if (transformed == null) {
            metadata.remove(key);
          } else {
            metadata[key] = transformed;
          }
          return user.copyWith(metadata: metadata);
        },
      );
      _lastEmittedUser = activeUser.copyWith(metadata: persisted!.metadata);
    });
  }

  void _ensureMetadataWalletIdentity(
    WalletId expectedWalletId,
    WalletId activeWalletId,
  ) {
    // Name-only identities can compare equal after a wallet is recreated with
    // a different seed. Both identities must include a verified public-key
    // hash; the caller's expected identity cannot be recovered from storage.
    if (!(expectedWalletId.pubkeyHash?.trim().isNotEmpty ?? false) ||
        !(activeWalletId.pubkeyHash?.trim().isNotEmpty ?? false) ||
        activeWalletId != expectedWalletId) {
      throw const WalletChangedDisconnectException(
        'Wallet identity is unavailable or changed '
        'before updating wallet metadata',
      );
    }
  }

  @override
  Future<void> restoreSession(KdfUser user) =>
      _runAuthTransition(() => _restoreSession(user));

  Future<void> _restoreSession(KdfUser user) async {
    // Restoring the same wallet still establishes a new session boundary.
    invalidateAuthSession();
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
        'ensureKdfHealthy: Health check already in progress, awaiting '
        'result',
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
          'ensureKdfHealthy: In cooldown period '
          '(${timeSinceLastCheck.inSeconds}s since last check)',
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
        'ensureKdfHealthy: Completed in ${elapsed.inMilliseconds}ms, '
        'result=omitted',
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
    _logger.info('_performHealthCheck: Starting health check');
    final stopwatch = Stopwatch()..start();
    var restartTransitionStarted = false;

    try {
      // First check if KDF is healthy with a short timeout
      final isHealthy = await _kdfFramework.isHealthy().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.warning(
            '_performHealthCheck: isHealthy() timed out after 2s',
          );
          return false;
        },
      );

      if (isHealthy) {
        // Double verification: even if isHealthy() returns true, verify with version() RPC
        // This prevents false positives where native status reports "running" but HTTP is down
        _logger.info(
          '_performHealthCheck: Initial check passed, performing double '
          'verification',
        );
        final doubleCheck = await _verifyKdfHealthy().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _logger.warning(
              '_performHealthCheck: Double verification timed out',
            );
            return false;
          },
        );

        if (doubleCheck) {
          stopwatch.stop();
          _logger.info(
            '_performHealthCheck: KDF is healthy (double verified) in '
            '${stopwatch.elapsedMilliseconds}ms',
          );
          return true;
        }

        _logger.warning(
          '_performHealthCheck: Double verification failed, KDF not '
          'actually healthy',
        );
      }

      beginAuthTransition();
      restartTransitionStarted = true;
      _logger.warning(
        '_performHealthCheck: KDF is not healthy, forcing full restart',
      );

      // Use _lastEmittedUser instead of calling _getActiveUser() RPC when KDF is down
      // This avoids blocking on a dead KDF
      final hadAuthenticatedUser = _lastEmittedUser != null;
      _logger.info('_performHealthCheck: hadAuthenticatedUser=omitted');

      // FORCE a full stop->start cycle when we've determined KDF is unhealthy
      // Don't trust isRunning() as it can be stale after iOS backgrounding
      _logger.info(
        '_performHealthCheck: Forcing clean shutdown (ignoring '
        'isRunning status)',
      );
      try {
        await _stopKdf().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _logger.warning('_performHealthCheck: kdfStop() timed out');
          },
        );
      } catch (e) {
        _logger.warning(
          '_performHealthCheck: Error during shutdown: '
          '${DiagnosticSanitizer.safeError(e)} (continuing with restart)',
        );
        // KDF might already be dead, continue with restart
      }

      // Reset HTTP client unconditionally to drop stale keep-alive connections
      _logger.info('_performHealthCheck: Resetting HTTP client');
      _kdfFramework.resetHttpClient();

      // Force restart KDF in no-auth mode (we don't have the password)
      // Use _forceStartKdf instead of _ensureKdfRunning to bypass isRunning check
      _logger.info('_performHealthCheck: Force starting KDF');
      final restartStopwatch = Stopwatch()..start();
      await _forceStartKdfWithinWriteLock();
      restartStopwatch.stop();
      _logger.info(
        '_performHealthCheck: KDF force start completed in '
        '${restartStopwatch.elapsedMilliseconds}ms',
      );

      // Reset HTTP client again after restart to ensure no stale sockets
      _logger.info(
        '_performHealthCheck: Resetting HTTP client again after restart',
      );
      _kdfFramework.resetHttpClient();

      // Add 200ms delay after restart before verification to avoid race where
      // native status reports "up" but HTTP listener hasn't bound yet
      _logger.info(
        '_performHealthCheck: Waiting 200ms for HTTP listener to bind',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Check if restart was successful with a strong health check (version RPC)
      _logger.info(
        '_performHealthCheck: Verifying KDF health with version check',
      );
      final verifyStopwatch = Stopwatch()..start();
      final isHealthyAfterRestart = await _verifyKdfHealthy().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.warning('_performHealthCheck: Health verification timed out');
          return false;
        },
      );
      verifyStopwatch.stop();
      _logger.info(
        '_performHealthCheck: Health verification took '
        '${verifyStopwatch.elapsedMilliseconds}ms, '
        'result=${isHealthyAfterRestart}',
      );

      // If we had an authenticated user, emit logged-out state
      // This will trigger the UI to show re-authentication prompt
      if (hadAuthenticatedUser && _lastEmittedUser != null) {
        _logger.info('_performHealthCheck: Emitting logged-out state');
        _emitAuthStateChange(null);
      }

      stopwatch.stop();
      _logger.info(
        '_performHealthCheck: Health check completed in '
        '${stopwatch.elapsedMilliseconds}ms, '
        'result=${isHealthyAfterRestart}',
      );
      return isHealthyAfterRestart;
    } catch (e) {
      stopwatch.stop();
      _logger.severe(
        '_performHealthCheck: Error during health check after '
        '${stopwatch.elapsedMilliseconds}ms: '
        '${DiagnosticSanitizer.safeError(e)}',
      );
      // If we can't restart KDF and had an authenticated user, emit logged-out state
      if (_lastEmittedUser != null) {
        _logger.info(
          '_performHealthCheck: Emitting logged-out state due to error',
        );
        _emitAuthStateChange(null);
      }
      // Log the error but don't throw - return false to indicate failure
      return false;
    } finally {
      if (restartTransitionStarted) endAuthTransition();
    }
  }

  /// Force starts KDF without checking isRunning() status
  /// This is needed when we've determined KDF is unhealthy but isRunning() returns stale true
  Future<void> _forceStartKdfWithinWriteLock() async {
    _logger.info('_forceStartKdf: Starting KDF (bypassing isRunning check)');
    final startStopwatch = Stopwatch()..start();
    final result = await _kdfFramework.startKdf(await _noAuthConfig);
    startStopwatch.stop();
    _logger.info(
      '_forceStartKdf: startKdf() returned omitted in '
      '${startStopwatch.elapsedMilliseconds}ms',
    );

    if (!result.isStartingOrAlreadyRunning()) {
      _logger.severe('_forceStartKdf: Failed to start KDF: omitted');
      throw KdfExtensions._mapStartupErrorToAuthException(result);
    }

    _kdfFramework.resetHttpClient();
    _logger.info('_forceStartKdf: Waiting for RPC to be ready');
    final waitStopwatch = Stopwatch()..start();
    await _waitUntilKdfRpcReady();
    await _subscribeToShutdownSignals();
    waitStopwatch.stop();
    _logger.info(
      '_forceStartKdf: RPC ready after '
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
        '_verifyKdfHealthy: Version check failed: '
        '${DiagnosticSanitizer.safeError(e)}',
      );
      return false;
    }
  }
}
