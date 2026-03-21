import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_state.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_local_auth/src/trezor/_trezor_index.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The [KomodoDefiAuth] class provides a simplified local authentication
/// service for managing user sign-in, registration, and mnemonic handling
/// within the Komodo DeFi Framework.
///
/// By default, the class operates in HD mode, which may be unexpected for
/// developers familiar with the KDF API's default behavior. The default
/// [AuthOptions] enables HD wallet mode, but this can be changed using
/// the [AuthOptions] parameter in the sign-in and registration methods.
///
/// NB: Pubkey address
abstract interface class KomodoDefiAuth {
  /// Ensures that the local authentication system has been initialized.
  ///
  /// This method must be called before interacting with authentication features.
  /// If the system is already initialized, this method does nothing.
  Future<void> ensureInitialized();

  /// Signs in a user with the specified [walletName] and [password].
  ///
  /// By default, the system will launch in HD mode (enabled in the [AuthOptions]),
  /// which may differ from the non-HD mode used in other areas of the KDF API.
  /// Developers can override the [derivationMethod] in [AuthOptions] to change
  /// this behavior.
  ///
  /// Throws [AuthException] if an error occurs during sign-in.
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  });

  /// Signs in a user with the specified [walletName] and [password].
  ///
  /// Returns a stream of [AuthenticationState] that provides real-time updates
  /// of the authentication process. For Trezor wallets, this includes device
  /// initialization states. For regular wallets, it will emit completion or error states.
  Stream<AuthenticationState> signInStream({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  });

  /// Registers a new user with the specified [walletName] and [password].
  ///
  /// By default, the system will launch in HD mode (enabled in the [AuthOptions]),
  /// which may differ from the non-HD mode used in other areas of the KDF API.
  /// Developers can override the [DerivationMethod] in [AuthOptions] to change
  /// this behavior. An optional [mnemonic] can be provided during registration.
  ///
  /// Throws [AuthException] if registration is disabled or if an error occurs
  /// during registration.
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
  });

  /// Registers a new user with the specified [walletName] and [password].
  ///
  /// Returns a stream of [AuthenticationState] that provides real-time updates
  /// of the registration process. For Trezor wallets, this includes device
  /// initialization states. For regular wallets, it will emit completion or error states.
  Stream<AuthenticationState> registerStream({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
  });

  /// A stream that emits authentication state changes for the current user.
  ///
  /// Returns a [Stream] of [KdfUser?] representing the currently signed-in
  /// user. The stream will emit `null` if the user is signed out.
  Stream<KdfUser?> get authStateChanges;

  /// Watches the current user state and emits updates when it changes.
  ///
  /// Returns a [Stream] of [KdfUser?] that continuously monitors the current
  /// user state. This is useful for reactive UI updates when the user signs
  /// in, signs out, or when user data is updated.
  ///
  /// The stream will emit `null` if no user is signed in, and a [KdfUser]
  /// object when a user is authenticated.
  Stream<KdfUser?> watchCurrentUser();

  /// Retrieves the current signed-in user, if available.
  ///
  /// Returns a [KdfUser] if a user is signed in, otherwise returns `null`.
  Future<KdfUser?> get currentUser;

  /// Retrieves a list of all users registered on the device.
  ///
  /// Returns a [List] of [KdfUser] objects representing all registered users.
  Future<List<KdfUser>> getUsers();

  /// Signs out the current user.
  ///
  /// Throws [AuthException] if an error occurs during the sign-out process.
  Future<void> signOut();

  /// Checks whether a user is currently signed in.
  ///
  /// Returns `true` if a user is signed in, otherwise `false`.
  Future<bool> isSignedIn();

  /// Retrieves the encrypted mnemonic of the currently signed-in user.
  ///
  /// Throws [AuthException] if an error occurs during retrieval or if no user
  /// is signed in.
  Future<Mnemonic> getMnemonicEncrypted();

  /// Retrieves the plain text mnemonic of the currently signed-in user.
  ///
  /// A [walletPassword] must be provided to decrypt the mnemonic.
  /// Throws [AuthException] if an error occurs during retrieval or if no user
  /// is signed in.
  Future<Mnemonic> getMnemonicPlainText(String walletPassword);

  /// Changes the password used to encrypt/decrypt the mnemonic.
  ///
  /// This is used to change the password that protects the wallet's seed phrase.
  /// Both the current and new passwords must be provided.
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

  /// Sets the value of a single key in the active user's metadata.
  ///
  /// This preserves any existing metadata, and overwrites the value only for
  /// the specified key.
  ///
  /// Throws an exception if there is no active user.
  ///
  /// Setting a value to `null` will remove the key from the metadata.
  ///
  /// This does not emit an auth state change event.
  ///
  ///
  /// NB: This is intended to only be a short-term solution until the SDK
  /// is fully integrated with KW. This may be deprecated in the future.
  ///
  /// Example:
  /// final _komodoDefiSdk = KomodoDefiSdk.global;
  ///
  ///   await _komodoDefiSdk.auth.setOrRemoveActiveUserKeyValue(
  ///   'custom_tokens',
  ///   {
  ///     'tokens': [
  ///       {
  ///         'foo': 'bar',
  ///         'name': 'Foo Token',
  ///         'symbol': 'FOO',
  ///         // ...
  ///       }
  ///     ],
  ///   }.toJsonString(),
  /// );
  /// final tokenJson = (await _komodoDefiSdk.auth.currentUser)
  ///     ?.metadata
  ///     .valueOrNull<JsonList>('custom_tokens', 'tokens');
  ///
  /// print('Custom tokens: $tokenJson');

  Future<void> setOrRemoveActiveUserKeyValue(String key, dynamic value);

  /// Atomically reads the current value of [key] from the active user's
  /// metadata, applies [transform], and writes the result back.
  ///
  /// Safe to call concurrently — uses a dedicated metadata mutex internally.
  Future<void> updateActiveUserKeyValue(
    String key,
    dynamic Function(dynamic currentValue) transform,
  );

  /// Provides PIN to a Trezor hardware device during authentication.
  ///
  /// The [taskId] should be obtained from the authentication state when the
  /// device requests PIN input. The [pin] should be entered as it appears on
  /// your keyboard numpad, mapped according to the grid shown on the Trezor device.
  ///
  /// This method should only be called when using Trezor authentication and
  /// the device is requesting PIN input.
  ///
  /// Throws [AuthException] if the device is not connected, the task ID is
  /// invalid, or if an error occurs during PIN provision.
  Future<void> setHardwareDevicePin(int taskId, String pin);

  /// Provides passphrase to a Trezor hardware device during authentication.
  ///
  /// The [taskId] should be obtained from the authentication state when the
  /// device requests passphrase input. The [passphrase] acts like an additional
  /// word in your recovery seed. Use an empty string to access the default
  /// wallet without passphrase.
  ///
  /// This method should only be called when using Trezor authentication and
  /// the device is requesting passphrase input.
  ///
  /// Throws [AuthException] if the device is not connected, the task ID is
  /// invalid, or if an error occurs during passphrase provision.
  Future<void> setHardwareDevicePassphrase(int taskId, String passphrase);

  /// Cancels an ongoing Trezor hardware device initialization.
  ///
  /// The [taskId] should be obtained from the authentication state when the
  /// device is being initialized. This method allows cancelling the initialization
  /// process if needed.
  ///
  /// This method should only be called when using Trezor authentication and
  /// there is an active initialization process.
  ///
  /// Throws [AuthException] if the task ID is invalid or if an error occurs
  /// during cancellation.
  Future<void> cancelHardwareDeviceInitialization(int taskId);

  /// Ensures that KDF is healthy and responsive. If KDF is not healthy,
  /// attempts to restart it with the current user's configuration.
  /// This is useful for recovering from situations where KDF has become
  /// unavailable, especially on mobile platforms after app backgrounding.
  /// Returns true if KDF is healthy or was successfully restarted, false otherwise.
  Future<bool> ensureKdfHealthy();

  /// Disposes of any resources held by the authentication service.
  ///
  /// This method should be called when the authentication service is no longer
  /// needed to clean up resources.
  Future<void> dispose();
}

