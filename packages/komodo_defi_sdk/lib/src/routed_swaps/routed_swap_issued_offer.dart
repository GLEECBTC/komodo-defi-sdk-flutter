part of 'routed_swap_manager.dart';

/// Execution authority stays in the manager's library. Public display offers
/// cannot acquire it, and copies retain the original issuer and session.
final class _IssuedRoutedSwapOffer extends RoutedSwapOffer {
  _IssuedRoutedSwapOffer(
    RoutedSwapOffer offer, {
    required this.owner,
    required this.session,
  }) : super(
         from: offer.from,
         to: offer.to,
         sellAmount: offer.sellAmount,
         expectedReceive: offer.expectedReceive,
         guaranteedReceive: offer.guaranteedReceive,
         kind: offer.kind,
         costs: offer.costs,
         networkFees: offer.networkFees,
         legs: offer.legs,
         quotedAt: offer.quotedAt,
         provider: offer.provider,
         toolKey: offer.toolKey,
         toolName: offer.toolName,
         route: offer.route,
         order: offer.order,
         fromAddress: offer.fromAddress,
         toAddress: offer.toAddress,
         approval: offer.approval,
         toolLogoUrl: offer.toolLogoUrl,
         estimatedDuration: offer.estimatedDuration,
         slippage: offer.slippage,
       );

  final Object owner;
  final AuthSessionContext session;

  @override
  RoutedSwapOffer copyWith({DateTime? quotedAt}) => _IssuedRoutedSwapOffer(
    super.copyWith(quotedAt: quotedAt),
    owner: owner,
    session: session,
  );

  @override
  RoutedSwapOffer? keepingMinimum(Decimal minimum) {
    final kept = super.keepingMinimum(minimum);
    if (kept == null || identical(kept, this)) return kept;
    return _IssuedRoutedSwapOffer(kept, owner: owner, session: session);
  }
}
