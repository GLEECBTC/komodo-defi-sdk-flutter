import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  group('enable_eth_with_tokens legacy response parsing', () {
    test('preserves zero-balance tickers when get_balances is false', () {
      final response = EnableEthWithTokensResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'current_block': 64265247,
          'eth_addresses_infos': {
            '0x083C32B38e8050473f6999e22f670d1404235592': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
            },
          },
          'erc20_addresses_infos': {
            '0x083C32B38e8050473f6999e22f670d1404235592': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
              'tickers': ['PGX-PLG20', 'AAVE-PLG20'],
            },
          },
          'nfts_infos': {},
        },
      }, platformTicker: 'MATIC');

      final addressBalance = response
          .walletBalance
          .accounts
          .first
          .addresses
          .first
          .balance
          .toJson();
      final totalBalance = response.walletBalance.accounts.first.totalBalance
          .toJson();

      expect(addressBalance.keys, containsAll(['PGX-PLG20', 'AAVE-PLG20']));
      expect(totalBalance.keys, containsAll(['PGX-PLG20', 'AAVE-PLG20']));
      expect(addressBalance.keys, isNot(contains('MATIC')));
      expect(
        response.walletBalance.accounts.first.addresses.first.balance
            .balanceOf('PGX-PLG20')
            .spendable,
        Decimal.zero,
      );
      expect(
        response.walletBalance.accounts.first.addresses.first.balance
            .balanceOf('AAVE-PLG20')
            .unspendable,
        Decimal.zero,
      );
    });

    test('merges tickers with real balances without overwriting them', () {
      final response = EnableEthWithTokensResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'current_block': 64265343,
          'eth_addresses_infos': {
            '0x083C32B38e8050473f6999e22f670d1404235592': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
            },
          },
          'erc20_addresses_infos': {
            '0x083C32B38e8050473f6999e22f670d1404235592': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
              'tickers': ['PGX-PLG20', 'AAVE-PLG20'],
              'balances': {
                'PGX-PLG20': {
                  'spendable': '237.729414631067',
                  'unspendable': '0',
                },
              },
            },
          },
          'nfts_infos': {},
        },
      }, platformTicker: 'MATIC');

      final addressBalance =
          response.walletBalance.accounts.first.addresses.first.balance;

      expect(
        addressBalance.toJson().keys,
        containsAll(['PGX-PLG20', 'AAVE-PLG20']),
      );
      expect(
        addressBalance.balanceOf('PGX-PLG20').spendable,
        Decimal.parse('237.729414631067'),
      );
      expect(addressBalance.balanceOf('AAVE-PLG20').spendable, Decimal.zero);
    });
  });
}
