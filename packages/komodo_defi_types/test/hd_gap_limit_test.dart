import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

/// `gap_limit` is the BIP-44 **consecutive-empty** tolerance, so lowering it
/// trades node requests against how much of a wallet's history can still be
/// found - and the failure mode is a balance that is silently too low. These
/// pin the policy so a future edit has to be deliberate about that trade.
void main() {
  const trezor = PrivateKeyPolicy.trezor();
  const software = PrivateKeyPolicy.contextPrivKey();

  group('HdGapLimit.resolve', () {
    test('hardware keeps the full BIP-44 gap', () {
      expect(
        HdGapLimit.resolve(
          privKeyPolicy: trezor,
          isNewlyGeneratedFirstSignIn: false,
        ),
        20,
      );
    });

    test('hardware keeps 20 even if flagged newly generated', () {
      // A Trezor seed is never created by this app, so the flag should never
      // be set for one - but if it ever were, the hardware path must not
      // narrow. Its seed is expected to have been used by other software,
      // which is exactly the history a short gap fails to find.
      expect(
        HdGapLimit.resolve(
          privKeyPolicy: trezor,
          isNewlyGeneratedFirstSignIn: true,
        ),
        20,
      );
    });

    test('a software wallet uses the reduced gap', () {
      expect(
        HdGapLimit.resolve(
          privKeyPolicy: software,
          isNewlyGeneratedFirstSignIn: false,
        ),
        3,
      );
    });

    test('a newly generated software wallet uses the minimum', () {
      expect(
        HdGapLimit.resolve(
          privKeyPolicy: software,
          isNewlyGeneratedFirstSignIn: true,
        ),
        1,
      );
    });

    test('the three tiers are ordered and distinct', () {
      expect(HdGapLimit.newlyGeneratedFirstSignIn, lessThan(HdGapLimit.software));
      expect(HdGapLimit.software, lessThan(HdGapLimit.hardware));
    });
  });

  group('the first-sign-in flag is transient', () {
    const walletId = WalletId(
      name: 'w',
      pubkeyHash: 'aaaa',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );

    test('KdfUser defaults it to false', () {
      // Anything that reconstructs a user without knowing - storage, a test
      // double, a JSON round trip - must get the safe answer, because false
      // means "use the wider gap".
      const user = KdfUser(walletId: walletId, isBip39Seed: true);
      expect(user.isGeneratedThisSession, isFalse);
    });

    test('it never round-trips through JSON', () {
      const user = KdfUser(
        walletId: walletId,
        isBip39Seed: true,
        isGeneratedThisSession: true,
      );

      final restored = KdfUser.fromJson(user.toJson());

      expect(
        restored.isGeneratedThisSession,
        isFalse,
        reason:
            'persisting it would keep telling the address scan there is '
            'nothing to find long after the wallet could have received funds',
      );
    });

    test('copyWith carries it', () {
      const user = KdfUser(
        walletId: walletId,
        isBip39Seed: true,
        isGeneratedThisSession: true,
      );
      expect(user.copyWith().isGeneratedThisSession, isTrue);
      expect(
        user.copyWith(isGeneratedThisSession: false).isGeneratedThisSession,
        isFalse,
      );
    });

    test('it does not affect equality', () {
      // Identity checks across the SDK compare users to detect a wallet
      // switch. A stamped and an unstamped read of the same wallet must not
      // look like two different wallets.
      const stamped = KdfUser(
        walletId: walletId,
        isBip39Seed: true,
        isGeneratedThisSession: true,
      );
      const plain = KdfUser(walletId: walletId, isBip39Seed: true);
      expect(stamped, plain);
    });
  });
}
