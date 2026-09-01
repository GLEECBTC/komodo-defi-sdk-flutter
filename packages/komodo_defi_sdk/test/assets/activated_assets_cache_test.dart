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

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('ActivatedAssetsCache', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockAssetLookup assetLookup;

    final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
    final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      assetLookup = _MockAssetLookup();

      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => const Stream<KdfUser?>.empty());
      when(() => auth.isSignedIn()).thenAnswer((_) async => true);
    });

    ActivatedAssetsCache build() => ActivatedAssetsCache(
      client: client,
      auth: auth,
      assetLookup: assetLookup,
    );

    test(
      'includes the parent platform coin when KDF only reports the token',
      () async {
        // KDF reports ONLY the TRC20 token as enabled (the TRON platform is
        // omitted from get_enabled_coins for this flow).
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'mmrpc': '2.0',
            'result': {
              'coins': [
                {'ticker': 'USDT-TRC20'},
              ],
            },
          },
        );
        when(
          () => assetLookup.findAssetsByConfigId('USDT-TRC20'),
        ).thenReturn({child});
        when(() => assetLookup.fromId(parent.id)).thenReturn(parent);

        final cache = build();
        addTearDown(cache.dispose);

        final ids = await cache.getActivatedAssetIds();

        // The token is active, so its platform parent must be reported active
        // too — otherwise `isAssetActive(TRX)` stays false and the platform is
        // treated as never-activated (no balance streaming).
        expect(ids, containsAll(<AssetId>{child.id, parent.id}));
      },
    );

    test('does not add a parent for a platform coin with no parent', () async {
      when(() => client.executeRpc(any())).thenAnswer(
        (_) async => {
          'mmrpc': '2.0',
          'result': {
            'coins': [
              {'ticker': 'TRX'},
            ],
          },
        },
      );
      when(() => assetLookup.findAssetsByConfigId('TRX')).thenReturn({parent});

      final cache = build();
      addTearDown(cache.dispose);

      final ids = await cache.getActivatedAssetIds();

      // A platform coin with no parent must not pull in any extra asset.
      expect(ids, equals(<AssetId>{parent.id}));
    });

    group('fetch liveness ceiling', () {
      // `get_enabled_coins` is a local KDF state read, but nothing below this
      // cache bounds it - not the RPC client, not the transport. An unbounded
      // read here defeats every deadline built on top of it: both
      // `KomodoDefiSdk.waitForEnabledAssetsToPassThreshold` and the app's
      // `waitForEnabledCoinsToPassThreshold` evaluate their documented timeout
      // *after* awaiting this read, so a wedged node made a
      // documented-timeout method hang forever.
      const fetchTimeout = Duration(milliseconds: 50);

      ActivatedAssetsCache buildBounded() => ActivatedAssetsCache(
        client: client,
        auth: auth,
        assetLookup: assetLookup,
        fetchTimeout: fetchTimeout,
      );

      void stubNeverCompletingRpc() {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) => Completer<Map<String, dynamic>>().future);
      }

      test('the originating caller times out rather than hanging', () async {
        stubNeverCompletingRpc();
        final cache = buildBounded();
        addTearDown(cache.dispose);

        await expectLater(
          cache.getActivatedAssetIds(),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('a caller that joined the same fetch is released too', () async {
        stubNeverCompletingRpc();
        final cache = buildBounded();
        addTearDown(cache.dispose);

        final first = cache.getActivatedAssetIds();
        final joined = cache.getActivatedAssetIds();

        await expectLater(first, throwsA(isA<TimeoutException>()));
        await expectLater(joined, throwsA(isA<TimeoutException>()));
      });

      test('a later caller starts a fresh fetch', () async {
        stubNeverCompletingRpc();
        final cache = buildBounded();
        addTearDown(cache.dispose);

        await expectLater(
          cache.getActivatedAssetIds(),
          throwsA(isA<TimeoutException>()),
        );
        await expectLater(
          cache.getActivatedAssetIds(),
          throwsA(isA<TimeoutException>()),
        );

        // Two real round trips, not a second caller joining a dead fetch.
        verify(() => client.executeRpc(any())).called(2);
      });

      test('rejects a non-positive ceiling', () {
        expect(
          () => ActivatedAssetsCache(
            client: client,
            auth: auth,
            assetLookup: assetLookup,
            fetchTimeout: Duration.zero,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