class KomodoDefiLocalAuth implements KomodoDefiAuth {
  KomodoDefiLocalAuth({
    required KomodoDefiFramework kdf,
    required IKdfHostConfig hostConfig,
    bool allowRegistrations = true,
  }) : _allowRegistrations = allowRegistrations,
       _authService = KdfAuthService(kdf, hostConfig) {
    _trezorAuthService = TrezorAuthService(_authService, TrezorRepository(kdf));
  }

  final SecureLocalStorage _secureStorage = SecureLocalStorage();
  final bool _allowRegistrations;
  late final IAuthService _authService;
  late final TrezorAuthService _trezorAuthService;
  bool _initialized = false;

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _authService.getActiveUser();
    _initialized = true;
  }

  // Save AuthOptions when registering or signing in
  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  }) async {
    await ensureInitialized();
    await _assertAuthState(false);

    // Trezor is not supported in non-stream functions
    if (options.privKeyPolicy == const PrivateKeyPolicy.trezor()) {
      throw AuthException(
        'Trezor authentication requires using signInStream() method '
        'to handle device interactions (PIN, passphrase) asynchronously',
        type: AuthExceptionType.generalAuthError,
      );
    }

    final user = await _findUser(walletName);
    final updatedUser = user.copyWith(
      walletId: user.walletId.copyWith(authOptions: options),
    );

    // Save AuthOptions to secure storage by wallet name
    await _secureStorage.saveUser(updatedUser);

    return _authService.signIn(
      walletName: walletName,
      password: password,
      options: options,
    );
  }

  @override
  Stream<AuthenticationState> signInStream({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  }) async* {
    await ensureInitialized();
    await _assertAuthState(false);

    if (options.privKeyPolicy == const PrivateKeyPolicy.trezor()) {
      // Trezor requires streaming to handle interactive device prompts
      yield* _trezorAuthService.signInStreamed(options: options);
    } else {
      yield* _handleRegularSignIn(
        walletName: walletName,
        password: password,
        options: options,
      );
    }
  }

  Future<KdfUser> _findUser(String walletName) async {
    final matchedUsers = (await _authService.getUsers()).where(
      (user) => user.walletId.name == walletName,
    );

    if (matchedUsers.isEmpty) {
      throw AuthException(
        'No user found with the specified wallet name.',
        type: AuthExceptionType.walletNotFound,
      );
    }

    if (matchedUsers.length > 1) {
      throw AuthException(
        'Multiple users found with the specified wallet name.',
        type: AuthExceptionType.internalError,
      );
    }

    return matchedUsers.first;
  }

  static Future<AuthOptions?> storedAuthOptions(String walletName) async {
    return SecureLocalStorage()
        .getUser(walletName)
        .then((user) => user?.authOptions);
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
    await ensureInitialized();
    await _assertAuthState(false);

    if (!_allowRegistrations) {
      throw AuthException(
        'Registration is not allowed.',
        type: AuthExceptionType.registrationNotAllowed,
      );
    }

    // Trezor is not supported in non-stream functions
    if (options.privKeyPolicy == const PrivateKeyPolicy.trezor()) {
      throw AuthException(
        'Trezor registration requires using registerStream() method '
        'to handle device interactions (PIN, passphrase) asynchronously',
        type: AuthExceptionType.generalAuthError,
      );
    }

    final user = await _authService.register(
      walletName: walletName,
      password: password,
      options: options,
      mnemonic: mnemonic,
    );

    await _secureStorage.saveUser(user);

    return user;
  }

  @override
  Stream<AuthenticationState> registerStream({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
  }) async* {
    await ensureInitialized();
    await _assertAuthState(false);

    if (!_allowRegistrations) {
      yield AuthenticationState.error('Registration is not allowed');
      return;
    }

    if (options.privKeyPolicy == const PrivateKeyPolicy.trezor()) {
      // Trezor requires streaming to handle interactive device prompts
      yield* _trezorAuthService.registerStream(
        options: options,
        mnemonic: mnemonic,
      );
    } else {
      yield* _handleRegularRegister(
        walletName: walletName,
        password: password,
        options: options,
        mnemonic: mnemonic,
      );
    }
  }

  Stream<AuthenticationState> _handleRegularSignIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  }) async* {
    try {
      yield const AuthenticationState(
        status: AuthenticationStatus.authenticating,
      );
      final user = await signIn(
        walletName: walletName,
        password: password,
        options: options,
      );
      yield AuthenticationState.completed(user);
    } catch (e) {
      yield AuthenticationState.error('Sign-in failed: $e');
    }
  }

  Stream<AuthenticationState> _handleRegularRegister({
    required String walletName,
    required String password,
    required AuthOptions options,
    Mnemonic? mnemonic,
  }) async* {
    try {
      yield const AuthenticationState(
        status: AuthenticationStatus.authenticating,
      );
      final user = await register(
        walletName: walletName,
        password: password,
        options: options,
        mnemonic: mnemonic,
      );
      yield AuthenticationState.completed(user);
    } catch (e) {
      yield AuthenticationState.error('Registration failed: $e');
    }
  }

  @override
  Stream<KdfUser?> get authStateChanges async* {
    await ensureInitialized();
    yield* _authService.authStateChanges;
  }

  @override
  Stream<KdfUser?> watchCurrentUser() async* {
    await ensureInitialized();

    // Emit the current user state as the initial value
    yield await _authService.getActiveUser();

    // Then emit subsequent changes
    yield* _authService.authStateChanges;
  }

  @override
  Future<KdfUser?> get currentUser async {
    await ensureInitialized();
    return _authService.getActiveUser();
  }

  @override
  Future<List<KdfUser>> getUsers() async {
    await ensureInitialized();

    return _authService.getUsers();
  }

  @override
  Future<void> signOut() async {
    await ensureInitialized();
    await _assertAuthState(true);

    try {
      await _authService.signOut();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'An unexpected error occurred while signing out: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<bool> isSignedIn() async {
    await ensureInitialized();
    return _authService.isSignedIn();
  }

  @override
  Future<Mnemonic> getMnemonicEncrypted() async {
    await ensureInitialized();
    await _assertAuthState(true);

    try {
      return await _authService.getMnemonic(
        encrypted: true,
        walletPassword: null,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'An unexpected error occurred while retrieving the mnemonic: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<Mnemonic> getMnemonicPlainText(String walletPassword) async {
    await ensureInitialized();
    await _assertAuthState(true);

    try {
      return _authService.getMnemonic(
        encrypted: false,
        walletPassword: walletPassword,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'An unexpected error occurred while retrieving the mnemonic: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await ensureInitialized();
    await _assertAuthState(true);

    try {
      await _authService.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'An unexpected error occurred while changing the password: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<void> deleteWallet({
    required String walletName,
    required String password,
  }) async {
    await ensureInitialized();
    try {
      await _authService.deleteWallet(
        walletName: walletName,
        password: password,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        'An unexpected error occurred while deleting the wallet: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<void> setOrRemoveActiveUserKeyValue(String key, dynamic value) async {
    await _authService.updateActiveUserMetadataKey(key, (_) => value);
  }

  @override
  Future<void> updateActiveUserKeyValue(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) async {
    await _authService.updateActiveUserMetadataKey(key, transform);
  }

  @override
  Future<void> setHardwareDevicePin(int taskId, String pin) async {
    await ensureInitialized();

    try {
      await _trezorAuthService.provideTrezorPin(taskId, pin);
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      throw AuthException(
        'Failed to provide PIN to hardware device: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<void> setHardwareDevicePassphrase(
    int taskId,
    String passphrase,
  ) async {
    await ensureInitialized();

    try {
      await _trezorAuthService.provideTrezorPassphrase(taskId, passphrase);
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      throw AuthException(
        'Failed to provide passphrase to hardware device: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  @override
  Future<void> cancelHardwareDeviceInitialization(int taskId) async {
    await ensureInitialized();

    try {
      await _trezorAuthService.cancelTrezorInitialization(taskId);
    } catch (e) {
      throw AuthException(
        'Failed to cancel hardware device initialization: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  Future<void> _assertAuthState(bool expected) async {
    await ensureInitialized();
    final signedIn = await isSignedIn();
    if (signedIn != expected) {
      throw AuthException(
        'User is ${signedIn ? 'signed in' : 'not signed in'}.',
        type:
            signedIn
                ? AuthExceptionType.alreadySignedIn
                : AuthExceptionType.unauthorized,
      );
    }
  }

  @override
  Future<bool> ensureKdfHealthy() async {
    await ensureInitialized();
    return _authService.ensureKdfHealthy();
  }

  @override
  Future<void> dispose() async {
    await _authService.dispose();
  }
}
