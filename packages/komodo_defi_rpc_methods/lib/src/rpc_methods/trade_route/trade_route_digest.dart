import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_rpc_methods/src/rpc_methods/trade_route/trade_route_models.dart';

const int _digestVersion = 1;
const int _javascriptMaxSafeInteger = 9007199254740991;

/// A route digest projection could not be represented as RFC 8785 JSON.
final class TradeRouteDigestException implements Exception {
  const TradeRouteDigestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the SHA-256 digest of an RFC 8785-compatible JSON value.
///
/// KDF rejects numeric values outside JavaScript's safe-integer range before
/// canonicalization. Route contracts use decimal strings for economic values;
/// keeping the same numeric guard here prevents a Dart-only digest from
/// silently disagreeing with native or WASM KDF.
String tradeRouteCanonicalDigest(Object? value) {
  _validateSafeNumbers(value, r'$');
  return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
}

/// Recomputes KDF's exact digest projection for a route candidate.
String tradeRouteCandidateDigest(TradeRouteCandidate candidate) {
  final json = _normalizeKdfWire(candidate.toJson());
  return tradeRouteCanonicalDigest({
    'digest_version': _digestVersion,
    'route_source': json['route_source'],
    'stages': json['stages'],
    'expected_receive': json['expected_receive'],
    'minimum_receive': json['minimum_receive'],
    'fees': json['fees'],
    'net_receive_value': json['net_receive_value'],
    'valuation_observed_at': json['valuation_observed_at'],
    'rank_status': json['rank_status'],
    'quote_observed_at': json['quote_observed_at'],
    'expires_at': json['expires_at'],
    'warnings': json['warnings'],
  });
}

/// Recomputes KDF's exact versioned digest for a resolved route intent.
String tradeRouteIntentDigest(TradeIntent intent) => tradeRouteCanonicalDigest({
  'digest_version': _digestVersion,
  'route_intent': _normalizeKdfWire(intent.toJson()),
});

/// Recomputes the RFC 8785 digest of KDF's safe prepared Review projection.
String tradeRoutePreparedExecutionReviewDigest(
  PreparedExecutionReview review,
) => tradeRouteCanonicalDigest(_normalizeKdfWire(review.toJson()));

/// Recomputes KDF's exact digest projection for one external stage consent.
String tradeRouteStageConsentDigest(StageConsent consent) {
  final json = _normalizeKdfWire(consent.toJson());
  return tradeRouteCanonicalDigest({
    'digest_version': json['digest_version'],
    'candidate_reference': json['candidate_reference'],
    'route_intent': json['route_intent'],
    'stage_intent': json['stage_intent'],
    'execution_source': json['execution_source'],
    'mode': json['mode'],
    'atomic_order_guard': json['atomic_order_guard'],
    if (json.containsKey('prepared_execution'))
      'prepared_execution': json['prepared_execution'],
  });
}

/// Recomputes KDF's exact digest projection for complete route consent.
String tradeRouteConsentDigest(RouteConsent consent) {
  final json = _normalizeKdfWire(consent.toJson());
  return tradeRouteCanonicalDigest({
    'digest_version': json['digest_version'],
    'evaluation_id': json['evaluation_id'],
    'candidate_id': json['candidate_id'],
    'candidate_digest': json['candidate_digest'],
    'route_intent': json['route_intent'],
    'external_stage_consents': json['external_stage_consents'],
    'atomic_order_guards': json['atomic_order_guards'],
    'mode': json['mode'],
    'consent_expires_at': json['consent_expires_at'],
    if (json.containsKey('prepared_at')) 'prepared_at': json['prepared_at'],
    if (json.containsKey('prepared_review_digest'))
      'prepared_review_digest': json['prepared_review_digest'],
  });
}

Map<String, Object?> _normalizeKdfWire(Map<String, dynamic> value) =>
    Map<String, Object?>.from(_normalizeWireValue(value)! as Map);

Object? _normalizeWireValue(Object? value, [String? field]) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _normalizeWireValue(
          entry.value,
          entry.key as String,
        ),
    };
  }
  if (value is List) {
    return value.map(_normalizeWireValue).toList(growable: false);
  }
  if (value is String && _timestampFields.contains(field)) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw TradeRouteDigestException('Invalid KDF timestamp at $field.');
    }
    return _kdfTimestamp(parsed);
  }
  return value;
}

String _kdfTimestamp(DateTime value) {
  final encoded = value.toUtc().toIso8601String();
  return encoded
      .replaceFirst(RegExp(r'\.0+Z$'), 'Z')
      .replaceFirstMapped(
        RegExp(r'\.(\d+?)0+Z$'),
        (match) => '.${match.group(1)}Z',
      );
}

const _timestampFields = <String>{
  'archived_at',
  'consent_expires_at',
  'expires_at',
  'observed_at',
  'order_snapshot_at',
  'prepared_at',
  'provider_observed_at',
  'quote_observed_at',
  'valuation_observed_at',
  'valid_until',
};

void _validateSafeNumbers(Object? value, String path) {
  if (value is int) {
    if (value < -_javascriptMaxSafeInteger ||
        value > _javascriptMaxSafeInteger) {
      throw TradeRouteDigestException(
        'Numeric value outside the JavaScript safe-integer range at $path.',
      );
    }
    return;
  }
  if (value is double) {
    if (!value.isFinite ||
        value < -_javascriptMaxSafeInteger ||
        value > _javascriptMaxSafeInteger) {
      throw TradeRouteDigestException('Invalid numeric value at $path.');
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw TradeRouteDigestException('Non-string JSON key at $path.');
      }
      _validateSafeNumbers(entry.value, '$path.${entry.key}');
    }
    return;
  }
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      _validateSafeNumbers(value[index], '$path[$index]');
    }
    return;
  }
  if (value != null && value is! bool && value is! String) {
    throw TradeRouteDigestException(
      'Unsupported JSON value ${value.runtimeType} at $path.',
    );
  }
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    final entries = keys.map(
      (key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}',
    );
    return '{${entries.join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}
