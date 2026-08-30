import 'dart:math';

import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

void main() {
  group('Password validation tests', () {
    test('Too short passwords should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Abc1!'),
        PasswordValidationError.tooShort,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(''),
        PasswordValidationError.tooShort,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('A1b!'),
        PasswordValidationError.tooShort,
      );
    });

    test('Passwords containing "password" should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('myPassword123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('PASSWORDabc123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('pAsSwOrD123!'),
        PasswordValidationError.containsPassword,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('My-password-is-secure!123'),
        PasswordValidationError.containsPassword,
      );
    });

    test('Passwords without digits should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('StrongPass!'),
        PasswordValidationError.missingDigit,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('NoDigitsHere!@#'),
        PasswordValidationError.missingDigit,
      );
    });

    test('Passwords without lowercase should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('STRONG123!'),
        PasswordValidationError.missingLowercase,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('ALL123CAPS!@#'),
        PasswordValidationError.missingLowercase,
      );
    });

    test('Passwords without uppercase should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('strong123!'),
        PasswordValidationError.missingUppercase,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('all123lower!@#'),
        PasswordValidationError.missingUppercase,
      );
    });

    test('Passwords without special characters should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Strong123'),
        PasswordValidationError.missingSpecialCharacter,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('NoSpecial1Characters2'),
        PasswordValidationError.missingSpecialCharacter,
      );
    });

    test('Multiple validation errors should return most critical first', () {
      expect(
        SecurityUtils.checkPasswordRequirements('pass'),
        PasswordValidationError.tooShort,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('passwordddd'),
        PasswordValidationError.containsPassword,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Abcaaa1234*%'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Abcde123'),
        PasswordValidationError.missingSpecialCharacter,
      );
    });

    test('Edge cases with spaces and special formatting', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Pass 123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Tab\t123!A'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Line\nBreak123!A'),
        PasswordValidationError.none,
      );
    });

    test('Passwords with numbers in various positions', () {
      expect(
        SecurityUtils.checkPasswordRequirements('1AbcSpecial!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Abc1Special!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('AbcSpecial!1'),
        PasswordValidationError.none,
      );
    });

    test('Various special characters', () {
      expect(
        SecurityUtils.checkPasswordRequirements('AbcDef123@'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Abc_Def123#'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(r'AbcDef123$'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('AbcDef123%'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('AbcDef123&'),
        PasswordValidationError.none,
      );
    });

    test('Valid passwords should not fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Very!hard!pass!77'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Komodo2024!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Complex!P4ssword123'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(r'!P4ssword#$@'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Mix3d_Ch4r4ct3rs!'),
        PasswordValidationError.none,
      );
    });

    test('Password specifically mentioned in the issue should be rejected', () {
      // Should fail (has consecutive characters)
      expect(
        SecurityUtils.checkPasswordRequirements('Very!hard!pass!777'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test('Passwords with three or more consecutive identical '
        'characters should fail', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Strong111Security!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Secure222!A'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('A1!Secure333'),
        PasswordValidationError.consecutiveCharacters,
      );

      expect(
        SecurityUtils.checkPasswordRequirements('aaaStrong1!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!bbb'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!CCC'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!!!Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1###Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(r'Strong1$$$Secure'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!aaaaa'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!44444'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1!!!!!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test(
      'Valid passwords with two consecutive identical characters should pass',
      () {
        expect(
          SecurityUtils.checkPasswordRequirements('Strong11Secured!'),
          PasswordValidationError.none,
        );
        expect(
          SecurityUtils.checkPasswordRequirements('Strong!!Secured1'),
          PasswordValidationError.none,
        );
        expect(
          SecurityUtils.checkPasswordRequirements('aaStrong1!Secured'),
          PasswordValidationError.none,
        );
      },
    );

    test('Special case - passwords with unicode characters', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Пароль123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('密码Abc123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Mötley123!'),
        PasswordValidationError.none,
      );
    });

    test('Extended Unicode character password tests', () {
      expect(
        SecurityUtils.checkPasswordRequirements('علي123!Abc'), // Arabic
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('こんにちは123!Ab'), // Japanese
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('안녕하세요123!Ab'), // Korean
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Привет123!Ab'), // Cyrillic
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Γειά123!Aa'), // Greek
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('שלום123!Aa'), // Hebrew
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('नमस्ते123!Ab'), // Devanagari
        PasswordValidationError.none,
      );
    });

    test('Unicode edge cases and challenging patterns', () {
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Раssw0rd!',
        ), // Cyrillic 'Р' (not Latin 'P')
        PasswordValidationError.none,
      );

      expect(
        SecurityUtils.checkPasswordRequirements('Pass\u200Bword123!'),
        PasswordValidationError.none,
      );

      expect(
        // a + combining acute accent
        SecurityUtils.checkPasswordRequirements('Pa\u0301ssword123!'),
        PasswordValidationError.none,
      );

      expect(
        SecurityUtils.checkPasswordRequirements('Strong🔑123!A'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('A1!🎮🎲🎯aa'),
        PasswordValidationError.none,
      );

      expect(
        SecurityUtils.checkPasswordRequirements('Strоng123!'),
        PasswordValidationError.none,
      );
    });

    test('Unicode sequential characters detection', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Strong爱爱爱123!'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong😊😊😊123!'),
        PasswordValidationError.consecutiveCharacters,
      );

      // Characters that look similar but are actually different code points
      expect(
        SecurityUtils.checkPasswordRequirements('StrongАААbc123!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });

    test('Bidirectional text and special Unicode formatting', () {
      // Right-to-left marks and embedding
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Pass\u200Eword123!A',
        ), // Contains LTR mark
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Pass\u200Fword123!A',
        ), // Contains RTL mark
        PasswordValidationError.none,
      );

      // Mixed directionality
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Abcהמסיסמ123!',
        ), // Hebrew mixed with Latin
        PasswordValidationError.none,
      );

      // Special spaces
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Pass\u2007word123!A',
        ), // Figure space
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements(
          'Pass\u00A0word123!A',
        ), // Non-breaking space
        PasswordValidationError.none,
      );
    });

    test('Advanced emoji password tests in valid passwords', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Strong123!🔒'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('🔑Abcasba123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Pass🔥123!A'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Abc123!🌟✨🚀'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('🎮🎯A1!abaa'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong👨‍👩‍👧‍👦123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('A1!👍🏽Strong1234'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Pass🇺🇸123!A'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong123A🎯'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Strong1A🎯🎯🎯'),
        PasswordValidationError.consecutiveCharacters,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('🔥🔥🔥Strong1A!'),
        PasswordValidationError.consecutiveCharacters,
      );
    });
    test('Complex emoji sequences and ZWJ', () {
      expect(
        // ZWJ sequence (man technologist)
        SecurityUtils.checkPasswordRequirements('Strong123A👨‍💻'),
        PasswordValidationError.none,
      );
      expect(
        // Complex ZWJ sequence
        SecurityUtils.checkPasswordRequirements('Strong123A👁️‍🗨️'),
        PasswordValidationError.none,
      );
      expect(
        // Emoji presentation selector
        SecurityUtils.checkPasswordRequirements('Strong123A☺️'),
        PasswordValidationError.none,
      );
    });

    test('Mixed emoji and text patterns', () {
      expect(
        SecurityUtils.checkPasswordRequirements('Aaba🔒1🔑!🚀'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('Se🔒cure123!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('St🔑r🔒ng1!'),
        PasswordValidationError.none,
      );
      expect(
        // Should not trigger containsPassword
        SecurityUtils.checkPasswordRequirements('p🔑ssw🔒rd123A!'),
        PasswordValidationError.none,
      );
      expect(
        SecurityUtils.checkPasswordRequirements('🔒🚀🎮��Aa1!'),
        PasswordValidationError.none,
      );
    });

    test('Limited fuzzy testing', () {
      final random = Random();
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123'
          r'456789!@#$%^&*()';

      for (int i = 0; i < 10; i++) {
        final length = random.nextInt(15) + 1;
        final passwordBuffer = StringBuffer();

        for (var j = 0; j < length; j++) {
          passwordBuffer.write(chars[random.nextInt(chars.length)]);
        }

        // Test the random password - we don't assert specific errors,
        // just verify the validator properly handles random input
        SecurityUtils.checkPasswordRequirements(passwordBuffer.toString());
      }

      final problematicInputs = <String>[
        // Password too short
        'a',
        // Repeated characters
        'aaaPassword1!',
        'Password111!',
        'Password!!!1',
        // Mixed borderline cases
        'pass A1!',
        'PASS a1!',
        'Pass A!',
        'Pass A1',
        // Contains "password"
        'MyPasswordIs1!',
        'password123A!',
        '!PASSWORDabc1',
      ];

      for (final input in problematicInputs) {
        SecurityUtils.checkPasswordRequirements(input);
      }
    });
  });

  group('Password generation tests', () {
    test('Should throw error when length is less than 8', () {
      expect(
        () => SecurityUtils.generatePasswordSecure(7),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SecurityUtils.generatePasswordSecure(0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SecurityUtils.generatePasswordSecure(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Should generate password of specified length', () {
      final password8 = SecurityUtils.generatePasswordSecure(8);
      final password16 = SecurityUtils.generatePasswordSecure(16);
      final password32 = SecurityUtils.generatePasswordSecure(32);

      expect(password8.length, equals(8));
      expect(password16.length, equals(16));
      expect(password32.length, equals(32));
    });

    test('Should include all required character types', () {
      final password = SecurityUtils.generatePasswordSecure(12);

      // Check for at least one uppercase letter
      expect(RegExp('[A-Z]').hasMatch(password), isTrue);

      // Check for at least one lowercase letter
      expect(RegExp('[a-z]').hasMatch(password), isTrue);

      // Check for at least one digit
      expect(RegExp('[0-9]').hasMatch(password), isTrue);

      // Check for at least one special character
      expect(RegExp('[@]').hasMatch(password), isTrue);
    });

    test('Should include extended special characters when flag is set', () {
      final password = SecurityUtils.generatePasswordSecure(
        20,
        extendedSpecialCharacters: true,
      );

      expect(RegExp(r'[~`$^*+=<>?]').hasMatch(password), isTrue);
      expect(password.length, equals(20));
    });

    test('Generated passwords should be different (randomness check)', () {
      final passwords = <String>{};

      // Generate multiple passwords and check they're unique
      for (var i = 0; i < 10; i++) {
        passwords.add(SecurityUtils.generatePasswordSecure(12));
      }

      // If passwords are truly random, they should all be different
      expect(passwords.length, equals(10));
    });

    test(
      'Generated passwords should pass checkPasswordRequirements validation',
      () {
        for (var i = 0; i < 10; i++) {
          final password = SecurityUtils.generatePasswordSecure(12);
          final validationResult = SecurityUtils.checkPasswordRequirements(
            password,
          );
          expect(validationResult, equals(PasswordValidationError.none));
        }

        // Test with extended characters too
        for (var i = 0; i < 10; i++) {
          final password = SecurityUtils.generatePasswordSecure(
            12,
            extendedSpecialCharacters: true,
          );
          final validationResult = SecurityUtils.checkPasswordRequirements(
            password,
          );
          expect(validationResult, equals(PasswordValidationError.none));
        }
      },
    );

    test(
      'Should not generate passwords with consecutive identical characters',
      () {
        // Generate multiple passwords and confirm none have 3+ consecutive identical characters
        for (var i = 0; i < 20; i++) {
          final password = SecurityUtils.generatePasswordSecure(32);

          // Check for consecutive identical characters with regular expressions
          final hasConsecutiveChars = RegExp(r'(.)\1{2,}').hasMatch(password);

          expect(hasConsecutiveChars, isFalse);
        }
      },
    );

    test('Should generate valid passwords at minimum length (8)', () {
      final password = SecurityUtils.generatePasswordSecure(8);
      expect(password.length, equals(8));
      expect(
        SecurityUtils.checkPasswordRequirements(password),
        equals(PasswordValidationError.none),
      );
    });

    test('Should generate valid passwords at large lengths', () {
      final password = SecurityUtils.generatePasswordSecure(100);
      expect(password.length, equals(100));
      expect(
        SecurityUtils.checkPasswordRequirements(password),
        equals(PasswordValidationError.none),
      );
    });

    test(
      'Should generate exact length password with extended special characters',
      () {
        final password12 = SecurityUtils.generatePasswordSecure(
          12,
          extendedSpecialCharacters: true,
        );
        final password16 = SecurityUtils.generatePasswordSecure(
          16,
          extendedSpecialCharacters: true,
        );
        final password24 = SecurityUtils.generatePasswordSecure(
          24,
          extendedSpecialCharacters: true,
        );

        expect(password12.length, equals(12));
        expect(password16.length, equals(16));
        expect(password24.length, equals(24));

        expect(
          SecurityUtils.checkPasswordRequirements(password12),
          equals(PasswordValidationError.none),
        );
      },
    );
  });

  group('Diagnostic JSON redaction', () {
    test('recursively removes credentials and signed relay payloads', () {
      final request = <String, dynamic>{
        'method': 'send_raw_transaction',
        'userpass': 'rpc-password-value',
        'tx_hex': 'signed-standard-transaction',
        'tx_json': <String, dynamic>{
          'request_id': 'safe-request-id',
          'from_address': 'private-wallet-address',
          'authorization_fingerprint': 'safe-fingerprint',
          'signed_authorization': <String, dynamic>{
            'sig': 'signed-gasfree-payload',
            'receiver': 'private-recipient',
          },
        },
        'providers': <Object?>[
          <String, dynamic>{
            'api_key': 'provider-api-key',
            'api_secret': 'provider-api-secret',
          },
          <Object?>[
            <String, dynamic>{'access_token': 'nested-access-token'},
          ],
        ],
        'expected_authorization': <String, dynamic>{
          'account': 'private-account',
          'amount': '5000000',
        },
      };

      final redacted = request.censored();
      final encoded = redacted.toJsonString();

      for (final secret in <String>[
        'rpc-password-value',
        'signed-standard-transaction',
        'private-wallet-address',
        'signed-gasfree-payload',
        'private-recipient',
        'provider-api-key',
        'provider-api-secret',
        'nested-access-token',
        'private-account',
        '5000000',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      expect(redacted['userpass'], '<redacted>');
      expect(redacted['tx_hex'], '<redacted>');
      expect(
        (redacted['tx_json'] as Map<String, dynamic>)['signed_authorization'],
        '<redacted>',
      );
      expect(redacted['expected_authorization'], '<redacted>');
      expect(
        (redacted['tx_json'] as Map<String, dynamic>)['request_id'],
        'safe-request-id',
      );
      expect(
        (redacted['tx_json']
            as Map<String, dynamic>)['authorization_fingerprint'],
        'safe-fingerprint',
      );

      // Logging must not mutate the request that is subsequently sent to KDF.
      expect(request['userpass'], 'rpc-password-value');
      expect(
        ((request['tx_json'] as Map<String, dynamic>)['signed_authorization']
            as Map<String, dynamic>)['sig'],
        'signed-gasfree-payload',
      );
    });

    test('normalizes case and separators in sensitive keys', () {
      final redacted = <String, dynamic>{
        'API-SECRET': 'secret-one',
        'walletPassword': 'not-matched-camel-case',
        'service_password': 'secret-two',
        'provider-signature': 'secret-three',
      }.censored();

      expect(redacted['API-SECRET'], '<redacted>');
      expect(redacted['service_password'], '<redacted>');
      expect(redacted['provider-signature'], '<redacted>');
      expect(redacted['walletPassword'], '<redacted>');
    });
  });
}
