@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

/// The benchmark, run as a test so it gets the Flutter test binding the harness
/// needs.
///
/// Emits one JSON document per run to `BENCH_OUT` (default
/// `build/bench_result.json`). Machine-readable **per phase**, never one
/// conflated number: the phases have different owners and a single
/// "login took N ms" figure cannot say which one moved.
///
/// Not every phase is gateable, and the file says which are:
///
/// - `sdk_init_ms` is **not** gated. `KomodoDefiSdk.initialize` fetches seed
///   nodes over the network (`SeedNodeUpdater.fetchSeedNodes`, 15s timeout,
///   falls back to a bundled asset). On a runner with no egress that is a
///   timeout, not a measurement.
/// - `auth_signin_ms` and `first_post_activation_balance_ms` are gated. Both
///   are pure SDK orchestration against a zero-latency backend.
/// - `first_paint_ms` is recorded and **never** gated: it can legitimately be a
///   cached or synthetic-zero paint, so it would stay green while activation
///   regressed to minutes.
const _ticker = 'KMD';

const _outputPathVariable = 'BENCH_OUT';

/// Repeats per wallet type. Small on purpose - this is a regression tripwire
/// with a 30% tolerance, not a microbenchmark. More iterations would buy
/// precision the gate does not spend.
const _iterations = 3;

Future<Map<String, Object?>> _runOnce(KdfWalletType walletType) async {
  final fixture = KdfWalletFixture()
    ..enableUtxo(_ticker, inProgressPolls: 2)
    ..balance(_ticker, spendable: '10');

  final harness = await KdfHarness.replayed(script: fixture.build());
  try {
    await harness.signIn(walletType: walletType);
    final asset = harness.sdk.assets.available.values.firstWhere(
      (a) => a.id.id == _ticker,
    );
    await harness.measureFirstBalance(asset.id);
    return {
      'wallet_type': walletType.name,
      'phases': harness.metrics.phases,
      'counters': harness.metrics.counters,
    };
  } finally {
    await harness.dispose();
  }
}

void main() {
  test('wallet load benchmark', () async {
    final runs = <Map<String, Object?>>[];
    for (final walletType in harnessWalletTypes) {
      for (var i = 0; i < _iterations; i++) {
        runs.add(await _runOnce(walletType));
      }
    }

    // Median rather than mean: a single scheduling hiccup on a shared CI runner
    // moves a mean of three enough to trip a 30% gate on its own.
    final summary = <String, Map<String, int>>{};
    for (final walletType in harnessWalletTypes) {
      final ofType = runs.where((r) => r['wallet_type'] == walletType.name);
      final phaseNames = <String>{
        for (final run in ofType) ...(run['phases']! as Map<String, int>).keys,
      };
      summary[walletType.name] = {
        for (final phase in phaseNames)
          phase: _median([
            for (final run in ofType)
              if ((run['phases']! as Map<String, int>)[phase] case final int v)
                v,
          ]),
      };
      final counterNames = <String>{
        for (final run in ofType)
          ...(run['counters']! as Map<String, int>).keys,
      };
      for (final counter in counterNames) {
        summary[walletType.name]!['counter.$counter'] = _median([
          for (final run in ofType)
            if ((run['counters']! as Map<String, int>)[counter]
                case final int v)
              v,
        ]);
      }
    }

    final document = <String, Object?>{
      'iterations': _iterations,
      'runs': runs,
      'median': summary,
      // Recorded so a surprising baseline diff can be attributed rather than
      // argued about. Not compared against anything.
      'environment': {
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'dart_version': Platform.version,
      },
    };

    final outputPath =
        Platform.environment[_outputPathVariable] ?? 'build/bench_result.json';
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
    );

    // ignore: avoid_print
    print('BENCH: wrote ${file.absolute.path}');
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(summary));

    for (final walletType in harnessWalletTypes) {
      expect(
        summary[walletType.name],
        contains('first_post_activation_balance_ms'),
        reason:
            'the gated phase is missing for ${walletType.name}: the benchmark '
            'produced a file that compare_bench.dart cannot gate on, which is '
            'worse than failing here',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

int _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : ((sorted[middle - 1] + sorted[middle]) / 2).round();
}
