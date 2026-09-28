import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fixtures/mock_helpers.dart';
import 'fixtures/test_constants.dart';
import 'fixtures/test_fixtures.dart';
import 'fixtures/verification_helpers.dart';

// Runs the real provider over a client that keys each ticker's quotes by the
// symbols requested, as the live API does, so the key the provider asks for is
// checked against the key the repository reads.
void main() {
  setUpAll(MockHelpers.registerFallbackValues);

  group('CoinPaprikaRepository ticker quote keys', () {
    late MockHttpClient httpClient;
    late CoinPaprikaRepository repository;

    setUp(() {
      httpClient = MockHttpClient();
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        final quotes = uri.queryParameters['quotes']!.toUpperCase();
        final requested = quotes.split(',');
        return TestFixtures.createTickerResponse(
          quotes: TestFixtures.createMultipleQuotes(
            currencies: requested,
            prices: [for (final _ in requested) TestConstants.bitcoinPrice],
          ),
        );
      });
      repository = CoinPaprikaRepository(
        coinPaprikaProvider: CoinPaprikaProvider(httpClient: httpClient),
        enableMemoization: false,
      );
    });

    test('reads a USDT price from the USD quote CoinPaprika returns', () async {
      final price = await repository.getCoinFiatPrice(TestData.bitcoinAsset);

      expect(price, equals(TestData.bitcoinPriceDecimal));
      VerificationHelpers.verifyTickerUrl(
        httpClient,
        TestConstants.bitcoinCoinId,
        expectedQuotes: TestConstants.usdQuote,
      );
    });

    test(
      'reads a USDT 24h change from the USD quote CoinPaprika returns',
      () async {
        final change = await repository.getCoin24hrPriceChange(
          TestData.bitcoinAsset,
        );

        expect(change, equals(TestData.positiveChangeDecimal));
        VerificationHelpers.verifyTickerUrl(
          httpClient,
          TestConstants.bitcoinCoinId,
          expectedQuotes: TestConstants.usdQuote,
        );
      },
    );
  });
}
