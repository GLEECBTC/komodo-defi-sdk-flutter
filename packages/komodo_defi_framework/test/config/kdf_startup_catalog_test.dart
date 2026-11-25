import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:path/path.dart' as path;

/// A catalog of [tickers] that counts how often KDF startup reads it.
class _CountingCatalog implements CoinConfigProvider, CoinConfigDataFactory {
  _CountingCatalog(this.tickers);

  final List<String> tickers;
  int reads = 0;

  List<Asset> get _assets => const AssetParser().parseAssetsFromConfig({
    for (final ticker in tickers)
      ticker: {
        'coin': ticker,
        'type': 'UTXO',
        'fname': ticker,
        'is_testnet': true,
        'protocol': {'type': 'UTXO'},
      },
  });

  @override
  Future<List<Asset>> getAssets({String? branch}) async {
    reads++;
    return _assets;
  }

  @override
  Future<List<Asset>> getAssetsForCommit(String commit) => getAssets();

  @override
  Future<String> getLatestCommit({
    String? branch,
    String? apiBaseUrl,
    String? githubToken,
  }) async => 'fixed';

  @override
  CoinConfigProvider createLocalProvider(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) => this;

  @override
  CoinConfigRepository createRepository(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) => CoinConfigRepository(coinConfigProvider: this);
}

List<String> _tickers(KdfStartupConfig config) => [
  for (final coin in config.encodeStartParams()['coins'] as List<dynamic>)
    (coin as Map<String, dynamic>)['coin'] as String,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('kdf_startup_catalog_');
    // Startup resolves Hive's folder, and a signed-out start its home,
    // through path_provider.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => home.path,
        );
  });
  tearDown(() => home.delete(recursive: true));

  Future<KdfStartupConfig> signIn(KdfStartupCatalog catalog) =>
      KdfStartupConfig.generateWithDefaults(
        walletName: 'wallet',
        walletPassword: 'wallet-secret',
        enableHd: true,
        rpcPassword: 'rpc-secret',
        userHome: home.path,
        dbDir: path.join(home.path, 'db'),
        seedNodes: const ['seed01.kmdefi.net'],
        catalog: catalog,
      );

  group('KdfStartupConfig coins', () {
    test('come from the injected catalog', () async {
      final catalog = KdfStartupCatalog(
        dataFactory: _CountingCatalog(['ONE-TEST', 'TWO-TEST']),
        storageNamespace: 'startup-catalog-test',
      );

      expect(_tickers(await signIn(catalog)), ['ONE-TEST', 'TWO-TEST']);
      expect(_tickers(await KdfStartupConfig.noAuthStartup(catalog: catalog)), [
        'ONE-TEST',
        'TWO-TEST',
      ]);
    });

    test('are read once per catalog, and catalogs stay apart', () async {
      final first = _CountingCatalog(['FIRST-TEST']);
      final second = _CountingCatalog(['SECOND-TEST']);
      KdfStartupCatalog catalog(_CountingCatalog source) => KdfStartupCatalog(
        dataFactory: source,
        storageNamespace: 'startup-catalog-test',
      );

      expect(_tickers(await signIn(catalog(first))), ['FIRST-TEST']);
      final firstLoadReads = first.reads;
      expect(firstLoadReads, isPositive);
      expect(_tickers(await signIn(catalog(second))), ['SECOND-TEST']);
      expect(second.reads, isPositive);
      expect(_tickers(await signIn(catalog(first))), ['FIRST-TEST']);
      expect(first.reads, firstLoadReads);
    });

    test('a coins path still wins over the catalog', () async {
      final source = _CountingCatalog(['UNREAD-TEST']);
      final config = await KdfStartupConfig.generateWithDefaults(
        walletName: 'wallet',
        walletPassword: 'wallet-secret',
        enableHd: true,
        rpcPassword: 'rpc-secret',
        coinsPath: 'coins',
        userHome: home.path,
        dbDir: path.join(home.path, 'db'),
        seedNodes: const ['seed01.kmdefi.net'],
        catalog: KdfStartupCatalog(dataFactory: source),
      );

      expect(config.encodeStartParams()['coins'], 'coins');
      expect(source.reads, 0);
    });
  });

  group('KdfStartupCatalog', () {
    test('with nothing injected is the bundled catalog', () {
      // Built at run time, as SDK bootstrap does, so not canonicalised.
      KdfStartupCatalog fromSdk({String? namespace}) =>
          KdfStartupCatalog(storageNamespace: namespace);

      expect(identical(fromSdk(), KdfStartupCatalog.bundled), isFalse);
      expect(fromSdk(), KdfStartupCatalog.bundled);
      expect(fromSdk().hashCode, KdfStartupCatalog.bundled.hashCode);
    });

    test('is keyed by its sources', () {
      final source = _CountingCatalog(['ONE-TEST']);
      const config = AssetRuntimeUpdateConfig(coinsRepoBranch: 'candidate');

      expect(
        KdfStartupCatalog(dataFactory: source, storageNamespace: 'a'),
        KdfStartupCatalog(dataFactory: source, storageNamespace: 'a'),
      );
      for (final other in [
        KdfStartupCatalog(dataFactory: source, storageNamespace: 'b'),
        KdfStartupCatalog(
          dataFactory: _CountingCatalog(['ONE-TEST']),
          storageNamespace: 'a',
        ),
        KdfStartupCatalog(
          dataFactory: source,
          storageNamespace: 'a',
          runtimeUpdateConfig: config,
        ),
      ]) {
        expect(
          other,
          isNot(KdfStartupCatalog(dataFactory: source, storageNamespace: 'a')),
        );
      }
      expect(
        const KdfStartupCatalog(runtimeUpdateConfig: config),
        const KdfStartupCatalog(
          runtimeUpdateConfig: AssetRuntimeUpdateConfig(
            coinsRepoBranch: 'candidate',
          ),
        ),
      );
    });
  });
}
