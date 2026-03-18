<p align="center">
    <a href="https://github.com/GLEECBTC/komodo-defi-framework" alt="Komodo DeFi Framework">
        <img width="420" src="https://user-images.githubusercontent.com/24797699/252396802-de8f9264-8056-4430-a17d-5ecec9668dfc.png" />
    </a>
</p>

# Komodo DeFi SDK for Flutter

A Flutter SDK for building cross-platform DeFi apps on top of the Komodo DeFi Framework (KDF) with a few lines of code. The SDK provides a high-level, batteries-included developer experience while still exposing the low-level framework and RPC methods when you need them.

Maintained by [GLEEC](https://www.gleec.com).

- Primary entry point: see `packages/komodo_defi_sdk`.
- Full KDF access: see `packages/komodo_defi_framework`.
- RPC models and namespaces: see `packages/komodo_defi_rpc_methods`.
- Core types: see `packages/komodo_defi_types`.
- Coins metadata utilities: see `packages/komodo_coins`.
- Market data: see `packages/komodo_cex_market_data`.
- UI widgets: see `packages/komodo_ui`.
- Build hooks and artifacts: see `packages/komodo_wallet_build_transformer`.

Supported platforms: Android, iOS, macOS, Windows, Linux, and Web (WASM).

See the Komodo DeFi Framework (API) source at `https://github.com/GLEECBTC/komodo-defi-framework` and a hosted demo at `https://gleec-sdk-playground.web.app`.

## Quick start (SDK)

Add the SDK to your app and initialize it:

```dart
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() async {
  final sdk = KomodoDefiSdk(
    // Local by default; use RemoteConfig to connect to a remote node
    host: LocalConfig(https: false, rpcPassword: 'your-secure-password'),
    config: const KomodoDefiSdkConfig(
      defaultAssets: {'KMD', 'BTC', 'ETH'},
    ),
  );

  await sdk.initialize();

  // Register or sign in
  await sdk.auth.register(walletName: 'my_wallet', password: 'strong-pass');

  // Activate assets and get a balance
  final btc = sdk.assets.findAssetsByConfigId('BTC').first;
  await sdk.assets.activateAsset(btc).last;
  final balance = await sdk.balances.getBalance(btc.id);
  print('BTC balance: ${balance.total}');

  // Direct RPC access when needed
  final myKmd = await sdk.client.rpc.wallet.myBalance(coin: 'KMD');
  print('KMD: ${myKmd.balance}');
}
```

## Architecture overview

- `komodo_defi_sdk`: High-level orchestration (auth, assets, balances, tx history, withdrawals, signing, market data).
- `komodo_defi_framework`: Platform client for KDF with multiple backends (native/WASM/local process, remote). Provides the `ApiClient` used by the SDK.
- `komodo_defi_rpc_methods`: Typed RPC request/response models and method namespaces available via `client.rpc.*`.
- `komodo_defi_types`: Shared, lightweight domain types (e.g., `Asset`, `AssetId`, `BalanceInfo`, `WalletId`).
- `komodo_coins`: Fetch/transform Komodo coins metadata, filtering strategies, seed-node utilities.
- `komodo_cex_market_data`: Price providers (Komodo, Binance, CoinGecko) with repository selection and fallbacks.
- `komodo_ui`: Reusable, SDK-friendly Flutter UI components.
- `komodo_wallet_build_transformer`: Build-time artifact & assets fetcher (KDF binaries, coins, icons) integrated via Flutter’s asset transformers.

## Remote vs Local

- Local (default): Uses native FFI on desktop/mobile and WASM in Web builds. The SDK handles artifact provisioning via the build transformer.
- Remote: Connect with `RemoteConfig(ipAddress: 'host', port: 7783, rpcPassword: '...', https: true/false)`. You manage the remote KDF lifecycle.

Seed nodes: From KDF v2.5.0-beta, `seednodes` are required unless `disable_p2p` is `true`. The framework includes a validator and helpers. See `packages/komodo_defi_framework/README.md`.

## Packages in this monorepo

- `packages/komodo_defi_sdk` – High-level SDK (start here)
- `packages/komodo_defi_framework` – Low-level KDF client + lifecycle
- `packages/komodo_defi_rpc_methods` – Typed RPC surfaces
- `packages/komodo_defi_types` – Shared domain types
- `packages/komodo_coins` – Coins metadata + filters
- `packages/komodo_cex_market_data` – CEX price data
- `packages/komodo_ui` – UI widgets
- `packages/dragon_logs` – Cross-platform logging
- `packages/komodo_wallet_build_transformer` – Build artifacts/hooks
- `packages/dragon_charts_flutter` – Lightweight charts (moved here)

## Contributing

We follow practices inspired by Flutter BLoC and Very Good Ventures’ standards. Please open PRs and issues in this repository.

## License

MIT. See individual package LICENSE files where present.
