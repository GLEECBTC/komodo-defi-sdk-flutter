# SDK 0.9.0: changes accepted after the RC opened

Snapshot: **4 November 2026**. This records accepted content, not a new
version, tag, publication, main promotion or test execution.

## Exact range

- Release PR [#416](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/416)
  opened on 28 October at 18:50:51 UTC with head
  `22e14ac94fb555776eda370de08f1dafd5ca4019`. Its first Actions runs use that
  exact SHA, independently confirming the initial boundary.
- Audited accepted RC: `bb5b4187bf49f844c01672799b451b50a5b08808`.
- [Complete post-opening comparison](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/compare/22e14ac94fb555776eda370de08f1dafd5ca4019...bb5b4187bf49f844c01672799b451b50a5b08808).
  The range contains **24 non-merge commits**, including source-branch
  preparation commits reachable through the ten accepted carries below.
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
| [#437](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/437) / [#438](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/438) | Bounded, engine-only dispatch lease (10 s) and transport resets that wait for it; the local executable's reset aborts pending requests and its stop gives up after 5 s; a failed stop still resets; offers compare by their numbers. Root, `komodo_defi_local_auth`, `komodo_defi_framework` and `komodo_defi_sdk` changelogs and the migration guide. |
| [#439](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/439) / [#440](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/440) | Final coins roll `efd3a647` → `cc8249e8`: Yenten (YTN), L2 fee models for AVAX, ETH-BASE, MNT and MON, and signature versions that restate KDF's defaults; no coin removed. Root and `komodo_defi_framework` changelogs, migration guide and checklist. |
| [#434](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/434) / [#435](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/435) | Build-log privacy: failed GitHub API requests report whether authentication was used without printing authorization headers. Root and `komodo_wallet_build_transformer` changelogs. |

Git author names `CharlVS` and `Nitride` in this range resolve to **@CharlVS**;
source and carry PR author metadata was checked. Existing initial-RC features
and older published-release entries remain in the changelog without being
repeated as new post-opening changes.

## Current qualification and pending work

Accepted SDK #430 squash is `db73613cd34a2c0779da024a71338052e4bbb030`;
normal carry #431 is `3b4629048d8513af8f8a9d17a5cdf7eb5763d206`. Session
follow-up #437 was squash accepted as `34dd5febb45193c7c66b649b89b68ef3d90f3675`
and normal carry #438 is `ad1799272121c18c7391287b9744247f89c04e44`. The final
coins roll #439 was squash accepted as `ab29d57aa05aa48240ab7430c6d51a4f5e60a579`
and normal carry #440 is `7636f554c77b0d4bfa02d20dc030f1a95596a755`. Logging carry #435 is the
audited frozen head above; its tree equals the carry head
`caab72b973c3fa74a4b6a11a663e4e67798023e1` that the app RC pins. The complete accepted
trees matched their tested candidates. Saved qualification includes 16 SDK
suites (**3,112 passed /14 skipped**), browser/WASM **249 +10 +10**, offline
bootstrap/repeated generation, seven independently checked archives and a
fresh-unfunded native smoke. Exact input/results and original failures with
passing retries are in [3 November provenance](KDF_ARTIFACTS_2026-11-03.json).
No KDF repository tests were run for this documentation audit.

Accepted development logging fix [#434](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/434)
reached the RC through normal carry [#435](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/435)
(`bb5b4187bf49f844c01672799b451b50a5b08808`); no SDK carry is pending at this snapshot.

Main release #416 remains open. Final review/checks, the consumer's eventual
main-commit pin, signed consumer install/upgrade evidence and any publication
steps retain their separate gates. A passing older input does not qualify a
later head; older failed inputs do not replace this pin's passing results.
