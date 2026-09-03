import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Reproduction for "transactions load every time the asset details page opens".
///
/// The app builds a fresh TransactionHistoryBloc per page open
/// (coin_details.dart), which starts in `loading` and only clears when the
/// first batch arrives. It subscribes through `watchTransactionHistoryMerged`,
/// so that is what this drives - not `getTransactionsStreamed`, which the
/// other harness test covers.
///
/// A second open must be served from storage. To make "served from storage"
/// checkable rather than assumed, the RPC call count is asserted: nothing may
/// have been fetched when the rows arrive.
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

KdfScript _script({required bool serveHistory}) {
  final script =
      (KdfWalletFixture()
            ..enableUtxo(_ticker)
            ..balance(_ticker))
          .build();
  if (serveHistory) {
    script.reply('my_tx_history', _historyResult());
  } else {
    script.hang('my_tx_history');
  }
  return script;
}

void main() {
  group('repeat asset-details opens', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('tx_repeat_');
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    for (final walletType in KdfWalletType.values) {
      test('${walletType.name}: a second open in the SAME session is cached',
          () async {
        final harness = await KdfHarness.replayed(
          script: _script(serveHistory: true),
          workspace: workspace,
          deleteWorkspaceOnDispose: false,
        );
        addTearDown(harness.dispose);
        await harness.signIn(walletType: walletType);
        final asset = _assetFor(harness);

        // First page open.
        await harness.sdk.transactions
            .watchTransactionHistoryMerged(asset)
            .first
            .timeout(const Duration(seconds: 20));

        final callsAfterFirstOpen = harness.script.callsTo('my_tx_history');
        expect(
          callsAfterFirstOpen,
          greaterThan(0),
          reason: 'the first open has to fetch',
        );

        // Second page open, exactly as a rebuilt bloc would.
        final second = await harness.sdk.transactions
            .watchTransactionHistoryMerged(asset)
            .first
            .timeout(const Duration(seconds: 20));

        expect(
          second.single.internalId,
          _internalId,
          reason: 'the second open should render the stored row',
        );
        expect(
          harness.script.callsTo('my_tx_history'),
          callsAfterFirstOpen,
          reason: 'the second open must render before it fetches anything',
        );
      });

      test('${walletType.name}: a NEW session is cached', () async {
        final first = await KdfHarness.replayed(
          script: _script(serveHistory: true),
          workspace: workspace,
          deleteWorkspaceOnDispose: false,
        );
        await first.signIn(walletType: walletType);
        await first.sdk.transactions
            .watchTransactionHistoryMerged(_assetFor(first))
            .first
            .timeout(const Duration(seconds: 20));
        await first.dispose();

        // Cold start. my_tx_history never answers, so anything emitted came
        // from disk.
        final second = await KdfHarness.replayed(
          script: _script(serveHistory: false),
          workspace: workspace,
          deleteWorkspaceOnDispose: false,
        );
        addTearDown(second.dispose);
        await second.signIn(walletType: walletType);

        final rows = await second.sdk.transactions
            .watchTransactionHistoryMerged(_assetFor(second))
            .first
            .timeout(const Duration(seconds: 20));

        expect(
          rows.single.internalId,
          _internalId,
          reason: 'a cold start should render the stored row',
        );
      });
    }
  });
}
