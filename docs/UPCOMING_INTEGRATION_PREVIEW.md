# Upcoming SDK integration preview

This branch combines the active post-0.10.0 SDK feature stack for the wallet's
early preview. It targets `dev` and preserves the original feature PRs for
focused review.

| Source | Included commit |
| --- | --- |
| Flutter 3.50 / Dart 3.14, SDK #447 | `b61f1759ea1010ed8be7f0b436a585a02e4d65a5` |
| Audited authentication, SDK #445 | `cbe1eb6f82751db0425256fb36e23a45109389fc` |
| Audited Solana, SDK #444 | `dafadbeff1ac1d07c49d01d02c1acaedeb343b06` |
| Audited pricing, SDK #443 | `938d4d52eb3d4f5fe0684a7cc2a4aa3f61f38a98` |

All four source branches are ancestors of this integration. The application
pins the resulting integration commit, rather than selecting one feature's
SDK and omitting the others.

Merge decisions retain Flutter 3.50's locked workspace setup, the private
Firebase deployment wrapper, bounded package suites, the auth dispatch/session
guards, durable Solana intent revisions and pricing fallback/cooldown behavior.
The fee union was regenerated from its merged model source. Older source files
were formatted with Dart 3.14.

Local combined-tree validation:

- Core SDK: 1,324 passed, one existing skip.
- Local authentication: 196 passed.
- Market data: 374 passed, six opt-in live-provider skips.
- Deployment privacy: 27 passed; preview-URL parser: eight fixtures passed.

The package tests used cached assets, with the source coin-config fixture
available to authentication tests. Separate native asset generation must run
serially: concurrent transformers share framework output paths. Complete
package, WebAssembly, preview and native packaging checks are also required
on the published integration head; their final results are recorded in the PR.

The production KDF/catalog pins and capability gates remain in effect. An
integration preview does not satisfy SDK merge/repin, physical credential,
trusted signing, funded Solana/swap, uncertain-signature, combined artifact,
bot policy or historical-log/credential review gates. No release promotion is
performed by this branch.
