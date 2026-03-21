import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
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
  /// **Performance Note**: This method returns the last user emitted by health
  /// checks (updated every 5 minutes) to reduce RPC load. This means the
  /// returned value could be up to 5 minutes stale if the active wallet is
  /// changed externally. For most use cases, this trade-off is acceptable and
  /// significantly reduces RPC spam.
  ///
  /// NOTE: this function does not start/stop KDF or modify the active user,
  /// so atomic read/write protection is not used within and not required when
  /// calling this function.
  Future<KdfUser?> getActiveUser();

  /// Returns the [Mnemonic] for the active wallet, throws an [AuthException]
  /// otherwise.
  ///
  /// If [encrypted] is true, the encrypted mnemonic is returned. Otherwise,
  /// the plaintext mnemonic is returned, which requires the [walletPassword]
  /// to be provided.
  ///
  /// NOTE: this function does not start/stop KDF or modify the active user,
  /// so atomic read/write protection is not used within and not required when
  /// calling this function.
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
  KdfAuthService(this._kdfFramework, this._hostConfig)
    : _sessionId = const Uuid().v4() {
    _logger.info('[$_sessionId] KdfAuthService initialized');
    _startHealthCheck();
    _subscribeToShutdownSignals();
  }

  final KomodoDefiFramework _kdfFramework;
  final IKdfHostConfig _hostConfig;
  final StreamController<KdfUser?> _authStateController =
      StreamController.broadcast();
  final SecureLocalStorage _secureStorage = SecureLocalStorage();
  final ReadWriteMutex _authMutex = ReadWriteMutex();
  final Mutex _metadataMutex = Mutex();
  final Logger _logger = Logger('KdfAuthService');
  final String _sessionId;

  KdfUser? _lastEmittedUser;
  Timer? _healthCheckTimer;

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

    // [getActiveUser] performs a read lock, which should happen outside of
    // the write lock to prevent deadlocks. If kdf is not running, null is
    // returned, so we can safely call it here without any checks.
    final activeUser = await getActiveUser();

    final user = await _lockWriteOperation<KdfUser>(() async {
      // Check if already signed in first
      if (await _kdfFramework.isRunning()) {
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

      final user = await _authenticateUser(config);
      _emitAuthStateChange(user);
      return user;
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
    await _ensureKdfRunning();

    await _runReadOperation(() async {
      final walletExists = await _walletExists(walletName);
      if (walletExists) {
        throw AuthException(
          'Wallet already exists',
          type: AuthExceptionType.generalAuthError,
        );
      }
    });

    // replaces the __assertWalletOrStop method - wait for read/write locks to
    // be released here.
    // can be used outside of a lock, since both functions are public-facing
    // and manage their own read/write locks
    if (await isSignedIn()) {
      await signOut();
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
      final isImported = mnemonic != null;
      final currentUser = await _registerNewUser(config, options, isImported);
      _emitAuthStateChange(currentUser);
      _invalidateUsersCache();
      return currentUser;
    });
  }

  @override
  Future<List<KdfUser>> getUsers() async {
    await _ensureKdfRunning();

    return _runReadOperation(() async {
      // Serve from cache if fresh
      if (_usersCache != null &&
          _usersCacheTimestamp != null &&
          DateTime.now().difference(_usersCacheTimestamp!) < _usersCacheTtl) {
        return _usersCache!;
      }

      final walletNames = await _client.rpc.wallet.getWalletNames();

      final users = await Future.wait(
        walletNames.walletNames.map((name) async {
          final user = await _secureStorage.getUser(name);
          if (user != null) return user;

          // Create new user record if none exists
          final newUser = KdfUser(
            walletId: WalletId.fromName(name, _fallbackAuthOptions),
            isBip39Seed: true, // Default to true until verified otherwise
          );
          await _secureStorage.saveUser(newUser);
          return newUser;
        }),
      );

      _usersCache = users;
      _usersCacheTimestamp = DateTime.now();
      return users;
    });
  }

  Future<void> updateUserBip39Status(String walletName, bool isBip39) async {
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
    return _runReadOperation(() async {
      // Prefer last known user emitted by health checks to avoid extra RPCs
      if (_lastEmittedUser != null) {
        return _lastEmittedUser;
      }
      return _getActiveUser();
    });
  }

  AuthOptions get _fallbackAuthOptions =>
      const AuthOptions(derivationMethod: DerivationMethod.hdWallet);

  @override
  Future<Mnemonic> getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  }) async {
    return _runReadOperation(() async {
      assert(
        encrypted || walletPassword != null,
        'walletPassword is required to retrieve plaintext mnemonic.',
      );

      if (await getActiveUser() == null) {
        throw AuthException(
          'No user signed in',
          type: AuthExceptionType.unauthorized,
        );
      }

      return _getMnemonic(encrypted: encrypted, walletPassword: walletPassword);
    });
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _runReadOperation(() async {
      if (await getActiveUser() == null) {
        throw AuthException(
          'No user signed in',
          type: AuthExceptionType.unauthorized,
        );
      }

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
    return _runReadOperation(() async {
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
      _authStateController.close();
      _lastEmittedUser = null;
    });
  }

  late final Future<KdfStartupConfig> _noAuthConfig =
      KdfStartupConfig.noAuthStartup(rpcPassword: _hostConfig.rpcPassword);

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

  /// Returns the [KdfUser] associated with the active wallet if authenticated,
  /// otherwise throws an [AuthException].
  Future<KdfUser> _activeUserOrThrow() async {
    final activeUser = await getActiveUser();
    if (activeUser == null) {
      throw AuthException.notSignedIn();
    }
    return activeUser;
  }

  @override
  Future<void> setActiveUserMetadata(Map<String, dynamic> metadata) async {
    await _metadataMutex.protect(() async {
      final activeUser = await _activeUserOrThrow();
      final user = await _secureStorage.getUser(activeUser.walletId.name);
      if (user == null) throw AuthException.notFound();

      final updatedUser = user.copyWith(metadata: metadata);
      await _secureStorage.saveUser(updatedUser);

      // Update cache silently without triggering auth state change. Updating
      // the storage and cache at the same time emulates the same behaviour as
      // before. Update user metadata for any subsequent access without emitting
      // auth state changes, as the metadata field is currently used for events
      // like coin activation, wallet type (derivation), and seed backup status
      _lastEmittedUser = updatedUser;
    });
  }

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) async {
    await _metadataMutex.protect(() async {
      final activeUser = await _activeUserOrThrow();
      final user = await _secureStorage.getUser(activeUser.walletId.name);
      if (user == null) throw AuthException.notFound();

      final metadata = JsonMap.from(user.metadata);
      final transformed = transform(metadata[key]);
      if (transformed == null) {
        metadata.remove(key);
      } else {
        metadata[key] = transformed;
      }

      final updatedUser = user.copyWith(metadata: metadata);
      await _secureStorage.saveUser(updatedUser);
      _lastEmittedUser = updatedUser;
    });
  }

  @override
  Future<void> restoreSession(KdfUser user) async {
    // Only attempt to restore the session if KDF is running
    return _runReadOperation(() async {
      try {
        // Check if KDF is running
        if (!await _kdfFramework.isRunning()) {
          throw AuthException(
            'KDF API is not running, cannot restore session',
            type: AuthExceptionType.apiConnectionError,
          );
        }

        // Verify the wallet exists in KDF
        final wallets = await getUsers();
        final walletExists = wallets.any(
          (w) => w.walletId.name == user.walletId.name,
        );

        if (!walletExists) {
          throw AuthException(
            'Wallet not found: ${user.walletId.name}',
            type: AuthExceptionType.walletNotFound,
          );
        }

        // Update internal state and emit auth state change
        _lastEmittedUser = user;
        _emitAuthStateChange(user);
      } catch (e) {
        throw AuthException(
          'Failed to restore session: $e',
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

  Future<bool> _performHealthCheck() async {
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
      await _forceStartKdf();
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
  Future<void> _forceStartKdf() async {
    _logger.info(
      '[$_sessionId] _forceStartKdf: Starting KDF (bypassing isRunning check)',
    );
    await _lockWriteOperation(() async {
      final startStopwatch = Stopwatch()..start();
      final result = await _kdfFramework.startKdf(await _noAuthConfig);
      startStopwatch.stop();
      _logger.info(
        '[$_sessionId] _forceStartKdf: startKdf() returned ${result.name} in ${startStopwatch.elapsedMilliseconds}ms',
      );

      if (!result.isStartingOrAlreadyRunning()) {
        _logger.severe(
          '[$_sessionId] _forceStartKdf: Failed to start KDF: ${result.name}',
        );
        throw KdfExtensions._mapStartupErrorToAuthException(result);
      }

      _logger.info('[$_sessionId] _forceStartKdf: Waiting for RPC to be up');
      final waitStopwatch = Stopwatch()..start();
      await _waitUntilKdfRpcIsUp();
      waitStopwatch.stop();
      _logger.info(
        '[$_sessionId] _forceStartKdf: RPC is up after ${waitStopwatch.elapsedMilliseconds}ms',
      );
    });
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
