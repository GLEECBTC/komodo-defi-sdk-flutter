import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Supported simple market maker bot RPC methods.
enum MarketMakerBotMethod {
  /// `start_simple_market_maker_bot`
  start('start_simple_market_maker_bot'),

  /// `stop_simple_market_maker_bot`
  stop('stop_simple_market_maker_bot');

  const MarketMakerBotMethod(this.rpcMethod);

  /// RPC method name.
  final String rpcMethod;
}

/// Trade volume limit used by simple market maker bot pair config.
class MarketMakerBotTradeVolume {
  const MarketMakerBotTradeVolume._({this.percentage, this.usd})
    : assert(
        percentage != null || usd != null,
        'Either percentage or usd must be provided',
      ),
      assert(
        percentage == null || usd == null,
        'Only one volume type can be provided',
      );

  /// Percentage of available balance.
  const factory MarketMakerBotTradeVolume.percentage(double value) =
      MarketMakerBotTradeVolumePercentage;

  /// USD-denominated volume limit.
  const factory MarketMakerBotTradeVolume.usd(double value) =
      MarketMakerBotTradeVolumeUsd;

  /// Parses a volume object containing either `percentage` or `usd`.
  factory MarketMakerBotTradeVolume.fromJson(JsonMap json) {
    final percentage = double.tryParse(json['percentage']?.toString() ?? '');
    final usd = double.tryParse(json['usd']?.toString() ?? '');
    if (percentage != null && usd != null) {
      throw ArgumentError(
        'Trade volume cannot contain both percentage and usd',
      );
    }
    if (percentage != null) {
      return MarketMakerBotTradeVolume.percentage(percentage);
    }
    if (usd != null) {
      return MarketMakerBotTradeVolume.usd(usd);
    }
    throw ArgumentError('Trade volume requires percentage or usd');
  }

  /// Percentage value if this is a percentage volume.
  final double? percentage;

  /// USD value if this is a USD volume.
  final double? usd;

  Map<String, dynamic> toJson() => {
    if (percentage != null) 'percentage': percentage.toString(),
    if (usd != null) 'usd': usd.toString(),
  };
}

/// Percentage volume limit for the market maker bot.
class MarketMakerBotTradeVolumePercentage extends MarketMakerBotTradeVolume {
  const MarketMakerBotTradeVolumePercentage(double value)
    : super._(percentage: value);
}

/// USD volume limit for the market maker bot.
class MarketMakerBotTradeVolumeUsd extends MarketMakerBotTradeVolume {
  const MarketMakerBotTradeVolumeUsd(double value) : super._(usd: value);
}

/// Configuration for one simple market maker bot trade pair.
class MarketMakerBotTradePairConfig {
  const MarketMakerBotTradePairConfig({
    required this.name,
    required this.base,
    required this.rel,
    required this.spread,
    this.maxBalancePerTrade,
    this.minVolume,
    this.maxVolume,
    this.minBasePriceUsd,
    this.minRelPriceUsd,
    this.minPairPrice,
    this.baseConfs,
    this.baseNota,
    this.relConfs,
    this.relNota,
    this.enable = true,
    this.priceElapsedValidity,
    this.checkLastBidirectionalTradeThreshold,
  });

  factory MarketMakerBotTradePairConfig.fromJson(JsonMap json) {
    return MarketMakerBotTradePairConfig(
      name: json.value<String>('name'),
      base: json.value<String>('base'),
      rel: json.value<String>('rel'),
      spread: json.value<String>('spread'),
      maxBalancePerTrade: json.valueOrNull<bool>('max'),
      minVolume: json.valueOrNull<JsonMap>('min_volume') == null
          ? null
          : MarketMakerBotTradeVolume.fromJson(
              json.value<JsonMap>('min_volume'),
            ),
      maxVolume: json.valueOrNull<JsonMap>('max_volume') == null
          ? null
          : MarketMakerBotTradeVolume.fromJson(
              json.value<JsonMap>('max_volume'),
            ),
      minBasePriceUsd: json.valueOrNull<double>('min_base_price'),
      minRelPriceUsd: json.valueOrNull<double>('min_rel_price'),
      minPairPrice: json.valueOrNull<double>('min_pair_price'),
      baseConfs: json.valueOrNull<int>('base_confs'),
      baseNota: json.valueOrNull<bool>('base_nota'),
      relConfs: json.valueOrNull<int>('rel_confs'),
      relNota: json.valueOrNull<bool>('rel_nota'),
      enable: json.valueOrNull<bool>('enable') ?? true,
      priceElapsedValidity: json.valueOrNull<int>('price_elapsed_validity'),
      checkLastBidirectionalTradeThreshold: json.valueOrNull<bool>(
        'check_last_bidirectional_trade_thresh_hold',
      ),
    );
  }

  /// Pair config name, usually `BASE/REL`.
  final String name;

  /// Base coin ticker/config id.
  final String base;

