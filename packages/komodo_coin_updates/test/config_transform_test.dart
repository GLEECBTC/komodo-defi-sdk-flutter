import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Unit tests for coin configuration transformation pipeline and individual transforms.
///
/// **Purpose**: Tests the configuration transformation system that modifies coin
/// configurations based on platform requirements, business rules, and runtime
/// conditions, ensuring consistent and correct transformation behavior.
///
/// **Test Cases**:
/// - Transformation idempotency (applying twice yields same result)
/// - Platform-specific filtering (WSS vs TCP protocols)
/// - Parent coin remapping and transformation
/// - Transform pipeline consistency and ordering
/// - Platform detection and conditional logic
///
/// **Functionality Tested**:
/// - Configuration transformation pipeline
/// - Platform-specific protocol filtering
/// - Parent coin relationship mapping
/// - Transform application and validation
/// - Platform detection and conditional transforms
/// - Configuration modification workflows
///
/// **Edge Cases**:
/// - Platform-specific behavior differences
/// - Transform idempotency validation
/// - Parent coin mapping edge cases
/// - Protocol filtering edge cases
/// - Configuration modification consistency
///
/// **Dependencies**: Tests the transformation system that adapts coin configurations
/// for different platforms and requirements, including WSS filtering for web platforms
/// and parent coin relationship mapping.
void main() {
  group('CoinConfigTransformer', () {
    test('idempotency: applying twice yields same result', () {
      const transformer = CoinConfigTransformer();
      final input = JsonMap.of({
        'coin': 'KMD',
        'type': 'UTXO',
        'protocol': {'type': 'UTXO'},
        'electrum': [
          {'url': 'wss://example.com', 'protocol': 'WSS'},
        ],
      });
      final once = transformer.apply(JsonMap.of(input));
      final twice = transformer.apply(JsonMap.of(once));
      expect(twice, equals(once));
    });
  });

  group('WssWebsocketTransform', () {
    test('filters WSS or non-WSS correctly by platform', () {
      const t = WssWebsocketTransform();
      final config = JsonMap.of({
        'coin': 'KMD',
        'electrum': [
          {'url': 'wss://wss.example', 'protocol': 'WSS'},
          {'url': 'tcp://tcp.example', 'protocol': 'TCP'},
        ],
      });

      if (kIsWeb) {
        final out = t.transform(JsonMap.of(config));
        final list = JsonList.of(
          List<Map<String, dynamic>>.from(out['electrum'] as List),
        );
        expect(list.length, 1);
        expect(list.first['protocol'], 'WSS');
        expect(list.first['ws_url'], isNotNull);
      } else {
        final out = t.transform(JsonMap.of(config));
        final list = JsonList.of(
          List<Map<String, dynamic>>.from(out['electrum'] as List),
        );
        expect(list.length, 1);
        expect(list.first['protocol'] != 'WSS', isTrue);
      }
    });
  });

  group('ParentCoinTransform', () {
    test('SLP remaps to BCH', () {
      const t = ParentCoinTransform();
      final config = JsonMap.of({'coin': 'ANY', 'parent_coin': 'SLP'});
      final out = t.transform(JsonMap.of(config));
      expect(out['parent_coin'], 'BCH');
    });

    test('Unmapped parent is a no-op', () {
      const t = ParentCoinTransform();
      final config = JsonMap.of({'coin': 'ANY', 'parent_coin': 'XYZ'});
      final out = t.transform(JsonMap.of(config));
      expect(out['parent_coin'], 'XYZ');
    });
  });

  group('CoinFilter', () {
    test('filters invalid EVM configs with missing activation fields', () {
      const filter = CoinFilter();
      final config = JsonMap.of({
        'coin': 'BROKENETH',
        'type': 'ETH',
        'protocol': {
          'type': 'ETH',
          'protocol_data': {'chain_id': 1},
        },
        'nodes': [
          {'url': 'https://eth.example.com'},
        ],
        'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
      });

      expect(filter.shouldFilter(config), isTrue);
    });

    test('filters invalid EVM configs with empty node lists', () {
      const filter = CoinFilter();
      final config = JsonMap.of({
        'coin': 'BROKENMATIC',
        'type': 'Matic',
        'protocol': {
          'type': 'ETH',
          'protocol_data': {'chain_id': 137},
        },
        'nodes': <JsonMap>[],
        'swap_contract_address': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
        'fallback_swap_contract': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
      });

      expect(filter.shouldFilter(config), isTrue);
    });

    test('filters unsupported protocol subclasses before parsing', () {
      const filter = CoinFilter();
      final config = JsonMap.of({
        'coin': 'SBCH',
        'type': 'SmartBCH',
        'protocol': {
          'type': 'ETH',
          'protocol_data': {'chain_id': 10000},
        },
      });

      expect(filter.shouldFilter(config), isTrue);
    });

    test('keeps complete EVM configs', () {
      const filter = CoinFilter();
      final config = JsonMap.of({
        'coin': 'ETH',
        'type': 'ETH',
        'protocol': {
          'type': 'ETH',
          'protocol_data': {'chain_id': 1},
        },
        'nodes': [
          {'url': 'https://eth.example.com'},
        ],
        'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
        'fallback_swap_contract': '0x24ABE4c71FC658C91313b6552cd40cD808b3Ea80',
      });

      expect(filter.shouldFilter(config), isFalse);
    });
  });
}
