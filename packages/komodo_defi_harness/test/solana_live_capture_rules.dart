part of 'solana_live_capture_test.dart';

// Replies captured verbatim from KDF 3.2.0-beta_46769c4 (native, macOS) on
// 2026-11-18 against Solana devnet, from fresh unfunded Iguana wallets,
// through the wallet's `tool/solana_smoke.py` RPC allowlist. The owner address
// is replaced by the fixture's placeholder in [_rulesExchanges] and removed
// from [_disableExchanges]; only whitespace was changed otherwise. A matching
// HD capture agreed, except where devnet rate limiting (429) failed one
// balance read.

/// Each catalog/custom request shape against one engine, in call order.
const _rulesExchanges = <_Exchange>[
  _Exchange(
    'batch_unknown_ticker_without_protocol',
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
        "ticker": "MISSING-TESTSOL"
      }
    ]
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "Token MISSING-TESTSOL config is not found",
  "error_path": "platform_coin_with_tokens.prelude",
  "error_trace": "platform_coin_with_tokens:497] platform_coin_with_tokens:167] platform_coin_with_tokens:157] prelude:108]",
  "error_type": "TokenConfigIsNotFound",
  "error_data": "MISSING-TESTSOL",
  "id": null
}
''',
  ),
  _Exchange(
    'batch_catalog_token_with_protocol',
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
        "ticker": "TESTUSDC-TESTSOL",
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
  "error": "Custom token error: Token with the same ticker already exists in coins configs, ticker in config: TESTUSDC-TESTSOL",
  "error_path": "platform_coin_with_tokens.prelude",
  "error_trace": "platform_coin_with_tokens:497] platform_coin_with_tokens:167] platform_coin_with_tokens:157] prelude:102]",
  "error_type": "CustomTokenError",
  "error_data": {
    "DuplicateTickerInConfig": {
      "ticker_in_config": "TESTUSDC-TESTSOL"
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'batch_catalog_token_by_ticker',
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
    "address": "11111111111111111111111111111111",
    "current_block": 523652732,
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
    'batch_platform_already_active',
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
    "tokens_params": []
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "TESTSOL",
  "error_path": "platform_coin_with_tokens",
  "error_trace": "platform_coin_with_tokens:475]",
  "error_type": "PlatformIsAlreadyActivated",
  "error_data": "TESTSOL",
  "id": null
}
''',
  ),
  _Exchange(
    'disable_catalog_token',
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
    'later_catalog_token_with_protocol',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_token",
  "params": {
    "ticker": "TESTUSDC-TESTSOL",
    "activation_params": {},
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
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "Custom token error: Token with the same ticker already exists in coins configs, ticker in config: TESTUSDC-TESTSOL",
  "error_path": "token.prelude",
  "error_trace": "token:135] prelude:102]",
  "error_type": "CustomTokenError",
  "error_data": {
    "DuplicateTickerInConfig": {
      "ticker_in_config": "TESTUSDC-TESTSOL"
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'later_catalog_token_by_ticker',
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
  "result": {
    "ticker": "TESTUSDC-TESTSOL",
    "address": "11111111111111111111111111111111",
    "current_block": 523652735,
    "balance": {
      "spendable": "0",
      "unspendable": "0"
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'later_token_already_active',
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
  _Exchange(
    'later_custom_token_with_protocol',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_token",
  "params": {
    "ticker": "CUSTOM-TESTSOL",
    "activation_params": {},
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
}
''',
    '''
{
  "mmrpc": "2.0",
  "result": {
    "ticker": "CUSTOM-TESTSOL",
    "address": "11111111111111111111111111111111",
    "current_block": 523652736,
    "balance": {
      "spendable": "0",
      "unspendable": "0"
    }
  },
  "id": null
}
''',
  ),
  _Exchange(
    'later_unknown_ticker_without_protocol',
    '''
{
  "mmrpc": "2.0",
  "method": "experimental::enable_solana_token",
  "params": {
    "ticker": "MISSING-TESTSOL",
    "activation_params": {}
  }
}
''',
    '''
{
  "mmrpc": "2.0",
  "error": "Token MISSING-TESTSOL config is not found",
  "error_path": "token.prelude",
  "error_trace": "token:135] prelude:108]",
  "error_type": "TokenConfigIsNotFound",
  "error_data": "MISSING-TESTSOL",
  "id": null
}
''',
  ),
  _Exchange(
    'disable_platform',
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
    'batch_custom_token_with_protocol',
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
        "ticker": "CUSTOMB-TESTSOL",
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
    "address": "11111111111111111111111111111111",
    "current_block": 523652737,
    "balance": {
      "spendable": "0",
      "unspendable": "0"
    },
    "tokens_balances": {
      "TESTUSDC-TESTSOL": {
        "spendable": "0",
        "unspendable": "0"
      },
      "CUSTOMB-TESTSOL": {
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
    'later_token_without_platform',
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
