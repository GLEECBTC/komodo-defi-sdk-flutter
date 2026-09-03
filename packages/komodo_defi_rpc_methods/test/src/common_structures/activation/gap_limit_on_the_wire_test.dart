import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

/// The gap policy is only real if it reaches KDF.
///
/// Two independent walks exist and both had to be covered, because either one
/// left at 20 defeats the other: KDF's activation-time walk, driven by
/// `gap_limit` on the activation request, and the SDK's own
/// `task::scan_for_new_addresses`.
///
/// The ETH-family case is the one that silently did nothing before:
/// `EthActivationV2Request.gap_limit` is `Option<u32>` and KDF falls back to
/// `DEFAULT_GAP_LIMIT` = 20 when it is absent, so omitting the key looked like
/// "no opinion" and behaved like "the maximum".
JsonMap _ethConfig() => {
  'coin': 'GLEEC',
  'nodes': [
    {'url': 'https://evm-rpc.gleec.com'},
  ],
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
};

JsonMap _utxoConfig() => {
  'coin': 'KMD',
  'type': 'UTXO',
  'protocol': {'type': 'UTXO'},
  'derivation_path': "m/44'/141'",
  'is_testnet': true,
  'electrum': [
    {'url': 'electrum1.example:10001'},
  ],
};

void main() {
  group('EVM activation carries gap_limit', () {
    test('an explicit gap limit reaches the payload', () {
      final params = EthWithTokensActivationParams.fromJson(
        _ethConfig(),
      ).copyWith(gapLimit: HdGapLimit.newlyGeneratedFirstSignIn);

      expect(params.toRpcParams()['gap_limit'], 1);
    });

    test('the software gap reaches the payload', () {
      final params = EthWithTokensActivationParams.fromJson(
        _ethConfig(),
      ).copyWith(gapLimit: HdGapLimit.software);

      expect(params.toRpcParams()['gap_limit'], 3);
    });

    test('an absent gap limit emits no key at all', () {
      // Rather than emitting 20 explicitly: absent means "KDF decides", and
      // KDF's own default is the full BIP-44 gap. Emitting a number here would
      // make a future change to that default invisible to us.
      final params = EthWithTokensActivationParams.fromJson(_ethConfig());
      expect(params.toRpcParams().containsKey('gap_limit'), isFalse);
    });

    test('gap_limit survives a fromJson round trip', () {
      final params = EthWithTokensActivationParams.fromJson({
        ..._ethConfig(),
        'gap_limit': 3,
      });
      expect(params.gapLimit, 3);
    });
  });

  group('UTXO activation carries gap_limit', () {
    test('a software wallet gets the reduced gap', () {
      final protocol = UtxoProtocol.fromJson(_utxoConfig());
      final params = protocol.defaultActivationParams(
        gapLimit: HdGapLimit.software,
      );

      expect(params.gapLimit, 3);
      expect(
        params.scanPolicy,
        ScanPolicy.scanIfNewWallet,
        reason: 'the gap changes; whether KDF scans at all does not',
      );
    });

    test('a newly generated wallet gets the minimum', () {
      final params = UtxoProtocol.fromJson(
        _utxoConfig(),
      ).defaultActivationParams(
        gapLimit: HdGapLimit.newlyGeneratedFirstSignIn,
      );
      expect(params.gapLimit, 1);
    });

    test('Trezor keeps the full gap and the stronger scan policy', () {
      final params = UtxoProtocol.fromJson(
        _utxoConfig(),
      ).defaultActivationParams(
        privKeyPolicy: const PrivateKeyPolicy.trezor(),
        gapLimit: HdGapLimit.hardware,
      );

      expect(params.gapLimit, 20);
      expect(params.scanPolicy, ScanPolicy.scan);
    });

    test('omitting the gap limit falls back to the full BIP-44 gap', () {
      // A caller that did not resolve a policy has not established that this
      // wallet is safe to scan shallowly, so the safe end is the default.
      final params = UtxoProtocol.fromJson(
        _utxoConfig(),
      ).defaultActivationParams();
      expect(params.gapLimit, 20);
    });
  });

  group('the SDK scan gap is separate from the address-creation gap', () {
    const user = KdfUser(
      walletId: WalletId(
        name: 'w',
        pubkeyHash: 'aaaa',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      ),
      isBip39Seed: true,
    );

    test('the strategy takes the scan gap it is given', () {
      final strategy = ContextPrivKeyHDWalletStrategy(
        kdfUser: user,
        scanGapLimit: HdGapLimit.newlyGeneratedFirstSignIn,
      );
      expect(strategy.scanGapLimit, 1);
    });

    test('a strategy built without one keeps the full gap', () {
      final strategy = ContextPrivKeyHDWalletStrategy(kdfUser: user);
      expect(strategy.scanGapLimit, 20);
    });

    test('Trezor always scans at the full gap', () {
      expect(TrezorHDWalletStrategy(kdfUser: user).scanGapLimit, 20);
    });

    test('address creation is never narrowed by the scan gap', () {
      // `task::get_new_address` refuses once there are already `gap_limit`
      // unused addresses in a row (get_new_address.rs:615-617). Feeding the
      // scan gap in would cap how many unused addresses a user may hold - at
      // the newly-generated limit they could create exactly one and then be
      // refused. Address creation is a user action with no node-load problem.
      final narrow = ContextPrivKeyHDWalletStrategy(
        kdfUser: user,
        scanGapLimit: HdGapLimit.newlyGeneratedFirstSignIn,
      );
      final wide = ContextPrivKeyHDWalletStrategy(kdfUser: user);

      expect(
        narrow.availableNewAddressesCount(const <PubkeyInfo>[]),
        completion(equals(20)),
      );
      expect(
        wide.availableNewAddressesCount(const <PubkeyInfo>[]),
        completion(equals(20)),
      );
    });
  });
}
