import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show BackoffStrategy;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Primary extends Mock implements CexRepository {}

class _Fallback extends Mock implements CexRepository {}

const _delay = Duration(milliseconds: 60);

/// Records each wait the mixin asks for.
class _RecordingBackoff implements BackoffStrategy {
  _RecordingBackoff(this.attempts);

  final List<int> attempts;

  @override
  Duration nextDelay(int attempt, Duration currentDelay) {
    attempts.add(attempt);
    return _delay;
  }

  @override
  BackoffStrategy clone() => _RecordingBackoff(attempts);
}

class _InListOrder implements RepositorySelectionStrategy {
  @override
  Future<void> ensureCacheInitialized(List<CexRepository> repositories) async {}

  @override
  Future<CexRepository?> selectRepository({
    required AssetId assetId,
    required QuoteCurrency fiatCurrency,
    required PriceRequestType requestType,
    required List<CexRepository> availableRepositories,
  }) async => availableRepositories.firstOrNull;
}

class _Manager with RepositoryFallbackMixin {
  _Manager(this.priceRepositories);

  final waits = <int>[];

  @override
  final List<CexRepository> priceRepositories;

  @override
  final RepositorySelectionStrategy selectionStrategy = _InListOrder();

  @override
  BackoffStrategy get fallbackBackoffStrategy => _RecordingBackoff(waits);
}

final _btc = AssetId(
  id: 'BTC',
  name: 'Bitcoin',
  symbol: AssetSymbol(assetConfigId: 'BTC'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

void main() {
  late _Primary primary;
  late _Fallback fallback;
  late List<(CexRepository, Duration)> calls;
  late Stopwatch clock;

  setUpAll(() {
    registerFallbackValue(_btc);
    registerFallbackValue(Stablecoin.usdt);
    registerFallbackValue(PriceRequestType.currentPrice);
  });

  setUp(() {
    primary = _Primary();
    fallback = _Fallback();
    calls = [];
    clock = Stopwatch()..start();
    for (final repo in <CexRepository>[primary, fallback]) {
      when(() => repo.supports(any(), any(), any()))
          .thenAnswer((_) async => true);
    }
  });

  void answer(CexRepository repo, Future<Decimal> Function() price) {
    when(
      () => repo.getCoinFiatPrice(
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) {
      calls.add((repo, clock.elapsed));
      return price();
    });
  }

  Future<Decimal> lookUp(_Manager manager) => manager.tryRepositoriesInOrder(
    _btc,
    Stablecoin.usdt,
    PriceRequestType.currentPrice,
    (repo) => repo.getCoinFiatPrice(_btc),
    'fiatPrice',
  );

  group('RepositoryFallbackMixin retries', () {
    test(
      'waits before asking a repository that already failed in the lookup',
      () async {
        final manager = _Manager([primary]);
        answer(primary, () async => throw Exception('Connection reset'));

        await expectLater(lookUp(manager), throwsException);

        expect(calls, hasLength(3));
        expect(manager.waits, [0, 1]);
        // Timers may fire a little early against a Stopwatch.
        const tolerance = Duration(milliseconds: 10);
        expect(calls[1].$2 - calls[0].$2, greaterThan(_delay - tolerance));
        expect(calls[2].$2 - calls[1].$2, greaterThan(_delay - tolerance));
      },
    );

    test('moves on to another repository without waiting', () async {
      final manager = _Manager([primary, fallback]);
      answer(primary, () async => throw Exception('Connection reset'));
      answer(fallback, () async => Decimal.one);

      expect(await lookUp(manager), Decimal.one);

      expect(calls.map((call) => call.$1), [primary, fallback]);
      expect(manager.waits, isEmpty);
    });

    test('never asks a rate-limited repository again', () async {
      final manager = _Manager([primary]);
      answer(
        primary,
        () async => throw MarketDataApiException(
          ApiErrorParser.parseCoinPaprikaError(402, null),
          service: 'CoinPaprika',
        ),
      );

      await expectLater(lookUp(manager), throwsException);
      await expectLater(lookUp(manager), throwsException);

      expect(calls, hasLength(1));
      expect(manager.waits, isEmpty);
    });
  });

  group('RepositoryFallbackMixin rejected requests', () {
    test('are not repeated within the lookup', () async {
      final manager = _Manager([primary]);
      answer(primary, () async => throw ArgumentError('Asset not found'));

      await expectLater(lookUp(manager), throwsException);

      expect(calls, hasLength(1));
      expect(manager.waits, isEmpty);
    });

    test('still fall back to the next repository', () async {
      final manager = _Manager([primary, fallback]);
      answer(
        primary,
        () async => throw UnsupportedError('No history from this feed'),
      );
      answer(fallback, () async => Decimal.one);

      expect(await lookUp(manager), Decimal.one);
      expect(calls.map((call) => call.$1), [primary, fallback]);
    });
  });
}
