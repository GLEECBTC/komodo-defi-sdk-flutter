import 'dart:io' show Platform;

/// A value that must never reach a log, an assertion message or CI output.
///
/// [toString] is deliberately lossy, so an accidental interpolation - the usual
/// way a seed escapes - prints `Secret(***)` instead of the value.
class Secret {
  const Secret(this._value);

  final String _value;

  /// The only way to read the value. Call it as late as possible, and never
  /// into a variable that outlives the call.
  String reveal() => _value;

  bool get isEmpty => _value.isEmpty;

  @override
  String toString() => 'Secret(***)';
}

/// A seed for the process tier of the harness.
///
/// Constructible only from the environment: there is no literal constructor, so
/// a seed cannot be committed to this repo by accident.
class KdfTestSeed {
  const KdfTestSeed._(this.value);

  /// Reads [variable] from the environment, or null when unset/blank.
  ///
  /// Returning null (rather than throwing) lets a test skip cleanly on a
  /// machine that has no funded seed configured.
  static KdfTestSeed? fromEnv(String variable) {
    final raw = Platform.environment[variable]?.trim();
    if (raw == null || raw.isEmpty) return null;
    return KdfTestSeed._(Secret(raw));
  }

  final Secret value;

  @override
  String toString() => 'KdfTestSeed(***)';
}

/// Redacts every known secret from [line] before it is written anywhere.
///
/// Applied sink-side rather than at each call site: the framework's own log
/// stream echoes start parameters, which contain the passphrase and both
/// passwords.
String redactSecrets(String line, Iterable<Secret> secrets) {
  var redacted = line;
  for (final secret in secrets) {
    if (secret.isEmpty) continue;
    redacted = redacted.replaceAll(secret.reveal(), '***');
  }
  return redacted;
}
