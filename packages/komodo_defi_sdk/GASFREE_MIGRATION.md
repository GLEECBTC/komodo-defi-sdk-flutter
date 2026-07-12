# GasFree SDK 1.0 migration

GasFree is disabled unless both `tronGaslessProvider` and an explicit
`tronGaslessAssetIds` allowlist are configured. Only built-in TRC-20 assets in
that set can become eligible, and eligibility becomes ready only after KDF
confirms the custody account at runtime.

Production provider configuration must use `GaslessServiceKomodoProxy`, HTTPS,
and a pinned `serviceProvider`. Provider discovery, direct HMAC credentials,
and plain HTTP each require their explicit unsafe flag and are rejected by a
release build.

Withdrawal callers must inspect `WithdrawalProgress.submission`:

- `WithdrawalSubmission.onChain` has an immediate `txHash`.
- `WithdrawalSubmission.gaslessRelay` has a `requestId` and `traceId`; the
  on-chain hash is not available until confirmation.
- A submitted/unknown GasFree state is not a retry signal. Keep it in activity
  and call `resumePendingGaslessTransfer` or
  `reconcilePendingGaslessTransfers` after connectivity or login returns.

The SDK stores unresolved GasFree transfers in encrypted, wallet-scoped,
versioned storage. Wallet login starts status-only reconciliation; logout and
wallet switching stop polling but never delete these records or resubmit a
payload. Legacy pubkey caches are migrated conservatively: every retained
address is considered previously used so empty historical addresses are not
silently hidden. Secondary addresses are always Standard/recovery sources;
only the canonical primary may advertise the GasFree custody receive address.

Pending storage now records `GaslessVerificationMode`. Bound KDF responses use
`boundRelay`. KDF PR #9 previews and relay responses use `legacyOnChain`: the
SDK first keeps capability provisional, then proves the configured provider and
wallet identity from the signed preview without changing or persisting that
preview. Legacy mode is limited to sending/recovering funds already held in
custody; `KomodoDefiSdk.canReceiveGasless` remains false. New custody receives
require `boundRelay`. At execution the SDK keeps PR #9's strict `tx_json`
unchanged, creates a local UUID and deterministic payload fingerprint before
submission, and does not confirm or delete the journal record until a raw
TRONGrid event matches the hash, enrolled token, custody source, recipient,
signed base-unit amount, and fee ceiling. Existing records without a mode
migrate to `legacyOnChain` and are never silently discarded.

`WithdrawalResult.txHash` is nullable until relay finality. Receipts should use
`FeeInfoTronGasless.finalFee` for the authoritative charged fee while retaining
`totalTokenFee` (preview) and `signedMaxFee` (authorization ceiling), plus
`confirmationBlockHeight` and `confirmedAt` when available.

Use `BalanceManager.getGaslessBalanceSnapshot` when a surface needs portfolio
ownership across both rails. Its custody totals, Standard balances, freshness,
and provenance must remain distinct; do not substitute an EOA balance when a
custody lookup fails.

GasFree account status now requires explicit custody-balance and provider-
availability provenance. After a restart or kill switch, retained canonical
custody metadata uses a provider-independent mainnet/Nile TRONGrid balance read
for recovery; it never enables spendability or substitutes an EOA balance.

Android arm64 and armv7 KDF artifacts for the pending hardened KDF commit are
not published. Keep builds pinned to the last fetchable full KDF SHA until
immutable native/WASM artifacts and checksums are promoted.
