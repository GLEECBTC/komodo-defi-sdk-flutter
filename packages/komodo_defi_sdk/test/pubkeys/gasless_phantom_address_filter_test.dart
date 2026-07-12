import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

PubkeyInfo _pubkey(
  String address, {
  String spendable = '0',
  String? gasfreeAddress,
  String path = "m/44'/195'/0'/0/0",
}) => PubkeyInfo(
  address: address,
  derivationPath: path,
  chain: 'external',
  balance: BalanceInfo(
    total: Decimal.parse(spendable),
    spendable: Decimal.parse(spendable),
    unspendable: Decimal.zero,
  ),
  coinTicker: 'USDT-TRC20',
  gasfreeAddress: gasfreeAddress,
);

AssetPubkeys _pubkeys(Asset asset, List<PubkeyInfo> keys) => AssetPubkeys(
  assetId: asset.id,
  keys: keys,
  availableAddressesCount: keys.length,
  syncStatus: SyncStatusEnum.success,
);

void main() {
  final trx = Asset.fromJson(_trxConfig(), knownIds: const {});
  final usdt = Asset.fromJson(_trc20Config(), knownIds: {trx.id});

  group('filterGaslessPhantomAddresses', () {
    test('drops never-used secondary addresses, keeps the enabled one', () {
      final filtered = filterGaslessPhantomAddresses(
        usdt,
        _pubkeys(usdt, [
          _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
          _pubkey(
            'T-phantom-1',
            gasfreeAddress: 'T-custody-1',
            path: "m/44'/195'/0'/0/1",
          ),
          _pubkey(
            'T-phantom-2',
            gasfreeAddress: 'T-custody-2',
            path: "m/44'/195'/0'/0/2",
          ),
        ]),
      );

      expect(filtered.keys.map((k) => k.address), ['T-enabled']);
    });

    test(
      'keeps funded secondary addresses (stranded balances stay visible)',
      () {
        final filtered = filterGaslessPhantomAddresses(
          usdt,
          _pubkeys(usdt, [
            _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
            _pubkey(
              'T-funded',
              spendable: '7',
              gasfreeAddress: 'T-custody-1',
              path: "m/44'/195'/0'/0/1",
            ),
            _pubkey(
              'T-phantom',
              gasfreeAddress: 'T-custody-2',
              path: "m/44'/195'/0'/0/2",
            ),
          ]),
        );

        expect(filtered.keys.map((k) => k.address), ['T-enabled', 'T-funded']);
        expect(filtered.keys.first.gasfreeAddress, 'T-custody-0');
        expect(filtered.keys.last.gasfreeAddress, isNull);
      },
    );

    test('keeps an unfunded ENABLED address even when others are funded', () {
      final filtered = filterGaslessPhantomAddresses(
        usdt,
        _pubkeys(usdt, [
          _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
          _pubkey(
            'T-funded',
            spendable: '7',
            gasfreeAddress: 'T-custody-1',
            path: "m/44'/195'/0'/0/1",
          ),
        ]),
      );

      expect(filtered.keys.first.address, 'T-enabled');
      expect(filtered.keys, hasLength(2));
      expect(filtered.keys.last.gasfreeAddress, isNull);
    });

    test('keeps used-then-emptied addresses via the ever-funded set', () {
      // An address that once held funds (e.g. consolidated to custody and now
      // empty) must stay visible so its transaction history stays reachable.
      final filtered = filterGaslessPhantomAddresses(
        usdt,
        _pubkeys(usdt, [
          _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
          _pubkey(
            'T-emptied',
            gasfreeAddress: 'T-custody-1',
            path: "m/44'/195'/0'/0/1",
          ),
          _pubkey(
            'T-phantom',
            gasfreeAddress: 'T-custody-2',
            path: "m/44'/195'/0'/0/2",
          ),
        ]),
        everFunded: {'T-emptied'},
      );

      expect(filtered.keys.map((k) => k.address), ['T-enabled', 'T-emptied']);
    });

    test('applies to the TRX platform coin too', () {
      final filtered = filterGaslessPhantomAddresses(
        trx,
        _pubkeys(trx, [
          _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
          _pubkey(
            'T-phantom',
            gasfreeAddress: 'T-custody-1',
            path: "m/44'/195'/0'/0/1",
          ),
        ]),
      );

      expect(filtered.keys.map((k) => k.address), ['T-enabled']);
    });

    test('no-op without a gasless provider (no gasfreeAddress anywhere)', () {
      final original = _pubkeys(usdt, [
        _pubkey('T-a'),
        _pubkey('T-b', path: "m/44'/195'/0'/0/1"),
      ]);

      expect(filterGaslessPhantomAddresses(usdt, original), same(original));
    });

    test('no-op for single-address lists and non-TRON assets', () {
      final single = _pubkeys(usdt, [
        _pubkey('T-enabled', gasfreeAddress: 'T-custody-0'),
      ]);
      expect(filterGaslessPhantomAddresses(usdt, single), same(single));

      final doc = Asset.fromJson({
        'coin': 'DOC',
        'type': 'Smart Chain',
        'name': 'Doc',
        'fname': 'Doc',
        'wallet_only': false,
        'mm2': 1,
        'chain_id': 141,
        'decimals': 8,
        'is_testnet': true,
        'required_confirmations': 1,
        'derivation_path': "m/44'/141'/0'",
        'protocol': {'type': 'UTXO'},
      }, knownIds: const {});
      final utxo = _pubkeys(doc, [
        _pubkey('R-a'),
        _pubkey('R-b', path: "m/44'/141'/0'/0/1"),
      ]);
      expect(filterGaslessPhantomAddresses(doc, utxo), same(utxo));
    });
  });
}
