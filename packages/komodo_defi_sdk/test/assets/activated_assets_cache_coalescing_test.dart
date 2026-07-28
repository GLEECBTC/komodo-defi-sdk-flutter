import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

/// `forceRefresh` used to call `invalidate()`, which nulls `_pendingCompleter`
/// and therefore destroyed request coalescing: every concurrent forced read
/// became its own real `get_enabled_coins` round trip, each re-parsing the
/// whole response against the asset catalogue. The login path issues them in
/// exactly that pattern - the activation fan-out plus
/// `SharedActivationCoordinator._waitForCoinAvailability`'s per-asset polling.
void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('ActivatedAssetsCache forced-refresh coalescing', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockAssetLookup assetLookup;
    final parent = Asset.fromJson(_trxConfig(), knownIds: const {});

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      assetLookup = _MockAssetLookup();

      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => const Stream<KdfUser?>.empty());
      when(() => auth.isSignedIn()).thenAnswer((_) async => true);
      when(() => assetLookup.findAssetsByConfigId('TRX')).thenReturn({parent});
    });

    test('concurrent forced refreshes share a single round trip', () async {
      var rpcCalls = 0;
      final gate = Completer<void>();
      when(() => client.executeRpc(any())).thenAnswer((_) async {
        rpcCalls++;
        await gate.future;
        return {
          'mmrpc': '2.0',
          'result': {
            'coins': [
              {'ticker': 'TRX'},
            ],
          },
        };
      });

      final cache = ActivatedAssetsCache(
        client: client,
        auth: auth,
        assetLookup: assetLookup,
      );
      addTearDown(cache.dispose);

      // Ten assets in a login fan-out all demanding fresh activation state.
      final futures = List.generate(
        10,
        (_) => cache.getActivatedAssetIds(forceRefresh: true),
      );
      // Let them all reach the cache before the RPC resolves.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();

      final results = await Future.wait(futures);

      expect(rpcCalls, 1);
      for (final ids in results) {
        expect(ids, contains(parent.id));
      }
    });

    test(
      'a forced refresh after a stale in-flight fetch is not coalesced',
      () async {
        var now = DateTime(2026);
        var rpcCalls = 0;
        final gate = Completer<void>();
        when(() => client.executeRpc(any())).thenAnswer((_) async {
          rpcCalls++;
          if (rpcCalls == 1) await gate.future;
          return {
            'mmrpc': '2.0',
            'result': {
              'coins': [
                {'ticker': 'TRX'},
              ],
            },
          };
        });

        final cache = ActivatedAssetsCache(
          client: client,
          auth: auth,
          assetLookup: assetLookup,
          clock: () => now,
        );
        addTearDown(cache.dispose);

        final first = cache.getActivatedAssetIds(forceRefresh: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // The in-flight fetch is now older than the join window, so a caller
        // asking for fresh data must not be served by it.
        now = now.add(const Duration(seconds: 5));
        final second = cache.getActivatedAssetIds(forceRefresh: true);
        await second;

        expect(rpcCalls, 2);

        gate.complete();
        await first;
      },
    );
  });
}
