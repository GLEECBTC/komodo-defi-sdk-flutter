import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
// ignore: implementation_imports
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Why the asset details page still spins even though history is cached.
///
/// `TransactionHistoryBloc._onSubscribe` awaits
/// `pubkeys.lastKnown(id) ?? await pubkeys.getPubkeys(asset)` *before* it
/// subscribes to the history stream. `lastKnown` reads only the in-memory
/// cache, and `getPubkeys` falls through to `_fetchFreshPubkeys`, which awaits
/// `activateAsset` with retry, whenever the persisted pubkey cache misses.
///
/// So the ordering is: block on an unbounded pubkey fetch, *then* read a
/// transaction cache that was ready the whole time. The UI renders
/// `UiSpinnerList` for that entire window, because a freshly built bloc starts
/// at `transactions: []` with `loading: true`.
///
/// This pins both halves: the history is servable immediately, and the gate in
/// front of it is not.
const _ticker = 'KMD';
const _internalId = 'harness-tx-0';

Asset _assetFor(KdfHarness harness) => harness.sdk.assets.available.values
    .firstWhere((asset) => asset.id.id == _ticker);

Map<String, dynamic> _historyResult() => {
  'mmrpc': '2.0',
  'result': {
    'coin': _ticker,
    'current_block': 900,
    'from_id': null,
    'limit': 50,
    'skipped': 0,
    'sync_status': {'state': 'Finished'},
    'total': 1,
    'total_pages': 1,
    'page_number': 1,
    'transactions': [
      {
        'tx_hash': 'harness-hash-0',
        'from': ['from-address'],
        'to': ['to-address'],
        'my_balance_change': '-1.5',
        'block_height': 900,
        'confirmations': 6,
        'timestamp': 1783641600,
        'coin': _ticker,
        'internal_id': _internalId,
        'spent_by_me': '1.5',
        'received_by_me': '0',
      },
    ],
  },
};

/// [wedgeActivation] models the ordinary cold-start case where activation is
/// simply slow: the strategy polls `::status` forever and makes no progress.
KdfScript _script({bool wedgeActivation = false}) {
  final fixture = KdfWalletFixture()
    ..enableUtxo(_ticker)
    ..balance(_ticker);
  if (wedgeActivation) fixture.hang('task::enable_utxo::status');
  final script = fixture.build();
  script.reply('my_tx_history', _historyResult());
  return script;
}

void main() {
  group('the pubkey gate in front of cached history', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('tx_gate_');
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test(
      'cached history is servable while getPubkeys is still blocked',
      () async {
        // Session one: populate both caches the way normal use would.
        final first = await KdfHarness.replayed(
          script: _script(),
          workspace: workspace,
          deleteWorkspaceOnDispose: false,
        );
        final firstUser = await first.signIn(walletType: KdfWalletType.iguana);
        await first.sdk.transactions
            .watchTransactionHistoryMerged(_assetFor(first))
            .first
            .timeout(const Duration(seconds: 20));

        // Drop only the pubkey cache. That is the state the bloc actually hits
        // whenever pubkey hydration misses - a newly opened asset, a cleared
        // cache - while the transaction cache is still perfectly good.
        await HivePubkeysStorage().purgeWallet(firstUser.walletId);
        await first.dispose();

        // Session two, with activation making no progress.
        final second = await KdfHarness.replayed(
          script: _script(wedgeActivation: true),
          workspace: workspace,
          deleteWorkspaceOnDispose: false,
          config: const KomodoDefiSdkConfig(
            // Keep sign-in from racing the same wedged activation, so the only
            // thing under test is the page-open path.
            preActivateDefaultAssets: false,
            preActivateHistoricalAssets: false,
            preActivateCustomTokenAssets: false,
          ),
        );
        addTearDown(second.dispose);
        await second.signIn(walletType: KdfWalletType.iguana);
        final asset = _assetFor(second);

        // What the bloc awaits first. It cannot finish: hydration misses, so
        // getPubkeys goes to _fetchFreshPubkeys, which awaits activateAsset.
        var pubkeysCompleted = false;
        unawaited(
          second.sdk.pubkeys
              .getPubkeys(asset)
              .then((_) => pubkeysCompleted = true)
              .catchError((Object _) => pubkeysCompleted = true),
        );

        // What the bloc could have shown immediately, had it subscribed first.
        final rows = await second.sdk.transactions
            .watchTransactionHistoryMerged(asset)
            .first
            .timeout(const Duration(seconds: 10));

        expect(
          rows.single.internalId,
          _internalId,
          reason: 'the cached row is servable without pubkeys or activation',
        );
        expect(
          pubkeysCompleted,
          isFalse,
          reason: 'the bloc would still be waiting here, showing a spinner '
              'over a list it already had',
        );

        // And the non-blocking API the bloc should be using answers fine.
        expect(
          (await second.sdk.pubkeys.hydratedPubkeys(asset)),
          anyOf(isNull, isA<AssetPubkeys>()),
          reason: 'hydratedPubkeys never activates, so it always returns',
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
