import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'solana_fixture_catalog.dart';

KomodoDefiSdkConfig _config({bool enabled = true}) => solanaFixtureSdkConfig(
  storageNamespace: 'solana-replay-only',
  enabled: enabled,
);

/// The tickers KDF's coins config listed at the last start.
Set<String> _startTickers(KdfHarness harness) => {
  for (final coin in harness.operations.startParams_['coins'] as List<dynamic>)
    (coin as Map<String, dynamic>)['coin'] as String,
};

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
          // KDF's coins config is the injected catalog, not the bundled one.
          expect(_startTickers(harness), {
            SolanaWalletFixture.platform,
            SolanaWalletFixture.token,
          });
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
          // A catalog token is in KDF's coins config, which refuses a
          // request protocol for it as a duplicate custom token.
          expect(late, {
            'ticker': SolanaWalletFixture.token,
            'activation_params': <String, dynamic>{},
          });
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
            {
              ...SolanaWalletFixture.tokenConfig(),
              'coin': 'CUSTOM-TESTSOL',
              'is_custom_token': true,
            },
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

    test('each SDK starts KDF with its own catalog', () async {
      // KDF startup once memoized the first catalog it read for the process.
      final fixture = await KdfHarness.replayed(
        script: SolanaWalletFixture().build(),
        config: _config(),
      );
      await fixture.signIn(walletType: KdfWalletType.iguana);
      expect(_startTickers(fixture), hasLength(2));
      await fixture.dispose();
      final bundled = await KdfHarness.replayed(
        script: KdfWalletFixture().build(),
      );
      addTearDown(bundled.dispose);
      await bundled.signIn(walletType: KdfWalletType.iguana);
      expect(_startTickers(bundled), contains('KMD'));
      expect(
        _startTickers(bundled),
        isNot(contains(SolanaWalletFixture.platform)),
      );
    });

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
