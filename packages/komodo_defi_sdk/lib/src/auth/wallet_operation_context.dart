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

/// Compares the stable identity when either side has one.
///
/// A missing hash on one side is deliberately not treated as equal to a full
/// identity: doing so could let a name-only login race reuse another wallet's
/// in-flight result. Name comparison is retained only for legacy/test wallets
/// where neither side has acquired a public-key hash yet.
bool isSameStableWallet(WalletId left, WalletId right) {
  final leftHash = left.pubkeyHash?.trim();
  final rightHash = right.pubkeyHash?.trim();
  final hasStableIdentity =
      (leftHash != null && leftHash.isNotEmpty) ||
      (rightHash != null && rightHash.isNotEmpty);
  if (hasStableIdentity) {
    return leftHash != null &&
        leftHash.isNotEmpty &&
        rightHash != null &&
        rightHash.isNotEmpty &&
        leftHash == rightHash;
  }
  return left.isSameAs(right);
}
