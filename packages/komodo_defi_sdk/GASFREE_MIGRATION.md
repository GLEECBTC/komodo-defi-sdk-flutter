# GasFree SDK 1.0 migration

SDK 1.0 implements the GasFree contract from KDF
`bd413dcfea73c9de2e85903323946a378b180fa7`. Runtime configuration,
legacy V0/V1 relay modes, locally invented request/fingerprint fields, and
external TRONGrid finality or custody readers are no longer supported.

## Activation

Supply `tronGaslessProvider` before TRX activation. The SDK serializes only
`base_url`, `service`, optional `service_provider`, `request_timeout_ms`, and
`status_poll_interval_ms`. Generic SDK clients may omit `service_provider` for
KDF discovery; production applications should provide and verify a pin.

GasFree token enrollment comes from the activated TRC20 configuration:

```json
{
  "gasless": {
    "enabled": true,
    "transfer_max_fee": "5"
  }
}
```

An explicit `tronGaslessAssetIds` set may still opt in assets whose
configuration does not yet contain a `gasless` object. It is an application
rollout gate, not an SDK-owned token registry, and cannot override an explicit
`gasless.enabled: false`. The provider is installed during ordinary TRX
activation even when TRX is activated before an enrolled token. An
already-active platform that was started without the provider must be
reactivated under application control; there is no runtime configure RPC.

Trezor remains excluded. Application network, contract, token, derivation,
provider-pin, build-switch, and remote-switch policies remain additional
requirements above the generic SDK.

## Account status and balances

`gaslessAccountStatus` returns a typed `GaslessAccountStatusResponse` whose
`availability` is required:

- `available`: provider identity, activity, balances, transfer fee, and maximum
  are present; the optional activation fee may be absent.
- `pending_transfer`: provider, balances, locks, and fee remain visible, but a
  new GasFree send is blocked.
- `token_unsupported`: provider identity remains visible while provider balance
  and fee fields are absent.
- `provider_unreachable`: the fresh KDF on-chain custody total remains visible;
  provider identity, spendability, and fee fields are absent.

Provider identity must continue to equal the activation/session identity after
discovery. `ProviderIdentityMismatch`, `GasfreeAddressMismatch`, and
`TokenDecimalMismatch` are exposed as typed GasFree errors. Do not parse error
messages or infer availability from missing legacy fields.

`GaslessAccountStatusResponse` is the custody source; `BalanceManager` continues
to report ordinary Standard-address balances. Product rail view models may show
both, but must keep the fresh custody total, provider-backed spendability, and
Standard balances separate. Provider failure must never turn an EOA balance
into a custody balance.

## Withdrawal and rail selection

A GasFree withdrawal uses `fee_method: "gasless"` with `max_fee`,
`deadline_seconds`, and `fallback_to_native`. A maximum withdrawal sets
`max: true` and omits `amount`.

Generic clients may request native fallback and must inspect
`WithdrawalProgress.submission` for the actual rail:

- `WithdrawalSubmission.onChain` contains an immediate transaction hash.
- `WithdrawalSubmission.gaslessRelay` contains KDF's accepted `traceId` and the
  local `journalId`.
- `WithdrawalSubmission.gaslessUnknown` contains only the local `journalId` and
  must not be resubmitted blindly.

The Gleec production application requests `fallback_to_native: false` and treats
an unexpected Standard result as a rail mismatch. The signed relay payload and
submission response contain only KDF's documented fields. `journalId` is a
local reservation identity and is never serialized to KDF.

`FeeInfoTronGasless` contains preview data only. Receipts obtain the
authoritative final fee, transaction hash, block height, and finality from
GasFree trace status.

## Trace tracking and persistence

Before submitting a relay, the SDK enables the coin-level GasFree trace stream.
After KDF accepts the relay, the SDK persists its `trace_id`, immediately calls
`gasless::trace_status` once, and then follows `GASLESS_TRACE:<coin>` and
`ERROR:GASLESS_TRACE:<coin>` events filtered by coin and trace ID.

The encrypted journal remains wallet-scoped and is reserved before submission.
Restart or stream-disconnection recovery performs one authoritative trace-status
reconciliation; it does not start arbitrary client polling or resubmit a relay.
Accepted legacy records that contain a trace ID migrate into trace recovery.
Records without a trace ID remain `submissionOutcomeUnknown`, stay
non-resubmittable, and never retain signed authorization material.

Wallet switching invalidates in-flight probes, stream observations, and cached
capability state. Recovery, consolidation, Standard TRON withdrawals, custody
history refresh, and duplicate-send protection remain available under their
existing product policies.

## KDF artifacts

All seven native/WASM targets are available for commit
`bd413dcfea73c9de2e85903323946a378b180fa7`, including Android arm64 and armv7.
Build markers and configured archive hashes must identify that full commit and
a non-empty extracted-core digest. The aggregate mirror `SHA256SUMS` is stale;
use updater-computed hashes and the individual sidecars.
