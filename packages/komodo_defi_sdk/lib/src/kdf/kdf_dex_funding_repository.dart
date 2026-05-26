// ignore_for_file: document_ignores, public_member_api_docs

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/kdf/kdf_evm_account_repository.dart';
import 'package:komodo_defi_sdk/src/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const String kdfDexFundingProviderId = 'gleec_kdf_dex';

const Map<String, String> kdfGnosisSpendableTokenAssets = {
  'EURe': 'EURE-GNO',
  'GBPe': 'GBPE-GNO',
  'USDCe': 'USDC-GNO',
  'USDC.e': 'USDC-GNO',
};

final class KdfDexFundingSource {
  const KdfDexFundingSource({
    required this.walletRef,
    required this.addressRef,
    required this.address,
    required this.assetId,
    required this.chainId,
    required this.displaySymbol,
    required this.balance,
    this.enabled = true,
    this.disabledReason,
  });

  final String walletRef;
  final String addressRef;
  final String address;
  final String assetId;
  final int chainId;
  final String displaySymbol;
  final String balance;
  final bool enabled;
  final String? disabledReason;
}

final class KdfDexFundingQuoteRequest {
  const KdfDexFundingQuoteRequest({
    required this.source,
    required this.sourceAmount,
    required this.destinationSafeAddress,
    required this.destinationToken,
  });

  final KdfDexFundingSource source;
  final String sourceAmount;
  final String destinationSafeAddress;
  final String destinationToken;
}

final class KdfDexFundingQuote {
  const KdfDexFundingQuote({
    required this.request,
    required this.providerId,
    required this.routeLabelKey,
    required this.expectedReceiveAmount,
    required this.minimumReceiveAmount,
    required this.providerFeeAmount,
    required this.networkFeeAmount,
    required this.etaSeconds,
    required this.routeMetadataRef,
    required this.steps,
    required this.baseAssetId,
    required this.relAssetId,
    required this.baseCoinAmount,
    required this.relCoinAmount,
    required this.swapMethod,
    required this.routeKind,
  });

  final KdfDexFundingQuoteRequest request;
  final String providerId;
  final String routeLabelKey;
  final String expectedReceiveAmount;
  final String minimumReceiveAmount;
  final String providerFeeAmount;
  final String networkFeeAmount;
  final int etaSeconds;
  final String routeMetadataRef;
  final List<KdfDexFundingStep> steps;
  final String baseAssetId;
  final String relAssetId;
  final String baseCoinAmount;
  final String relCoinAmount;
  final SwapMethod swapMethod;
  final String routeKind;

  bool get isDirectTransfer => routeKind == 'direct_transfer';
}

final class KdfDexFundingStep {
  const KdfDexFundingStep({
    required this.labelKey,
    required this.providerId,
    required this.sourceAssetId,
    required this.destinationToken,
    required this.etaSeconds,
  });

  final String labelKey;
  final String providerId;
  final String sourceAssetId;
  final String destinationToken;
  final int etaSeconds;
}

final class KdfDexFundingOrder {
  const KdfDexFundingOrder({
    required this.localOrderRef,
    required this.quote,
    required this.swapUuid,
    required this.status,
    this.completedDestinationAmount,
  });

  final String localOrderRef;
  final KdfDexFundingQuote quote;
  final String swapUuid;
  final KdfDexFundingStatusKind status;
  final String? completedDestinationAmount;
}

enum KdfDexFundingStatusKind {
  preparing,
  swapPending,
  swapCompleted,
  transferReady,
  transferPending,
  completed,
  failed,
  recovery,
}

final class KdfDexFundingStatus {
  const KdfDexFundingStatus({
    required this.order,
    required this.status,
    this.messageKey,
    this.swapTxHash,
    this.transferTxHash,
    this.completedDestinationAmount,
  });

  final KdfDexFundingOrder order;
  final KdfDexFundingStatusKind status;
  final String? messageKey;
  final String? swapTxHash;
  final String? transferTxHash;
  final String? completedDestinationAmount;
}

