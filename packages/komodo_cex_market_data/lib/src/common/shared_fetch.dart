import 'package:async/async.dart';

/// Runs one fetch at a time and gives its outcome to every concurrent caller.
///
/// The shared future completes with a [Result], never an error. Callers can
/// sit in different error zones (`RepositoryFallbackMixin` wraps each lookup
/// in `retry`), and Dart does not deliver a future's error across error zones,
/// so a caller that joined a failing future from another zone would never
/// complete.
class SharedFetch<T> {
  Future<Result<T>>? _inFlight;

  /// Joins the running fetch, or starts [fetch] when none is running.
  Future<T> run(Future<T> Function() fetch) async {
    final result = await (_inFlight ??= Result.capture(Future.sync(fetch))
        .whenComplete(() => _inFlight = null));
    return result.asFuture;
  }
}

/// Keeps the first successful result of a fetch.
///
/// Unlike `AsyncMemoizer`, a failure is not kept for good. Callers get a
/// [StateError] without a request until [failureCooldown] has passed, and the
/// next call after that fetches again.
class RetryingMemoizer<T extends Object> {
  /// [name] describes the fetch in the cooldown error, e.g.
  /// `Binance coin list`.
  RetryingMemoizer({
    required this.name,
    this.failureCooldown = const Duration(minutes: 5),
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  /// What is fetched, for the cooldown error.
  final String name;

  /// How long after a failure the fetch is not attempted again.
  final Duration failureCooldown;

  final DateTime Function() _clock;
  final _fetch = SharedFetch<T>();
  T? _value;
  DateTime? _lastFailure;

  /// Returns the kept result, or runs [fetch] to obtain it.
  Future<T> runOnce(Future<T> Function() fetch) async {
    final value = _value;
    if (value != null) return value;

    final lastFailure = _lastFailure;
    if (lastFailure != null) {
      // A clock that moved backwards counts as expired rather than cooling.
      final elapsed = _clock().difference(lastFailure);
      if (!elapsed.isNegative && elapsed < failureCooldown) {
        throw StateError(
          '$name fetch is in cooldown after a recent failure '
          '(${(failureCooldown - elapsed).inSeconds}s remaining)',
        );
      }
    }

    return _fetch.run(() async {
      try {
        final fetched = await fetch();
        _lastFailure = null;
        return _value = fetched;
      } catch (_) {
        _lastFailure = _clock();
        rethrow;
      }
    });
  }
}
