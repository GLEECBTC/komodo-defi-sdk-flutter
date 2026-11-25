part of 'solana_live_capture_test.dart';

// Captured with the replies in solana_live_capture_rules.dart; see there.

/// What KDF lists around token and platform `disable_coin`, in call order.
const _disableExchanges = <_Exchange>[
  _Exchange(
    'enable_platform_with_token',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_with_assets",
  "params": {
    "ticker": "TESTSOL",
    "nodes": [
      {
        "url": "https://api.devnet.solana.com"
      }
    ],
    "tx_history": true,
    "tokens_params": [
      {
        "ticker": "TESTUSDC-TESTSOL"
      }
    ]
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "ticker": "TESTSOL",
    "current_block": 523652855,
    "balance": {
      "spendable": "0",
      "unspendable": "0"
    },
    "tokens_balances": {
      "TESTUSDC-TESTSOL": {
        "spendable": "0",
        "unspendable": "0"
      }
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'enabled_after_activation',
    '''
{
  "mmrpc": "2.0",
  "method": "get_enabled_coins",
  "params": {}
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "coins": [
      {
        "ticker": "TESTSOL"
      },
      {
        "ticker": "TESTUSDC-TESTSOL"
      }
    ]
  },
  "id": null
}
''',
  ),
  _Exchange(
    'disable_token',
    '''
{
  "method": "disable_coin",
  "coin": "TESTUSDC-TESTSOL"
}
''',
    '''
{
  "result": {
    "coin": "TESTUSDC-TESTSOL",
    "cancelled_orders": [],
    "passivized": false
  }
}
''',
  ),
  _Exchange(
    'enabled_after_token_disable',
    '''
{
  "mmrpc": "2.0",
  "method": "get_enabled_coins",
  "params": {}
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "coins": [
      {
        "ticker": "TESTSOL"
      }
    ]
  },
  "id": null
}
''',
  ),
  _Exchange(
    'disable_platform_no_tokens',
    '''
{
  "method": "disable_coin",
  "coin": "TESTSOL"
}
''',
    '''
{
  "result": {
    "coin": "TESTSOL",
    "cancelled_orders": [],
    "passivized": false
  }
}
''',
  ),
  _Exchange(
    'enabled_after_platform_disable',
    '''
{
  "mmrpc": "2.0",
  "method": "get_enabled_coins",
  "params": {}
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "coins": []
  },
  "id": null
}
''',
  ),
  _Exchange(
    'token_without_platform',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_token",
  "params": {
    "ticker": "TESTUSDC-TESTSOL",
    "activation_params": {}
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "Platform coin TESTSOL is not activated",
  "error_path": "token.lp_coins",
  "error_trace": "token:139] lp_coins:5459]",
  "error_type": "PlatformCoinIsNotActivated",
  "error_data": "TESTSOL",
  "id": null
}
''',
  ),
  _Exchange(
    'enable_platform_again',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_with_assets",
  "params": {
    "ticker": "TESTSOL",
    "nodes": [
      {
        "url": "https://api.devnet.solana.com"
      }
    ],
    "tx_history": true,
    "tokens_params": [
      {
        "ticker": "TESTUSDC-TESTSOL"
      },
      {
        "ticker": "CUSTOM-TESTSOL",
        "protocol": {
          "type": "SOLANATOKEN",
          "protocol_data": {
            "platform": "TESTSOL",
            "decimals": 6,
            "mint_address": "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU",
            "program_id": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
          }
        }
      }
    ]
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "ticker": "TESTSOL",
    "current_block": 523652859,
    "balance": {
      "spendable": "0",
      "unspendable": "0"
    },
    "tokens_balances": {
      "TESTUSDC-TESTSOL": {
        "spendable": "0",
        "unspendable": "0"
      },
      "CUSTOM-TESTSOL": {
        "spendable": "0",
        "unspendable": "0"
      }
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'disable_platform_with_tokens',
    '''
{
  "method": "disable_coin",
  "coin": "TESTSOL"
}
''',
    '''
{
  "result": {
    "coin": "TESTSOL",
    "cancelled_orders": [],
    "passivized": true
  }
}
''',
  ),
  _Exchange(
    'enabled_after_platform_with_tokens_disable',
    '''
{
  "mmrpc": "2.0",
  "method": "get_enabled_coins",
  "params": {}
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "coins": [
      {
        "ticker": "TESTSOL"
      },
      {
        "ticker": "TESTUSDC-TESTSOL"
      },
      {
        "ticker": "CUSTOM-TESTSOL"
      }
    ]
  },
  "id": null
}
''',
  ),
  _Exchange(
    'token_after_platform_with_tokens_disable',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_token",
  "params": {
    "ticker": "TESTUSDC-TESTSOL",
    "activation_params": {}
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "Token TESTUSDC-TESTSOL is already activated",
  "error_path": "token",
  "error_trace": "token:131]",
  "error_type": "TokenIsAlreadyActivated",
  "error_data": "TESTUSDC-TESTSOL",
  "id": null
}
''',
  ),
];