final class KdfDexSafeTransferPreview {
  const KdfDexSafeTransferPreview({
    required this.previewRef,
    required this.order,
    required this.assetId,
    required this.toAddress,
    required this.amount,
    required this.networkFeeAmount,
    required this.gasAssetId,
    required this.hasGas,
    WithdrawalPreview? withdrawalPreview,
  }) : _withdrawalPreview = withdrawalPreview;

  final String previewRef;
  final KdfDexFundingOrder order;
  final String assetId;
  final String toAddress;
  final String amount;
  final String networkFeeAmount;
  final String gasAssetId;
  final bool hasGas;
  final WithdrawalPreview? _withdrawalPreview;
}

final class KdfDexSafeTransferResult {
  const KdfDexSafeTransferResult({
    required this.txHash,
    required this.assetId,
    required this.toAddress,
    required this.amount,
  });

  final String txHash;
  final String assetId;
  final String toAddress;
  final String amount;
}

final class KdfDexFundingRepository {
  KdfDexFundingRepository({
    required KomodoDefiSdk sdk,
    List<String> sourceAssetIds = const ['EURE-GNO', 'GBPE-GNO', 'USDC-GNO'],
    Map<String, String> destinationTokenAssets = kdfGnosisSpendableTokenAssets,
    DateTime Function()? clock,
  }) : _sdk = sdk,
       _sourceAssetIds = sourceAssetIds,
       _destinationTokenAssets = destinationTokenAssets,
       _clock = clock;

  final KomodoDefiSdk _sdk;
  final List<String> _sourceAssetIds;
  final Map<String, String> _destinationTokenAssets;
  final DateTime Function()? _clock;

  Future<List<KdfDexFundingSource>> listFundingSources() async {
    await _sdk.ensureInitialized();
    final user = await _requireCurrentUser();
    final gasAsset = await _requireAsset(kdfGnosisGasAssetId);
    await _ensureActivated(gasAsset);
    final gasBalance = await _sdk.balances.getBalance(gasAsset.id);
    final hasGas = gasBalance.spendable > Decimal.zero;
    final sources = <KdfDexFundingSource>[];

    for (final assetId in _sourceAssetIds) {
      final asset = await _requireAsset(assetId);
      await _ensureActivated(asset);
      final pubkeys = await _sdk.pubkeys.getPubkeys(asset);
      for (final key in pubkeys.keys) {
        if (!key.isActiveForSwap) continue;
        sources.add(
          KdfDexFundingSource(
            walletRef: user.walletId.compoundId,
            addressRef: '$assetId:${key.derivationPath ?? key.address}',
            address: key.address,
            assetId: assetId,
            chainId: kdfGnosisChainId,
            displaySymbol: _displaySymbol(assetId),
            balance: key.balance.spendable.toString(),
            enabled: hasGas,
            disabledReason: hasGas ? null : 'xdai_gas_required',
          ),
        );
      }
    }

    return sources;
  }

  Future<KdfDexFundingQuote> quote(KdfDexFundingQuoteRequest request) async {
    _validateQuoteRequest(request, _destinationTokenAssets);
    await _sdk.ensureInitialized();
    await _requireCurrentUser();
    final destinationAssetId = _destinationAssetId(
      request.destinationToken,
      _destinationTokenAssets,
    );
    final sourceAsset = await _requireAsset(request.source.assetId);
    final destinationAsset = await _requireAsset(destinationAssetId);
    await _ensureActivated(sourceAsset);
    await _ensureActivated(destinationAsset);

    if (request.source.assetId == destinationAssetId) {
      return _directTransferQuote(request, destinationAssetId);
    }

    final sourceAmount = Decimal.parse(request.sourceAmount);
    final expectedReceive = await _estimateReceiveAmount(
      base: request.source.assetId,
      rel: destinationAssetId,
      baseAmount: sourceAmount,
    );
    final preimage = await _sdk.trading.tradePreimage(
      base: request.source.assetId,
      rel: destinationAssetId,
      swapMethod: SwapMethod.sell,
      volume: request.sourceAmount,
    );
    final networkFee = _totalPreimageFees(preimage);

    return KdfDexFundingQuote(
      request: request,
      providerId: kdfDexFundingProviderId,
      routeLabelKey: 'funding.route.gleec_kdf_dex',
      expectedReceiveAmount: expectedReceive.toString(),
      minimumReceiveAmount: expectedReceive.toString(),
      providerFeeAmount: '0',
      networkFeeAmount: networkFee.toString(),
      etaSeconds: 120,
      routeMetadataRef: _routeMetadata({
        'provider': kdfDexFundingProviderId,
        'routeKind': 'kdf_swap',
        'baseAssetId': request.source.assetId,
        'relAssetId': destinationAssetId,
        'swapMethod': 'sell',
      }),
      steps: [
        KdfDexFundingStep(
          labelKey: 'funding.step.kdf_swap',
          providerId: kdfDexFundingProviderId,
          sourceAssetId: request.source.assetId,
          destinationToken: request.destinationToken,
          etaSeconds: 120,
        ),
      ],
      baseAssetId: request.source.assetId,
      relAssetId: destinationAssetId,
      baseCoinAmount: request.sourceAmount,
      relCoinAmount: expectedReceive.toString(),
      swapMethod: SwapMethod.sell,
      routeKind: 'kdf_swap',
    );
  }

