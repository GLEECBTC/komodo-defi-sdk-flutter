import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// How far an HD address scan walks past the last used address.
///
/// `gap_limit` is the BIP-44 **consecutive-empty** tolerance, not a count of
/// addresses to probe. KDF walks forward from `known_addresses_number`,
/// incrementing a counter on each unused address and **resetting it to zero on
/// each used one** (`mm2src/coins/lp_coins.rs:6448-6450`), stopping once the
/// counter exceeds the limit. So on an all-empty wallet a scan costs
/// `gap_limit + 1` probes, and on a wallet with history the limit decides how
/// long a run of unused addresses the scan will step over before giving up.
///
/// KDF's own docs state the consequence plainly: *"If transactions were sent to
/// an address outside the `gap_limit`, they will not be identified when
/// scanning."* Lowering it is therefore a trade of node requests against how
/// much of a restored wallet's history the app can still see - and the failure
/// is silent, showing a balance that is simply too low.
///
/// One probe is not one request. For an *unused* EVM address KDF issues
/// `eth_getTransactionCount`, then `eth_getBalance`, then one
/// `eth_call balanceOf` per ERC-20 registered on the platform coin
/// (`mm2src/coins/eth/eth_hd_wallet.rs:125-150`). The nonce short-circuit only
/// fires on addresses that *are* used, so a gap walk over empty addresses pays
/// the full price every time: GLEEC with six GRC-20 tokens costs 8 requests per
/// probe, so 21 probes is 168 requests against an endpoint measured at ~20/s.
abstract final class HdGapLimit {
  /// Hardware wallets keep the full BIP-44 gap.
  ///
  /// A hardware wallet's seed is expected to have been used by other software -
  /// Trezor Suite, Ledger Live, another wallet - which is exactly the case a
  /// short gap loses. It is also the case where the user cannot simply re-derive
  /// the addresses to check, so a missed balance looks like missing funds.
  static const int hardware = 20;

  /// Software wallets after their first sign-in.
  ///
  /// Deliberately below the BIP-44 standard of 20. This is a product decision:
  /// it removes 17 of every 21 probes from the scan, and accepts that a wallet
  /// whose history contains a run of more than three consecutive unused
  /// addresses will not have anything past that run discovered.
  static const int software = 3;

  /// A software wallet that this session generated, on its first sign-in.
  ///
  /// Safe at 1 because the wallet provably has no on-chain history: the seed
  /// was created moments ago and no address beyond the first can have been
  /// funded. Nothing is given up here, and it is the largest single saving on
  /// the first-login burst.
  static const int newlyGeneratedFirstSignIn = 1;

  /// The gap limit for a wallet with [privKeyPolicy].
  ///
  /// [isNewlyGeneratedFirstSignIn] must mean *this SDK session created the
  /// wallet without an imported mnemonic* - not merely that the wallet was
  /// generated at some point. A restored wallet, or a later sign-in of a
  /// generated one, can legitimately have history the scan needs to find.
  static int resolve({
    required PrivateKeyPolicy privKeyPolicy,
    required bool isNewlyGeneratedFirstSignIn,
  }) {
    if (privKeyPolicy == const PrivateKeyPolicy.trezor()) return hardware;
    return isNewlyGeneratedFirstSignIn ? newlyGeneratedFirstSignIn : software;
  }
}
