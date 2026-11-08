import 'package:komodo_defi_harness/src/kdf_fixture.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';

/// Source-shaped Solana RPCs for exercising the real SDK coordinator.
///
/// This fixture deliberately provides no HD discovery/account RPCs. Global HD
/// wallet derivation still reaches KDF's startup configuration, while Solana
/// always resolves one owner address. Values are synthetic and never funded.
class SolanaWalletFixture {
  /// Creates an unfunded fixture unless explicit balances are supplied.
  SolanaWalletFixture({
    this.address = '11111111111111111111111111111111',
    this.solBalance = '0',
    this.tokenBalance = '0',
    this.serveHistory = true,
  });

  /// Reviewed testnet platform identity.
  static const platform = 'TESTSOL';

  /// Reviewed classic SPL testnet identity.
  static const token = 'TESTUSDC-TESTSOL';

  /// Mixed-case synthetic signature used to detect destructive normalization.
  static const signature = '5SigCaseSensitiveABCabcXYZxyz123';

  /// The one owner address shared by the platform and its token.
  final String address;

  /// Platform spendable balance, expressed in SOL.
  final String solBalance;

  /// Token spendable balance, expressed in token units.
  final String tokenBalance;

  /// False hangs history RPCs so a test can prove cached rows are served.
  final bool serveHistory;
  final Set<String> _enabled = {};

  /// Minimal normalized catalog entry, never added to production assets.
  static Map<String, dynamic> platformConfig() => {
    'coin': platform,
    'type': 'SOLANA',
    'fname': 'Solana Devnet',
    'is_testnet': true,
    'wallet_only': true,
    'decimals': 9,
    'derivation_path': "m/44'/501'",
    'protocol': {'type': 'SOLANA'},
    'nodes': [
      {'url': 'https://api.devnet.solana.com'},
    ],
  };

  /// Complete trusted token metadata, including its explicit platform link.
  static Map<String, dynamic> tokenConfig() => {
    'coin': token,
    'type': 'SOLANATOKEN',
    'fname': 'USDC Devnet',
    'parent_coin': platform,
    'is_testnet': true,
    'wallet_only': true,
    'protocol': {
      'type': 'SOLANATOKEN',
      'protocol_data': {
        'platform': platform,
        'decimals': 6,
        'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        'program_id': 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
      },
    },
  };

  Map<String, dynamic> _balance(String ticker) => {
    'spendable': ticker == platform ? solBalance : tokenBalance,
    'unspendable': '0',
  };

  /// Indexed history does not supply a memo or execution-success field.
  /// Incoming ATA receipts can include a SOL fee with no SOL amount received.
  Map<String, dynamic> transaction(String ticker) => {
    'coin': ticker,
    'tx_hash': signature,
    'internal_id': '$ticker-$signature',
    'tx_hex': '',
    'from': <String>[],
    'to': [address],
    'my_balance_change': '0.000001',
    'spent_by_me': '0',
    'received_by_me': '0.000001',
    'total_amount': '0.000001',
    'block_height': 42,
    'confirmations': 1,
    'timestamp': 1783641600,
    'memo': null,
    'fee_details': {
      'type': 'Solana',
      'fee_amount': '0.000005',
      'rent_amount': '0',
      'total_amount': '0.000005',
    },
  };

  /// Builds a stateful activation/history script on the standard auth fixture.
  KdfScript build() {
    final script = KdfWalletFixture().build()
      ..on(
        'get_enabled_coins',
        (_) => {
          'mmrpc': '2.0',
          'result': {
            'coins': [
              for (final ticker in _enabled) {'ticker': ticker},
            ],
          },
        },
      )
      ..on('experimental::enable_solana_with_assets', (request) {
        final params = request['params'] as Map<String, dynamic>;
        final tokens = params['tokens_params'] as List<dynamic>;
        _enabled.add(platform);
        for (final token in tokens.cast<Map<String, dynamic>>()) {
          _enabled.add(token['ticker'] as String);
        }
        return {
          'mmrpc': '2.0',
          'result': {
            'ticker': platform,
            'address': address,
            'current_block': 42,
            'balance': _balance(platform),
            'tokens_balances': {
              for (final token in tokens.cast<Map<String, dynamic>>())
                token['ticker'] as String: _balance(token['ticker'] as String),
            },
          },
        };
      })
      ..on('experimental::enable_solana_token', (request) {
        _enabled.add(token);
        return {
          'mmrpc': '2.0',
          'result': {
            'ticker': token,
            'address': address,
            'current_block': 42,
            'balance': _balance(token),
          },
        };
      })
      ..on('my_balance', (request) {
        final ticker = request['coin'] as String;
        if (!_enabled.contains(ticker)) {
          return {'error': 'No such coin', 'error_type': 'NoSuchCoin'};
        }
        return {
          'coin': ticker,
          'address': address,
          'balance': _balance(ticker)['spendable'],
          'unspendable_balance': '0',
        };
      })
      ..on('disable_coin', (request) {
        final ticker = request['coin'] as String;
        _enabled.remove(ticker);
        if (ticker == platform) _enabled.remove(token);
        return {
          'result': {'coin': ticker},
        };
      });
    if (serveHistory) {
      script.on('my_tx_history', (request) {
        final params = request['params'] as Map<String, dynamic>;
        final ticker = params['coin'] as String;
        return {
          'mmrpc': '2.0',
          'result': {
            'coin': ticker,
            'current_block': 42,
            'from_id': null,
            'limit': params['limit'],
            'skipped': 0,
            'sync_status': {'state': 'Finished'},
            'total': 1,
            'total_pages': 1,
            'page_number': 1,
            'transactions': [transaction(ticker)],
          },
        };
      });
    } else {
      script.hang('my_tx_history');
    }
    return script;
  }
}