  Future<Decimal> _estimateReceiveAmount({
    required String base,
    required String rel,
    required Decimal baseAmount,
  }) async {
    final orderbook = await _sdk.trading.getOrderbook(base: base, rel: rel);
    final bids = <_KdfDexPricedBid>[];
    for (final bid in orderbook.bids) {
      final price = _decimalValue(bid.price);
      final maxBaseVolume = _decimalValue(
        bid.baseMaxVolumeAggregated ?? bid.baseMaxVolume,
      );
      if (price == null || price <= Decimal.zero) continue;
      bids.add(_KdfDexPricedBid(price: price, maxBaseVolume: maxBaseVolume));
    }
    if (bids.isEmpty) {
      throw StateError('No KDF DEX route is available for $base/$rel.');
    }
    bids.sort((a, b) => b.price.compareTo(a.price));
    final bestBid = bids.first;
    final maxBaseVolume = bestBid.maxBaseVolume;
    if (maxBaseVolume != null && maxBaseVolume < baseAmount) {
      throw StateError('KDF DEX route has insufficient liquidity.');
    }
    return baseAmount * bestBid.price;
  }

  Future<KdfDexFundingOrder> startSwap(KdfDexFundingQuote quote) async {
    await _sdk.ensureInitialized();
    await _requireCurrentUser();
    if (quote.isDirectTransfer) {
      final ref = 'direct-${_now().microsecondsSinceEpoch}';
      return KdfDexFundingOrder(
        localOrderRef: ref,
        quote: quote,
        swapUuid: ref,
        status: KdfDexFundingStatusKind.swapCompleted,
        completedDestinationAmount: quote.expectedReceiveAmount,
      );
    }
    final response = await _sdk.trading.startSwap(
      base: quote.baseAssetId,
      rel: quote.relAssetId,
      baseCoinAmount: quote.baseCoinAmount,
      relCoinAmount: quote.relCoinAmount,
      method: quote.swapMethod,
    );
    if (response.uuid.trim().isEmpty) {
      throw StateError('KDF start_swap returned an empty UUID.');
    }
    return KdfDexFundingOrder(
      localOrderRef: response.uuid,
      quote: quote,
      swapUuid: response.uuid,
      status: KdfDexFundingStatusKind.swapPending,
    );
  }

  Stream<KdfDexFundingStatus> watchSwap(KdfDexFundingOrder order) async* {
    if (order.quote.isDirectTransfer) {
      yield KdfDexFundingStatus(
        order: order,
        status: KdfDexFundingStatusKind.transferReady,
        completedDestinationAmount: order.completedDestinationAmount,
      );
      return;
    }
    await for (final swap in _sdk.trading.watchSwapStatus(
      uuid: order.swapUuid,
    )) {
      if (swap.errorEvents.isNotEmpty) {
        yield KdfDexFundingStatus(
          order: order,
          status: KdfDexFundingStatusKind.failed,
          messageKey: 'funding.kdf_swap_failed',
        );
      } else if (swap.isSuccessful) {
        yield KdfDexFundingStatus(
          order: order,
          status: KdfDexFundingStatusKind.swapCompleted,
          completedDestinationAmount: _completedDestinationAmount(order, swap),
        );
      } else {
        yield KdfDexFundingStatus(
          order: order,
          status: KdfDexFundingStatusKind.swapPending,
        );
      }
    }
  }

