# SDK 0.9.0: changes accepted after the RC opened

Snapshot: **4 November 2026**. This records accepted content, not a new
version, tag, publication, main promotion or test execution.

## Exact range

- Release PR [#416](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/416)
  opened on 28 October at 18:50:51 UTC with head
  `22e14ac94fb555776eda370de08f1dafd5ca4019`. Its first Actions runs use that
  exact SHA, independently confirming the initial boundary.
- Audited accepted RC: `3b4629048d8513af8f8a9d17a5cdf7eb5763d206`.
- [Complete post-opening comparison](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/compare/22e14ac94fb555776eda370de08f1dafd5ca4019...3b4629048d8513af8f8a9d17a5cdf7eb5763d206).
  The range contains **14 non-merge commits**, including source-branch
  preparation commits reachable through the seven accepted carries below.
  Repeated preparations and their accepted merge are one change, not two features.

## Coverage

| Accepted source / RC carry | Change and changelog disposition |
| --- | --- |
| [#417](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/417) / [#418](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/418) | Follow every in-flight recovery page; reject the complete read if wallet ownership changes. Root and `komodo_defi_sdk` 0.9.0 notes now both cover it. |
| [#419](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/419) / [#420](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/420) | Interim `e40ac2f` engine roll, including its duplicate preparation and dated CI-disposition records. Superseded by #431; keep the 29 October artifact record as history rather than a current pin or current failure disposition. |
| [#422](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/422) / [#423](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/423) | Clarify routed availability, consumer-owned consent, commission configuration and hardware limits. Retained in root limits and migration guidance; this did not add another runtime feature. |
| [#424](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/424) / [#425](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/425) | Trezor orphan-file recovery, case-insensitive names, placeholder-policy rollback, retry of known wallets, remembered fallback names and successful initialization/active-user requirements. Root and local-auth 0.7.0 notes cover the complete correction. |
| [#426](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/426) / [#427](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/427) | Manager/session-issued routed offers, private issuance retained by supported copies, session-leased dispatch and revocable `beforeDispatch`. Root, SDK 0.9.0 and local-auth 0.7.0 notes cover it, including the custom-auth migration. |
| [#428](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/428) / [#429](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/429) | Complete native/WASM auth-transition regressions and fixtures. Recorded as testing coverage, not another runtime feature. |
| [#430](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/430) / [#431](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/431) | Validated `a51d69a` engine and `efd3a647` coin inputs, checksum/provenance and release records. Root, framework 0.7.0 and coin 0.5.0 notes now describe the final frozen inputs instead of the superseded preparation pins. |

Git author names `CharlVS` and `Nitride` in this range resolve to **@CharlVS**;
source and carry PR author metadata was checked. Existing initial-RC features
and older published-release entries remain in the changelog without being
repeated as new post-opening changes.

## Current qualification and pending work

Accepted SDK #430 squash is `db73613cd34a2c0779da024a71338052e4bbb030`;
normal carry #431 is the audited frozen head above. The complete accepted
trees matched their tested candidates. Saved qualification includes 16 SDK
suites (**3,112 passed /14 skipped**), browser/WASM **249 +10 +10**, offline
bootstrap/repeated generation, seven independently checked archives and a
fresh-unfunded native smoke. Exact input/results and original failures with
passing retries are in [3 November provenance](KDF_ARTIFACTS_2026-11-03.json).
No KDF repository tests were run for this documentation audit.

At this snapshot, accepted development logging fix
[#434](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/434) still awaits
normal RC carry [#435](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/435).
It is not described here as an accepted RC change. Refresh the changelog,
coverage boundary and consumer pin after that carry actually completes.

Main release #416 remains open. Final review/checks, the consumer's eventual
main-commit pin, signed consumer install/upgrade evidence and any publication
steps retain their separate gates. A passing older input does not qualify a
later head; older failed inputs do not replace this pin's passing results.
