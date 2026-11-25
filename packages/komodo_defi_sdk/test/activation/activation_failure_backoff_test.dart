import 'package:komodo_defi_sdk/src/activation/activation_failure_backoff.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

AssetId _assetId(String id) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

void main() {
  final clc = _assetId('CLC');
  final mona = _assetId('MONA');
  late DateTime now;
  late ActivationFailureBackoff backoff;

  setUp(() {
    now = DateTime.utc(2026, 11, 25, 12);
    backoff = ActivationFailureBackoff(clock: () => now);
  });

  test('tolerates failures below the threshold', () {
    expect(backoff.recordFailure(clc, 'no servers'), isNull);
    expect(backoff.recordFailure(clc, 'no servers'), isNull);
    expect(backoff.deferralFor(clc), isNull);
  });

  test('defers after the third identical failure', () {
    backoff
      ..recordFailure(clc, 'no servers')
      ..recordFailure(clc, 'no servers');
    final deferral = backoff.recordFailure(clc, 'no servers');

    expect(deferral, isNotNull);
    expect(deferral!.consecutiveFailures, 3);
    expect(deferral.lastError, 'no servers');
    expect(deferral.retryAfter, now.add(const Duration(minutes: 1)));
    expect(backoff.deferralFor(clc)?.retryAfter, deferral.retryAfter);
  });

  test('lifts the deferral once its delay has passed', () {
    for (var i = 0; i < 3; i++) {
      backoff.recordFailure(clc, 'no servers');
    }
    now = now.add(const Duration(seconds: 59));
    expect(backoff.deferralFor(clc), isNotNull);
    now = now.add(const Duration(seconds: 1));
    expect(backoff.deferralFor(clc), isNull);
  });

  test('doubles the delay per identical failure up to the ceiling', () {
    final delays = <Duration>[];
    for (var i = 0; i < 10; i++) {
      final deferral = backoff.recordFailure(clc, 'no servers');
      if (deferral != null) delays.add(deferral.retryAfter.difference(now));
    }

    expect(delays, const [
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 4),
      Duration(minutes: 8),
      Duration(minutes: 16),
      Duration(minutes: 30),
      Duration(minutes: 30),
      Duration(minutes: 30),
    ]);
  });

  test('a different error starts the count again', () {
    backoff
      ..recordFailure(clc, 'no servers')
      ..recordFailure(clc, 'no servers');

    expect(backoff.recordFailure(clc, 'connection refused'), isNull);
    expect(backoff.recordFailure(clc, 'connection refused'), isNull);
    expect(backoff.recordFailure(clc, 'connection refused'), isNotNull);
  });

  test('errors that differ only in numbers count as the same error', () {
    backoff
      ..recordFailure(clc, 'timed out after 180s [utxo.rs:101]')
      ..recordFailure(clc, 'timed out after 181s [utxo.rs:102]');

    expect(
      backoff.recordFailure(clc, 'timed out after 179s [utxo.rs:99]'),
      isNotNull,
    );
  });

  test('a success clears the history', () {
    for (var i = 0; i < 3; i++) {
      backoff.recordFailure(clc, 'no servers');
    }
    backoff.recordSuccess(clc);

    expect(backoff.deferralFor(clc), isNull);
    expect(backoff.recordFailure(clc, 'no servers'), isNull);
  });

  test('reset clears only the named assets, or all of them', () {
    for (var i = 0; i < 3; i++) {
      backoff
        ..recordFailure(clc, 'no servers')
        ..recordFailure(mona, 'no servers');
    }

    backoff.reset([clc]);
    expect(backoff.deferralFor(clc), isNull);
    expect(backoff.deferralFor(mona), isNotNull);

    backoff.reset();
    expect(backoff.deferralFor(mona), isNull);
  });

  test('assets are tracked independently', () {
    for (var i = 0; i < 3; i++) {
      backoff.recordFailure(clc, 'no servers');
    }
    expect(backoff.deferralFor(mona), isNull);
    expect(backoff.recordFailure(mona, 'no servers'), isNull);
  });
}