  Future<KdfDexSafeTransferPreview> previewSafeTransfer({
    required KdfDexFundingOrder order,
    required String destinationSafeAddress,
  }) async {
    await _sdk.ensureInitialized();
    await _requireCurrentUser();
    _requireEvmAddress(destinationSafeAddress, 'destinationSafeAddress');
    final destinationAssetId = _destinationAssetId(
      order.quote.request.destinationToken,
      _destinationTokenAssets,
    );
    final amount = Decimal.parse(
      order.completedDestinationAmount ?? order.quote.minimumReceiveAmount,
    );
    final params = WithdrawParameters(
      asset: destinationAssetId,
      toAddress: destinationSafeAddress,
      amount: amount,
      from: _withdrawalSource(order.quote.request.source.addressRef),
    );

    try {
      final preview = await _sdk.withdrawals.previewWithdrawal(params);
      return KdfDexSafeTransferPreview(
        previewRef: preview.internalId ?? preview.txHash,
        order: order,
        assetId: destinationAssetId,
        toAddress: destinationSafeAddress,
        amount: amount.toString(),
        networkFeeAmount: preview.fee.totalFee.toString(),
        gasAssetId: kdfGnosisGasAssetId,
        hasGas: true,
        withdrawalPreview: preview,
      );
    } catch (error) {
      if (_looksLikeMissingGas(error)) {
        return KdfDexSafeTransferPreview(
          previewRef: 'missing-gas-${_now().microsecondsSinceEpoch}',
          order: order,
          assetId: destinationAssetId,
          toAddress: destinationSafeAddress,
          amount: amount.toString(),
          networkFeeAmount: '0',
          gasAssetId: kdfGnosisGasAssetId,
          hasGas: false,
        );
      }
      rethrow;
    }
  }

  Future<KdfDexSafeTransferResult> executeSafeTransfer(
    KdfDexSafeTransferPreview preview,
  ) async {
    await _sdk.ensureInitialized();
    await _requireCurrentUser();
    if (!preview.hasGas) {
      throw StateError('Cannot execute Gnosis transfer without xDAI gas.');
    }
    final withdrawalPreview = preview._withdrawalPreview;
    if (withdrawalPreview == null) {
      throw StateError('Cannot execute a transfer without a KDF preview.');
    }
    final progress = await _sdk.withdrawals
        .executeWithdrawal(withdrawalPreview, preview.assetId)
        .last;
    final result = progress.withdrawalResult;
    if (progress.status != WithdrawalStatus.complete || result == null) {
      throw StateError(
        progress.errorMessage ?? 'KDF withdrawal did not finish.',
      );
    }
    return KdfDexSafeTransferResult(
      txHash: result.txHash,
      assetId: result.coin,
      toAddress: result.toAddress,
      amount: result.amount.toString(),
    );
  }

  Future<KdfUser> _requireCurrentUser() async {
    final user = await _sdk.auth.currentUser;
    if (user == null) {
      throw AuthException.notSignedIn();
    }
    return user;
  }

  Future<Asset> _requireAsset(String assetId) async {
    final matches = _sdk.assets.findAssetsByConfigId(assetId);
    if (matches.isEmpty) {
      throw StateError('KDF asset $assetId is not configured.');
    }
    return matches.single;
  }

  Future<void> _ensureActivated(Asset asset) async {
    final activated = await _sdk.ensureAssetActivated(asset);
    if (!activated) {
      throw StateError('KDF asset ${asset.id.id} could not be activated.');
    }
  }

  DateTime _now() => (_clock ?? DateTime.now).call().toUtc();
}

