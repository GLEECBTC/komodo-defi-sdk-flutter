import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _hdAuth = AuthOptions(derivationMethod: DerivationMethod.hdWallet);
const _iguanaAuth = AuthOptions(derivationMethod: DerivationMethod.iguana);

WalletId _wallet({
  required String name,
  required AuthOptions authOptions,
  String? pubkeyHash,
}) {
  return WalletId(name: name, authOptions: authOptions, pubkeyHash: pubkeyHash);
}

void main() {
  group('isSameStableWallet', () {
    test('isolates the same public-key hash across derivation modes', () {
      final hdWallet = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final iguanaWallet = _wallet(
        name: 'wallet',
        authOptions: _iguanaAuth,
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(hdWallet, iguanaWallet), isFalse);
      expect(isSameStableWallet(iguanaWallet, hdWallet), isFalse);
    });

    test('isolates the same public-key hash across signing modes', () {
      final softwareWallet = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final trezorWallet = _wallet(
        name: 'wallet',
        authOptions: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          privKeyPolicy: PrivateKeyPolicy.trezor(),
        ),
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(softwareWallet, trezorWallet), isFalse);
      expect(isSameStableWallet(trezorWallet, softwareWallet), isFalse);
    });

    test('ignores password-strength acceptance for wallet identity', () {
      final strict = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final weakPasswordAccepted = _wallet(
        name: 'wallet',
        authOptions: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(strict, weakPasswordAccepted), isTrue);
      expect(isSameStableWallet(weakPasswordAccepted, strict), isTrue);
    });

    test('accepts enrichment but rejects loss of an established hash', () {
      final nameOnly = _wallet(name: 'wallet', authOptions: _hdAuth);
      final enriched = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(nameOnly, enriched), isTrue);
      expect(isSameStableWallet(enriched, nameOnly), isFalse);
    });

    test('rejects enrichment when the wallet name differs', () {
      final nameOnly = _wallet(name: 'wallet-a', authOptions: _hdAuth);
      final enriched = _wallet(
        name: 'wallet-b',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(nameOnly, enriched), isFalse);
      expect(isSameStableWallet(enriched, nameOnly), isFalse);
    });

    test('rejects enrichment when the derivation mode differs', () {
      final nameOnly = _wallet(name: 'wallet', authOptions: _hdAuth);
      final enriched = _wallet(
        name: 'wallet',
        authOptions: _iguanaAuth,
        pubkeyHash: '0123456789abcdef',
      );

      expect(isSameStableWallet(nameOnly, enriched), isFalse);
      expect(isSameStableWallet(enriched, nameOnly), isFalse);
    });

    test('uses the public-key hash after both identities are enriched', () {
      final originalName = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final renamed = _wallet(
        name: 'renamed-wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final otherIdentity = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'fedcba9876543210',
      );

      expect(isSameStableWallet(originalName, renamed), isTrue);
      expect(isSameStableWallet(originalName, otherIdentity), isFalse);
    });

    test('treats legacy uppercase public-key hashes as equivalent', () {
      final lowercase = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789abcdef',
      );
      final uppercase = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: '0123456789ABCDEF',
      );

      expect(isSameStableWallet(lowercase, uppercase), isTrue);
    });

    test('compares names when neither identity has been enriched', () {
      final wallet = _wallet(name: 'wallet', authOptions: _hdAuth);
      final sameWallet = _wallet(name: 'wallet', authOptions: _hdAuth);
      final otherWallet = _wallet(name: 'other-wallet', authOptions: _hdAuth);

      expect(isSameStableWallet(wallet, sameWallet), isTrue);
      expect(isSameStableWallet(wallet, otherWallet), isFalse);
    });
  });

  group('preferEnrichedWalletIdentity', () {
    test('accepts a name-only to enriched transition', () {
      final nameOnly = _wallet(name: 'wallet', authOptions: _hdAuth);
      final hashA = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'hash-a',
      );

      expect(preferEnrichedWalletIdentity(nameOnly, hashA), hashA);
      expect(
        () => preferEnrichedWalletIdentity(hashA, nameOnly),
        throwsArgumentError,
      );
    });

    test('A hash to name-only to B hash requires a new session', () {
      final hashA = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'hash-a',
      );
      final nameOnly = _wallet(name: 'wallet', authOptions: _hdAuth);
      final hashB = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'hash-b',
      );

      expect(isSameStableWallet(hashA, nameOnly), isFalse);
      expect(isSameStableWallet(nameOnly, hashB), isTrue);
      expect(isSameStableWallet(hashA, hashB), isFalse);
      expect(preferEnrichedWalletIdentity(nameOnly, hashB), hashB);
    });

    test('rejects a different hash after enrichment', () {
      final hashA = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'hash-a',
      );
      final hashB = _wallet(
        name: 'wallet',
        authOptions: _hdAuth,
        pubkeyHash: 'hash-b',
      );

      expect(
        () => preferEnrichedWalletIdentity(hashA, hashB),
        throwsArgumentError,
      );
    });
  });
}
