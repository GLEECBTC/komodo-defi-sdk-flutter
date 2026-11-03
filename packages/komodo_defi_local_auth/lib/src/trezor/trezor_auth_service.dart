import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show KdfStartupResult;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_local_auth/src/trezor/trezor_wallet_password_store.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// High level helper that handles sign in/register and Trezor device
/// initialization for the built in "My Trezor" wallet.
///
/// This service implements [IAuthService] and provides Trezor-specific
/// authentication logic while using composition with [KdfAuthService] to
/// avoid duplicating existing auth service functionality. The [signIn] and
/// [register] methods are customized for Trezor devices, automatically
/// handling passphrase requirements and ignoring PIN prompts. All other
/// [IAuthService] methods are delegated to the composed auth service.
class TrezorAuthService implements IAuthService {
  TrezorAuthService(
    this._authService,
    this._trezor, {
    TrezorConnectionMonitor? connectionMonitor,
    FlutterSecureStorage? secureStorage,
    SecureLocalStorage? userStorage,
    String Function(int length)? passwordGenerator,
  }) : _connectionMonitor =
           connectionMonitor ?? TrezorConnectionMonitor(_trezor),
       _passwordStore = TrezorWalletPasswordStore(
         storage: secureStorage,
         passwordGenerator: passwordGenerator,
       ),
       _userStorage = userStorage ?? SecureLocalStorage();

  static const String trezorWalletName = 'My Trezor';
  static const _trezorPolicy = PrivateKeyPolicy.trezor();
  static final _log = Logger('TrezorAuthService');

  final IAuthService _authService;
  final TrezorRepository _trezor;
  final TrezorWalletPasswordStore _passwordStore;
  final SecureLocalStorage _userStorage;
  final TrezorConnectionMonitor _connectionMonitor;

  Future<void> provideTrezorPin(int taskId, String pin) =>
      _trezor.providePin(taskId, pin);

  Future<void> provideTrezorPassphrase(int taskId, String passphrase) =>
      _trezor.providePassphrase(taskId, passphrase);

  Future<void> cancelTrezorInitialization(int taskId) =>
      _trezor.cancelInitialization(taskId);

  /// Handles Trezor sign-in with stream-based progress updates
  Stream<AuthenticationState> signInStreamed({
    required AuthOptions options,
  }) async* {
    try {
      yield* _authenticateTrezorStream();
    } catch (e) {
      await _signOutCurrentTrezorUser();
      yield AuthenticationState.error('Trezor sign-in failed: $e');
    }
  }

  /// Handles Trezor registration with stream-based progress updates
  Stream<AuthenticationState> registerStream({
    required AuthOptions options,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
  }) async* {
    try {
      yield* _authenticateTrezorStream(initialMetadata: initialMetadata);
    } catch (e) {
      await _signOutCurrentTrezorUser();
      yield AuthenticationState.error('Trezor registration failed: $e');
    }
  }

