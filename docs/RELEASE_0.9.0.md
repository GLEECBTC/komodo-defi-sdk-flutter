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

Prefer `sdk.routedSwaps`. Direct construction of `RoutedSwapManager` requires
`auth: sdk.auth` so cached handles and background work share the SDK's runtime
wallet ownership. Signing out, switching wallets or reauthenticating the same
wallet invalidates existing sessions and rejects late responses. An unanswered
initial status remains `RoutedSwapStartUnconfirmedException` with its task ID;
matching amounts or minima in history never establish which swap was started.

Start only offers the manager issued in the current session: from `quote`,
`quoteMax`, `maxSellAmount` or a failure's `freshOffer`, or a `copyWith` or
`keepingMinimum` copy of one. For an offer priced before a sign-out, a wallet
switch or same-wallet reauthentication, and for one constructed directly,
`start` throws `AuthSessionChangedException` having sent nothing; quote again.

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

### Submission ownership

Executable routed offers must come from the same `RoutedSwapManager` that
executes them, in the same uninterrupted wallet session. Directly constructed
offers are display-only. `copyWith` and `keepingMinimum` preserve private
issuance; there is no public session-rebinding API. Reauthentication, including
the same wallet, requires a fresh quote and confirmation.

Custom auth implementations must implement
`runWithSession<T>(AuthSessionContext expected, Future<T> Function() dispatch)`.
Validate the original session before waiting and after acquiring the auth read
lease. Retain that lease until the raw request settles; auth transitions use
the corresponding write lease. The callback must not re-enter authentication
or await status polling. Do not release ownership using a timeout while the
underlying request can still execute. A stalled request can delay wallet
switching until it settles; a bounded, abortable transport is separate work.

`RoutedSwapManager.start` accepts an optional synchronous `beforeDispatch`
callback for a caller's revocable confirmation. It runs under the session lease
immediately before raw init. A callback failure sends nothing and propagates
unchanged. Once dispatch may have occurred, retain the existing unconfirmed
handling and recover through task/history lookup rather than retrying.

### Engine inputs

`KomodoDefiSdkConfig.lifiProxyUrl` is optional. A proxy must be HTTP(S), without
credentials/query/fragment, and requires P2P enabled because KDF signs requests.
The proxy owns its API key. Leave it unset to use KDF's public provider path.
Optional `LifiIntegratorConfig` sets validated global commission at startup;
the SDK default is unset. Preserve it through registration, sign-in and restart.

Use the seven-platform KDF manifest at exact `dev` source `a51d69a` and the
contract at specs `7c388ea`. A remote KDF must implement that contract too.
The frozen coins pin is `efd3a647`; runtime coin updates remain enabled and
build-time revision advancement stays disabled. Never replace a checksum
without independent artifact provenance. The [3 November roll record](KDF_ARTIFACTS_2026-11-03.json)
compares all seven archives with GitHub artifact digests and ordinary mirrors.

The two KDF commits after `e40ac2f` bump the engine to `3.2.0-beta` and repair
CI fixtures, shared-wallet test races, test endpoints and proving performance
in development/test profiles. All ten platform builds and all 17 test jobs
passed. The original Linux Tendermint timeout and macOS Telegram assertion
failure remain recorded alongside their passing retries. The upstream main
merge later changed only `CHANGELOG.md`; this pin retains the exact requested
and validated revision.

The coins bundle adds TAR, TAR-segwit and TEL-BASE, removes TEL-KRC20 and
updates TEL ERC-20/Polygon contracts and decimals. It also refreshes GLEEC/GRC-20
Trezor metadata, ARRR activation data, endpoints and verified icons. Review
existing TEL integrations against these network-specific migrations.

Trezor asset selection now includes configured GLEEC/GRC-20 assets; this does
not establish routed hardware signing, all-EVM support or funded device QA.
Keep web websocket expansion disabled as documented for this engine. Native
bridge-fee compatibility and provider/status polling remain upstream review
items. The [checklist](RELEASE_0.9.0_CHECKLIST.md) records release gates.

### EVM history provider and reconciliation fixes

Ethereum Classic uses its configured Blockscout explorer. The legacy
`https://blockscout.com/etc/mainnet/` config is mapped to the canonical
`https://etc.blockscout.com/api` endpoint; the proxy's absent ETC route is no
longer selected. The public account API was checked without wallet data.
Explorer errors remain errors, rather than being rendered as empty histories.
The existing per-address 1,000-row Blockscout bound remains; it is not a claim
of complete internal-call coverage or unbounded archival history.

Repeated proxy pages and older net-only cache rows retain their signed balance
movement. Optional debit/credit fields no longer turn outgoing transfers into
unsigned gross amounts, and complementary wallet-address perspectives still
merge without duplication. Debug builds fetch history instead of returning a
successful empty page. Existing wallet-session history isolation remains in force.
