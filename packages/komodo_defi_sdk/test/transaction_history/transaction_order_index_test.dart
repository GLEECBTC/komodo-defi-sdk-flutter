import 'package:komodo_defi_sdk/src/transaction_history/transaction_order_index.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';

void main() {
  final wallet = testWallet();
  final asset = testAssetId();
  final otherAsset = testAssetId(id: 'KMD', subClass: CoinSubClass.smartChain);
  final prefix = TransactionStorageKey.prefix(wallet, asset);
  final otherPrefix = TransactionStorageKey.prefix(wallet, otherAsset);

  String keyFor(String internalId, {DateTime? timestamp, String? withPrefix}) =>
      TransactionStorageKey.build(
        prefix: withPrefix ?? prefix,
        timestamp: timestamp ?? DateTime.utc(2026, 7, 10),
        internalId: internalId,
      );

  List<String> idsOf(Iterable<String> keys) => [
    for (final key in keys) TransactionStorageKey.parse(key)!.idToken,
  ];

  group('rebuildFromKeys', () {
    test('orders by timestamp descending', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('oldest', timestamp: DateTime.utc(2026, 7, 1)),
          keyFor('newest', timestamp: DateTime.utc(2026, 7, 20)),
          keyFor('middle', timestamp: DateTime.utc(2026, 7, 10)),
        ]);

      expect(idsOf(index.keysFor(prefix)), ['newest', 'middle', 'oldest']);
    });

    test('breaks ties by internal id descending', () {
      final shared = DateTime.utc(2026, 7, 10);
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          for (final id in ['tx-a', 'tx-c', 'tx-e', 'tx-b', 'tx-d'])
            keyFor(id, timestamp: shared),
        ]);

      expect(idsOf(index.keysFor(prefix)), [
        'tx-e',
        'tx-d',
        'tx-c',
        'tx-b',
        'tx-a',
      ]);
    });

    test('keeps prefixes independent', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('usdt-tx'),
          keyFor('kmd-tx', withPrefix: otherPrefix),
        ]);

      expect(idsOf(index.keysFor(prefix)), ['usdt-tx']);
      expect(idsOf(index.keysFor(otherPrefix)), ['kmd-tx']);
      expect(index.length, 2);
    });

    test('reports unparseable keys instead of indexing them', () {
      final index = TransactionOrderIndex();
      final rejected = index.rebuildFromKeys([
        keyFor('good'),
        'not-a-key',
        'still|not|a|key',
      ]);

      expect(rejected, ['not-a-key', 'still|not|a|key']);
      expect(index.length, 1);
    });

    test('discards previous state', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([keyFor('first')])
        ..rebuildFromKeys([keyFor('second')]);

      expect(idsOf(index.keysFor(prefix)), ['second']);
      expect(index.keyForId('first'), isNull);
    });
  });

  group('insert', () {
    test('places a key in sorted position', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('oldest', timestamp: DateTime.utc(2026, 7, 1)),
          keyFor('newest', timestamp: DateTime.utc(2026, 7, 20)),
        ])
        ..insert(keyFor('middle', timestamp: DateTime.utc(2026, 7, 10)));

      expect(idsOf(index.keysFor(prefix)), ['newest', 'middle', 'oldest']);
    });

    test('inserting at either end keeps the order', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([keyFor('mid', timestamp: DateTime.utc(2026, 7, 10))])
        ..insert(keyFor('first', timestamp: DateTime.utc(2026, 7, 20)))
        ..insert(keyFor('last', timestamp: DateTime.utc(2026, 7, 1)));

      expect(idsOf(index.keysFor(prefix)), ['first', 'mid', 'last']);
    });

    test('re-keying returns the stale key and keeps one entry', () {
      // A pending row gains a real timestamp, so its key changes. The caller
      // needs the old key back so it can delete the orphaned record.
      final pending = keyFor(
        'tx-0',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final confirmed = keyFor('tx-0', timestamp: DateTime.utc(2026, 7, 10));

      final index = TransactionOrderIndex()..rebuildFromKeys([pending]);
      expect(index.insert(confirmed), pending);

      expect(index.keysFor(prefix), [confirmed]);
      expect(index.count(prefix), 1);
      expect(index.keyForPrefixedId(prefix, 'tx-0'), confirmed);
      expect(index.keyForId('tx-0'), confirmed);
    });

    test('re-inserting an identical key is a no-op', () {
      final key = keyFor('tx-0');
      final index = TransactionOrderIndex()..rebuildFromKeys([key]);

      expect(index.insert(key), isNull);
      expect(index.count(prefix), 1);
    });

    test('positions stay consistent after many inserts', () {
      final index = TransactionOrderIndex();
      for (var i = 0; i < 50; i++) {
        index.insert(
          keyFor('tx-$i', timestamp: DateTime.utc(2026).add(Duration(days: i))),
        );
      }

      // Timestamps ascend with i, and the order is newest-first, so the row
      // after tx-i is tx-(i-1). Walking every cursor proves the position map
      // stayed in step with the ordered list across all 50 insertions.
      expect(idsOf(index.keysFor(prefix)).first, 'tx-49');
      for (var i = 49; i > 0; i--) {
        expect(
          idsOf(index.page(prefix, limit: 1, fromId: 'tx-$i')).single,
          'tx-${i - 1}',
        );
      }
      // tx-0 is oldest, so it has no successor.
      expect(index.page(prefix, limit: 1, fromId: 'tx-0'), isEmpty);
      expect(index.count(prefix), 50);
    });
  });

  group('remove', () {
    test('drops a key and closes the gap', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('a', timestamp: DateTime.utc(2026, 7, 3)),
          keyFor('b', timestamp: DateTime.utc(2026, 7, 2)),
          keyFor('c', timestamp: DateTime.utc(2026, 7, 1)),
        ])
        ..remove(keyFor('b', timestamp: DateTime.utc(2026, 7, 2)));

      expect(idsOf(index.keysFor(prefix)), ['a', 'c']);
      expect(index.keyForId('b'), isNull);
      expect(idsOf(index.page(prefix, limit: 10, fromId: 'a')), ['c']);
    });

    test('ignores unknown keys', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([keyFor('a')])
        ..remove(keyFor('nope'))
        ..remove('garbage');

      expect(index.count(prefix), 1);
    });

    test('removePrefix clears only that pair', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('usdt-tx'),
          keyFor('kmd-tx', withPrefix: otherPrefix),
        ])
        ..removePrefix(prefix);

      expect(index.keysFor(prefix), isEmpty);
      expect(idsOf(index.keysFor(otherPrefix)), ['kmd-tx']);
      expect(index.keyForId('usdt-tx'), isNull);
      expect(index.keyForId('kmd-tx'), isNotNull);
    });

    test('removeWallet clears every asset for that wallet', () {
      final otherWallet = testWallet(pubkeyHash: 'other-pubkey');
      final otherWalletPrefix = TransactionStorageKey.prefix(
        otherWallet,
        asset,
      );
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('usdt-tx'),
          keyFor('kmd-tx', withPrefix: otherPrefix),
          keyFor('other-wallet-tx', withPrefix: otherWalletPrefix),
        ])
        ..removeWallet(TransactionStorageKey.walletPrefix(wallet));

      expect(index.keysFor(prefix), isEmpty);
      expect(index.keysFor(otherPrefix), isEmpty);
      expect(idsOf(index.keysFor(otherWalletPrefix)), ['other-wallet-tx']);
    });
  });

  group('lookups', () {
    test('latestKey is the newest row', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('old', timestamp: DateTime.utc(2026, 7, 1)),
          keyFor('new', timestamp: DateTime.utc(2026, 7, 20)),
        ]);

      expect(
        TransactionStorageKey.parse(index.latestKey(prefix)!)!.idToken,
        'new',
      );
      expect(index.latestKey(otherPrefix), isNull);
    });

    test('the global id lookup spans prefixes', () {
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('usdt-tx'),
          keyFor('kmd-tx', withPrefix: otherPrefix),
        ]);

      expect(index.keyForId('kmd-tx'), isNotNull);
      expect(index.keyForPrefixedId(prefix, 'kmd-tx'), isNull);
      expect(index.keyForId('nope'), isNull);
    });

    test('removing one of two same-id rows falls back to the other', () {
      // The same internal id can legitimately appear under two assets.
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('shared'),
          keyFor('shared', withPrefix: otherPrefix),
        ]);

      index.removePrefix(prefix);
      expect(index.keyForId('shared'), isNotNull);
      expect(
        index.keyForId('shared'),
        index.keyForPrefixedId(otherPrefix, 'shared'),
      );
    });

    test('statsFor reports count and bounds', () {
      final oldest = DateTime.utc(2026, 7, 1);
      final newest = DateTime.utc(2026, 7, 20);
      final index = TransactionOrderIndex()
        ..rebuildFromKeys([
          keyFor('a', timestamp: oldest),
          keyFor('b', timestamp: DateTime.utc(2026, 7, 10)),
          keyFor('c', timestamp: newest),
        ]);

      final stats = index.statsFor(prefix)!;
      expect(stats.count, 3);
      expect(stats.oldestMicros, oldest.microsecondsSinceEpoch);
      expect(stats.newestMicros, newest.microsecondsSinceEpoch);
      expect(index.statsFor(otherPrefix), isNull);
    });
  });

  group('page', () {
    late TransactionOrderIndex index;

    setUp(() {
      index = TransactionOrderIndex()
        ..rebuildFromKeys([
          for (var i = 0; i < 5; i++)
            keyFor(
              'tx-$i',
              // Descending timestamps, so tx-0 is newest.
              timestamp: DateTime.utc(2026, 7, 20).subtract(Duration(days: i)),
            ),
        ]);
    });

    test('returns the first page by default', () {
      expect(idsOf(index.page(prefix, limit: 2)), ['tx-0', 'tx-1']);
    });

    test('walks pages by number', () {
      expect(idsOf(index.page(prefix, limit: 2, pageNumber: 2)), [
        'tx-2',
        'tx-3',
      ]);
      expect(idsOf(index.page(prefix, limit: 2, pageNumber: 3)), ['tx-4']);
    });

    test('a page past the end is empty', () {
      expect(index.page(prefix, limit: 2, pageNumber: 99), isEmpty);
    });

    test('walks by cursor, exclusive of it', () {
      expect(idsOf(index.page(prefix, limit: 2, fromId: 'tx-1')), [
        'tx-2',
        'tx-3',
      ]);
    });

    test('a cursor on the last row yields an empty page', () {
      expect(index.page(prefix, limit: 2, fromId: 'tx-4'), isEmpty);
    });

    test('a cursor wins over a page number', () {
      expect(
        idsOf(index.page(prefix, limit: 2, fromId: 'tx-0', pageNumber: 3)),
        ['tx-1', 'tx-2'],
      );
    });

    test('an unknown cursor throws', () {
      expect(
        () => index.page(prefix, limit: 2, fromId: 'nope'),
        throwsA(isA<TransactionOrderIndexCursorException>()),
      );
    });

    test('a cursor belonging to another prefix throws', () {
      index.insert(keyFor('kmd-tx', withPrefix: otherPrefix));
      expect(
        () => index.page(prefix, limit: 2, fromId: 'kmd-tx'),
        throwsA(isA<TransactionOrderIndexCursorException>()),
      );
    });

    test('an unknown prefix yields an empty page', () {
      expect(index.page(otherPrefix, limit: 2), isEmpty);
    });

    test('a limit at or over the total returns everything', () {
      expect(index.page(prefix, limit: 5), hasLength(5));
      expect(index.page(prefix, limit: 500), hasLength(5));
    });

    test('a non-positive limit returns nothing', () {
      expect(index.page(prefix, limit: 0), isEmpty);
    });
  });
}
