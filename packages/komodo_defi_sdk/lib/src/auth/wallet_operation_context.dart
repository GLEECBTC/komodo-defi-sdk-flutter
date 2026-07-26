import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Captures the authenticated wallet and manager generation at the start of an
/// asynchronous operation.
///
/// Managers increment their generation as soon as authentication changes. A
/// result fetched for an older generation must never populate a cache, emit to
/// a new wallet's stream, or be written under a newly resolved wallet ID.
final class WalletOperationContext {
  /// Creates a token for one authenticated wallet generation.
  const WalletOperationContext({
    required this.walletId,
    required this.generation,
  });

  /// Stable wallet identity captured before the asynchronous work starts.
  final WalletId walletId;

  /// Manager generation captured with [walletId].
  final int generation;
}

/// Checks whether [current] can safely continue the [previous] wallet session.
///
/// Once both identities have a public-key hash, the hash remains stable across
/// wallet renames. During the name-only to enriched transition, the wallet name
/// is the only available compatibility key. The reverse transition is
/// deliberately rejected: losing an established hash must advance the owning
/// manager's generation before any later same-name identity is accepted.
///
/// Derivation and private-key policy must match so an operation or cache cannot
/// cross address or signing modes. Password-strength acceptance is not wallet
/// identity and may change between sign-ins without invalidating wallet-scoped
/// state.
///
/// This comparison is intentionally asymmetric. Callers must pass the
/// previously accepted identity first and the newly observed identity second.
bool isSameStableWallet(WalletId previous, WalletId current) {
  if (previous.authOptions.derivationMethod !=
          current.authOptions.derivationMethod ||
      previous.authOptions.privKeyPolicy != current.authOptions.privKeyPolicy) {
    return false;
  }

  final previousHash = previous.pubkeyHash?.trim();
  final currentHash = current.pubkeyHash?.trim();
  final normalizedPreviousHash = previousHash == null || previousHash.isEmpty
      ? null
      : previousHash.toLowerCase();
  final normalizedCurrentHash = currentHash == null || currentHash.isEmpty
      ? null
      : currentHash.toLowerCase();

  if (normalizedPreviousHash != null) {
    return normalizedCurrentHash != null &&
        normalizedPreviousHash == normalizedCurrentHash;
  }

  return previous.name == current.name;
}

/// Accepts [current] as the latest compatible wallet identity.
///
/// A name-only identity may be enriched, but an enriched identity may never be
/// downgraded. Callers must pass the previously accepted identity first.
WalletId preferEnrichedWalletIdentity(WalletId previous, WalletId current) {
  if (!isSameStableWallet(previous, current)) {
    throw ArgumentError.value(
      current,
      'current',
      'Wallet identities are not compatible',
    );
  }
  return current;
}
