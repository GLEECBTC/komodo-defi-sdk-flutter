# Adopting SDK 0.8.0

SDK 0.8.0 is prepared for the GitHub checkout/submodule workflow. Its stable
package versions do not imply pub.dev availability. Use all SDK packages from
one reviewed commit. The [changelog](../CHANGELOG.md#sdk-080-overview) covers the
changes since `komodo_defi_sdk-v0.4.0+3`; the
[checklist](RELEASE_0.8.0_CHECKLIST.md) records validation and publication handoff.

## Pin the complete checkout

For a new consumer, add the SDK as a submodule. Replace the placeholder with
the full reviewed release commit after the preparation PR has merged and the
release commit is available on the distribution branch:

```sh
git submodule add https://github.com/GLEECBTC/komodo-defi-sdk-flutter.git sdk
git -C sdk fetch origin
git -C sdk checkout --detach <full-reviewed-release-commit>
```

For an existing submodule, omit `submodule add`. For a standalone SDK checkout,
clone the same repository and check out that same commit. Resolve it from its
root with Flutter 3.41.4:

```sh
flutter --version
flutter pub get
```

Use `flutter pub get --offline` when the dependency cache is already populated.
The SDK workspace ignores its generated lockfile; do not add it to this
repository. Consumer applications should retain their own lockfile policy.
The SDK's declared Dart/Flutter minimum versions remain unchanged; this release
is validated with Flutter 3.41.4, not every version in those supported ranges.

In the consumer's `pubspec.yaml`, declare the SDK path:

```yaml
dependencies:
  komodo_defi_sdk:
    path: sdk/packages/komodo_defi_sdk
```

Merge the following into the consumer's root `pubspec_overrides.yaml` so
transitive SDK dependencies resolve from the same checkout rather than mixing
local code with hosted packages. Preserve any existing consumer overrides.

```yaml
dependency_overrides:
  dragon_charts_flutter:
    path: sdk/packages/dragon_charts_flutter
  dragon_logs:
    path: sdk/packages/dragon_logs
  komodo_cex_market_data:
    path: sdk/packages/komodo_cex_market_data
  komodo_coin_updates:
    path: sdk/packages/komodo_coin_updates
  komodo_coins:
    path: sdk/packages/komodo_coins
  komodo_defi_framework:
    path: sdk/packages/komodo_defi_framework
  komodo_defi_local_auth:
    path: sdk/packages/komodo_defi_local_auth
  komodo_defi_rpc_methods:
    path: sdk/packages/komodo_defi_rpc_methods
  komodo_defi_sdk:
    path: sdk/packages/komodo_defi_sdk
  komodo_defi_types:
    path: sdk/packages/komodo_defi_types
  komodo_ui:
    path: sdk/packages/komodo_ui
  komodo_wallet_build_transformer:
    path: sdk/packages/komodo_wallet_build_transformer
```

If the consumer also imports the migration, harness, symbol-converter or CLI
packages, add their paths from this checkout as well. Resolve the consumer,
review its lockfile changes, then run its gates before committing its SDK
gitlink and dependency files. Do not use a floating `dev` reference or
`submodule update --remote` to select release contents.

## Wallet identity and authentication

Metadata setters and atomic updates require `expectedWalletId`, captured from
the authenticated user before the operation starts. Carry it across prompts,
awaits and rollbacks. Both expected and current identities must have a verified
public-key hash; a wallet name alone is insufficient. A stale or unverifiable
write throws `WalletChangedDisconnectException` before transformation or
persistence. Abort that operation instead of retrying against the new wallet.

See the [metadata-write migration](../packages/komodo_defi_local_auth/README.md#migrating-metadata-writes)
for a complete example. Custom authentication implementations and test doubles
must also implement the synchronous generation and transition contract described
in the [authentication lifecycle migration](../packages/komodo_defi_local_auth/README.md#migrating-authentication-lifecycle).
Auth transitions revoke export capabilities before asynchronous work continues,
even when the transition returns to the same wallet. Keep the SDK's serialized
transition behavior when adapting a custom auth implementation.

## Diagnostic storage lifecycle

`LogStorage.init`, `LoggerInterface.init` and `DragonLogs.init` accept
`storageNamespace` and `purgeLegacy`; storage and logger interfaces now require
`dispose`. `FileLogStorage` instances are independent. Await initialization
before logging, clearing or exporting, handle initialization failure, and await
disposal before selecting another namespace. Custom implementations must follow
the same lifecycle.

Select a versioned namespace for sanitized diagnostics and purge legacy storage
before new records are accepted. `DragonLogs.writeRecord` accepts one JSON
object per line; **the caller must sanitize it**. Existing `log()` calls retain
their format and are not a privacy boundary. The SDK/framework diagnostic paths
emit sanitized metadata and omit RPC/configuration/response/exception bodies.

Clearing logs also clears cached exports, while active exports keep their
snapshot/share file until consumption, cancellation or sharing completes.
Native export ownership is shared across storage instances **in one Dart
isolate**, using canonical directory paths. It survives storage disposal.
Disk locks serialize storage operations, but export retention is not a lease
across isolates or processes: keep native export and export-cache cleanup in
the same isolate. Browser writes and migration require Web Locks and fail
closed when unavailable. Older clients can recreate legacy records; close them
to complete migration. Files already downloaded or shared cannot be revoked.

See [Dragon Logs migration guidance](../packages/dragon_logs/README.md#migrating-to-sanitized-diagnostic-records).

## Private-key export coverage

Use `SecurityManager.exportPrivateKeys` and inspect every asset's outcome and
coverage. Preserve unavailable outcomes and the reported account/range in the
consumer UI and exported manifest. Do not describe a successful subset as a
complete wallet backup.

| Coverage | Meaning |
| --- | --- |
| `offlineHdRange` | The explicitly reported HD account/range, not all accounts or addresses. |
| `offlineAccount` | The reported shielded account, including supported shielded key metadata. |
| `legacyWallet` | The supported asset's legacy key. |

TRON/TRC20 private-key export is temporarily unsupported until KDF implements
`get_private_keys` for TRON. Structured export reports `unsupportedProtocol`
for each requested TRON/TRC20 asset and continues exporting supported assets.
The strict `getPrivateKeys` API rejects selections containing these protocols
before issuing an RPC. This applies to activated and inactive assets, legacy
and HD wallets, and every address index. Consumer apps must disable TRON/TRC20
private-key display and export, including older backup paths.

The temporary `show_priv_key` and `account_balance_read` wrappers, private-key
address derivation and HD metadata searches have been removed. Consumers of
this unreleased API must also remove `allowTronActiveKey`, `activeAddressOnly`,
`hasLimitedCoverage`, `limited_coverage`, `signingAssetId` and the TRON-only
failure categories. Exported keys are attributed directly to the requested
asset. SIA export remains unsupported; hardware-wallet secrets are not
exportable.

An export session belongs to the verified wallet, authentication generation and
issuing manager. Retain it through the operation and recheck it immediately
before presenting or sharing sensitive output. An authentication transition
invalidates pending results even when the wallet name stays the same.

## Earlier migrations included in this release

Consumers upgrading from the last SDK tag also need the changes documented in
the historical package entries: `BatchActivationProgress` was replaced by
per-asset activation state; GasFree uses activation-time configuration, typed
account status and journal/trace recovery; maximum withdrawals omit `amount`;
SIA uses its hardened RPC namespace; filtered assets are immutable snapshots.
Preserve unknown GasFree submission outcomes for explicit recovery and do not
resubmit them automatically. Provider outages must not erase recovery state.

The current KDF contract and artefacts are pinned in the release checklist.
This release does not add a new KDF/coins roll or broaden native/browser
validation beyond the checks recorded there.
