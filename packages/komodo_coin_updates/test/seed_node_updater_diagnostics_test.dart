import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _UnprintableFailure implements Exception {
  @override
  String toString() => throw StateError('Must not stringify upstream failures');
}

void main() {
  late DebugPrintCallback originalDebugPrint;
  late List<String> diagnostics;
  setUp(() {
    diagnostics = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => diagnostics.add(message ?? '');
  });
  tearDown(() => debugPrint = originalDebugPrint);

  final failures = <String, Future<http.Response> Function(http.Request)>{
    'malformed response body': (_) async =>
        http.Response('synthetic-body-secret', 200),
    'malformed node fields': (_) async =>
        http.Response('[{"name":"synthetic-field-secret","host":{}}]', 200),
    'HTTP error body': (_) async => http.Response('synthetic-body-secret', 503),
    'transport exception': (_) async => throw http.ClientException(
      'synthetic-transport-secret',
      Uri.parse('https://example.test/?token=synthetic-url-secret'),
    ),
    'timeout exception': (_) async =>
        throw TimeoutException('synthetic-timeout-secret'),
    'unprintable exception': (_) async => throw _UnprintableFailure(),
  };
  for (final entry in failures.entries) {
    test(
      '${entry.key} is absent from diagnostics and public failure',
      () async {
        final client = MockClient(entry.value);
        addTearDown(client.close);
        await expectLater(
          SeedNodeUpdater.fetchSeedNodes(
            config: const AssetRuntimeUpdateConfig(
              coinsRepoContentUrl:
                  'https://example.test/synthetic-config-secret',
            ),
            httpClient: client,
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'diagnostic-safe failure',
              isNot(contains('synthetic-')),
            ),
          ),
        );
        expect(diagnostics, ['Peer configuration update failed']);
      },
    );
  }

  test(
    'invalid configured URI cannot escape the safe failure boundary',
    () async {
      await expectLater(
        SeedNodeUpdater.fetchSeedNodes(
          config: const AssetRuntimeUpdateConfig(
            coinsRepoContentUrl: 'http://[synthetic-config-secret',
          ),
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'safe failure',
            isNot(contains('synthetic-')),
          ),
        ),
      );
      expect(diagnostics, ['Peer configuration update failed']);
    },
  );

  test('valid configuration still returns the original node', () async {
    final client = MockClient(
      (_) async => http.Response('''[
      {"name":"test","host":"test.example","type":"domain","wss":true,
       "netid":6133,"contact":[]}
    ]''', 200),
    );
    addTearDown(client.close);
    final result = await SeedNodeUpdater.fetchSeedNodes(
      config: const AssetRuntimeUpdateConfig(),
      httpClient: client,
    );
    expect(result.seedNodes.single.host, 'test.example');
    expect(result.netId, 6133);
    expect(diagnostics, isEmpty);
  });
}
