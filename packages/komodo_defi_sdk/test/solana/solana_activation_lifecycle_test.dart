import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/base_strategies/activation_strategy_base.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/solana_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'solana_fixtures.dart';

class _Cache extends Mock implements ActivatedAssetsCache {}

class _Client implements ApiClient {
  final enabled = <String>[];
  String? failTicker;
  Map<String, dynamic>? response;

  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    final ticker =
        (request['params'] as Map<String, dynamic>)['ticker'] as String;
    if (ticker == failTicker) throw const FormatException('Token rejected');
    enabled.add(ticker);
    if (response != null) return response!;
    return {
      'mmrpc': '2.0',
      'result': {
        'ticker': ticker,
        'address': 'WalletBase58',
        'current_block': 42,
        'balance': {'spendable': '0', 'unspendable': '0'},
      },
    };
  }
}

void main() {
  final sol = solanaAsset();
  final first = solanaToken(sol);
  final second = Asset.fromJson(
    {...first.protocol.config, 'coin': 'SECOND-SOL-DEV'},
    knownIds: {sol.id},
  );

  SmartAssetActivator activator(_Client client, Set<AssetId> enabled) {
    final cache = _Cache();
    when(cache.getActivatedAssetIds).thenAnswer((_) async => enabled);
    return SmartAssetActivator(
      client,
      CompositeAssetActivator(client, [
        SolanaActivationStrategy(
          client,
          const PrivateKeyPolicy.contextPrivKey(),
          const SolanaCapabilities(enabled: true),
        ),
      ]),
      cache,
    );
  }

  test(
    'late token group succeeds only after every token is activated',
    () async {
      final client = _Client();
      final result = await activator(client, {sol.id})
          .activate(sol, [first, second])
          .firstWhere((progress) => progress.isComplete);
      expect(result.isSuccess, isTrue);
      expect(client.enabled, [first.id.id, second.id.id]);
    },
  );

  test(
    'a rejected later token fails the group without publishing success',
    () async {
      final client = _Client()..failTicker = second.id.id;
      final progress = await activator(client, {
        sol.id,
      }).activate(sol, [first, second]).toList();
      expect(progress.where((event) => event.isSuccess), isEmpty);
      expect(progress.last.isError, isTrue);
      expect(client.enabled, [first.id.id]);
    },
  );

  test('already-active token group still emits one terminal result', () async {
    final client = _Client();
    final progress = await activator(client, {
      sol.id,
      first.id,
      second.id,
    }).activate(sol, [first, second]).toList();
    expect(progress.where((event) => event.isComplete), hasLength(1));
    expect(progress.last.isSuccess, isTrue);
    expect(client.enabled, isEmpty);
  });

  test(
    'batch response cannot silently omit a requested zero-balance token',
    () async {
      final client = _Client()
        ..response = {
          'mmrpc': '2.0',
          'result': {
            'ticker': sol.id.id,
            'address': 'WalletBase58',
            'current_block': 42,
            'balance': {'spendable': '0', 'unspendable': '0'},
            'tokens_balances': {
              first.id.id: {'spendable': '0', 'unspendable': '0'},
            },
          },
        };
      final progress = await activator(
        client,
        {},
      ).activate(sol, [first, second]).toList();
      expect(progress.where((event) => event.isSuccess), isEmpty);
      expect(progress.last.isError, isTrue);
    },
  );
}
