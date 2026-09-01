import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Transaction history persistence, exercised through the real `bootstrap()`.
///
/// The unit suites in `komodo_defi_sdk/test/transaction_history/` cover the
/// store itself. This is the integration-level claim the feature actually
/// makes: that a *cold start* renders history before the network answers.
///
/// It is only checkable across two SDK lifetimes over the same on-disk
/// workspace, which is why [KdfHarness.replayed] grew `workspace` and
/// `deleteWorkspaceOnDispose`. The second harness is given a KDF whose
/// `my_tx_history` never answers, so anything it emits provably came from disk.
const _ticker = 'KMD';
const _internalId = 'harness-tx-0';
const _txHash = 'harness-hash-0';

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
        'tx_hash': _txHash,
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

KdfScript _scriptWith({required bool serveHistory}) {
  final fixture = KdfWalletFixture()
    ..enableUtxo(_ticker)
    ..balance(_ticker);
  final script = fixture.build();
  if (serveHistory) {
    script.reply('my_tx_history', _historyResult());
  } else {
    // A KDF that accepted the request and never answers. Anything the stream
    // emits under this script came from disk, not the wire.
    script.hang('my_tx_history');
  }
  return script;
}

Future<KdfHarness> _harness({
  required Directory workspace,
  required bool serveHistory,
  bool persist = true,
}) async {
  final harness = await KdfHarness.replayed(
    script: _scriptWith(serveHistory: serveHistory),
    workspace: workspace,
    deleteWorkspaceOnDispose: false,
    config: KomodoDefiSdkConfig(persistTransactionHistory: persist),
  );
  await harness.signIn(walletType: KdfWalletType.iguana);
  return harness;
}

void main() {
  group('transaction history persistence (integration)', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('tx_persist_');
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test('a cold start serves history before the network answers', () async {
      final first = await _harness(workspace: workspace, serveHistory: true);
      final firstAsset = _assetFor(first);
      final fetched = await first.sdk.transactions
          .getTransactionsStreamed(firstAsset)
          .first
          .timeout(const Duration(seconds: 20));
      expect(fetched.single.internalId, _internalId);
      await first.dispose();

      // Same workspace, new SDK, and a KDF that will never answer a history
      // request.
      final second = await _harness(workspace: workspace, serveHistory: false);
      addTearDown(second.dispose);
      final secondAsset = _assetFor(second);

      final cached = await second.sdk.transactions
          .getTransactionsStreamed(secondAsset)
          .first
          .timeout(const Duration(seconds: 20));

      expect(cached.single.internalId, _internalId);
      expect(cached.single.txHash, _txHash);
      expect(
        second.script.callsTo('my_tx_history'),
        0,
        reason:
            'storage is read before activation, so the cached rows must '
            'reach the caller before a history request is even issued - not '
            'merely before one comes back',
      );
    });

    test('disabling the flag leaves nothing to serve', () async {
      final first = await _harness(
        workspace: workspace,
        serveHistory: true,
        persist: false,
      );
      final firstAsset = _assetFor(first);
      await first.sdk.transactions
          .getTransactionsStreamed(firstAsset)
          .first
          .timeout(const Duration(seconds: 20));
      await first.dispose();

      final second = await _harness(
        workspace: workspace,
        serveHistory: false,
        persist: false,
      );
      addTearDown(second.dispose);
      final secondAsset = _assetFor(second);

      // Nothing was written, so the stream has only the hung fetch to wait on.
      await expectLater(
        second.sdk.transactions
            .getTransactionsStreamed(secondAsset)
            .first
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
