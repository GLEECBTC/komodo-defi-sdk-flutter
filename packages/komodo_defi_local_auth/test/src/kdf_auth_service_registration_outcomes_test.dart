import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'support/fake_kdf_engine.dart';
import 'support/source_assets.dart';

const _provisioningId = 'provisioning-test-entry-0001';
const _foreignEntryId = 'foreign-catalog-entry-0002';

/// Persists every user record under another entry, as a concurrent writer
/// replacing the record would.
class _ReplacingStorage extends FlutterSecureStorage {
  const _ReplacingStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => super.write(
    key: key,
    value: key.startsWith('user_')
        ? value?.replaceAll(_provisioningId, _foreignEntryId)
        : value,
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useSourceAssets(binding);

  test('a creation that cannot be verified does not leave its engine '
      'session to be adopted', () async {
    seedStoredUsers(const []);
    final engine = FakeKdfEngine(wallets: [], activeWallet: null);
    final storage = SecureLocalStorage.withStorage(const _ReplacingStorage());
    final service = authServiceFor(engine, storage: storage);
    addTearDown(service.dispose);
    final signedIn = <KdfUser>[];
    final subscription = service.authStateChanges.listen((user) {
      if (user != null) signedIn.add(user);
    });
    addTearDown(subscription.cancel);

    await expectLater(
      service.register(
        walletName: 'new-wallet',
        password: testPassword,
        provisioningId: _provisioningId,
      ),
      throwsA(isA<StateError>()),
    );

    expect(engine.running, isFalse);
    expect(await service.getActiveUser(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(signedIn, isEmpty);
    expect(service.isAuthTransitionInProgress, isFalse);
    // The reservation stays, so only the same operation can resume the name.
    expect(
      (await storage.getProvisioning('new-wallet'))?['id'],
      _provisioningId,
    );
  });

  test('a completed creation resumes after a sign-in rewrote its stored '
      'options', () async {
    // A password sign-in stores the options it was given, so the completed
    // record no longer carries the ones the creation was requested with.
    seedStoredUsers([
      KdfUser(
        walletId: WalletId.withPubkeyHash(
          'new-wallet',
          const AuthOptions(
            derivationMethod: DerivationMethod.iguana,
            allowWeakPassword: true,
          ),
          testPublicKeyHash,
        ),
        isBip39Seed: true,
        metadata: const {
          walletEntryIdMetadataKey: _provisioningId,
          'has_backup': true,
        },
      ),
    ]);
    final engine = FakeKdfEngine(wallets: ['new-wallet'], activeWallet: null);
    final service = authServiceFor(engine);
    addTearDown(service.dispose);

    final resumed = await service.register(
      walletName: 'new-wallet',
      password: testPassword,
      provisioningId: _provisioningId,
    );

    expect(resumed.metadata[walletEntryIdMetadataKey], _provisioningId);
    expect(resumed.metadata['has_backup'], isTrue);
    expect(resumed.walletId.authOptions, testHdOptions);
    expect(engine.wallets, ['new-wallet']);
    expect(
      engine.starts.where((start) => start['allow_registrations'] == true),
      isEmpty,
    );
  });

  test('another operation still cannot claim a completed creation', () async {
    seedStoredUsers([
      verifiedUser(
        'new-wallet',
      ).copyWith(metadata: const {walletEntryIdMetadataKey: _provisioningId}),
    ]);
    final engine = FakeKdfEngine(wallets: ['new-wallet'], activeWallet: null);
    final service = authServiceFor(engine);
    addTearDown(service.dispose);

    await expectLater(
      service.register(
        walletName: 'new-wallet',
        password: testPassword,
        provisioningId: 'another-provisioning-entry-0003',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.type,
          'type',
          AuthExceptionType.walletAlreadyExists,
        ),
      ),
    );
    expect(engine.starts, isEmpty);
  });
}
