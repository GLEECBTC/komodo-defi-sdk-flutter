# Adopting SDK 0.9.0

This candidate is distributed as a complete GitHub checkout/submodule. Keep
every SDK package at one reviewed commit and retain consumer path overrides.
SDK 0.8.1 is the previous distribution commit (`a96398ba`); the last published
GitHub release is 0.8.0. This document does not announce publication.

## Upgrade the checkout

Follow the [complete-checkout instructions](RELEASE_0.8.0.md#pin-the-complete-checkout),
including all consumer overrides. Resolve the approved full commit from the
merged SDK release PR before checking it out. Do not select a floating branch.
Resolve with Flutter 3.41.4 / Dart 3.11.1; review the application's lockfile and
run its four-define GasFree unit gate. The SDK workspace lockfile is generated
and ignored; do not add it. Package and dependency versions are listed in the
[0.9.0 overview](../CHANGELOG.md#sdk-090-overview).

## Stable API changes since 0.8.1

- Implement `fetchTickers` in custom `ICoinPaprikaProvider` adapters. Current
  prices and 24h changes share a bulk response for five minutes. A coin absent
  from it is unsupported; let repository selection choose another provider.
  Do not assume the bulk endpoint has every coin the metadata endpoint lists.
  Failed fetches also cool down. Handle nullable `CoinPaprikaMarket.marketUrl`.
- Move custom-token capability from `BatchCapableActivator` to
  `ProtocolActivationStrategy`. Check `supportedProtocols`, `supportedRoles`
  and `supportsCustomTokenActivation`: custom and configured tokens must not
  overlap, and a platform-only task must not receive a token. The default role
  set contains both roles; override it for protocols with separate RPC paths.
- Adopt Hive CE ^2.14.0 with the workspace. The refused encrypted history box
  is recovered despite asynchronous close/delete ordering. Existing wallet keys and seeds are not
  migrated by this preparation.

## Adding routed swaps

Use `sdk.routedSwaps` separately from atomic `sdk.trading`. Activate supported
assets first. Use `quote` for an exact amount or `quoteMax` for KDF's complete
Max offer. Show funding requirements separately from estimated spending and
show the route's minimum without a second fee/slippage deduction. Preserve
the reviewed concrete amount and accepted minimum through start/revalidation.
Never interpret a quote as a broadcast or automatically resubmit an uncertain
start. Track/resume with the durable UUID (`watch(uuid)`); task IDs are transient.

The [manager](../packages/komodo_defi_sdk/lib/src/routed_swaps/routed_swap_manager.dart)
and [typed requests](../packages/komodo_defi_rpc_methods/lib/src/rpc_methods/routed_swap/routed_swap_requests.dart)
define the supported parameters. Preserve typed errors, approval hashes,
required/locked balances, accepted versus executed routes and recorded gas in
recovery UI. A provider report or expected quote output is not a measured
receipt. An absent `received`/receipt amount means measurement unavailable.

For adopters of interim development branches, remove `guardMargin`,
`defaultGuardMargin`, `maxSellFeeMargin`, `maxSellFundingMargin` and
`nativeGasReserve`; `RoutedSwapFinished.received` is nullable. These were not
part of stable SDK 0.8.1. Gleec Wallet's extra native-Max gas headroom is a
separate, bounded quote policy and is not introduced into the reusable SDK.

## Startup and engine compatibility

`KomodoDefiSdkConfig.lifiProxyUrl` is optional. A proxy must be HTTP(S), without
credentials/query/fragment, and requires P2P enabled because KDF signs requests.
The proxy owns its API key. Leave it unset to use KDF's public provider path.
Optional `LifiIntegratorConfig` sets validated global commission at startup;
the SDK default is unset. Preserve it through registration, sign-in and restart.

Use the seven-platform KDF manifest at source `35f0bde` and the contract at
specs `7c388ea`. A remote KDF must implement that contract too. The frozen coins
pin is `2b0aefb7`; runtime coin updates remain enabled independently of the
bundle pin. Never replace a verified checksum with a freshly calculated value
without independent rebuild provenance.

Trezor asset selection now includes configured GLEEC/GRC-20 assets; this does
not establish routed hardware signing, all-EVM support or funded device QA.
Keep web websocket expansion disabled as documented for this engine. Native
bridge-fee compatibility and provider/status polling remain upstream review
items. The [checklist](RELEASE_0.9.0_CHECKLIST.md) records release gates.
