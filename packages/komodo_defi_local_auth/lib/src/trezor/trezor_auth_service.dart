import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
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
    String Function(int length)? passwordGenerator,
  }) : _connectionMonitor =
           connectionMonitor ?? TrezorConnectionMonitor(_trezor),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _generatePassword =
           passwordGenerator ?? SecurityUtils.generatePasswordSecure;

  static const String trezorWalletName = 'My Trezor';
  static const String _passwordKey = 'trezor_wallet_password';
  static final _log = Logger('TrezorAuthService');

  final IAuthService _authService;
  final TrezorRepository _trezor;
  final FlutterSecureStorage _secureStorage;
  final TrezorConnectionMonitor _connectionMonitor;
  final String Function(int length) _generatePassword;

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
  }) async* {
    try {
      yield* _authenticateTrezorStream();
    } catch (e) {
      await _signOutCurrentTrezorUser();
      yield AuthenticationState.error('Trezor registration failed: $e');
    }
  }

  // IAuthService implementation - delegate to composed auth service
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
  Future<void> setActiveUserMetadata(JsonMap metadata) =>
      _authService.setActiveUserMetadata(metadata);

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) =>
      _authService.updateActiveUserMetadataKey(key, transform);

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
  }) => _authService.deleteWallet(walletName: walletName, password: password);

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
        'Trezor registration failed: $e',
        type: AuthExceptionType.generalAuthError,
      );
    }
  }

  Future<String> _getPassword({required bool isNewUser}) async {
    final existing = await _secureStorage.read(key: _passwordKey);
    if (!isNewUser) {
      if (existing == null) {
        throw AuthException(
          'Authentication failed for Trezor wallet',
          type: AuthExceptionType.generalAuthError,
        );
      }
      return existing;
    }

    if (existing != null) return existing;

    final newPassword = _generatePassword(16);
    await _secureStorage.write(key: _passwordKey, value: newPassword);
    return newPassword;
  }

  /// Clears the stored password for the Trezor wallet.
  Future<void> clearTrezorPassword() =>
      _secureStorage.delete(key: _passwordKey);

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
    if (current?.walletId.name == trezorWalletName) {
      _log.warning("Signing out current '${current?.walletId.name}' user");
      await _stopConnectionMonitoring();
      try {
        await _authService.signOut();
      } catch (_) {
        // ignore sign out errors
      }
    }
  }

  /// Finds an existing Trezor user in the user list
  Future<KdfUser?> _findExistingTrezorUser() async {
    final users = await _authService.getUsers();
    return users.firstWhereOrNull(
      (u) =>
          u.walletId.name == trezorWalletName &&
          u.walletId.authOptions.privKeyPolicy ==
              const PrivateKeyPolicy.trezor(),
    );
  }

  /// Authenticates with the Trezor wallet (sign in or register)
  /// [derivationMethod] The derivation method to use for the wallet.
  /// Defaults to [DerivationMethod.hdWallet], since trezor requires HD wallet
  /// RPCs to function.
  /// [existingUser] The existing user to authenticate
  Future<void> _authenticateWithTrezorWallet({
    required KdfUser? existingUser,
    required String password,
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  }) async {
    final authOptions = AuthOptions(
      derivationMethod: derivationMethod,
      privKeyPolicy: const PrivateKeyPolicy.trezor(),
    );

    if (existingUser != null) {
      await _authService.signIn(
        walletName: trezorWalletName,
        password: password,
        options: authOptions,
      );
    } else {
      await _authService.register(
        walletName: trezorWalletName,
        password: password,
        options: authOptions,
      );
    }
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
    DerivationMethod derivationMethod,
  ) async* {
    await _signOutCurrentTrezorUser();

    final existingUser = await _findExistingTrezorUser();
    final isNewUser = existingUser == null;
    final password = await _getPassword(isNewUser: isNewUser);

    await _authenticateWithTrezorWallet(
      existingUser: existingUser,
      password: password,
      derivationMethod: derivationMethod,
    );

    yield* _initializeTrezorDevice();
  }

  Stream<AuthenticationState> _authenticateTrezorStream({
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  }) async* {
    try {
      await for (final trezorState in _initializeTrezorAndAuthenticate(
        derivationMethod,
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
    DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  }) async {
    // Copy over contents from the streamed function
    await for (final trezorState in _initializeTrezorAndAuthenticate(
      derivationMethod,
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
