# komodo_defi_harness

Launches **pre-authenticated** Komodo DeFi Framework instances for tests and
benchmarks: a real `KomodoDefiSdk`, signed in as HD or iguana, with no UI.

```dart
final fixture = KdfWalletFixture()
  ..enableUtxo('KMD', inProgressPolls: 2)
  ..balance('KMD', spendable: '10');

final harness = await KdfHarness.replayed(script: fixture.build());
addTearDown(harness.dispose);

await harness.signIn(walletType: KdfWalletType.hd);
await harness.measureFirstBalance(assetId);

print(harness.metrics);
// sdk_init_ms=76 auth_signin_ms=510 first_paint_ms=7 activation_ms=1014
// first_post_activation_balance_ms=1025 identity_rpcs_per_signin=5 …
```

There are two tiers. See `docs/WALLET_LOAD_MEASUREMENT.md` in the app repo for
how they fit into the wider measurement story, including the browser.

---

## Tier 1: replay (`KdfHarness.replayed`) — the per-PR gate

Only the RPC backend is faked. Auth, activation, pubkeys, balances and storage
are all production code paths, so a measurement here is the SDK's own
orchestration cost with backend latency held at zero, and an assertion here is
about real behaviour rather than a mock of it.

A real KDF *is* available — `komodo_defi_framework/{macos,linux}/bin/kdf` is a
~120 MB executable the build transformer fetches — and it is still the wrong
default:

- **It is a build artifact**, gitignored, present only after the transformer
  runs.
- **Balances need live electrum servers**, making a per-PR gate depend on
  third-party uptime - and, as the numbers below show, taking over a minute.
- **The most valuable test cannot be written against it.** The activation
  deadline in `SharedActivationCoordinator` fires when KDF accepts a task and
  then stops making progress. A real KDF cannot be asked for that on demand;
  `KdfScript.hang()` produces it exactly, in bounded time. That test found two
  real defects — see below.

## Tier 2: process (`KdfHarness.process`) — nightly, informational

Spawns the real binary and talks HTTP to it. **This tier works end to end**, and
its first run produced the sharpest number in this whole effort:

| phase (real KDF, real electrum, same seed, KMD) | HD | iguana |
|---|---|---|
| `auth_signin_ms` | 2 123 | 2 221 |
| `activation_ms` | **35 966** | 2 566 |
| `first_post_activation_balance_ms` | **77 986** | 3 149 |

Same binary, same coin, same wallet. **HD is ~14x slower to activate and ~25x
slower to a balance.** The replay tier cannot show this - it holds backend
latency at zero, and this cost is entirely backend work (the HD address scan and
`task::account_balance`). That is the whole argument for keeping a real-KDF tier
even though it can never gate.

Returns **null rather than throwing** when it cannot run — no `KDF_HARNESS`, no
`KDF_TEST_SEED`, no binary, or the port already busy. Those are the normal
states of a fresh clone and of every per-PR run, so a test that gets null should
`markTestSkipped(requirements.skipReason)`.

Gating is on the `KDF_HARNESS` env var and **not** on binary-existence: the
SDK's own `flutter-tests.yml` runs the build transformer, so an existence check
would fail to skip there and a real KDF would spawn in a workflow with no
timeout budget for it.

`ProcessKdfOperations` **delegates to the framework's own**
`KdfOperationsLocalExecutable`. It used to reimplement it, and that was a
mistake with a concrete cost: re-deriving the lifecycle contract got
`version()` wrong. It must return null rather than throw when KDF is not up,
because `KomodoDefiFramework.isRunning` calls it as a fallback probe *before*
`kdfMain` has ever run - the reimplementation let the `SocketException` escape
and the symptom was `KDF RPC did not become ready within 15 seconds`, which
points at KDF rather than at the caller.

The framework class was made injectable instead (breaking change): `create` now
takes `executableFinder`, a `temporaryDirectory` provider in place of a direct
`getTemporaryDirectory()` call, and a `startParamsTransform` seam; and the RPC
endpoint comes from `LocalConfig.rpcUrl` rather than a `static final Uri` pinned
to 7783. The wrapper keeps only what a *measurement* harness needs and an app
must not have: per-method RPC counting, kill-by-pid signal handlers, and
`disable_p2p`.

