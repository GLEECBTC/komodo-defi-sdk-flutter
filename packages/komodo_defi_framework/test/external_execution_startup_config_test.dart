import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

void main() {
  group('ExternalExecutionStartupConfig', () {
    test('defaults are explicit and fail-closed', () {
      const config = ExternalExecutionStartupConfig();

      expect(config.toJson(), {
        'allow_client_materialized_transaction': false,
        'client_materialized_evm_targets': <String, dynamic>{},
        'lifi': {
          'enabled': false,
          'case_a_enabled': false,
          'integrator': 'gleec-kdf',
          'transport': {'transport_type': 'disabled'},
        },
      });
    });

    test('encodes the exact fixed Gleec proxy transport', () {
      const config = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(
          enabled: true,
          caseAEnabled: true,
          transport: LifiTransport.gleecProxy(
            'https://proxy.gleec.com/lifi/v1',
          ),
        ),
      );

      expect(config.toJson()['lifi'], {
        'enabled': true,
        'case_a_enabled': true,
        'integrator': 'gleec-kdf',
        'transport': {
          'transport_type': 'gleec_proxy',
          'base_url': 'https://proxy.gleec.com/lifi/v1',
        },
      });
    });

    test('requires the parent Li.Fi switch for Case A', () {
      const config = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(caseAEnabled: true),
      );

      expect(config.toJson, throwsStateError);
    });

    test('requires an explicit override for every direct transport', () {
      const blocked = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(transport: LifiTransport.direct()),
      );
      const blockedEnabled = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(
          enabled: true,
          transport: LifiTransport.direct(),
        ),
      );
      const allowed = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(
          enabled: true,
          transport: LifiTransport.direct(),
          allowDirectNonProduction: true,
        ),
      );

      expect(blocked.toJson, throwsStateError);
      expect(blockedEnabled.toJson, throwsStateError);
      expect(
        allowed.toJson()['lifi'],
        containsPair('transport', {'transport_type': 'direct'}),
      );
    });

    test('disabled transport cannot be enabled', () {
      const config = ExternalExecutionStartupConfig(
        lifi: LifiStartupConfig(enabled: true),
      );

      expect(config.toJson, throwsStateError);
    });

    test('rejects proxy URLs outside the exact production boundary', () {
      const invalidUrls = [
        'http://proxy.gleec.com/lifi/v1',
        'https://proxy.gleec.com/lifi/v1/',
        'https://proxy.gleec.com/lifi/v1?key=value',
        'https://user@proxy.gleec.com/lifi/v1',
        'https://proxy.gleec.com/anything-else',
      ];

      for (final url in invalidUrls) {
        final config = ExternalExecutionStartupConfig(
          lifi: LifiStartupConfig(transport: LifiTransport.gleecProxy(url)),
        );
        expect(config.toJson, throwsFormatException, reason: url);
      }
    });

    test('startup validates transport before creating storage', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'kdf-startup-validation-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final dbDir = Directory('${tempDir.path}/must-not-be-created');

      await expectLater(
        KdfStartupConfig.generateWithDefaults(
          walletName: 'wallet',
          walletPassword: 'password',
          enableHd: false,
          coinsPath: '${tempDir.path}/coins.json',
          userHome: tempDir.path,
          dbDir: dbDir.path,
          seedNodes: const ['seed.example.com'],
          externalExecution: const ExternalExecutionStartupConfig(
            lifi: LifiStartupConfig(
              enabled: true,
              transport: LifiTransport.direct(),
            ),
          ),
        ),
        throwsStateError,
      );
      expect(dbDir.existsSync(), isFalse);
    });

    test(
      'authenticated startup serializes external execution into KDF',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'kdf-startup-config-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final config = await KdfStartupConfig.generateWithDefaults(
          walletName: 'wallet',
          walletPassword: 'password',
          enableHd: false,
          rpcPassword: 'rpc-password',
          coinsPath: '${tempDir.path}/coins.json',
          userHome: tempDir.path,
          dbDir: '${tempDir.path}/kdf',
          seedNodes: const ['seed.example.com'],
          externalExecution: const ExternalExecutionStartupConfig(
            lifi: LifiStartupConfig(
              enabled: true,
              caseAEnabled: true,
              transport: LifiTransport.gleecProxy(
                'https://proxy.gleec.com/lifi/v1',
              ),
            ),
          ),
        );

        expect(config.encodeStartParams()['external_execution'], {
          'allow_client_materialized_transaction': false,
          'client_materialized_evm_targets': <String, dynamic>{},
          'lifi': {
            'enabled': true,
            'case_a_enabled': true,
            'integrator': 'gleec-kdf',
            'transport': {
              'transport_type': 'gleec_proxy',
              'base_url': 'https://proxy.gleec.com/lifi/v1',
            },
          },
        });
      },
    );
  });
}
