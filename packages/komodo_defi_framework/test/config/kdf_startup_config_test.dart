import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('kdf_startup_config_');
  });
  tearDown(() => home.delete(recursive: true));

  Future<KdfStartupConfig> generate({String? lifiApiUrl}) =>
      KdfStartupConfig.generateWithDefaults(
        walletName: 'wallet',
        walletPassword: 'wallet-secret',
        enableHd: true,
        rpcPassword: 'rpc-secret',
        coinsPath: 'coins',
        userHome: home.path,
        dbDir: path.join(home.path, 'db'),
        seedNodes: const ['seed01.kmdefi.net'],
        lifiApiUrl: lifiApiUrl,
      );

  group('KdfStartupConfig lifi_api', () {
    test('is absent when no LI.FI URL is set', () async {
      final params = (await generate()).encodeStartParams();
      expect(params, isNot(contains('lifi_api')));
    });

    test('is absent when the LI.FI URL is empty', () async {
      final params = (await generate(lifiApiUrl: '')).encodeStartParams();
      expect(params, isNot(contains('lifi_api')));
    });

    test('carries the LI.FI URL as given', () async {
      const url = 'https://swap.example.com/lifi/';
      final params = (await generate(lifiApiUrl: url)).encodeStartParams();
      expect(params['lifi_api'], url);
    });

    for (final url in [
      'swap.example.com',
      'ftp://swap.example.com',
      'https://',
      'https://partner:secret@swap.example.com',
      'https://swap.example.com?apiKey=secret',
      'https://swap.example.com/lifi#v1',
    ]) {
      test('rejects $url without echoing it', () async {
        await expectLater(
          generate(lifiApiUrl: url),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'name', 'lifiApiUrl')
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains(url)),
                ),
          ),
        );
      });
    }
  });
}
