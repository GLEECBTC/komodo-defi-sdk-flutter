## Tech Debt Report: Market Data Price Streaming

### Context

- Current `MarketDataManager` APIs are request/response based.
- `priceIfKnown` is used as a read-only cache accessor by wallet totals.
- A recent stability fix keeps a last-known current-price cache to prevent
  transient null windows when live cache rotates.
- Native streaming is still missing in `MarketDataManager` (explicit TODO in
  `market_data_manager.dart`).

### Problem

- The app has no first-class SDK stream for fiat price updates.
- Existing app-level polling helpers are not SDK-owned contracts and are not
  consistently used across features.
- Consumers must combine periodic fetches with cache reads, which duplicates
  refresh logic in the app layer.

### Target Design

- Add native streaming support to `MarketDataManager`:
  - `Stream<Decimal?> watchFiatPrice(AssetId assetId, {QuoteCurrency quoteCurrency = Stablecoin.usdt, Duration refreshInterval = const Duration(minutes: 1)})`
  - Optional multi-asset API for aggregate screens:
    - `Stream<Map<AssetId, Decimal?>> watchFiatPrices(Iterable<AssetId> assetIds, {QuoteCurrency quoteCurrency = Stablecoin.usdt, Duration refreshInterval = const Duration(minutes: 1)})`
- Stream contract:
  - Emit immediately with last-known value (or null if none).
  - Refresh on interval using existing repository fallback logic.
  - Keep last successful value on transient provider failures.
  - Avoid duplicate requests for identical active watch keys.

### Migration Plan

1. SDK phase:
   - Implement stream APIs in `MarketDataManager` and `CexMarketDataManager`.
   - Reuse existing cache keys and fallback selection strategy.
   - Add cancellation-safe watcher bookkeeping and deduplication.
2. App phase:
   - Migrate wallet total displays to stream-driven updates.
   - Remove app-side price polling helpers once no longer used.
3. Cleanup phase:
   - Re-evaluate cache timer responsibilities when stream lifecycle is in place.
   - Keep `priceIfKnown` as synchronous access for non-reactive callers.

### Testing Requirements

- SDK unit tests:
  - initial stream emission from cache,
  - periodic refresh emission,
  - fallback behavior on repository failures,
  - watcher deduplication and resource cleanup.
- App integration tests:
  - wallet total remains stable during provider failures,
  - totals update when stream delivers new prices.

### Suggested Conventional Commits

- `feat(market-data): add native fiat price watch streams to MarketDataManager`
- `refactor(wallet): consume sdk price streams for wallet totals`
- `chore(wallet): remove legacy app-side fiat polling helper`
