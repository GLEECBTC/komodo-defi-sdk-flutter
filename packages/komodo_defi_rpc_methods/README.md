# Komodo DeFi RPC Methods

Typed RPC request/response models and method namespaces for the Komodo DeFi Framework API. This package is consumed by the framework (`ApiClient`) and the high-level SDK.

[![License: MIT][license_badge]][license_link]

## Install

```sh
dart pub add komodo_defi_rpc_methods
```

## Usage

RPC namespaces are exposed as extensions on `ApiClient` via `client.rpc` when using either the framework or the SDK.

```dart
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

final framework = KomodoDefiFramework.create(
  hostConfig: LocalConfig(https: false, rpcPassword: '...'),
);

final client = framework.client;

// Wallet
final names = await client.rpc.wallet.getWalletNames();
final kmdBalance = await client.rpc.wallet.myBalance(coin: 'KMD');

// Addresses
final v = await client.rpc.address.validateAddress(
  coin: 'BTC',
  address: 'bc1q...',
);

// General activation
final enabled = await client.rpc.generalActivation.getEnabledCoins();

// Message signing
final signed = await client.rpc.utility.signMessage(
  coin: 'BTC',
  message: 'Hello, Komodo!'
);
```

Explore exported modules in `lib/src/rpc_methods` for the full surface (activation, wallet, utxo/eth/trezor, trading, orderbook, transaction history, withdrawal, etc.).

## Development

### Regenerating RPC exceptions

`lib/src/models/mm2_rpc_exceptions.dart` is generated from the Komodo DeFi Framework error enums.

```sh
python3 tool/generate_mm2_rpc_exceptions.py --mm2-repo /path/to/komodo-defi-framework
# or let the script clone the API repo into a temp directory:
python3 tool/generate_mm2_rpc_exceptions.py
```

Generated error models and exception classes expose `errorType` as the raw
API string (e.g. `NoSuchCoin`), so app code can match on classes/strings
directly without depending on generated `*ErrorType` enums.

By default, the script runs `dart fix --apply` after generation. Use `--no-fix`
to skip it.

## License

MIT

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
