import 'package:flutter/services.dart' show AssetBundle, ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/services/seed_node_service.dart';

class _FakeBundle extends AssetBundle {
  _FakeBundle(this.map);

  final Map<String, String> map;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      map[key] ?? (throw StateError('Asset not found: $key'));

  @override
  void evict(String key) {}
}

void main() {
  group('SeedNodeService.loadBundledSeedNodes', () {
    test('filters bundled seed nodes by the current net id', () async {
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/seed_nodes.json': '''
[
  {
    "name": "seed-node-1",
    "host": "seed01.kmdefi.net",
    "type": "domain",
    "wss": true,
    "netid": 6133,
    "contact": [{"email": ""}]
  },
  {
    "name": "seed-node-2",
    "host": "seed02.kmdefi.net",
    "type": "domain",
    "wss": true,
    "netid": 8762,
    "contact": [{"email": ""}]
  }
]
''',
      });

      final seedNodes = await SeedNodeService.loadBundledSeedNodes(
        bundle: bundle,
      );

      expect(seedNodes, equals(const ['seed01.kmdefi.net']));
    });
  });
}