  // IAuthService implementation - delegate to composed auth service
  @override
  Future<AuthSessionContext> captureSessionContext() =>
      _authService.captureSessionContext();

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      _authService.isSessionContextCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) =>
      _authService.ensureSessionContextCurrent(context);

  @override
  Future<T> runWithSession<T>(
    AuthSessionContext expected,
    Future<T> Function() dispatch,
  ) => _authService.runWithSession(expected, dispatch);

  @override
  Stream<AuthSessionContext?> watchSessionContext() =>
      _authService.watchSessionContext();

  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  ) => _authService.updateMetadataForSession(context, updates);

  @override
  int get authGeneration => _authService.authGeneration;

  @override
  Stream<int> get authGenerationChanges => _authService.authGenerationChanges;

  @override
  bool get isAuthTransitionInProgress =>
      _authService.isAuthTransitionInProgress;

  @override
  void invalidateAuthSession() => _authService.invalidateAuthSession();

  @override
  void beginAuthTransition() => _authService.beginAuthTransition();

  @override
  void endAuthTransition() => _authService.endAuthTransition();

  @override
  Future<List<KdfUser>> getUsers() => _authService.getUsers();

  @override
  Future<KdfUser?> getActiveUser() => _authService.getActiveUser();

  @override
  Future<bool> isSignedIn() => _authService.isSignedIn();

  @override
  Future<Mnemonic> getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  }) => _authService.getMnemonic(
    encrypted: encrypted,
    walletPassword: walletPassword,
  );

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) => _authService.updatePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  @override
  Future<void> setActiveUserMetadata(
    JsonMap metadata, {
    required WalletId expectedWalletId,
  }) => _authService.setActiveUserMetadata(
    metadata,
    expectedWalletId: expectedWalletId,
  );

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform, {
    required WalletId expectedWalletId,
  }) => _authService.updateActiveUserMetadataKey(
    key,
    transform,
    expectedWalletId: expectedWalletId,
  );

  @override
  Future<void> restoreSession(KdfUser user) =>
      _authService.restoreSession(user);

  @override
  Stream<KdfUser?> get authStateChanges => _authService.authStateChanges;

  @override
  Future<void> dispose() async {
    _connectionMonitor.dispose();
    await _authService.dispose();
  }

  @override
  Future<void> signOut() async {
    await _stopConnectionMonitoring();
    await _authService.signOut();
  }

  @override
  Future<void> deleteWallet({
    required String walletName,
    required String password,
    Future<void> Function(KdfUser target)? beforeDelete,
    Future<void> Function()? afterDelete,
  }) => _authService.deleteWallet(
    walletName: walletName,
    password: password,
    beforeDelete: beforeDelete,
    afterDelete: afterDelete,
  );

  @override
  Future<bool> ensureKdfHealthy() => _authService.ensureKdfHealthy();

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  }) async {
    // Throw exception if PrivateKeyPolicy is NOT trezor
    if (options.privKeyPolicy != const PrivateKeyPolicy.trezor()) {
      throw AuthException(
        'TrezorAuthService only supports Trezor private key policy',
        type: AuthExceptionType.generalAuthError,
      );
    }

    try {
      final user = await _initializeTrezorWithPassphrase(passphrase: password);

      _startConnectionMonitoring();

      return user;
    } catch (e) {
      await _signOutCurrentTrezorUser();

      if (e is AuthException) rethrow;
      throw AuthException(
        'Trezor sign-in failed: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    required AuthOptions options,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
  }) async {
    // Throw exception if PrivateKeyPolicy is NOT trezor
    if (options.privKeyPolicy != const PrivateKeyPolicy.trezor()) {
      throw AuthException(
        'TrezorAuthService only supports Trezor private key policy',
        type: AuthExceptionType.generalAuthError,
      );
    }

    try {
      final user = await _initializeTrezorWithPassphrase(
        passphrase: password,
        initialMetadata: initialMetadata,
      );

      _startConnectionMonitoring();

      return user;
    } catch (e) {
      await _signOutCurrentTrezorUser();

      if (e is AuthException) rethrow;
      throw AuthException(
        'Trezor registration failed: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  /// Clears the stored password for the Trezor wallet.
  Future<void> clearTrezorPassword() => _passwordStore.clear();

  /// Start monitoring Trezor connection status after successful authentication.
  /// This will automatically sign out if the device becomes disconnected.
  void _startConnectionMonitoring({String? devicePubkey}) {
    _connectionMonitor.startMonitoring(
      devicePubkey: devicePubkey,
      onConnectionLost: () async {
        _log.warning('Trezor connection lost, signing out user');
        await _signOutCurrentTrezorUser();
      },
      onStatusChanged: (status) {
        _log.fine('Trezor connection status: ${status.value}');
      },
    );
  }

  /// Stop monitoring Trezor connection status.
  Future<void> _stopConnectionMonitoring() async {
    if (_connectionMonitor.isMonitoring) {
      await _connectionMonitor.stopMonitoring();
    }
  }

  /// Signs out the current user if they are using the Trezor wallet
  Future<void> _signOutCurrentTrezorUser() async {
    final current = await _authService.getActiveUser();
    if (current?.walletId.authOptions.privKeyPolicy == _trezorPolicy) {
      _log.warning("Signing out current '${current?.walletId.name}' user");
      await _stopConnectionMonitoring();
      try {
        await _authService.signOut();
      } catch (_) {
        // ignore sign out errors
      }
    }
  }

  /// Signs in to the local wallet behind the Trezor session, or registers it.
  ///
  /// The device holds the keys, so the local wallet's seed is never used.
  /// KDF's wallet files can outlive this app's secure storage or belong to
  /// another app sharing the directory. A wallet the Trezor session cannot
  /// use keeps its record, and a new one is registered under the next free
  /// name.
  /// [derivationMethod] The derivation method to use for the wallet.
  /// Defaults to [DerivationMethod.hdWallet], since trezor requires HD wallet
  /// RPCs to function.
  Future<void> _authenticateWithTrezorWallet({
    Map<String, dynamic> initialMetadata = const {},
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  }) async {
    final authOptions = AuthOptions(
      derivationMethod: derivationMethod,
      privKeyPolicy: _trezorPolicy,
    );
    final walletName =
        await _passwordStore.readWalletName() ?? trezorWalletName;
    final users = await _authService.getUsers();
    final existing = _findWallet(users, walletName);

    if (existing == null) {
      await _authService.register(
        walletName: walletName,
        password: await _passwordStore.getOrCreatePassword(),
        options: authOptions,
        initialMetadata: initialMetadata,
      );
      return;
    }

    final password = await _passwordStore.readPassword();
    if (password != null && _isClaimable(existing.walletId)) {
      final name = existing.walletId.name;
      final replaced = await _claimTrezorRecord(name, authOptions);
      try {
        final user = await _signInToExisting(existing, password, authOptions);
        if (user.walletId.authOptions.privKeyPolicy == _trezorPolicy) return;
        // The record gained an identity after the users were listed.
        _log.warning('The existing wallet is not a Trezor wallet; signing out');
        await _authService.signOut();
      } catch (e) {
        if (replaced != null) await _releaseTrezorRecord(name, replaced);
        if (e is! AuthException || !_cannotOpenWallet(e)) rethrow;
      }
    }

    final freshName = _nextFreeWalletName(users);
    final freshPassword = _passwordStore.generatePassword();
    _log.warning(
      'The existing local wallet cannot be used with this Trezor; '
      'registering a new one',
    );
    await _authService.register(
      walletName: freshName,
      password: freshPassword,
      options: authOptions,
      initialMetadata: initialMetadata,
    );
    // Only now, so a failed registration keeps the previous credentials.
    await _passwordStore.saveWallet(freshName, freshPassword);
  }

  /// Whether a sign-in failure means the password cannot open the wallet.
  ///
  /// Web and mobile engines report it as an incorrect password. The desktop
  /// executable exits with status 1 for every startup error, which the
  /// framework reports as invalid parameters.
  static bool _cannotOpenWallet(AuthException e) =>
      e.type == AuthExceptionType.incorrectPassword ||
      (e.type == AuthExceptionType.walletStartFailed &&
          e.details?['kdf_error'] == KdfStartupResult.invalidParams.name);

  /// The wallet named [walletName], or a case variant of it: KDF stores one
  /// file per name, and macOS and Windows file systems ignore case.
  static KdfUser? _findWallet(List<KdfUser> users, String walletName) {
    final lower = walletName.toLowerCase();
    return users.firstWhereOrNull((u) => u.walletId.name == walletName) ??
        users.firstWhereOrNull((u) => u.walletId.name.toLowerCase() == lower);
  }

  /// Signs in to [existing], retrying once if a wallet opened here before
  /// fails to start. The desktop executable reports a transient startup
  /// failure the same way as a wrong password.
  Future<KdfUser> _signInToExisting(
    KdfUser existing,
    String password,
    AuthOptions authOptions,
  ) async {
    Future<KdfUser> signIn() => _authService.signIn(
      walletName: existing.walletId.name,
      password: password,
      options: authOptions,
    );
    try {
      return await signIn();
    } on AuthException catch (e) {
      if (!_cannotOpenWallet(e) || !_hasIdentity(existing.walletId)) rethrow;
      _log.warning('A wallet opened here before failed to start; retrying');
      return signIn();
    }
  }

  /// Whether a Trezor session may use the wallet with [walletId]: a Trezor
  /// record, or one without a verified identity.
  ///
  /// When KDF lists a wallet that has no record, the auth service saves one
  /// with the default policy and no identity. A record with an identity and
  /// another policy is a software wallet, such as one a user named
  /// "My Trezor".
  static bool _isClaimable(WalletId walletId) =>
      walletId.authOptions.privKeyPolicy == _trezorPolicy ||
      !_hasIdentity(walletId);

  static bool _hasIdentity(WalletId walletId) =>
      walletId.pubkeyHash?.trim().isNotEmpty ?? false;

  /// Gives a placeholder record the Trezor policy before signing in to it.
  /// Signing in with the default policy would use the local seed instead of
  /// the device. Returns the options it replaced, or null if it changed
  /// nothing.
  Future<AuthOptions?> _claimTrezorRecord(
    String walletName,
    AuthOptions authOptions,
  ) async {
    AuthOptions? replaced;
    await _userStorage.updateUser(walletName, (current) {
      if (current == null ||
          current.walletId.authOptions.privKeyPolicy == _trezorPolicy ||
          !_isClaimable(current.walletId)) {
        return current;
      }
      replaced = current.walletId.authOptions;
      return current.copyWith(
        walletId: current.walletId.copyWith(authOptions: authOptions),
      );
    });
    return replaced;
  }

  /// Undoes [_claimTrezorRecord] after a failed sign-in, so a wallet the
  /// device session could not open keeps its original policy. A record that
  /// gained an identity meanwhile belongs to a session that opened it, and is
  /// kept.
  Future<void> _releaseTrezorRecord(String walletName, AuthOptions original) =>
      _userStorage.updateUser(walletName, (current) {
        if (current == null ||
            current.walletId.authOptions.privKeyPolicy != _trezorPolicy ||
            _hasIdentity(current.walletId)) {
          return current;
        }
        return current.copyWith(
          walletId: current.walletId.copyWith(authOptions: original),
        );
      });

  /// "My Trezor 2", "My Trezor 3", ... compared case-insensitively, because
  /// wallet files can share a case-insensitive file system.
  static String _nextFreeWalletName(List<KdfUser> users) {
    final taken = {for (final u in users) u.walletId.name.toLowerCase()};
    var suffix = 2;
    while (taken.contains('$trezorWalletName $suffix'.toLowerCase())) {
      suffix++;
    }
    return '$trezorWalletName $suffix';
  }

  /// Initializes the Trezor device and yields state updates
  Stream<TrezorInitializationState> _initializeTrezorDevice() async* {
    await for (final state in _trezor.initializeDevice()) {
      yield state;
      if (state.status == AuthenticationStatus.completed ||
          state.status == AuthenticationStatus.error ||
          state.status == AuthenticationStatus.cancelled) {
        break;
      }
    }
  }

  /// Registers or signs in to the "My Trezor" wallet and initializes the device
  ///
  /// Emits [TrezorInitializationState] updates while the device is initializing
  Stream<TrezorInitializationState> _initializeTrezorAndAuthenticate(
    DerivationMethod derivationMethod, {
    Map<String, dynamic> initialMetadata = const {},
  }) async* {
    await _signOutCurrentTrezorUser();

    await _authenticateWithTrezorWallet(
      initialMetadata: initialMetadata,
      derivationMethod: derivationMethod,
    );

    yield* _initializeTrezorDevice();
  }

  Stream<AuthenticationState> _authenticateTrezorStream({
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
    Map<String, dynamic> initialMetadata = const {},
  }) async* {
    try {
      await for (final trezorState in _initializeTrezorAndAuthenticate(
        derivationMethod,
        initialMetadata: initialMetadata,
      )) {
        if (trezorState.status == AuthenticationStatus.completed) {
          final user = await _authService.getActiveUser();
          if (user != null) {
            _startConnectionMonitoring();
            yield AuthenticationState.completed(user);
          } else {
            yield AuthenticationState.error(
              'Failed to retrieve signed-in user',
            );
          }
          break;
        }

        yield trezorState.toAuthenticationState();

        if (trezorState.status == AuthenticationStatus.error ||
            trezorState.status == AuthenticationStatus.cancelled) {
          await _signOutCurrentTrezorUser();
          break;
        }
      }
    } catch (e) {
      await _signOutCurrentTrezorUser();
      yield AuthenticationState.error('Trezor stream error: $e');
    }
  }

  /// Initializes the Trezor device and handles passphrase input
  /// This method is used for both sign-in and registration
  /// It returns the authenticated [KdfUser] on success.
  /// If the Trezor device requires a passphrase, it will provide the passphrase
  /// and return the authenticated user.
  /// If the Trezor device requires a PIN, it will ignore the PIN prompt and
  /// wait for the user to enter the PIN on the device.
  /// This method will throw an [AuthException] if the Trezor device
  /// initialization fails or if the user is not authenticated successfully.
  Future<KdfUser> _initializeTrezorWithPassphrase({
    required String passphrase,
    Map<String, dynamic> initialMetadata = const {},
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  }) async {
    // Copy over contents from the streamed function
    await for (final trezorState in _initializeTrezorAndAuthenticate(
      derivationMethod,
      initialMetadata: initialMetadata,
    )) {
      // If status is passphrase required, use the provided password
      if (trezorState.status == AuthenticationStatus.passphraseRequired) {
        await _trezor.providePassphrase(trezorState.taskId!, passphrase);
      }
      // Ignore pin required user action - user has to enter PIN on the device

      // Wait for task to finish and return result
      if (trezorState.status == AuthenticationStatus.completed) {
        final user = await _authService.getActiveUser();
        if (user != null) {
          return user;
        } else {
          throw AuthException(
            'Failed to retrieve registered user',
            type: AuthExceptionType.generalAuthError,
          );
        }
      }

      if (trezorState.status == AuthenticationStatus.error) {
        await _signOutCurrentTrezorUser();
        throw AuthException(
          trezorState.message ?? 'Trezor registration failed',
          type: AuthExceptionType.generalAuthError,
        );
      }

      if (trezorState.status == AuthenticationStatus.cancelled) {
        await _signOutCurrentTrezorUser();
        throw AuthException(
          'Trezor registration was cancelled',
          type: AuthExceptionType.generalAuthError,
        );
      }
    }

    await _signOutCurrentTrezorUser();
    throw AuthException(
      'Trezor registration did not complete',
      type: AuthExceptionType.generalAuthError,
    );
  }
}
