import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _encryptedResponse(Object? version) {
  const data = EncryptedMnemonicData.encryptedDataExample;
  final details = data['key_derivation_details'] as Map<String, dynamic>;
  final argon2 = details['Argon2'] as Map<String, dynamic>;
  return {
    'format': 'encrypted',
    'encrypted_mnemonic_data': {
      ...data,
      'key_derivation_details': {
        'Argon2': {
          ...argon2,
          'params': {
            ...argon2['params'] as Map<String, dynamic>,
            'version': version,
          },
        },
      },
    },
  };
}

void main() {
  for (final version in <Object>['0x13', '19', 19, 19.0]) {
    test('encrypted mnemonic accepts integral Argon2 version $version', () {
      final mnemonic = Mnemonic.fromRpcJson(_encryptedResponse(version));
      expect(mnemonic.isEncrypted, isTrue);
      expect(mnemonic.plaintextMnemonic, isNull);
      expect(mnemonic.encryptedMnemonic!.keyDerivationDetails.version, 19);
      final restored = Mnemonic.fromRpcJson(mnemonic.toJson());
      expect(
        restored.encryptedMnemonic!.toJson(),
        mnemonic.encryptedMnemonic!.toJson(),
      );
    });
  }

  for (final version in [
    19.5,
    double.nan,
    double.infinity,
    '19.5',
    true,
    null,
  ]) {
    test('encrypted mnemonic rejects non-integral version $version', () {
      expect(
        () => Mnemonic.fromRpcJson(_encryptedResponse(version)),
        throwsFormatException,
      );
    });
  }

  test('invalid version errors omit the untrusted value', () {
    expect(
      () => Mnemonic.fromRpcJson(_encryptedResponse('private-version-canary')),
      throwsA(
        isA<FormatException>()
            .having((error) => error.source, 'source', isNull)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('private-version-canary')),
            ),
      ),
    );
  });
}
