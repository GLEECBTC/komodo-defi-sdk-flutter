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
  ///
  /// KDF refuses a SOLANA protocol without `protocol_data`, even empty
  /// (`CoinProtocolParseError`), as the coins catalog writes it.
  static Map<String, dynamic> platformConfig() => {
    'coin': platform,
    'type': 'SOLANA',
    'fname': 'Solana Devnet',
    'is_testnet': true,
    'wallet_only': true,
    'decimals': 9,
    'derivation_path': "m/44'/501'",
    'protocol': {'type': 'SOLANA', 'protocol_data': <String, dynamic>{}},
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

  /// The tickers in KDF's coins config, as the last start listed them.
  ///
  /// Read from the start params' `coins`, which come from the SDK's asset
  /// catalog, so a test that injects a catalog sees what KDF would. Empty
  /// until the engine starts.
  final Set<String> _configured = {};

  /// True while KDF keeps a disabled platform for its still-active tokens.
  bool _passivized = false;

  Map<String, dynamic> _balance(String ticker) => {
    'spendable': ticker == platform ? solBalance : tokenBalance,
    'unspendable': '0',
  };

  Iterable<String> get _enabledTokens =>
      _enabled.where((ticker) => ticker != platform);

  // The rules and replies below follow KDF 3.2.0-beta_46769c4 as captured on
  // devnet; `solana_live_capture_test.dart` holds this fixture to them.

  static Map<String, dynamic> _error(
    String type,
    Object data,
    String message,
    String path,
    String trace,
  ) => {
    'mmrpc': '2.0',
    'error': message,
    'error_path': path,
    'error_trace': trace,
    'error_type': type,
    'error_data': data,
    'id': null,
  };

  static Map<String, dynamic> _result(Map<String, dynamic> result) => {
    'mmrpc': '2.0',
    'result': result,
    'id': null,
  };

  /// KDF's `coin_conf_with_protocol`: a request `protocol` defines a custom
  /// token, so KDF refuses it for a configured ticker and needs it otherwise.
  /// [batch] selects the platform-with-tokens error location.
  Map<String, dynamic>? _tokenConfigError(
    Map<String, dynamic> token, {
    required bool batch,
  }) {
    final ticker = token['ticker'] as String;
    final isCustom = token.containsKey('protocol');
    if (isCustom != _configured.contains(ticker)) return null;
    final path = batch ? 'platform_coin_with_tokens.prelude' : 'token.prelude';
    final via = batch
        ? 'platform_coin_with_tokens:497] platform_coin_with_tokens:167] '
              'platform_coin_with_tokens:157]'
        : 'token:135]';
    return isCustom
        ? _error(
            'CustomTokenError',
            {
              'DuplicateTickerInConfig': {'ticker_in_config': ticker},
            },
            'Custom token error: Token with the same ticker already exists '
                'in coins configs, ticker in config: $ticker',
            path,
            '$via prelude:102]',
          )
        : _error(
            'TokenConfigIsNotFound',
            ticker,
            'Token $ticker config is not found',
            path,
            '$via prelude:108]',
          );
  }

  Map<String, dynamic> _enablePlatform(Map<String, dynamic> params) {
    final tokens = (params['tokens_params'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final token in tokens) {
      final error = _tokenConfigError(token, batch: true);
      if (error != null) return error;
    }
    if (_enabled.contains(platform) && !_passivized) {
      return _error(
        'PlatformIsAlreadyActivated',
        platform,
        platform,
        'platform_coin_with_tokens',
        'platform_coin_with_tokens:475]',
      );
    }
    // Reactivating a passivized platform also reports the tokens it kept.
    _passivized = false;
    _enabled.add(platform);
    for (final token in tokens) {
      _enabled.add(token['ticker'] as String);
    }
    return _result({
      'ticker': platform,
      'address': address,
      'current_block': 42,
      'balance': _balance(platform),
      'tokens_balances': {
        for (final ticker in _enabledTokens) ticker: _balance(ticker),
      },
    });
  }

  Map<String, dynamic> _enableToken(Map<String, dynamic> params) {
    final ticker = params['ticker'] as String;
    if (_enabled.contains(ticker)) {
      return _error(
        'TokenIsAlreadyActivated',
        ticker,
        'Token $ticker is already activated',
        'token',
        'token:131]',
      );
    }
    final error = _tokenConfigError(params, batch: false);
    if (error != null) return error;
    if (!_enabled.contains(platform)) {
      return _error(
        'PlatformCoinIsNotActivated',
        platform,
        'Platform coin $platform is not activated',
        'token.lp_coins',
        'token:139] lp_coins:5459]',
      );
    }
    _enabled.add(ticker);
    return _result({
      'ticker': ticker,
      'address': address,
      'current_block': 42,
      'balance': _balance(ticker),
    });
  }

  /// A platform with active tokens is only passivized: KDF keeps listing it
  /// and its tokens, and the tokens stay usable.
  Map<String, dynamic> _disable(String ticker) {
    final passivize = ticker == platform && _enabledTokens.isNotEmpty;
    if (passivize) {
      _passivized = true;
    } else {
      _enabled.remove(ticker);
      if (ticker == platform) _passivized = false;
    }
    return {
      'result': {
        'coin': ticker,
        'cancelled_orders': <Object>[],
        'passivized': passivize,
      },
    };
  }

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

  /// A fresh engine has nothing enabled and knows only its start-up coins.
  void _onStart(Map<String, dynamic> startParams) {
    _enabled.clear();
    _passivized = false;
    _configured
      ..clear()
      ..addAll([
        for (final coin in startParams['coins'] as List<dynamic>)
          (coin as Map<String, dynamic>)['coin'] as String,
      ]);
  }

  /// Builds a stateful activation/history script on the standard auth fixture.
  KdfScript build() {
    final script = KdfWalletFixture().build();
    final inheritedStart = script.onKdfStart;
    script
      ..onKdfStart = ((startParams) {
        inheritedStart?.call(startParams);
        _onStart(startParams);
      })
      ..on(
        'get_enabled_coins',
        (_) => _result({
          'coins': [
            for (final ticker in _enabled) {'ticker': ticker},
          ],
        }),
      )
      ..on(
        'experimental::enable_solana_with_assets',
        (request) => _enablePlatform(request['params'] as Map<String, dynamic>),
      )
      ..on(
        'experimental::enable_solana_token',
        (request) => _enableToken(request['params'] as Map<String, dynamic>),
      )
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
      ..on('disable_coin', (request) => _disable(request['coin'] as String));
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