Two things that only a real KDF teaches you, both now encoded:

- Disabling p2p is not a one-flag change. KDF prechecks the combination and
  refuses to start with `Cannot disable P2P while seed nodes are configured.`,
  so the transform drops `seednodes` too.
- The rpc password may not contain the word "password" (`Password can't contain
  the word password`). The replay tier never validates it, so it cannot catch
  this.

`disableP2p` defaults to **true** here, and that is stated rather than assumed:
**never do this in the app**, which ships a DEX and for which p2p *is* the
product. This harness activates coins and reads balances, and p2p adds seed-node
discovery to every measured startup. Pass `disableP2p: false` for anything
touching orderbooks or swaps.

---

## Scripts are stateful on purpose

`KdfScript` keys responses by `(method, invocationIndex)` and exposes an
`onKdfStart` hook, because KDF is stateful in two ways a flat method→response
map cannot express:

- **Activation is task-based.** `task::enable_*::init` returns a task id and the
  SDK polls `::status` until terminal. A constant response either finishes on
  the first poll (hiding all activation latency) or never finishes.
- **`get_wallet_names` answers differently before and after activation.**
  Registration requires the wallet absent; the post-sign-in identity check
  requires it present.

`KdfWalletFixture` assembles the whole login + activation + balance script.
It dispatches `::status` by **task id** rather than by method, because
`sequence()` keeps one cursor per method — right for one asset, wrong the moment
two activate concurrently, since they share the method name.

An unscripted method **throws**. Deliberately: a permissive default would look
like a legitimate empty result and fail far from the real gap. It also makes the
script an executable record of exactly which RPCs a login performs.

Two contract details the type system will not tell you: v2 responses must carry
`mmrpc`, and `get_public_key_hash` must return 40 lowercase hex characters or
`_ensureAuthenticatedWalletIdentity` rejects it.

## Metrics: never one number

| phase | meaning |
|---|---|
| `sdk_init_ms` | `initialize()` — config parsing and DI. Not gated: on the replay tier the seed-node fetch is stubbed to an instant 400, on the process tier it is a real network round trip, so the two tiers measure different things under one name. |
| `auth_signin_ms` | register/sign-in, including the identity RPCs. Gated. |
| `first_paint_ms` | first `BalanceInfo` of any provenance. **Never gate on this.** |
| `activation_ms` | when the asset reached `AssetActivationStatus.active` |
| `first_post_activation_balance_ms` | **the real time-to-balance.** Gated. |

`first_paint_ms` is *not* a measure of activation. It can legitimately be a
hydrated cache value, or the synthetic zero `BalanceManager` emits for a
first-time asset in a new wallet — added *before* `_ensureAssetActivated` is
called. Gating on it alone would let activation regress to minutes while the
metric stayed green. A typical run: `first_paint_ms=7`,
`first_post_activation_balance_ms=1025`.

Post-activation is resolved against the observed activation state, not by
counting emissions ("the second one"). Emission order is not a contract — the
stale-balance guard, the polling fallback and the pubkey hint listener can each
add one.

Counts live in `metrics.counters`, separate from durations: a duration is
compared against a baseline with a tolerance, a count is a shape observation a
human should read. Conflating them is how "480 identity RPCs per login" stayed
invisible.

## What this harness found

The activation-deadline test was written to confirm a landed fix. It failed, and
the failures were real:

1. **The deadline released only one of two in-flight registries.**
   `SharedActivationCoordinator._pendingActivations` was cleared, but the wedged
   generator never reached its own cleanup, so
   `ActivationManager._activationCompleters` kept the dead completer. The retry
   registered a fresh coordinator attempt and immediately parked on the old one
   — a "fresh" attempt that issued no RPC at all. Fixed by
   `ActivationManager.abandonActivation`. The pre-existing unit tests could not
   see this: their mock manager has no completer map.
