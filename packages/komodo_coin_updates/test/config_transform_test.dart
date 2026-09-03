import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class _SetFieldTransform implements CoinConfigTransform {
  const _SetFieldTransform(this.key, this.value);

  final String key;
  final Object value;

  @override
  bool needsTransform(JsonMap config) => config[key] != value;

  @override
  JsonMap transform(JsonMap config) => JsonMap.of(config)..[key] = value;
}

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

    test('additional transforms run after the configured base transforms', () {
      const transformer = CoinConfigTransformer(
        transforms: [_SetFieldTransform('stage', 'base')],
        additionalTransforms: [_SetFieldTransform('stage', 'application')],
      );
      final input = <String, dynamic>{'coin': 'KMD'};

      final transformed = transformer.apply(input);

      expect(transformed['stage'], 'application');
      expect(input, {'coin': 'KMD'});
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

  group('TronQuickNodeTransform', () {
    test('adds QuickNode as the preferred mainnet TRX node', () {
      const t = TronQuickNodeTransform();
      final config = JsonMap.of({
        'coin': 'TRX',
        'type': 'TRX',
        'protocol': {
          'type': 'TRX',
          'protocol_data': {'network': 'Mainnet'},
        },
        'nodes': [
          {'url': 'https://api.trongrid.io'},
        ],
      });

      final out = t.transform(JsonMap.of(config));
      final nodes = out.value<JsonList>('nodes');

      expect(nodes.first['url'], TronQuickNodeTransform.quickNodeUrl);
      expect(nodes.first['komodo_proxy'], isTrue);
      expect(nodes[1]['url'], 'https://api.trongrid.io');
      expect(t.needsTransform(out), isFalse);
      expect(t.transform(JsonMap.of(out)), equals(out));
    });

    test('marks an existing QuickNode TRX node as a KDF proxy', () {
      const t = TronQuickNodeTransform();
      final config = JsonMap.of({
        'coin': 'TRX',
        'type': 'TRX',
        'protocol': {
          'type': 'TRX',
          'protocol_data': {'network': 'Mainnet'},
        },
        'nodes': [
          {'url': TronQuickNodeTransform.quickNodeUrl},
          {'url': 'https://api.trongrid.io'},
        ],
      });

      expect(t.needsTransform(config), isTrue);

      final out = t.transform(JsonMap.of(config));
      final nodes = out.value<JsonList>('nodes');

      expect(nodes, hasLength(2));
      expect(nodes.first, {
        'url': TronQuickNodeTransform.quickNodeUrl,
        'komodo_proxy': true,
      });
      expect(t.needsTransform(out), isFalse);
    });

    test('adds QuickNode to TRC20 tokens on TRX', () {
      const t = TronQuickNodeTransform();
      final config = JsonMap.of({
        'coin': 'USDT-TRC20',
        'type': 'TRC-20',
        'protocol': {
          'type': 'TRC20',
          'protocol_data': {
            'platform': 'TRX',
            'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          },
        },
        'nodes': <JsonMap>[],
      });

      final out = t.transform(JsonMap.of(config));
      final nodes = out.value<JsonList>('nodes');

      expect(nodes, hasLength(1));
      expect(nodes.first['url'], TronQuickNodeTransform.quickNodeUrl);
      expect(nodes.first['komodo_proxy'], isTrue);
    });

    test('does not add QuickNode to Nile TRX configs', () {
      const t = TronQuickNodeTransform();
      final config = JsonMap.of({
        'coin': 'TRXT',
        'type': 'TRX',
        'protocol': {
          'type': 'TRX',
          'protocol_data': {'network': 'Nile'},
        },
        'nodes': [
          {'url': 'https://nile.trongrid.io'},
        ],
      });

      expect(t.needsTransform(config), isFalse);
      expect(t.transform(JsonMap.of(config)), equals(config));
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
