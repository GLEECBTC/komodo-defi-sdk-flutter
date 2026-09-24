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

/// Whether [current] is an identity-RPC *degradation* of [previous] rather
/// than a different wallet.
///
/// `KdfAuthService._ensureAuthenticatedWalletIdentity` deliberately returns a
/// name-only [WalletId] when the `get_public_key_hash` RPC is unavailable, so
/// that wallet-scoped secrets stay locked until the active identity has been
/// verified in this session. That is correct for authorisation - but it means
/// an already-authenticated session can transiently observe its own wallet
/// without a `pubkeyHash`, which [isSameStableWallet] rejects by design.
///
/// Managers that use the wallet identity only to *scope caches* must not read
/// that rejection as a wallet switch and throw away their state: a real switch
/// always passes through a `null` user first (KDF is stopped for the outgoing
/// wallet), so a same-name, same-options observation within a live session is
/// the same wallet.
///
/// Returns false for anything else, including a name change, a hash change, or
/// a derivation/private-key policy change.
bool isDegradedWalletIdentity(WalletId previous, WalletId current) {
  final previousHash = previous.pubkeyHash?.trim();
  if (previousHash == null || previousHash.isEmpty) return false;

  final currentHash = current.pubkeyHash?.trim();
  if (currentHash != null && currentHash.isNotEmpty) return false;

  return previous.authOptions.derivationMethod ==
          current.authOptions.derivationMethod &&
      previous.authOptions.privKeyPolicy == current.authOptions.privKeyPolicy &&
      previous.name == current.name;
}

/// Whether an operation captured under [previous] may continue when the
/// freshly observed identity is [current].
///
/// True for the same stable wallet, and for a transient identity-RPC
/// degradation of it ([isDegradedWalletIdentity]). The capture paths already
/// tolerate a degraded observation and keep the enriched identity, so the
/// post-await guards must extend the same tolerance - otherwise an operation
/// admitted under a degraded identity dies at its first checkpoint, during
/// the exact blip the tolerance exists for. A real wallet switch still fails
/// this check: it always passes through a `null` user or a different
/// name/hash/options first.
///
/// Asymmetric like [isSameStableWallet]: pass the previously accepted
/// identity first and the newly observed identity second.
bool walletIdentityContinuesSession(WalletId previous, WalletId current) =>
    isSameStableWallet(previous, current) ||
    isDegradedWalletIdentity(previous, current);

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