2. **Unhandled async error on wallet change during activation.**
   `_resetState`/`dispose` complete pending attempts with an error, but
   `completer.future` is only handed to a caller at the bottom of
   `activateAsset` — so an attempt still streaming progress had no listener.
   Fixed with a side listener, matching what `_registerActivation` already did.

3. **`GetPublicKeyHashRequest` could never be sent over a JSON transport.** Its
   payload was `'params': <JsonMap>{}` - a single type argument on `{}` makes it
   an empty **Set**, not a Map - so `jsonEncode` refused it with
   `Converting object to an encodable object failed: _Set len:0`. Present since
   2024 and invisible to the type system, because `Set<JsonMap>` is a perfectly
   good `dynamic`. Only transports that serialise hit it (every non-web one);
   a replay or mock backend that reads the map directly never does, which is how
   it survived a test suite. Fixed, with a `jsonEncode`-round-trip test over the
   request types in `komodo_defi_rpc_methods`.
4. **A stopped-but-not-dead KDF was orphaned onto the fixed port.**
   `KdfOperationsLocalExecutable.kdfStop` awaits `exitCode` with a 10s timeout
   and then clears its process handle *whether or not the process died*, so the
   harness had nothing left to kill and every later run skipped with "port
   already in use". The wrapper now remembers the pid from `kdfMain`.

It also found a **test-isolation bug in this package**: Hive is process-global
and the SDK does not close its boxes, so a second harness in the same file
reused the first one's — pointed at a deleted directory. The symptom was not a
crash but a wrong measurement (a cached hydrate meant the balance RPC never
happened). `dispose` now closes Hive.

## The port is no longer fixed

It used to be, and not merely by default. `LocalConfig` had **no port field at
all**, so a locally started KDF had nowhere to put one: the auth path builds its
startup config with `KdfStartupConfig.generateWithDefaults` and passed only the
password, letting the `rpcPort = 7783` default win every time
(`auth_service_kdf_extension.dart`). Three other places then hardcoded the same
number independently - `KdfOperationsLocalExecutable._url`,
`KdfOperationsNativeLibrary._url`, and the SSE endpoint's non-`RemoteConfig`
fallback - so even pointing the RPC client elsewhere would have left event
streaming dialling 7783.

`port` now lives on `IKdfHostConfig` with `rpcUrl` derived from it, and the auth
path passes `_hostConfig.port` through. `KdfHarness.process(rpcPort: ...)` is a
parameter. Two consequences beyond this harness: two KDF instances can coexist
on one machine, and the SDK example's instance manager - which has always had a
port field in its UI - can finally honour it.

What stays serialised regardless: process-tier tests still want `-j 1` or one
file **unless** each allocates its own port, because the default is still one
shared port. The `KdfProcessRequirements` check now waits for the port to be
released rather than skipping immediately, so back-to-back tests on the default
port work.

## Two traps

**`FlutterSecureStorage.setMockInitialValues` before constructing the
framework.** `KomodoDefiSdk.fromFramework` passes `hostConfig: null`, so
bootstrap mints its own password for auth's `LocalConfig` by reading
`rpc_password` out of secure storage; a mismatch makes `startKdf` throw an
`ArgumentError` far from the cause.

**SSE event streaming escapes the replay seam.** It dials a hardcoded
`127.0.0.1:7783` outside `mm2Rpc`
(`komodo_defi_framework/lib/src/streaming/event_streaming_platform_io.dart`).
`requireNoImpostorKdf` therefore runs the same preflight the SSE client runs and
fails only if something there *accepts the harness's password* — which only
another harness can. A developer's own wallet build on that port is harmless and
must not be treated as a conflict, which is why this is not a "is the port free"
check. The process tier uses the bind check instead, because it genuinely binds.

## Security

Seeds and passwords are wrapped in `Secret` (`toString()` → `Secret(***)`, one
`reveal()`), redaction is applied sink-side to the framework log stream (which
echoes start parameters), and `KdfTestSeed` can only be constructed from the
environment — there is no literal constructor, so a funded seed cannot be
committed by accident. The workspace lives under `Directory.systemTemp` and is
deleted in teardown; **never upload it as a CI artifact**, it contains the
wallet DB.
