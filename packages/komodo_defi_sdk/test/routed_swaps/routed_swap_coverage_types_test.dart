import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/routed_swaps/routed_swap_value.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

class _Twin with RoutedSwapValue {
  _Twin(this.props);

  @override
  final List<Object?> props;
}

RoutedSwapCost _cost({
  AssetId? assetId,
  String? symbol,
  String amount = '0.1',
  RoutedSwapCostKind kind = RoutedSwapCostKind.providerFee,
  bool deducted = false,
}) => RoutedSwapCost(
  label: 'Bridge fee',
  amount: d(amount),
  kind: kind,
  isDeductedFromReceive: deducted,
  assetId: assetId,
  symbol: symbol,
);

void main() {
  group('value equality', () {
    test('equal fields are equal with equal hashes; a change is not', () {
      // Parsed rather than const, so the two legs are distinct objects.
      final leg = RoutedSwapLeg(
        type: RoutedSwapStepType.parse('cross'),
        fromChainId: 1,
        toChainId: 137,
      );
      final twin = RoutedSwapLeg(
        type: RoutedSwapStepType.parse('cross'),
        fromChainId: 1,
        toChainId: 137,
      );
      expect(leg, twin);
      expect(leg.hashCode, twin.hashCode);
      expect(
        leg,
        isNot(
          const RoutedSwapLeg(
            type: RoutedSwapStepType.cross,
            fromChainId: 1,
            toChainId: 10,
          ),
        ),
      );
      expect(
        leg,
        isNot(const RoutedSwapLeg(type: RoutedSwapStepType.swap, chainId: 1)),
      );
    });

    test('the same fields on another type are not equal', () {
      final bounds = RoutedSwapAmountBounds(min: d('1'), max: d('2'));
      expect(bounds, isNot(_Twin([d('1'), d('2')])));
      expect(_Twin([d('1'), d('2')]), isNot(bounds));
      expect(_Twin([d('1'), d('2')]), _Twin([d('1'), d('2')]));
      expect(bounds, isNot(equals(Object())));
    });

    test('collections inside compare by content', () {
      RoutedSwapFailure failure(String reason) => RoutedSwapFailure(
        kind: RoutedSwapFailureKind.quoteUnavailable,
        errorType: 'NoRouteFound',
        message: 'No route found',
        fundsMovement: RoutedSwapFundsMovement.none,
        retryPolicy: RoutedSwapRetryPolicy.requote,
        details: {
          'reasons': [reason],
        },
        noRouteReasons: [reason],
      );
      expect(failure('no liquidity'), failure('no liquidity'));
      expect(
        failure('no liquidity').hashCode,
        failure('no liquidity').hashCode,
      );
      expect(failure('no liquidity'), isNot(failure('amount too low')));
    });
  });

  group('costs and fees', () {
    test('a cost is labelled by its asset, else by its provider symbol', () {
      expect(_cost(assetId: usdc, symbol: 'USDC').tokenLabel, 'USDC-ERC20');
      expect(_cost(symbol: 'axlUSDC').tokenLabel, 'axlUSDC');
      expect(_cost().tokenLabel, isEmpty);

      expect(_cost(symbol: 'axlUSDC'), _cost(symbol: 'axlUSDC'));
      expect(
        _cost(symbol: 'axlUSDC').hashCode,
        _cost(symbol: 'axlUSDC').hashCode,
      );
      expect(_cost(symbol: 'axlUSDC'), isNot(_cost(symbol: 'USDC')));
      expect(_cost(), isNot(_cost(deducted: true)));
    });

    test('fees, approvals and max-sell results compare by value', () {
      RoutedSwapNetworkFee fee([String? usd]) => RoutedSwapNetworkFee(
        ticker: 'ETH',
        assetId: eth,
        amount: d('0.01'),
        usdValue: usd == null ? null : d(usd),
      );
      expect(fee('20'), fee('20'));
      expect(fee('20').hashCode, fee('20').hashCode);
      expect(fee('20'), isNot(fee()));

      RoutedSwapApprovalInfo approval({required bool reset}) =>
          RoutedSwapApprovalInfo(
            txCount: reset ? 2 : 1,
            resetsFirst: reset,
            spender: '0xdiamond',
          );
      expect(approval(reset: true), approval(reset: true));
      expect(approval(reset: true).hashCode, approval(reset: true).hashCode);
      expect(approval(reset: true), isNot(approval(reset: false)));

      RoutedSwapMaxSell max(AssetId? feeAsset) => RoutedSwapMaxSell(
        amount: d('0.99'),
        reservedForFees: d('0.01'),
        feeAsset: feeAsset,
      );
      expect(max(eth), max(eth));
      expect(max(eth).hashCode, max(eth).hashCode);
      expect(max(eth), isNot(max(null)));
    });
  });

  group('an offer', () {
    test('only a known same-chain route skips the bridge wait', () {
      expect(
        offerOf(kind: RoutedSwapRouteKind.sameChain).isCrossChain,
        isFalse,
      );
      expect(offerOf().isCrossChain, isTrue);
      expect(offerOf(kind: RoutedSwapRouteKind.unknown).isCrossChain, isTrue);
    });

    test('says whether approval comes first, and what slippage risks', () {
      expect(offerOf().requiresApproval, isFalse);
      expect(
        offerOf(
          approval: const RoutedSwapApprovalInfo(
            txCount: 2,
            resetsFirst: true,
            spender: '0xdiamond',
          ),
        ).requiresApproval,
        isTrue,
      );
      expect(offerOf().slippageAllowance, d('0.5'));
    });

    test('goes stale a minute after pricing, or at a chosen age', () {
      final offer = offerOf();
      final at = offer.quotedAt;
      expect(offer.isStaleAt(at.add(const Duration(seconds: 59))), isFalse);
      expect(offer.isStaleAt(at.add(const Duration(seconds: 60))), isTrue);
      expect(
        offer.isStaleAt(
          at.add(const Duration(seconds: 10)),
          maxAge: const Duration(seconds: 10),
        ),
        isTrue,
      );
      expect(
        offer.isStaleAt(
          at.add(const Duration(seconds: 9)),
          maxAge: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(offer.isStaleAt(at.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('extra fees are provider fees charged on top, per token', () {
      final offer = offerOf(
        costs: [
          _cost(assetId: usdc),
          _cost(assetId: usdc, amount: '0.2'),
          _cost(assetId: usdc, amount: '0.05', deducted: true),
          _cost(symbol: 'axlUSDC', amount: '0.02'),
          _cost(assetId: eth, amount: '0.01', kind: RoutedSwapCostKind.gas),
          _cost(
            assetId: eth,
            amount: '0.001',
            kind: RoutedSwapCostKind.approvalGas,
          ),
        ],
      );
      expect(offer.additionalFeesByToken, {
        'USDC-ERC20': d('0.3'),
        'symbol:axlUSDC': d('0.02'),
      });
    });

    test('copyWith re-stamps the quote time and keeps every other field', () {
      final full = offerOf(
        costs: [_cost(symbol: 'axlUSDC')],
        approval: const RoutedSwapApprovalInfo(
          txCount: 1,
          resetsFirst: false,
          spender: '0xdiamond',
        ),
        order: RoutedSwapOrder.fastest,
        toolLogoUrl: 'https://li.fi/stargate.png',
        estimatedDuration: const Duration(seconds: 95),
        slippage: 0.01,
        address: '0xwallet',
      );
      final later = full.copyWith(
        quotedAt: full.quotedAt.add(const Duration(minutes: 1)),
      );

      expect(later.quotedAt, DateTime.utc(2026, 9, 25, 12, 1));
      expect(later, isNot(full));
      expect(later.copyWith(quotedAt: full.quotedAt), full);
      expect(full.copyWith(), full);
      expect(full.copyWith().hashCode, full.hashCode);
      expect(
        [
          later.order,
          later.toolLogoUrl,
          later.estimatedDuration,
          later.slippage,
          later.fromAddress,
          later.toAddress,
          later.approval,
          later.route,
        ],
        [
          RoutedSwapOrder.fastest,
          'https://li.fi/stargate.png',
          const Duration(seconds: 95),
          0.01,
          '0xwallet',
          '0xwallet',
          full.approval,
          full.route,
        ],
      );
    });
  });
}
