# FAQ and troubleshooting

## Why do I get rate limited by GitHub?

If you hit GitHub rate limits, prefer authenticating server-side (proxy the request) rather than embedding a token in the client.
For development or CI-only use, inject a token via environment or secure runtime configuration (never hardcode).  
Use least privilege:  

- Fine‑grained token with read‑only access to repository contents.  
- Restrict to the specific repo if possible.  
Rotate and revoke tokens regularly.  
Note: Public repositories do not require a token for read access, but authentication raises rate limits.

## The app crashes due to Hive adapter registration

Call `KomodoCoinUpdater.ensureInitialized(appStoragePath)` once at startup to
initialize Hive and register adapters. Duplicate registration is handled.

## Missing or empty assets list

- Ensure `updateCoinConfig()` has run at least once.
- Confirm the `coins_config_unfiltered.json` path is correct for your branch.
- Check logs from `CoinConfigRepository` at `Level.FINE` for details.

## Web cannot connect to Electrum servers

On web, only WSS Electrum is supported. The transform pipeline filters to WSS
only; ensure your target coins configure `ws_url` for WSS endpoints.

## How can I pin to a specific commit?

Pass that commit hash to `getAssetsForCommit(commit)` on the provider or set
`coinsRepoBranch` to the commit hash when creating the provider/repository.

## Can I use my own storage?

Yes. Implement `CoinConfigStorage` and pass your implementation where needed,
mirroring methods in `CoinConfigRepository`.
