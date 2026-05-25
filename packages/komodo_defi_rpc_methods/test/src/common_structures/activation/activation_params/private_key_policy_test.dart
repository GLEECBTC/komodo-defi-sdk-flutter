import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('PrivateKeyPolicy.fromLegacyJson', () {
    group('handles null input', () {
      test('returns contextPrivKey when input is null', () {
        final result = PrivateKeyPolicy.fromLegacyJson(null);
        expect(result, const PrivateKeyPolicy.contextPrivKey());
      });
    });

    group('handles string inputs (legacy format)', () {
      test('parses "ContextPrivKey" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('ContextPrivKey');
        expect(result, const PrivateKeyPolicy.contextPrivKey());
      });

      test('parses "context_priv_key" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('context_priv_key');
        expect(result, const PrivateKeyPolicy.contextPrivKey());
      });

      test('parses "Trezor" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('Trezor');
        expect(result, const PrivateKeyPolicy.trezor());
      });

      test('parses "trezor" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('trezor');
        expect(result, const PrivateKeyPolicy.trezor());
      });

      test('parses "Metamask" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('Metamask');
        expect(result, const PrivateKeyPolicy.metamask());
      });

      test('parses "metamask" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('metamask');
        expect(result, const PrivateKeyPolicy.metamask());
      });

      test('parses "WalletConnect" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('WalletConnect');
        expect(result, const PrivateKeyPolicy.walletConnect(''));
      });

      test('parses "wallet_connect" string', () {
        final result = PrivateKeyPolicy.fromLegacyJson('wallet_connect');
        expect(result, const PrivateKeyPolicy.walletConnect(''));
      });

      test('throws ArgumentError for unknown string', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson('UnknownPolicy'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Unknown private key policy type: UnknownPolicy',
            ),
          ),
        );
      });

      test('throws ArgumentError for empty string', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(''),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Unknown private key policy type: ',
            ),
          ),
        );
      });
    });

    group('handles JSON object inputs', () {
      test('parses context_priv_key JSON object', () {
        final json = {'type': 'ContextPrivKey'};
        final result = PrivateKeyPolicy.fromLegacyJson(json);
        expect(result, const PrivateKeyPolicy.contextPrivKey());
      });

      test('parses trezor JSON object', () {
        final json = {'type': 'Trezor'};
        final result = PrivateKeyPolicy.fromLegacyJson(json);
        expect(result, const PrivateKeyPolicy.trezor());
      });

      test('parses metamask JSON object', () {
        final json = {'type': 'Metamask'};
        final result = PrivateKeyPolicy.fromLegacyJson(json);
        expect(result, const PrivateKeyPolicy.metamask());
      });

      test('parses wallet_connect JSON object without session_topic', () {
        final json = {'type': 'WalletConnect', 'session_topic': ''};
        final result = PrivateKeyPolicy.fromLegacyJson(json);
        expect(result, isA<PrivateKeyPolicy>());
        expect(result.toString(), contains('walletConnect'));
        expect(result.toJson()['type'], 'WalletConnect');
      });

      test('parses wallet_connect JSON object with session_topic', () {
        final json = {
          'type': 'WalletConnect',
          'session_topic': 'test_session_topic_123',
        };
        final result = PrivateKeyPolicy.fromLegacyJson(json);
        expect(result, isA<PrivateKeyPolicy>());
        expect(result.toString(), contains('walletConnect'));
        expect(result.toJson()['type'], 'WalletConnect');
        expect(result.toJson()['session_topic'], 'test_session_topic_123');
      });

      test('throws ArgumentError for JSON object with missing type field', () {
        final json = {'session_topic': 'test_topic'};
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(json),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid private key policy type'),
            ),
          ),
        );
      });

      test('throws ArgumentError for JSON object with null type field', () {
        final json = {'type': null};
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(json),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid private key policy type'),
            ),
          ),
        );
      });
    });

    group('handles invalid inputs', () {
      test('throws ArgumentError for non-string, non-map input', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(123),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Invalid private key policy type: int',
            ),
          ),
        );
      });

      test('throws ArgumentError for boolean input', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(true),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Invalid private key policy type: bool',
            ),
          ),
        );
      });

      test('throws ArgumentError for list input', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(['test']),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Invalid private key policy type: List<String>',
            ),
          ),
        );
      });
    });

    group('edge cases', () {
      test('handles case sensitivity for string inputs', () {
        // Test mixed case - should fail since not explicitly handled
        expect(
          () => PrivateKeyPolicy.fromLegacyJson('TREZOR'),
          throwsArgumentError,
        );

        expect(
          () => PrivateKeyPolicy.fromLegacyJson('TreZoR'),
          throwsArgumentError,
        );
      });

      test('handles whitespace in string inputs', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(' Trezor '),
          throwsArgumentError,
        );

        expect(
          () => PrivateKeyPolicy.fromLegacyJson('Trezor\n'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for empty JSON object', () {
        expect(
          () => PrivateKeyPolicy.fromLegacyJson(JsonMap()),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid private key policy type'),
            ),
          ),
        );
      });
    });

    group('integration with fromJson', () {
      test('validates that JSON objects are passed to fromJson correctly', () {
        final validJsonCases = [
          {'type': 'ContextPrivKey'},
          {'type': 'Trezor'},
          {'type': 'Metamask'},
          {'type': 'WalletConnect', 'session_topic': ''},
          {'type': 'WalletConnect', 'session_topic': 'test_topic'},
        ];

        for (final json in validJsonCases) {
          expect(
            () => PrivateKeyPolicy.fromLegacyJson(json),
            returnsNormally,
            reason: 'Should handle JSON: $json',
          );
        }
      });
    });

    group('return type validation', () {
      test('all valid inputs return PrivateKeyPolicy instances', () {
        final testCases = [
          null,
          'ContextPrivKey',
          'context_priv_key',
          'Trezor',
          'trezor',
          'Metamask',
          'metamask',
          'WalletConnect',
          'wallet_connect',
          {'type': 'ContextPrivKey'},
          {'type': 'Trezor'},
          {'type': 'Metamask'},
          {'type': 'WalletConnect', 'session_topic': ''},
          {'type': 'WalletConnect', 'session_topic': 'test'},
        ];

        for (final testCase in testCases) {
          final result = PrivateKeyPolicy.fromLegacyJson(testCase);
          expect(
            result,
            isA<PrivateKeyPolicy>(),
            reason: 'Input $testCase should return PrivateKeyPolicy',
          );
        }
      });
    });
  });

  group('PrivateKeyPolicy.pascalCaseName', () {
    test('returns correct PascalCase name for contextPrivKey', () {
      const policy = PrivateKeyPolicy.contextPrivKey();
      expect(policy.pascalCaseName, 'ContextPrivKey');
    });

    test('returns correct PascalCase name for trezor', () {
      const policy = PrivateKeyPolicy.trezor();
      expect(policy.pascalCaseName, 'Trezor');
    });

    test('returns correct PascalCase name for metamask', () {
      const policy = PrivateKeyPolicy.metamask();
      expect(policy.pascalCaseName, 'Metamask');
    });

    test('returns correct PascalCase name for walletConnect', () {
      const policy = PrivateKeyPolicy.walletConnect('test_session');
      expect(policy.pascalCaseName, 'WalletConnect');
    });

    test(
      'returns correct PascalCase name for walletConnect with empty session',
      () {
        const policy = PrivateKeyPolicy.walletConnect('');
        expect(policy.pascalCaseName, 'WalletConnect');
      },
    );

    test('pascalCaseName is consistent across different instances', () {
      const policy1 = PrivateKeyPolicy.walletConnect('session1');
      const policy2 = PrivateKeyPolicy.walletConnect('session2');
      expect(policy1.pascalCaseName, policy2.pascalCaseName);
    });

    test('pascalCaseName matches legacy string format', () {
      final testCases = [
        {
          'policy': const PrivateKeyPolicy.contextPrivKey(),
          'expected': 'ContextPrivKey',
        },
        {'policy': const PrivateKeyPolicy.trezor(), 'expected': 'Trezor'},
        {'policy': const PrivateKeyPolicy.metamask(), 'expected': 'Metamask'},
        {
          'policy': const PrivateKeyPolicy.walletConnect('test'),
          'expected': 'WalletConnect',
        },
      ];

      for (final testCase in testCases) {
        final policy = testCase['policy']! as PrivateKeyPolicy;
        final expected = testCase['expected']! as String;
        expect(policy.pascalCaseName, expected);
      }
    });
  });

  group('PrivKeyPolicySerializer', () {
    test('serializes Gnosis policies using EVM JSON form', () {
      final result = PrivKeyPolicySerializer.toRpc(
        const PrivateKeyPolicy.contextPrivKey(),
        protocol: CoinSubClass.gnosis,
      );

      expect(result, {'type': 'ContextPrivKey'});
    });
  });
}
