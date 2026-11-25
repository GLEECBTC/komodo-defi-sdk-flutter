import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/constants/coinpaprika_intervals.dart';

part 'coinpaprika_api_plan.freezed.dart';
part 'coinpaprika_api_plan.g.dart';

/// Represents the different CoinPaprika API plans with their specific limitations.
@freezed
abstract class CoinPaprikaApiPlan with _$CoinPaprikaApiPlan {
  /// Private constructor required for custom methods in freezed classes.
  const CoinPaprikaApiPlan._();

  /// Free plan: $0/mo
  /// - 20,000 calls/month
  /// - 1 year daily historical data
  /// - 1 year historical ticks data
  /// - Daily intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d
  const factory CoinPaprikaApiPlan.free({
    @Default(Duration(days: 365)) Duration ohlcHistoricalDataLimit,
    @Default(CoinPaprikaIntervals.freeDefaults) List<String> availableIntervals,
    @Default(20000) int monthlyCallLimit,
  }) = _FreePlan;

  /// Starter plan: $99/mo
  /// - 400,000 calls/month
  /// - 5 years daily historical data
  /// - Daily intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d
  /// - Hourly intervals: 1h, 2h, 3h, 6h, 12h (last 30 days)
  /// - 5-minute intervals: 5m, 10m, 15m, 30m, 45m (last 7 days)
  const factory CoinPaprikaApiPlan.starter({
    @Default(Duration(days: 1825)) Duration ohlcHistoricalDataLimit, // 5 years
    @Default(CoinPaprikaIntervals.premiumDefaults)
    List<String> availableIntervals,
    @Default(400000) int monthlyCallLimit,
  }) = _StarterPlan;

  /// Pro plan: $199/mo
  /// - 1,000,000 calls/month
  /// - Unlimited daily historical data
  /// - Daily intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d
  /// - Hourly intervals: 1h, 2h, 3h, 6h, 12h (last 90 days)
  /// - 5-minute intervals: 5m, 10m, 15m, 30m, 45m (last 30 days)
  const factory CoinPaprikaApiPlan.pro({
    Duration? ohlcHistoricalDataLimit, // null means unlimited
    @Default(CoinPaprikaIntervals.premiumDefaults)
    List<String> availableIntervals,
    @Default(1000000) int monthlyCallLimit,
  }) = _ProPlan;

  /// Business plan: $799/mo
  /// - 5,000,000 calls/month
  /// - Unlimited daily historical data
  /// - Daily intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d
  /// - Hourly intervals: 1h, 2h, 3h, 6h, 12h (last 365 days)
  /// - 5-minute intervals: 5m, 10m, 15m, 30m, 45m (last 365 days)
  const factory CoinPaprikaApiPlan.business({
    Duration? ohlcHistoricalDataLimit, // null means unlimited
    @Default(CoinPaprikaIntervals.premiumDefaults)
    List<String> availableIntervals,
    @Default(5000000) int monthlyCallLimit,
  }) = _BusinessPlan;

  /// Ultimate plan: $1,499/mo
  /// - 10,000,000 calls/month
  /// - Unlimited daily historical data
  /// - No limits on historical data
  /// - All intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d, 1h, 2h, 3h, 6h, 12h, 5m, 10m, 15m, 30m, 45m
  const factory CoinPaprikaApiPlan.ultimate({
    Duration? ohlcHistoricalDataLimit, // null means no limit
    @Default(CoinPaprikaIntervals.premiumDefaults)
    List<String> availableIntervals,
    @Default(10000000) int monthlyCallLimit,
  }) = _UltimatePlan;

  /// Enterprise plan: Custom pricing
  /// - No limits on calls/month
  /// - Unlimited daily historical data
  /// - No limits on historical data
  /// - All intervals: 24h, 1d, 7d, 14d, 30d, 90d, 365d, 1h, 2h, 3h, 6h, 12h, 5m, 10m, 15m, 30m, 45m
  const factory CoinPaprikaApiPlan.enterprise({
    Duration? ohlcHistoricalDataLimit, // null means no limit
    @Default(CoinPaprikaIntervals.premiumDefaults)
    List<String> availableIntervals,
    int? monthlyCallLimit, // null means no limit,
  }) = _EnterprisePlan;

  /// Creates a plan from JSON representation.
  factory CoinPaprikaApiPlan.fromJson(Map<String, dynamic> json) =>
      _$CoinPaprikaApiPlanFromJson(json);

  /// Returns true if the plan has unlimited OHLC historical data access.
  bool get hasUnlimitedOhlcHistory => ohlcHistoricalDataLimit == null;

  /// Returns true if the plan has unlimited monthly API calls.
  bool get hasUnlimitedCalls => monthlyCallLimit == null;

  /// Gets the historical data cutoff date based on the plan's limitations.
  /// Returns null if there's no limit.
  /// Uses UTC time and moves the cutoff [buffer] later for safer API requests.
  DateTime? getHistoricalDataCutoff({
    Duration buffer = const Duration(minutes: 1),
  }) {
    if (hasUnlimitedOhlcHistory) return null;

    final limit = ohlcHistoricalDataLimit!;
    final safeWindow = limit > buffer ? (limit - buffer) : Duration.zero;
    return DateTime.now().toUtc().subtract(safeWindow);
  }

  /// The earliest `start` the API accepts, as a UTC midnight. Returns null if
  /// there's no limit.
  ///
  /// The API reads a date-only `start` as 00:00 UTC, so the buffered cutoff is
  /// rounded up to the next midnight.
  DateTime? getEarliestStartDate() {
    final cutoff = getHistoricalDataCutoff();
    if (cutoff == null) return null;

    final midnight = DateTime.utc(cutoff.year, cutoff.month, cutoff.day);
    return midnight == cutoff
        ? midnight
        : midnight.add(const Duration(days: 1));
  }

  /// Validates if the given interval is supported by this plan.
  bool isIntervalSupported(String interval) {
    return availableIntervals.contains(interval);
  }

  /// Gets the plan name as a string.
  String get planName {
    return when(
      free: (_, __, ___) => 'Free',
      starter: (_, __, ___) => 'Starter',
      pro: (_, __, ___) => 'Pro',
      business: (_, __, ___) => 'Business',
      ultimate: (_, __, ___) => 'Ultimate',
      enterprise: (_, __, ___) => 'Enterprise',
    );
  }

  /// Gets a human-readable description of the OHLC historical data limitation.
  String get ohlcLimitDescription {
    if (hasUnlimitedOhlcHistory) {
      return 'No limit on historical OHLC data';
    }

    final limit = ohlcHistoricalDataLimit!;
    if (limit.inDays >= 365) {
      final years = (limit.inDays / 365).round();
      return '$years year${years > 1 ? 's' : ''} of OHLC historical data';
    } else if (limit.inDays >= 30) {
      final months = (limit.inDays / 30).round();
      return '$months month${months > 1 ? 's' : ''} of OHLC historical data';
    } else if (limit.inDays > 0) {
      return '${limit.inDays} day${limit.inDays > 1 ? 's' : ''} of OHLC '
          'historical data';
    } else {
      return '${limit.inHours} hour${limit.inHours > 1 ? 's' : ''} of OHLC '
          'historical data';
    }
  }
}
