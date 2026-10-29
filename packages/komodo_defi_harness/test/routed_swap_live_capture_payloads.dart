part of 'routed_swap_live_capture_test.dart';

// Responses captured verbatim from KDF 3.1.0-beta_4872ef2 (native, macOS)
// on 2026-09-24 against the public provider API, from a throwaway
// wallet that held no funds. Only whitespace was changed.

/// `routed_swap::supported_coins` — supported coins, HTTP 200.
const String _supportedCoins = '''
{
  "mmrpc": "2.0",
  "result": {
    "provider": "lifi",
    "coins": [
      {
        "coin": "ETH",
        "chain_id": 1
      },
      {
        "coin": "POL",
        "chain_id": 137
      },
      {
        "coin": "USDC-ERC20",
        "chain_id": 1
      },
      {
        "coin": "USDC-PLG20",
        "chain_id": 137
      }
    ]
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote same chain ETH USDC, HTTP 200.
const String _quoteSameChain = '''
{
  "mmrpc": "2.0",
  "result": {
    "routes": [
      {
        "provider": "lifi",
        "from": {
          "coin": "ETH",
          "amount": "0.05"
        },
        "to": {
          "coin": "USDC-ERC20",
          "amount": "132.767617",
          "amount_min": "132.103779"
        },
        "tool": {
          "key": "nordstern",
          "name": "Nordstern Finance",
          "logo_url": "https://raw.githubusercontent.com/lifinance/types/main/src/assets/icons/exchanges/nordstern_finance.svg"
        },
        "kind": "same_chain",
        "from_address": "0x1EB04037c89b10b935800f85bD7969c3cDeFfDd4",
        "to_address": "0x1EB04037c89b10b935800f85bD7969c3cDeFfDd4",
        "total_gas_costs": [
          {
            "coin": "ETH",
            "amount": "0.000563343781000275",
            "amount_usd": "1.4993"
          }
        ],
        "steps": [
          {
            "type": "swap",
            "tool": "nordstern",
            "chain_id": 1
          }
        ],
        "fee_costs": [
          {
            "name": "LIFI Fixed Fee",
            "coin": "ETH",
            "amount": "0.000125",
            "amount_usd": "0.3327",
            "included": true
          }
        ],
        "gas_costs": [
          {
            "coin": "ETH",
            "amount": "0.000563343781000275",
            "amount_usd": "1.4993"
          }
        ],
        "execution_duration_s": 0
      }
    ]
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote cross chain native POL USDC, HTTP 200.
const String _quoteCrossChain = '''
{
  "mmrpc": "2.0",
  "result": {
    "routes": [
      {
        "provider": "lifi",
        "from": {
          "coin": "POL",
          "amount": "50"
        },
        "to": {
          "coin": "USDC-ERC20",
          "amount": "4.785295",
          "amount_min": "4.761369"
        },
        "tool": {
          "key": "across",
          "name": "AcrossV4",
          "logo_url": "https://raw.githubusercontent.com/lifinance/types/main/src/assets/icons/bridges/across.svg"
        },
        "kind": "cross_chain",
        "from_address": "0x90b9C6b3dD75c619F8514c8742E40539159dE0ee",
        "to_address": "0x90b9C6b3dD75c619F8514c8742E40539159dE0ee",
        "total_gas_costs": [
          {
            "coin": "POL",
            "amount": "0.3684380396959408",
            "amount_usd": "0.0381"
          }
        ],
        "steps": [
          {
            "type": "swap",
            "tool": "okx",
            "chain_id": 137
          },
          {
            "type": "cross",
            "tool": "across",
            "from_chain_id": 137,
            "to_chain_id": 1
          }
        ],
        "fee_costs": [
          {
            "name": "LIFI Fixed Fee",
            "coin": "POL",
            "amount": "0.125",
            "amount_usd": "0.0129",
            "included": true
          },
          {
            "name": "Relayer fee",
            "coin": "USDC-PLG20",
            "amount": "0.000512",
            "amount_usd": "0.0005",
            "included": true
          },
          {
            "name": "Relayer gas fee",
            "coin": "USDC-PLG20",
            "amount": "0.3632",
            "amount_usd": "0.3629",
            "included": true
          }
        ],
        "gas_costs": [
          {
            "coin": "POL",
            "amount": "0.3684380396959408",
            "amount_usd": "0.0381"
          }
        ],
        "execution_duration_s": 2
      }
    ]
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote cross chain cheapest, HTTP 502.
const String _approvalEstimateFailed = '''
{
  "mmrpc": "2.0",
  "error": "Unable to estimate source-chain approval cost",
  "error_path": "quote.eth",
  "error_trace": "quote:334] eth:5378]",
  "error_type": "TransportError",
  "error_data": {
    "message": "Unable to estimate source-chain approval cost"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote GLEEC to USDC, HTTP 502.
const String _gleecChainRejected = '''
{
  "mmrpc": "2.0",
  "error": "/fromChain must be equal to one of the allowed values, /fromChain must match exactly one schema in oneOf",
  "error_path": "quote.client",
  "error_trace": "quote:72] client:138]",
  "error_type": "ProviderApiError",
  "error_data": {
    "message": "/fromChain must be equal to one of the allowed values, /fromChain must match exactly one schema in oneOf",
    "provider_request_id": "c0bdfaee-3321-4ef2-a80a-b06df1d68113"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote non evm KMD, HTTP 400.
const String _nonEvmPair = '''
{
  "mmrpc": "2.0",
  "error": "Pair KMD/ETH is not supported: KMD is not an EVM asset",
  "error_path": "quote.evm",
  "error_trace": "quote:415] evm:28]",
  "error_type": "PairNotSupported",
  "error_data": {
    "from": "KMD",
    "to": "ETH",
    "reason": "KMD is not an EVM asset"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote inactive BTC, HTTP 400.
const String _inactiveCoin = '''
{
  "mmrpc": "2.0",
  "error": "Coin BTC is not active",
  "error_path": "quote.evm.lp_coins",
  "error_trace": "quote:415] evm:25] lp_coins:5453]",
  "error_type": "CoinNotActive",
  "error_data": {
    "coin": "BTC"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote too many decimals, HTTP 400.
const String _tooManyDecimals = '''
{
  "mmrpc": "2.0",
  "error": "Invalid parameter amount: more than 6 decimal places",
  "error_path": "quote",
  "error_trace": "quote:496]",
  "error_type": "InvalidParam",
  "error_data": {
    "param": "amount",
    "reason": "more than 6 decimal places"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote slippage too high, HTTP 400.
const String _slippageOutOfBounds = '''
{
  "mmrpc": "2.0",
  "error": "Parameter slippage out of bounds, value: 0.6, min: 0 max: 0.5",
  "error_path": "quote",
  "error_trace": "quote:461]",
  "error_type": "AmountOutOfBounds",
  "error_data": {
    "param": "slippage",
    "value": "0.6",
    "min": "0",
    "max": "0.5"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote unknown provider, HTTP 400.
const String _unknownProvider = '''
{
  "mmrpc": "2.0",
  "error": "Invalid parameter provider: Unsupported routed swap provider",
  "error_path": "quote",
  "error_trace": "quote:442]",
  "error_type": "InvalidParam",
  "error_data": {
    "param": "provider",
    "reason": "Unsupported routed swap provider"
  },
  "id": null
}
''';

/// `routed_swap::quote` — quote null optional, HTTP 400.
const String _nullOptional = '''
{
  "mmrpc": "2.0",
  "error": "Error parsing request: invalid type: null, expected string or map",
  "error_path": "dispatcher",
  "error_trace": "dispatcher:150]",
  "error_type": "InvalidRequest",
  "error_data": "invalid type: null, expected string or map",
  "id": null
}
''';

/// `routed_swap::history` — history empty, HTTP 200.
const String _historyEmpty = '''
{
  "mmrpc": "2.0",
  "result": {
    "entries": [],
    "total": 0,
    "limit": 10,
    "page_number": 1,
    "total_pages": 0
  },
  "id": null
}
''';

/// `task::routed_swap::status` — status no such task, HTTP 400.
const String _statusNoSuchTask = '''
{
  "mmrpc": "2.0",
  "error": "No such task '987654'",
  "error_path": "swap_task",
  "error_trace": "swap_task:1952]",
  "error_type": "NoSuchTask",
  "error_data": 987654,
  "id": null
}
''';
