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

  Future<KdfStartupConfig> generate({String? lifiProxyUrl, bool? disableP2p}) =>
      KdfStartupConfig.generateWithDefaults(
        walletName: 'wallet',
        walletPassword: 'wallet-secret',
        enableHd: true,
        rpcPassword: 'rpc-secret',
        coinsPath: 'coins',
        userHome: home.path,
        dbDir: path.join(home.path, 'db'),
        seedNodes: (disableP2p ?? false) ? null : const ['seed01.kmdefi.net'],
        disableP2p: disableP2p,
        lifiProxyUrl: lifiProxyUrl,
      );

  group('KdfStartupConfig lifi_proxy_url', () {
    test('is absent when no LI.FI proxy is set', () async {
      final params = (await generate()).encodeStartParams();
      expect(params, isNot(contains('lifi_proxy_url')));
    });

    test('is absent when the LI.FI proxy URL is empty', () async {
      final params = (await generate(lifiProxyUrl: '')).encodeStartParams();
      expect(params, isNot(contains('lifi_proxy_url')));
    });

    test('carries the LI.FI proxy URL as given', () async {
      const url = 'https://swap.example.com/lifi/';
      final params = (await generate(lifiProxyUrl: url)).encodeStartParams();
      expect(params['lifi_proxy_url'], url);
      // KDF 7d6fd1e ignores the old key, so writing it would be a silent no-op.
      expect(params, isNot(contains('lifi_api')));
    });

    test('refuses a proxy when P2P is off', () async {
      // KDF signs proxy requests with its P2P key; without one every routed
      // swap fails with InternalError.
      await expectLater(
        generate(
          lifiProxyUrl: 'https://swap.example.com/lifi',
          disableP2p: true,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'lifiProxyUrl',
          ),
        ),
      );
    });

    test('allows P2P off when no proxy is set', () async {
      final params = (await generate(disableP2p: true)).encodeStartParams();
      expect(params['disable_p2p'], isTrue);
      expect(params, isNot(contains('lifi_proxy_url')));
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
          generate(lifiProxyUrl: url),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'name', 'lifiProxyUrl')
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
