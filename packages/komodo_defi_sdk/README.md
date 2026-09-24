# Komodo DeFi SDK (Flutter)

High-level, opinionated SDK for building cross-platform Komodo DeFi wallets and apps. The SDK orchestrates authentication, asset activation, balances, transaction history, withdrawals, message signing, and price data while exposing a typed RPC client for advanced use.

[![License: MIT][license_badge]][license_link] [![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

## Features

- Authentication and wallet lifecycle (HD by default, hardware wallets supported)
- Asset discovery and activation (with historical/custom token pre-activation)
- Balances and pubkeys (watch/stream and on-demand)
- Transaction history (paged + streaming sync)
- Withdrawals with progress and cancellation
- Message signing and verification
- CEX market data integration (Komodo, Binance, CoinGecko) with fallbacks
- Typed RPC namespaces via `client.rpc.*`

## Install

```sh
dart pub add komodo_defi_sdk
```

### Wallet-identity release candidate

This checkout prepares `0.8.0-rc.1`. It requires local-auth `0.6.0-rc.1` and the
[metadata-write migration](../komodo_defi_local_auth/README.md#migrating-metadata-writes).
Test the RC from a pinned checkout before publication. Once the RC is published,
opt in explicitly:

```sh
flutter pub add komodo_defi_sdk:0.8.0-rc.1
```

## Quick start

```dart
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

final sdk = KomodoDefiSdk(
  host: LocalConfig(https: false, rpcPassword: 'your-secure-password'),
  config: const KomodoDefiSdkConfig(
    defaultAssets: {'KMD', 'BTC', 'ETH'},
  ),
);

await sdk.initialize();

// Register or sign in
await sdk.auth.register(walletName: 'my_wallet', password: 'strong-pass');

// Activate an asset and read a balance
final btc = sdk.assets.findAssetsByConfigId('BTC').first;
await sdk.assets.activateAsset(btc).last;
final balance = await sdk.balances.getBalance(btc.id);

// Direct RPC when needed
final kmd = await sdk.client.rpc.wallet.myBalance(coin: 'KMD');
```

## Configuration

```dart
// Host selection: local (default) or remote
final local = LocalConfig(https: false, rpcPassword: '...');
final remote = RemoteConfig(
  ipAddress: 'example.org',
  port: 7783,
  rpcPassword: '...',
  https: true,
);

// SDK behavior
const config = KomodoDefiSdkConfig(
  defaultAssets: {'KMD', 'BTC', 'ETH', 'DOC'},
  preActivateDefaultAssets: true,
  preActivateHistoricalAssets: true,
  preActivateCustomTokenAssets: true,
  marketDataConfig: MarketDataConfig(
    enableKomodoPrice: true,
    enableBinance: true,
    enableCoinGecko: true,
  ),
);
```

## Common tasks

### Authentication

```dart
await sdk.auth.signIn(walletName: 'my_wallet', password: 'pass');
// Streams for progress/2FA/hardware interactions are also available
```

### Assets

```dart
final eth = sdk.assets.findAssetsByConfigId('ETH').first;
await for (final p in sdk.assets.activateAsset(eth)) {
  // p: ActivationProgress
}
final activated = await sdk.assets.getActivatedAssets();
```

### Pubkeys and addresses

```dart
final asset = sdk.assets.findAssetsByConfigId('BTC').first;
final pubkeys = await sdk.pubkeys.getPubkeys(asset);
final newAddr = await sdk.pubkeys.createNewPubkey(asset);
```

### Balances

```dart
final info = await sdk.balances.getBalance(asset.id);
final sub = sdk.balances.watchBalance(asset.id).listen((b) {
  // update UI
});
```

### Transaction history

```dart
final page = await sdk.transactions.getTransactionHistory(asset);
await for (final batch in sdk.transactions.getTransactionsStreamed(asset)) {
  // append to list
}
```

### Withdrawals

```dart
final stream = sdk.withdrawals.withdraw(
  WithdrawParameters(
    asset: 'BTC',
    toAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
    amount: Decimal.parse('0.001'),
    // feePriority optional until fee estimation endpoints are available
  ),
);
await for (final progress in stream) {
  // status / tx hash
}
```

### Message signing

```dart
final signature = await sdk.messageSigning.signMessage(
  coin: 'BTC',
  message: 'Hello, Komodo!',
  address: 'bc1q...',
);
final ok = await sdk.messageSigning.verifyMessage(
  coin: 'BTC',
  message: 'Hello, Komodo!',
  signature: signature,
  address: 'bc1q...',
);
```

### Market data

```dart
final price = await sdk.marketData.fiatPrice(
  asset.id,
  quoteCurrency: Stablecoin.usdt,
);
```

## UI helpers

This package includes lightweight adapters for `komodo_ui`. For example:

```dart
// Displays and live-updates an asset balance using the SDK
AssetBalanceText(asset.id)
```

## Advanced: direct RPC

The underlying `ApiClient` exposes typed RPC namespaces:

```dart
final resp = await sdk.client.rpc.address.validateAddress(
  coin: 'BTC',
  address: 'bc1q...',
);
```

## Lifecycle and disposal

Call `await sdk.dispose()` when you’re done to free resources and stop background timers.

## Platform notes

- Web uses the WASM build of KDF automatically via the framework plugin.
- Remote mode connects to an external KDF node you run and manage.
- From KDF v2.5.0-beta, seed nodes are required unless P2P is disabled. The framework handles validation and defaults; see its README for details.

## License

MIT

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
