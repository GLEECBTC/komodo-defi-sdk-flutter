import 'dart:async';

import 'package:komodo_defi_types/src/utils/security_utils.dart';

/// Conservative filtering for diagnostic copies, never operational payloads.
///
/// Sources must emit metadata-only events. This filter is defense in depth:
/// arbitrary free text cannot be proven secret-free by pattern matching.
abstract final class DiagnosticSanitizer {
  static const _methods = <String>{
    'unknown',
    'version',
    'stop',
    'get_mnemonic',
    'get_private_keys',
    'show_priv_key',
    'get_enabled_coins',
    'get_wallet_names',
    'get_public_key_hash',
    'get_public_key',
    'my_balance',
    'account_balance',
    'enable',
    'electrum',
    'disable_coin',
    'withdraw',
    'send_raw_transaction',
    'enable_eth_with_tokens',
    'enable_bch_with_tokens',
    'enable_tendermint_with_assets',
    'enable_erc20',
    'enable_slp',
    'enable_tendermint_token',
    'task::enable_utxo::init',
    'task::enable_utxo::status',
    'task::enable_eth::init',
    'task::enable_eth::status',
    'task::enable_z_coin::init',
    'task::enable_z_coin::status',
    'task::account_balance::init',
    'task::account_balance::status',
    'task::account_balance::cancel',
    'gasless::get_configuration',
    'gasless::get_account',
    'gasless::estimate',
    'gasless::submit',
  };

  static final _rpcSummary = RegExp(
    '^RPC method=([a-z_0-9]+(?:::[a-z_0-9]+)*) outcome=(success|failure)'
    r'(?: duration_ms=([0-9]{1,12}))?$',
  );
  static final _unsafeText = RegExp(
    r'[\x00-\x1f\x7f{}\[\]]|https?://'
    r'|\b(?:RPC response|mm2Rpc request|activation parameters|mm2 config)\b'
    r'|\b(?:mnemonic|passphrase|password|userpass|seed|priv[_ -]?key'
    '|private[_ -]?keys?|secret|authorization|bearer|access[_ -]?token'
    r'|refresh[_ -]?token|signature|wif)\b|(?:0x)?[0-9a-f]{40,}'
    r'|\b[5KL][1-9A-HJ-NP-Za-km-z]{50,51}\b|\b(?:[a-z]+ ){11,}[a-z]+\b',
    caseSensitive: false,
  );
  static final _fieldLabel = RegExp(r'([A-Za-z][A-Za-z0-9_-]*)\s*[:=]');

  /// Returns null when a record must be omitted. Never stringifies objects.
  static String? sanitizeMessage(Object? message) {
    if (message is! String || message.isEmpty || message.length > 1024) {
      return null;
    }
    final match = _rpcSummary.firstMatch(message);
    if (match != null && _methods.contains(match.group(1))) return message;
    // Unrecognized RPC text is never a fallback diagnostic format.
    if (message.toUpperCase().startsWith('RPC ')) return null;
    if (_fieldLabel
        .allMatches(message)
        .any(
          (match) => SecurityUtils.isSensitiveDiagnosticKey(match.group(1)!),
        )) {
      return null;
    }
    if (_unsafeText.hasMatch(message)) return null;
    return message;
  }

  /// Fixed categories only; messages, sources and stacks may be secret.
  static String safeError(Object? error) => switch (error) {
    TimeoutException() => 'timeout',
    FormatException() => 'format',
    ArgumentError() => 'argument',
    StateError() => 'state',
    UnsupportedError() || UnimplementedError() => 'unsupported',
    _ => 'unknown',
  };

  /// The method is an exact allowlist lookup, not an interpolated RPC field.
  static String rpcSummary({
    required Object? method,
    required bool success,
    int? elapsedMilliseconds,
  }) {
    final safeMethod = method is String && _methods.contains(method)
        ? method
        : 'unknown';
    final duration = elapsedMilliseconds;
    final durationText =
        duration != null && duration >= 0 && duration < 1000000000000
        ? ' duration_ms=$duration'
        : '';
    return 'RPC method=$safeMethod outcome=${success ? 'success' : 'failure'}'
        '$durationText';
  }
}
