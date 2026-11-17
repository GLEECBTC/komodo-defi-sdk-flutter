import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Fixed catalog injection exercises the production registry and storage path
/// without modifying bundled production assets or making update HTTP calls.
class _FixtureCatalog implements CoinConfigProvider, CoinConfigDataFactory {
  List<Asset> get assets => const AssetParser().parseAssetsFromConfig({
    SolanaWalletFixture.platform: SolanaWalletFixture.platformConfig(),
    SolanaWalletFixture.token: SolanaWalletFixture.tokenConfig(),
  });

  @override
  Future<List<Asset>> getAssets({String? branch}) async => assets;

  @override
  Future<List<Asset>> getAssetsForCommit(String commit) async => assets;

  @override
  Future<String> getLatestCommit({
    String? branch,
    String? apiBaseUrl,
    String? githubToken,
  }) async => 'solana-replay-immutable';

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

KomodoDefiSdkConfig _config({bool enabled = true}) => KomodoDefiSdkConfig(
  defaultAssets: const {},
  preActivateDefaultAssets: false,
  preActivateHistoricalAssets: false,
  preActivateCustomTokenAssets: false,
  assetsAutoUpdate: false,
  assetsStorageNamespace: 'solana-replay-only',
  assetsDataFactory: _FixtureCatalog(),
  solanaCapabilities: SolanaCapabilities(enabled: enabled),
);

Asset _asset(KdfHarness harness, String ticker) => harness
    .sdk
    .assets
    .available
    .values
    .singleWhere((asset) => asset.id.id == ticker);

void main() {
  group('Solana real SDK orchestration with replayed engine', () {
    for (final mode in harnessWalletTypes) {
      test(
        '${mode.name}: zero balance, single address and late SPL activation',
        () async {
          final harness = await KdfHarness.replayed(
            script: SolanaWalletFixture().build(),
            config: _config(),
          );
          addTearDown(harness.dispose);
          await harness.signIn(walletType: mode);
          final sol = _asset(harness, SolanaWalletFixture.platform);
          final token = _asset(harness, SolanaWalletFixture.token);
          expect((await harness.sdk.activateAsset(sol)).isSuccess, isTrue);
          final solKeys = await harness.sdk.pubkeys.getPubkeys(sol);
          expect((await harness.sdk.activateAsset(token)).isSuccess, isTrue);
          final tokenKeys = await harness.sdk.pubkeys.getPubkeys(token);
          expect(solKeys.keys, hasLength(1));
          expect(tokenKeys.keys, hasLength(1));
          expect(solKeys.keys.single.address, tokenKeys.keys.single.address);
          expect(solKeys.balance.spendable, Decimal.zero);
          expect(tokenKeys.balance.spendable, Decimal.zero);
          expect(
            harness.operations.startParams_['enable_hd'],
            mode == KdfWalletType.hd,
          );
          expect(
            harness.script.callsTo('experimental::enable_solana_with_assets'),
            1,
          );
          expect(
            harness.script.callsTo('experimental::enable_solana_token'),
            1,
          );
          expect(
            harness.script.callLog.where(
              (method) => method.startsWith('task::'),
            ),
            isEmpty,
          );
          final activation = harness.operations.requests.singleWhere(
            (request) =>
                request['method'] == 'experimental::enable_solana_with_assets',
          );
          final params = activation['params'] as Map<String, dynamic>;
          expect(params['nodes'], [
            {'url': 'https://api.devnet.solana.com'},
          ]);
          for (final forbidden in [
            'account',
            'path_to_address',
            'gap_limit',
            'scan_policy',
          ]) {
            expect(params.containsKey(forbidden), isFalse);
          }
          final late =
              harness.operations.requests.singleWhere(
                    (request) =>
                        request['method'] ==
                        'experimental::enable_solana_token',
                  )['params']
                  as Map<String, dynamic>;
          expect(
            late['protocol'],
            SolanaWalletFixture.tokenConfig()['protocol'],
          );
        },
      );

      test(
        '${mode.name}: a custom SPL token activates its inactive platform',
        () async {
          final harness = await KdfHarness.replayed(
            script: SolanaWalletFixture().build(),
            config: _config(),
          );
          addTearDown(harness.dispose);
          await harness.signIn(walletType: mode);
          final sol = _asset(harness, SolanaWalletFixture.platform);
          final custom = Asset.fromJson(
            {...SolanaWalletFixture.tokenConfig(), 'is_custom_token': true},
            knownIds: {sol.id},
          );
          expect((await harness.sdk.activateAsset(custom)).isSuccess, isTrue);
          expect(
            harness.script.callsTo('experimental::enable_solana_with_assets'),
            1,
          );
          expect(
            harness.script.callsTo('experimental::enable_solana_token'),
            0,
          );
          final params =
              harness.operations.requests.singleWhere(
                    (request) =>
                        request['method'] ==
                        'experimental::enable_solana_with_assets',
                  )['params']
                  as Map<String, dynamic>;
          expect((params['tokens_params'] as List).single, {
            'ticker': custom.id.id,
            'protocol': custom.protocol.config['protocol'],
          });
        },
      );

      test(
        '${mode.name}: SPL history keeps case, SOL fees and no invented memo '
        'across restart',
        () async {
          final workspace = await Directory.systemTemp.createTemp(
            'solana_history_',
          );
          addTearDown(() async {
            if (workspace.existsSync()) await workspace.delete(recursive: true);
          });
          final first = await KdfHarness.replayed(
            script: SolanaWalletFixture().build(),
            config: _config(),
            workspace: workspace,
            deleteWorkspaceOnDispose: false,
          );
          await first.signIn(walletType: mode);
          final rows = await first.sdk.transactions
              .watchTransactionHistoryMerged(
                _asset(first, SolanaWalletFixture.token),
              )
              .first
              .timeout(const Duration(seconds: 20));
          expect(rows.single.txHash, SolanaWalletFixture.signature);
          expect(rows.single.memo, isNull);
          expect(rows.single.fee, isA<SolanaFeeInfo>());
          expect(rows.single.fee!.coin, SolanaWalletFixture.platform);
          expect(rows.single.assetId.chainId.decimals, 6);
          final historyRequests = first.operations.requests.where(
            (r) => r['method'] == 'my_tx_history',
          );
          expect(historyRequests, isNotEmpty);
          for (final request in historyRequests) {
            expect(request['mmrpc'], '2.0');
            expect((request['params'] as Map).containsKey('target'), isFalse);
          }
          await first.dispose();
          final second = await KdfHarness.replayed(
            script: SolanaWalletFixture(serveHistory: false).build(),
            config: _config(),
            workspace: workspace,
            deleteWorkspaceOnDispose: false,
          );
          addTearDown(second.dispose);
          await second.signIn(walletType: mode);
          final restored = await second.sdk.transactions
              .watchTransactionHistoryMerged(
                _asset(second, SolanaWalletFixture.token),
              )
              .first
              .timeout(const Duration(seconds: 20));
          expect(restored.single.txHash, SolanaWalletFixture.signature);
          expect(restored.single.fee!.coin, SolanaWalletFixture.platform);
          expect(restored.single.fee!.totalFee, Decimal.parse('0.000005'));
          expect(restored.single.memo, isNull);
        },
      );
    }

    test('an unsupported engine cannot dispatch Solana activation', () async {
      final harness = await KdfHarness.replayed(
        script: SolanaWalletFixture().build(),
        config: _config(enabled: false),
      );
      addTearDown(harness.dispose);
      await harness.signIn(walletType: KdfWalletType.iguana);
      expect(harness.sdk.assets.available, isEmpty);
      final staleAsset = Asset.fromJson(SolanaWalletFixture.platformConfig());
      await expectLater(
        harness.sdk.pubkeys.getPubkeys(staleAsset),
        throwsA(anything),
      );
      expect(
        harness.script.callsTo('experimental::enable_solana_with_assets'),
        0,
      );
      expect(harness.script.callsTo('experimental::enable_solana_token'), 0);
      expect(harness.script.callsTo('my_balance'), 0);
    });
  });
}