  /// Rel coin ticker/config id.
  final String rel;

  /// Spread multiplier, for example `1.04` for 4%.
  final String spread;

  /// Whether to use the whole balance for each trade.
  final bool? maxBalancePerTrade;

  /// Minimum per-trade volume.
  final MarketMakerBotTradeVolume? minVolume;

  /// Maximum per-trade volume.
  final MarketMakerBotTradeVolume? maxVolume;

  /// Minimum accepted base USD price.
  final double? minBasePriceUsd;

  /// Minimum accepted rel USD price.
  final double? minRelPriceUsd;

  /// Minimum accepted pair price.
  final double? minPairPrice;

  /// Required confirmations for base coin.
  final int? baseConfs;

  /// Whether base coin notarization is required.
  final bool? baseNota;

  /// Required confirmations for rel coin.
  final int? relConfs;

  /// Whether rel coin notarization is required.
  final bool? relNota;

  /// Whether this pair is enabled for the bot.
  final bool enable;

  /// Price validity window in seconds.
  final int? priceElapsedValidity;

  /// Whether the bot should adjust against last bidirectional trade VWAP.
  final bool? checkLastBidirectionalTradeThreshold;

  Map<String, dynamic> toJson() => {
    'name': name,
    'base': base,
    'rel': rel,
    'spread': spread,
    if (maxBalancePerTrade != null) 'max': maxBalancePerTrade,
    if (minVolume != null) 'min_volume': minVolume!.toJson(),
    if (maxVolume != null) 'max_volume': maxVolume!.toJson(),
    if (minBasePriceUsd != null) 'min_base_price': minBasePriceUsd,
    if (minRelPriceUsd != null) 'min_rel_price': minRelPriceUsd,
    if (minPairPrice != null) 'min_pair_price': minPairPrice,
    if (baseConfs != null) 'base_confs': baseConfs,
    if (baseNota != null) 'base_nota': baseNota,
    if (relConfs != null) 'rel_confs': relConfs,
    if (relNota != null) 'rel_nota': relNota,
    'enable': enable,
    if (priceElapsedValidity != null)
      'price_elapsed_validity': priceElapsedValidity,
    if (checkLastBidirectionalTradeThreshold != null)
      'check_last_bidirectional_trade_thresh_hold':
          checkLastBidirectionalTradeThreshold,
  };
}

/// Parameters for the simple market maker bot.
class MarketMakerBotParameters {
  const MarketMakerBotParameters({
    this.priceUrl,
    this.botRefreshRate,
    this.tradeCoinPairs = const {},
  });

  factory MarketMakerBotParameters.fromJson(JsonMap json) {
    final cfg = json.valueOrNull<JsonMap>('cfg') ?? {};
    return MarketMakerBotParameters(
      priceUrl: json.valueOrNull<String>('price_url'),
      botRefreshRate: json.valueOrNull<int>('bot_refresh_rate'),
      tradeCoinPairs: cfg.map(
        (key, value) => MapEntry(
          key,
          MarketMakerBotTradePairConfig.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }

  /// Full URL to a price API endpoint.
  final String? priceUrl;

  /// Bot refresh interval in seconds.
  final int? botRefreshRate;

  /// Pair config keyed by pair name.
  final Map<String, MarketMakerBotTradePairConfig> tradeCoinPairs;

  Map<String, dynamic> toJson() => {
    if (priceUrl != null) 'price_url': priceUrl,
    if (botRefreshRate != null) 'bot_refresh_rate': botRefreshRate,
    'cfg': tradeCoinPairs.map((key, value) => MapEntry(key, value.toJson())),
  };
}

/// Request to start or stop the simple market maker bot.
class MarketMakerBotRequest
    extends BaseRequest<MarketMakerBotResponse, GeneralErrorResponse> {
  MarketMakerBotRequest({
    required String rpcPass,
    required this.id,
    required this.methodType,
    this.botParameters,
  }) : super(
         method: methodType.rpcMethod,
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  /// Bot id used by KDF.
  final int id;

  /// Start or stop RPC method.
  final MarketMakerBotMethod methodType;

  /// Bot configuration. Required for start, omitted for stop.
  final MarketMakerBotParameters? botParameters;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'id': id,
    'params': botParameters?.toJson() ?? <String, dynamic>{},
  });

  @override
  MarketMakerBotResponse parse(Map<String, dynamic> json) =>
      MarketMakerBotResponse.parse(json);
}

/// Raw response from the simple market maker bot RPC.
class MarketMakerBotResponse extends BaseResponse {
  MarketMakerBotResponse({required super.mmrpc, this.result});

  factory MarketMakerBotResponse.parse(JsonMap json) {
    return MarketMakerBotResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      result: json.valueOrNull<dynamic>('result'),
    );
  }

  /// Raw KDF result payload, if one is returned.
  final dynamic result;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    if (result != null) 'result': result,
  };
}
