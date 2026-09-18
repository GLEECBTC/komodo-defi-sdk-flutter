import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';

class _Operations implements IKdfOperations {
  _Operations(this.response, {this.error});
  final JsonMap response;
  final Exception? error;
  JsonMap? received;

  @override
  Future<JsonMap> mm2Rpc(JsonMap request) async {
    received = request;
    if (error != null) throw error!;
    return response;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> logs;
  late StreamSubscription<LogRecord> subscription;
  late Level previousLevel;
  setUp(() {
    logs = [];
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord.listen((record) {
      logs.add(record.message);
      expect(record.error, isNull);
      expect(record.stackTrace, isNull);
    });
  });
  tearDown(() async {
    await subscription.cancel();
    Logger.root.level = previousLevel;
    KomodoDefiFramework.enableDebugLogging = true;
    KdfApiClient.enableDebugLogging = true;
    KdfLoggingConfig.verboseLogging = false;
  });

  for (final debug in [false, true]) {
    for (final verbose in [false, true]) {
      for (final method in [
        'get_mnemonic',
        'get_private_keys',
        'show_priv_key',
        'enable_eth_with_tokens',
        'my_balance',
        'unknown-secret-method',
      ]) {
        test(
          '$method debug=$debug verbose=$verbose never logs bodies',
          () async {
            KomodoDefiFramework.enableDebugLogging = debug;
            KdfLoggingConfig.verboseLogging = verbose;
            final response = <String, dynamic>{
              'result': {
                'mnemonic': 'synthetic-mnemonic',
                'priv_key': 'synthetic-private-key',
                'unknown_future_field': 'synthetic-unknown-secret',
                'address': 'synthetic-address',
                'servers': ['synthetic-server'],
              },
            };
            final operations = _Operations(response);
            final framework = KomodoDefiFramework.createWithOperations(
              hostConfig: LocalConfig(
                https: false,
                rpcPassword: 'synthetic-rpc-password',
              ),
              kdfOperations: operations,
              externalLogger: logs.add,
            );
            addTearDown(framework.dispose);
            final actual = await framework.executeRpc({
              'method': method,
              'params': {
                'password': 'synthetic-wallet-password',
                'activation_params': {'mode': 'synthetic-config-secret'},
              },
            });
            await Future<void>.delayed(Duration.zero);
            expect(actual, response);
            expect(operations.received!['userpass'], 'synthetic-rpc-password');
            final diagnostic = logs.join('\n');
            expect(diagnostic, isNot(contains('synthetic-')));
            expect(diagnostic, isNot(contains('unknown-secret-method')));
            if (debug || verbose) {
              expect(diagnostic, contains('outcome=success'));
            }
          },
        );
      }
    }
  }

  test('RPC client never logs activation/balance/error payloads', () async {
    final response = <String, dynamic>{
      'result': {'address': 'synthetic-secret'},
    };
    final client = KdfApiClient((_) => response);
    expect(
      await client.executeRpc({
        'method': 'enable',
        'params': {
          'ticker': 'synthetic-secret',
          'activation_params': {'mode': 'synthetic-secret'},
        },
      }),
      response,
    );
    final failure = KdfApiClient(
      (_) =>
          throw const FormatException('synthetic-secret', 'synthetic-secret'),
    );
    await expectLater(
      failure.executeRpc({'method': 'synthetic-secret'}),
      throwsFormatException,
    );
    expect(logs.join('\n'), isNot(contains('synthetic-secret')));
    expect(logs.join('\n'), contains('outcome=failure'));
  });

  test(
    'framework errors and callback fallback do not expose their contents',
    () async {
      final printed = <String>[];
      await runZoned(
        () async {
          KdfLoggingConfig.verboseLogging = true;
          final framework = KomodoDefiFramework.createWithOperations(
            hostConfig: LocalConfig(
              https: false,
              rpcPassword: 'synthetic-password',
            ),
            kdfOperations: _Operations(
              {},
              error: const FormatException(
                'synthetic-error-secret',
                'synthetic-body-secret',
              ),
            ),
            externalLogger: (_) =>
                throw StateError('synthetic-callback-secret'),
          );
          await expectLater(
            framework.executeRpc({'method': 'get_mnemonic'}),
            throwsFormatException,
          );
          await Future<void>.delayed(Duration.zero);
          await framework.dispose();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) {
            printed.add(line);
          },
        ),
      );
      expect([...logs, ...printed].join('\n'), isNot(contains('synthetic-')));
      expect(printed, contains('KDF diagnostic callback failed'));
    },
  );
}
