import 'dart:collection';

import 'package:komodo_defi_sdk/src/activation/protocol_strategies/sia_activation_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _QueueApiClient implements ApiClient {
  _QueueApiClient({
    required Map<String, List<JsonMap>> responsesByMethod,
    this.errorsByMethod = const {},
  }) : _responsesByMethod = {
         for (final entry in responsesByMethod.entries)
           entry.key: Queue<JsonMap>.from(entry.value),
       };

  final Map<String, Queue<JsonMap>> _responsesByMethod;
  final Map<String, Exception> errorsByMethod;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    final method = request.value<String>('method');

    final error = errorsByMethod[method];
    if (error != null) {
      throw error;
    }

    final queue = _responsesByMethod[method];
    if (queue == null || queue.isEmpty) {
      throw StateError('No queued response for method $method');
    }

    return queue.removeFirst();
  }
}

Asset _createSiaAsset() {
  return Asset.fromJson(const {
    'coin': 'SC',
    'type': 'SIA',
    'name': 'Siacoin',
    'fname': 'Siacoin',
    'wallet_only': false,
    'mm2': 1,
    'chain_id': 2024,
    'decimals': 24,
    'required_confirmations': 1,
    'nodes': [
      {'url': 'https://api.siascan.com/wallet/api'},
    ],
  });
}

void main() {
  group('SiaActivationStrategy', () {
    test('emits exactly one terminal success event', () async {
      final strategy = SiaActivationStrategy(
        _QueueApiClient(
          responsesByMethod: {
            'task::enable_sia::init': [
              {
                'mmrpc': '2.0',
                'result': {'task_id': 7},
              },
            ],
            'task::enable_sia::status': [
              {
                'mmrpc': '2.0',
                'result': {'status': 'InProgress', 'details': 'syncing'},
              },
              {
                'mmrpc': '2.0',
                'result': {'status': 'Ok', 'details': 'done'},
              },
            ],
          },
        ),
      );

      final events = await strategy.activate(_createSiaAsset()).toList();
      final terminalEvents = events.where((event) => event.isComplete).toList();

      expect(terminalEvents, hasLength(1));
      expect(terminalEvents.single.isSuccess, isTrue);
    });

    test('emits exactly one terminal failure event for error status', () async {
      final strategy = SiaActivationStrategy(
        _QueueApiClient(
          responsesByMethod: {
            'task::enable_sia::init': [
              {
                'mmrpc': '2.0',
                'result': {'task_id': 8},
              },
            ],
            'task::enable_sia::status': [
              {
                'mmrpc': '2.0',
                'result': {'status': 'Error', 'details': 'activation failed'},
              },
            ],
          },
        ),
      );

      final events = await strategy.activate(_createSiaAsset()).toList();
      final terminalEvents = events.where((event) => event.isComplete).toList();

      expect(terminalEvents, hasLength(1));
      expect(terminalEvents.single.isError, isTrue);
      expect(terminalEvents.single.isSuccess, isFalse);
    });

    test('emits exactly one terminal failure event for exceptions', () async {
      final strategy = SiaActivationStrategy(
        _QueueApiClient(
          responsesByMethod: {
            'task::enable_sia::init': [
              {
                'mmrpc': '2.0',
                'result': {'task_id': 9},
              },
            ],
          },
          errorsByMethod: {
            'task::enable_sia::status': Exception('network failure'),
          },
        ),
      );

      final events = await strategy.activate(_createSiaAsset()).toList();
      final terminalEvents = events.where((event) => event.isComplete).toList();

      expect(terminalEvents, hasLength(1));
      expect(terminalEvents.single.isError, isTrue);
      expect(terminalEvents.single.isSuccess, isFalse);
    });
  });
}
