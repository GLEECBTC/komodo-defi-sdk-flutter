import 'dart:io';

import 'package:komodo_defi_harness/src/kdf_binary.dart';
import 'package:komodo_defi_harness/src/kdf_port.dart';
import 'package:komodo_defi_harness/src/secret.dart';

/// Everything the process tier needs, and a readable reason when it is absent.
///
/// The three preconditions are checked together and reported as text so a
/// skipped test says *why* it skipped. A nightly job that silently ran zero
/// tests for a month because a secret expired is the failure mode this exists
/// to avoid.
class KdfProcessRequirements {
  const KdfProcessRequirements._({
    required this.reasons,
    this.binary,
    this.seed,
  });

  /// The opt-in switch.
  ///
  /// Gating is on this and **not** on binary-existence. The SDK's own
  /// `flutter-tests.yml` runs the build transformer, so the binary does exist
  /// there; an existence check would fail to skip and a real KDF would spawn
  /// inside a workflow with no timeout budget for it.
  static const String environmentVariable = 'KDF_HARNESS';

  /// The only source of a seed. There is no literal constructor, so a funded
  /// seed cannot be committed by accident.
  static const String seedEnvironmentVariable = 'KDF_TEST_SEED';

  final List<String> reasons;
  final KdfBinary? binary;
  final KdfTestSeed? seed;

  bool get isSatisfied => reasons.isEmpty;

  /// A single line suitable for `skip:`.
  String get skipReason =>
      'process tier not run: ${reasons.join('; ')}';

  /// [port] is the port the run intends to bind, which no longer has to be
  /// [kdfRpcPort]: `LocalConfig` now carries one end to end.
  static Future<KdfProcessRequirements> check({
    int port = kdfRpcPort,
  }) async {
    final reasons = <String>[];

    final optIn = Platform.environment[environmentVariable]?.trim();
    if (optIn == null || optIn.isEmpty || optIn == '0' || optIn == 'false') {
      reasons.add('$environmentVariable is not set');
    }

    final seed = KdfTestSeed.fromEnv(seedEnvironmentVariable);
    if (seed == null) reasons.add('$seedEnvironmentVariable is not set');

    final binary = await KdfBinary.autoDetect();
    if (binary == null) {
      reasons.add(
        'no KDF binary found (run the build transformer, or set '
        '${KdfBinary.pathEnvironmentVariable})',
      );
    }

    // Wait rather than probe once: the previous test's KDF may still be
    // releasing the listener. Reporting "in use" immediately turned every
    // process test after the first into a skip, which looks like a missing
    // configuration rather than a race.
    if (reasons.isEmpty && !await waitForFreeKdfPort(port: port)) {
      reasons.add('port $port is still in use (lsof -nP -iTCP:$port)');
    }

    return KdfProcessRequirements._(
      reasons: reasons,
      binary: binary,
      seed: seed,
    );
  }
}
