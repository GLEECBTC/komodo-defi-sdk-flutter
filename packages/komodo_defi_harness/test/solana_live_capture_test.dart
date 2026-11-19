import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

part 'solana_live_capture_disable.dart';
part 'solana_live_capture_rules.dart';

/// Holds [SolanaWalletFixture] to what the pinned engine actually returned.
///
/// The replay suite trusts the fixture's Solana rules; this suite replays the
/// captured requests through it in order and compares every reply, so a
/// fixture that accepts a request KDF refuses (as it once accepted a catalog
/// SPL token with a `protocol`) fails here rather than hiding an SDK bug.
class _Exchange {
  const _Exchange(this.name, this.request, this.reply);

  final String name;
  final String request;
  final String reply;
}

/// The captured engine's coins config listed the fixture catalog.
final _captureStartParams = <String, dynamic>{
  'coins': [
    SolanaWalletFixture.platformConfig(),
    SolanaWalletFixture.tokenConfig(),
  ],
};

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// Slots differ per capture; [keepAddress] is false where it was removed.
Map<String, dynamic> _comparable(
  Map<String, dynamic> reply, {
  required bool keepAddress,
}) {
  final copy = _decode(jsonEncode(reply));
  final result = copy['result'];
  if (result is Map<String, dynamic>) {
    if (result.containsKey('current_block')) {
      expect(result['current_block'], isA<int>());
      result.remove('current_block');
    }
    if (!keepAddress) result.remove('address');
  }
  return copy;
}

void main() {
  group('Solana fixture replays the captured engine', () {
    for (final (name, exchanges, keepAddress) in [
      ('catalog, custom and unknown token requests', _rulesExchanges, true),
      ('token and platform disable', _disableExchanges, false),
    ]) {
      test(name, () async {
        final script = SolanaWalletFixture().build();
        script.onKdfStart!(_captureStartParams);
        for (final exchange in exchanges) {
          final actual = await script.respondTo(_decode(exchange.request));
          expect(actual, isNotNull, reason: exchange.name);
          expect(
            _comparable(actual!, keepAddress: keepAddress),
            _comparable(_decode(exchange.reply), keepAddress: keepAddress),
            reason: exchange.name,
          );
        }
      });
    }
  });

  group('captured replies', () {
    _Exchange find(String name) => [
      ..._rulesExchanges,
      ..._disableExchanges,
    ].singleWhere((exchange) => exchange.name == name);

    test('a catalog token with a protocol is a duplicate custom token', () {
      for (final name in [
        'batch_catalog_token_with_protocol',
        'later_catalog_token_with_protocol',
      ]) {
        final reply = _decode(find(name).reply);
        expect(GeneralErrorResponse.isErrorResponse(reply), isTrue);
        expect(reply['error_type'], 'CustomTokenError');
        expect(reply['error_data'], {
          'DuplicateTickerInConfig': {'ticker_in_config': 'TESTUSDC-TESTSOL'},
        });
      }
    });

    test('the SDK models read the successful activations', () {
      final batch = EnableSolanaWithAssetsResponse.parse(
        _decode(find('batch_catalog_token_by_ticker').reply),
      );
      expect(batch.ticker, SolanaWalletFixture.platform);
      expect(batch.tokensBalances.keys, [SolanaWalletFixture.token]);
      final later = EnableSolanaTokenResponse.parse(
        _decode(find('later_catalog_token_by_ticker').reply),
      );
      expect(later.ticker, SolanaWalletFixture.token);
      final custom = EnableSolanaTokenResponse.parse(
        _decode(find('later_custom_token_with_protocol').reply),
      );
      expect(custom.ticker, 'CUSTOM-TESTSOL');
    });

    test('disabling a platform with active tokens only passivizes it', () {
      final disabled = _decode(find('disable_platform_with_tokens').reply);
      expect((disabled['result'] as Map)['passivized'], isTrue);
      final listed = _decode(
        find('enabled_after_platform_with_tokens_disable').reply,
      );
      expect(
        ((listed['result'] as Map)['coins'] as List).map(
          (coin) => (coin as Map)['ticker'],
        ),
        [
          SolanaWalletFixture.platform,
          SolanaWalletFixture.token,
          'CUSTOM-TESTSOL',
        ],
      );
    });
  });
}
