import 'dart:math' as math;

import 'package:komodo_defi_types/komodo_defi_types.dart';

/// An activation was refused without contacting KDF, because recent attempts
/// for the asset kept failing with the same error.
///
/// See [ActivationFailureBackoff].
final class ActivationDeferredException implements Exception {
  /// Describes a refused activation and when the next attempt may start.
  const ActivationDeferredException({
    required this.assetId,
    required this.retryAfter,
    required this.consecutiveFailures,
    required this.lastError,
  });

  /// The asset whose activation was refused.
  final AssetId assetId;

  /// The earliest time another attempt will be made.
  final DateTime retryAfter;

  /// How many attempts in a row ended with [lastError].
  final int consecutiveFailures;

  /// The error those attempts ended with.
  final String lastError;

  @override
  String toString() =>
      'Activation deferred until ${retryAfter.toIso8601String()} after '
      '$consecutiveFailures identical failures: $lastError';
}

/// Spaces out activation attempts for assets that keep failing the same way.
///
/// An asset whose configuration cannot work (for example, no usable Electrum
/// servers) fails identically every time. Each caller that wants it active
/// retries on its own short schedule, and together they add up to several
/// rounds of KDF RPCs a minute for the rest of the session.
///
/// After [failuresBeforeBackoff] consecutive failures with the same error, an
/// asset's attempts are refused until a delay has passed. The delay starts at
/// [initialDelay] and doubles with each further identical failure, up to
/// [maxDelay]. A success, a different error, or [reset] starts over.
///
/// Errors are compared with digit runs collapsed, so a changing port, line
/// number or duration does not make each failure look new.
class ActivationFailureBackoff {
  /// Creates a backoff policy; [clock] is for tests.
  ActivationFailureBackoff({
    this.failuresBeforeBackoff = 3,
    this.initialDelay = const Duration(minutes: 1),
    this.maxDelay = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : assert(failuresBeforeBackoff > 0, 'needs at least one failure'),
       _clock = clock ?? DateTime.now;

  /// Identical failures tolerated before attempts are spaced out.
  final int failuresBeforeBackoff;

  /// The first delay once backoff starts.
  final Duration initialDelay;

  /// The ceiling the delay doubles up to.
  final Duration maxDelay;

  final DateTime Function() _clock;
  final Map<AssetId, _FailureStreak> _streaks = {};

  /// Records a failed attempt for [assetId].
  ///
  /// Returns the deferral this failure starts, or null if the next attempt may
  /// start at once.
  ActivationDeferredException? recordFailure(AssetId assetId, String error) {
    final signature = _signature(error);
    final previous = _streaks[assetId];
    final count = previous?.signature == signature ? previous!.count + 1 : 1;
    final retryAfter = count < failuresBeforeBackoff
        ? null
        : _clock().add(_delayFor(count));
    final streak = _FailureStreak(signature, error, count, retryAfter);
    _streaks[assetId] = streak;
    return streak.deferral(assetId);
  }

  /// Clears [assetId]'s failure history after it activated.
  void recordSuccess(AssetId assetId) => _streaks.remove(assetId);

  /// The deferral in force for [assetId], or null if it may be attempted now.
  ActivationDeferredException? deferralFor(AssetId assetId) {
    final deferral = _streaks[assetId]?.deferral(assetId);
    if (deferral == null || !_clock().isBefore(deferral.retryAfter)) {
      return null;
    }
    return deferral;
  }

  /// Forgets the failure history of [assetIds], or of every asset when null,
  /// so their next attempts start at once.
  void reset([Iterable<AssetId>? assetIds]) {
    if (assetIds == null) {
      _streaks.clear();
      return;
    }
    assetIds.forEach(_streaks.remove);
  }

  Duration _delayFor(int count) {
    // Clamped well below the shift that would overflow; the cap applies long
    // before then anyway.
    final doublings = math.min(count - failuresBeforeBackoff, 20);
    final delay = initialDelay.inMicroseconds * (1 << doublings);
    return Duration(microseconds: math.min(delay, maxDelay.inMicroseconds));
  }

  static final _digits = RegExp(r'\d+');

  static String _signature(String error) =>
      error.replaceAll(_digits, '#').trim();
}

class _FailureStreak {
  const _FailureStreak(this.signature, this.error, this.count, this.retryAfter);

  final String signature;
  final String error;
  final int count;
  final DateTime? retryAfter;

  ActivationDeferredException? deferral(AssetId assetId) {
    final until = retryAfter;
    if (until == null) return null;
    return ActivationDeferredException(
      assetId: assetId,
      retryAfter: until,
      consecutiveFailures: count,
      lastError: error,
    );
  }
}
