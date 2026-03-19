import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Interface for custom token storage operations
abstract class CustomTokenStore {
  /// Initializes/opens the underlying storage if required.
  Future<void> init();

  /// Stores a single custom token.
  /// If a token with the same storage key already exists, it is overwritten
  /// only when it represents the same contract on the same network.
  /// Otherwise, [CustomTokenConflictException] is thrown.
  Future<void> storeCustomToken(Asset asset);

  /// Stores multiple custom tokens atomically (all-or-nothing).
  /// Existing tokens with the same storage key are overwritten only when they
  /// represent the same contract on the same network.
  /// Otherwise, [CustomTokenConflictException] is thrown.
  /// Implementations should throw on partial failure.
  Future<void> storeCustomTokens(List<Asset> assets);

  /// Retrieves all custom tokens from storage.
  /// Returns an empty list if none.
  /// Implementations should return a deterministic order (e.g., sorted by AssetId).
  Future<List<Asset>> getAllCustomTokens(Set<AssetId> knownIds);

  /// Retrieves a single custom token by its AssetId.
  /// Returns null if the token is not found.
  Future<Asset?> getCustomToken(AssetId assetId);

  /// Checks if a custom token exists in storage.
  Future<bool> hasCustomToken(AssetId assetId);

  /// Deletes a single custom token by its AssetId. Returns true if a token was deleted.
  Future<bool> deleteCustomToken(AssetId assetId);

  /// Deletes multiple custom tokens by their AssetIds. Returns number of tokens deleted.
  Future<int> deleteCustomTokens(List<AssetId> assetIds);

  /// Deletes all custom tokens from storage.
  Future<void> deleteAllCustomTokens();

  /// Returns true if any custom tokens are stored.
  Future<bool> hasCustomTokens();

  /// Upserts a custom token: updates if it exists, inserts otherwise.
  /// Returns true if updated, false if inserted. Throws
  /// [CustomTokenConflictException] for same-key different-contract writes.
  Future<bool> upsertCustomToken(Asset asset);

  /// Adds a custom token to storage if it doesn't already exist.
  /// Returns true if the token was added, false if the same contract already
  /// existed. Throws [CustomTokenConflictException] for same-key
  /// different-contract writes.
  Future<bool> addCustomTokenIfNotExists(Asset asset);

  /// Returns the number of custom tokens in storage.
  Future<int> getCustomTokenCount();

  /// Closes the storage and releases resources.
  /// Must be idempotent and safe to call multiple times.
  /// Should complete after in-flight operations finish or are safely cancelled.
  Future<void> dispose();
}
