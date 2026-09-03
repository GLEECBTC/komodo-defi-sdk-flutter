// Compares a benchmark run against the committed baseline and fails on
// regression.
//
// Usage:
//   dart run tool/compare_bench.dart \
//     --baseline tool/bench_baseline.json \
//     --current build/bench_result.json \
//     --max-regression 0.30
//
// There is deliberately **no `--update` flag**. The baseline is a reviewed
// artefact: a gate that can rewrite its own reference silently ratchets, and
// three 10% "acceptable" regressions in a row become a 33% one that nothing
// ever reported. Moving it is a hand edit in a PR, with the number in the diff.

import 'dart:convert';
import 'dart:io';

/// Phases the gate acts on.
///
/// `auth_signin_ms` is the auth mutex plus the identity RPCs.
/// `first_post_activation_balance_ms` is time-to-a-fetched-balance.
///
/// Everything else in the file is recorded and reported but not gated:
///
/// - `sdk_init_ms` includes a seed-node fetch over the network
///   (`SeedNodeUpdater.fetchSeedNodes`, 15s timeout with a bundled fallback),
///   so on a runner without egress it measures a timeout.
/// - `first_paint_ms` can legitimately be a cached or synthetic-zero paint
///   emitted before activation is even requested. Gating on it would stay green
///   while activation regressed to minutes - which is the exact failure this
///   whole harness exists to catch.
/// - `activation_ms` is informative but is a strict prefix of
///   `first_post_activation_balance_ms`, so gating both double-counts one
///   regression.
const List<String> gatedPhases = [
  'auth_signin_ms',
  'first_post_activation_balance_ms',
];

/// Below this, percentage comparison is noise: a 4ms phase that lands at 6ms is
/// a 50% "regression" and means nothing. Absolute movement at this scale cannot
/// hurt a user.
const int noiseFloorMs = 50;

void main(List<String> arguments) {
  final args = _parseArgs(arguments);
  final maxRegression =
      double.tryParse(args['max-regression'] ?? '0.30') ?? 0.30;
  final baselinePath = args['baseline'] ?? 'tool/bench_baseline.json';
  final currentPath = args['current'] ?? 'build/bench_result.json';

  final baseline = _readMedians(baselinePath);
  final current = _readMedians(currentPath);

  final failures = <String>[];
  final rows = <List<String>>[];

  for (final walletType in current.keys.toList()..sort()) {
    final currentPhases = current[walletType]!;
    final baselinePhases = baseline[walletType];
    if (baselinePhases == null) {
      // A new wallet type with no reference is a reason to update the
      // baseline, not a reason to fail the build on a number nobody has
      // reviewed yet.
      stderr.writeln(
        'NOTE: no baseline for wallet type "$walletType"; not gated. '
        'Add it to $baselinePath in a reviewed change.',
      );
      continue;
    }

    for (final phase in gatedPhases) {
      final currentValue = currentPhases[phase];
      final baselineValue = baselinePhases[phase];
      if (currentValue == null) {
        failures.add(
          '$walletType/$phase: missing from $currentPath. The benchmark did '
          'not record it, which usually means measureFirstBalance timed out.',
        );
        continue;
      }
      if (baselineValue == null) {
        stderr.writeln(
          'NOTE: $walletType/$phase has no baseline; not gated.',
        );
        continue;
      }

      final delta = currentValue - baselineValue;
      final ratio = baselineValue == 0 ? 0.0 : delta / baselineValue;
      final withinNoiseFloor = currentValue < noiseFloorMs;
      final regressed = !withinNoiseFloor && ratio > maxRegression;

      rows.add([
        '$walletType/$phase',
        '${baselineValue}ms',
        '${currentValue}ms',
        '${delta >= 0 ? '+' : ''}${(ratio * 100).toStringAsFixed(1)}%',
        regressed ? 'REGRESSED' : (withinNoiseFloor ? 'noise floor' : 'ok'),
      ]);

      if (regressed) {
        failures.add(
          '$walletType/$phase: ${baselineValue}ms -> ${currentValue}ms '
          '(+${(ratio * 100).toStringAsFixed(1)}%, limit '
          '${(maxRegression * 100).toStringAsFixed(0)}%)',
        );
      }
    }
  }

  _printTable(rows);

  final baselineEnvironment = _readEnvironment(baselinePath);
  final currentEnvironment = _readEnvironment(currentPath);
  if (baselineEnvironment['os'] != currentEnvironment['os']) {
    // Loud, but not fatal on its own: the numbers are still the best signal
    // available, and a hard failure here would make the gate unusable locally.
    stderr.writeln(
      'WARNING: baseline was measured on ${baselineEnvironment['os']} and this '
      'run is on ${currentEnvironment['os']}. Treat a marginal result as '
      'inconclusive and re-run on the baseline platform.',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln('\nBench gate passed.');
    return;
  }

  stderr
    ..writeln('\nBench gate FAILED:')
    ..writeln(failures.map((f) => '  - $f').join('\n'))
    ..writeln(
      '\nIf this regression is intentional, edit $baselinePath in this PR so '
      'the new number is reviewed alongside the change that caused it.',
    );
  exit(1);
}

Map<String, Map<String, int>> _readMedians(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing benchmark file: $path');
    exit(2);
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic> || decoded['median'] is! Map) {
    stderr.writeln('$path has no "median" object; is it a bench result?');
    exit(2);
  }
  final median = decoded['median'] as Map<String, dynamic>;
  return {
    for (final entry in median.entries)
      entry.key: {
        for (final phase in (entry.value as Map<String, dynamic>).entries)
          if (phase.value is num) phase.key: (phase.value as num).round(),
      },
  };
}

Map<String, Object?> _readEnvironment(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is Map<String, dynamic> && decoded['environment'] is Map) {
    return (decoded['environment'] as Map).cast<String, Object?>();
  }
  return const {};
}

Map<String, String> _parseArgs(List<String> arguments) {
  final parsed = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('--')) continue;
    final name = argument.substring(2);
    if (name.contains('=')) {
      final split = name.split('=');
      parsed[split.first] = split.sublist(1).join('=');
    } else if (i + 1 < arguments.length &&
        !arguments[i + 1].startsWith('--')) {
      parsed[name] = arguments[++i];
    } else {
      parsed[name] = 'true';
    }
  }
  return parsed;
}

void _printTable(List<List<String>> rows) {
  if (rows.isEmpty) {
    stdout.writeln('No gated phases compared.');
    return;
  }
  const header = ['phase', 'baseline', 'current', 'delta', 'status'];
  final all = [header, ...rows];
  final widths = List<int>.generate(
    header.length,
    (i) => all.map((r) => r[i].length).reduce((a, b) => a > b ? a : b),
  );
  for (final row in all) {
    stdout.writeln(
      [
        for (var i = 0; i < row.length; i++) row[i].padRight(widths[i]),
      ].join('  '),
    );
  }
}
