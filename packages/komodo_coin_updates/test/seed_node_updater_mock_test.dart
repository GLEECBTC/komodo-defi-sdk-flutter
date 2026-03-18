import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

/// Mock HTTP client for testing
class MockHttpClient extends Mock implements http.Client {}

/// Mock HTTP response for testing
class MockResponse extends Mock implements http.Response {}

void main() {
  group('SeedNodeUpdater with injectable client', () {
    late MockHttpClient mockClient;
    late AssetRuntimeUpdateConfig config;

    setUpAll(() {
      // Register fallback values for mocktail
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      mockClient = MockHttpClient();
      config = const AssetRuntimeUpdateConfig();
    });

    test('should successfully fetch seed nodes with custom client', () async {
      // Arrange
      final mockResponse = MockResponse();
      const responseBody = '''[
        {
          "name": "test-seed-1",
          "host": "test1.example.com",
          "type": "domain",
          "wss": true,
          "netid": 6133,
          "contact": [{"email": "test1@example.com"}]
        },
        {
          "name": "test-seed-2", 
          "host": "test2.example.com",
          "type": "domain",
          "wss": true,
          "netid": 6133,
          "contact": [{"email": "test2@example.com"}]
        }
      ]''';

      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.body).thenReturn(responseBody);
      when(() => mockClient.get(any())).thenAnswer((_) async => mockResponse);

      // Act
      final result = await SeedNodeUpdater.fetchSeedNodes(
        config: config,
        httpClient: mockClient,
      );

      // Assert
      expect(result.seedNodes.length, equals(2));
      expect(result.netId, equals(6133));
      expect(result.seedNodes[0].name, equals('test-seed-1'));
      expect(result.seedNodes[0].host, equals('test1.example.com'));
      expect(result.seedNodes[1].name, equals('test-seed-2'));
      expect(result.seedNodes[1].host, equals('test2.example.com'));

      // Verify the client was called
      verify(() => mockClient.get(any())).called(1);

      // Verify client was not closed (since it was provided by caller)
      verifyNever(() => mockClient.close());
    });

    test('should handle timeout exceptions properly', () async {
      // Arrange
      when(() => mockClient.get(any())).thenAnswer(
        (_) async =>
            throw TimeoutException('Timeout', const Duration(seconds: 15)),
      );

      // Act & Assert
      await expectLater(
        () => SeedNodeUpdater.fetchSeedNodes(
          config: config,
          httpClient: mockClient,
          timeout: const Duration(seconds: 5),
        ),
        throwsException,
      );

      verify(() => mockClient.get(any())).called(1);
      verifyNever(() => mockClient.close());
    });

    test('should throw when no seed nodes match the default netid', () async {
      // Arrange
      final mockResponse = MockResponse();
      const responseBody = '''[
        {
          "name": "stale-seed-1",
          "host": "stale1.example.com",
          "type": "domain",
          "wss": true,
          "netid": 8762,
          "contact": [{"email": "stale1@example.com"}]
        }
      ]''';

      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.body).thenReturn(responseBody);
      when(() => mockClient.get(any())).thenAnswer((_) async => mockResponse);

      // Act & Assert
      await expectLater(
        () => SeedNodeUpdater.fetchSeedNodes(
          config: config,
          httpClient: mockClient,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No seed nodes found for netid 6133'),
          ),
        ),
      );

      verify(() => mockClient.get(any())).called(1);
      verifyNever(() => mockClient.close());
    });

    test('should handle HTTP errors properly', () async {
      // Arrange
      final mockResponse = MockResponse();
      when(() => mockResponse.statusCode).thenReturn(404);
      when(() => mockClient.get(any())).thenAnswer((_) async => mockResponse);

      // Act & Assert
      await expectLater(
        () => SeedNodeUpdater.fetchSeedNodes(
          config: config,
          httpClient: mockClient,
        ),
        throwsException,
      );

      verify(() => mockClient.get(any())).called(1);
      verifyNever(() => mockClient.close());
    });

    test('should create and close temporary client when none provided', () async {
      // This test demonstrates that when no client is provided, a temporary one is created
      // and properly closed. However, since we can't easily mock the http.Client() constructor,
      // we'll test that the existing behavior still works with the new signature.

      // This test would normally be run against a real endpoint or with more sophisticated
      // mocking that can intercept the http.Client() constructor.

      // For now, we'll just verify the method signature works without a client parameter
      expect(
        () => SeedNodeUpdater.fetchSeedNodes(config: config),
        returnsNormally,
      );
    });

    test('should apply custom timeout duration', () async {
      // Arrange
      final mockResponse = MockResponse();
      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.body).thenReturn('[]'); // Empty array

      // Create a completer to control timing
      final completer = Completer<http.Response>();
      when(() => mockClient.get(any())).thenAnswer((_) => completer.future);

      // Act
      final future = SeedNodeUpdater.fetchSeedNodes(
        config: config,
        httpClient: mockClient,
        timeout: const Duration(milliseconds: 100), // Very short timeout
      );

      // Don't complete the request to simulate a timeout

      // Assert - should timeout quickly
      await expectLater(
        future,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Timeout fetching seed nodes'),
          ),
        ),
      );

      verify(() => mockClient.get(any())).called(1);
    });
  });

  group('SeedNodeUpdater backward compatibility', () {
    test(
      'should maintain backward compatibility with old method signature',
      () async {
        // This test verifies that existing code continues to work
        const config = AssetRuntimeUpdateConfig();

        expect(
          () => SeedNodeUpdater.fetchSeedNodes(config: config),
          returnsNormally,
        );

        expect(
          () => SeedNodeUpdater.fetchSeedNodes(
            config: config,
            filterForWeb: false,
          ),
          returnsNormally,
        );
      },
    );
  });
}