KdfDexFundingQuote _directTransferQuote(
  KdfDexFundingQuoteRequest request,
  String destinationAssetId,
) {
  return KdfDexFundingQuote(
    request: request,
    providerId: kdfDexFundingProviderId,
    routeLabelKey: 'funding.route.gleec_kdf_direct',
    expectedReceiveAmount: request.sourceAmount,
    minimumReceiveAmount: request.sourceAmount,
    providerFeeAmount: '0',
    networkFeeAmount: '0',
    etaSeconds: 30,
    routeMetadataRef: _routeMetadata({
      'provider': kdfDexFundingProviderId,
      'routeKind': 'direct_transfer',
      'assetId': destinationAssetId,
    }),
    steps: [
      KdfDexFundingStep(
        labelKey: 'funding.step.kdf_direct_transfer',
        providerId: kdfDexFundingProviderId,
        sourceAssetId: request.source.assetId,
        destinationToken: request.destinationToken,
        etaSeconds: 30,
      ),
    ],
    baseAssetId: request.source.assetId,
    relAssetId: destinationAssetId,
    baseCoinAmount: request.sourceAmount,
    relCoinAmount: request.sourceAmount,
    swapMethod: SwapMethod.sell,
    routeKind: 'direct_transfer',
  );
}

Decimal _totalPreimageFees(TradePreimageResponse preimage) {
  return preimage.totalFees.fold<Decimal>(
    Decimal.zero,
    (total, fee) => total + Decimal.parse(fee.amount),
  );
}

String _completedDestinationAmount(KdfDexFundingOrder order, SwapInfo swap) {
  if (swap.makerCoin == order.quote.relAssetId) {
    return swap.makerAmount;
  }
  if (swap.takerCoin == order.quote.relAssetId) {
    return swap.takerAmount;
  }
  return order.quote.expectedReceiveAmount;
}

Decimal? _decimalValue(NumericValue? value) {
  final raw = value?.decimal;
  if (raw == null) return null;
  return Decimal.tryParse(raw);
}

final class _KdfDexPricedBid {
  const _KdfDexPricedBid({required this.price, required this.maxBaseVolume});

  final Decimal price;
  final Decimal? maxBaseVolume;
}

String _destinationAssetId(
  String destinationToken,
  Map<String, String> destinationTokenAssets,
) {
  final assetId = destinationTokenAssets[destinationToken];
  if (assetId == null) {
    throw StateError('Unsupported Gnosis Pay destination token.');
  }
  return assetId;
}

void _validateQuoteRequest(
  KdfDexFundingQuoteRequest request,
  Map<String, String> destinationTokenAssets,
) {
  _requirePositiveDecimal(request.sourceAmount, 'sourceAmount');
  _requireEvmAddress(request.destinationSafeAddress, 'destinationSafeAddress');
  if (!request.source.enabled) {
    throw StateError(
      request.source.disabledReason ?? 'Funding source disabled.',
    );
  }
  _destinationAssetId(request.destinationToken, destinationTokenAssets);
}

void _requirePositiveDecimal(String value, String label) {
  final amount = Decimal.tryParse(value);
  if (amount == null || amount <= Decimal.zero) {
    throw ArgumentError.value(value, label, 'must be greater than zero');
  }
}

void _requireEvmAddress(String value, String label) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value.trim())) {
    throw ArgumentError.value(value, label, 'must be a valid EVM address');
  }
}

WithdrawalSource? _withdrawalSource(String addressRef) {
  final parts = addressRef.split(':');
  if (parts.length < 2) return null;
  final derivationPath = parts.sublist(1).join(':');
  if (!derivationPath.startsWith('m/')) return null;
  return WithdrawalSource.hdDerivationPath(derivationPath);
}

String _displaySymbol(String assetId) {
  return switch (assetId) {
    'EURE-GNO' => 'EURe',
    'GBPE-GNO' => 'GBPe',
    'USDC-GNO' => 'USDC.e',
    'XDAI' => 'xDAI',
    _ => assetId,
  };
}

String _routeMetadata(Map<String, String> metadata) {
  final ordered = Map<String, String>.fromEntries(
    metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  return jsonEncode(ordered);
}

bool _looksLikeMissingGas(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('gas') &&
      (lower.contains('not enough') ||
          lower.contains('insufficient') ||
          lower.contains('balance'));
}
