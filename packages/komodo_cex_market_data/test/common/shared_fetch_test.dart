import 'dart:async';

import 'package:komodo_cex_market_data/src/common/shared_fetch.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:test/test.dart';

/// Runs each lookup the way RepositoryFallbackMixin does: inside `retry`,
/// which gives each attempt its own error zone.
Future<List<Object>> _outcomesAcrossZones<T extends Object>(
  Future<T> Function() lookup, {
  required void Function() release,
}) {
  final lookups = [for (var i = 0; i < 4; i++) retry(lookup, maxAttempts: 1)];
  release();
  return Future.wait([
    for (final lookup in lookups)
      lookup.then<Object>((value) => value, onError: (Object e) => e),
  ]).timeout(const Duration(seconds: 5));
}

void main() {
  group('SharedFetch', () {
    late SharedFetch<int> shared;
    late Completer<void> gate;
    late int calls;

    setUp(() {
      shared = SharedFetch<int>();
      gate = Completer<void>();
      calls = 0;
    });

    Future<int> succeed() async {
      calls++;
      await gate.future;
      return 7;
    }

    Future<int> fail() async {
      calls++;
      await gate.future;
      throw Exception('offline');
    }

    test('concurrent callers share one fetch', () async {
      final results = Future.wait([
        for (var i = 0; i < 3; i++) shared.run(succeed),
      ]);
      gate.complete();

      expect(await results, [7, 7, 7]);
      expect(calls, 1);
    });

    test('fetches again once the previous fetch has finished', () async {
      gate.complete();
      await shared.run(succeed);
      await expectLater(shared.run(fail), throwsException);
      expect(await shared.run(succeed), 7);
      expect(calls, 3);
    });

    test('a failure reaches callers in other error zones', () async {
      final outcomes = await _outcomesAcrossZones(
        () => shared.run(fail),
        release: gate.complete,
      );

      expect(outcomes, everyElement(isException));
      expect(calls, 1);
    });

    test('a fetch that throws synchronously fails every caller', () async {
      Future<int> throwNow() => throw StateError('no client');

      await expectLater(shared.run(throwNow), throwsStateError);
      expect(await shared.run(() async => 3), 3);
    });
  });

  group('RetryingMemoizer', () {
    late DateTime now;
    late RetryingMemoizer<List<int>> memoizer;
    late int calls;
    Object? failure;

    setUp(() {
      now = DateTime.utc(2026, 11, 17, 12);
      memoizer = RetryingMemoizer(name: 'Test list', clock: () => now);
      calls = 0;
      failure = null;
    });

    Future<List<int>> fetch() async {
      calls++;
      final error = failure;
      if (error != null) throw error;
      return [calls];
    }

    test('keeps a successful result', () async {
      expect(await memoizer.runOnce(fetch), [1]);
      now = now.add(const Duration(days: 1));
      expect(await memoizer.runOnce(fetch), [1]);
      expect(calls, 1);
    });

    test('does not keep a failure beyond the cooldown', () async {
      failure = Exception('offline');
      await expectLater(memoizer.runOnce(fetch), throwsException);

      failure = null;
      now = now.add(const Duration(minutes: 4, seconds: 59));
      await expectLater(
        memoizer.runOnce(fetch),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Test list'), contains('cooldown')),
          ),
        ),
      );
      expect(calls, 1);

      now = now.add(const Duration(seconds: 1));
      expect(await memoizer.runOnce(fetch), [2]);
      expect(await memoizer.runOnce(fetch), [2]);
      expect(calls, 2);
    });

    test('fetches again when the clock moves backwards', () async {
      failure = Exception('offline');
      await expectLater(memoizer.runOnce(fetch), throwsException);

      failure = null;
      now = now.subtract(const Duration(days: 1));
      expect(await memoizer.runOnce(fetch), [2]);
    });

    test('a failure reaches callers in other error zones', () async {
      final gate = Completer<void>();
      Future<List<int>> gatedFailure() async {
        calls++;
        await gate.future;
        throw Exception('offline');
      }

      final outcomes = await _outcomesAcrossZones(
        () => memoizer.runOnce(gatedFailure),
        release: gate.complete,
      );

      expect(outcomes, everyElement(isException));
      expect(calls, 1);
    });
  });
}
