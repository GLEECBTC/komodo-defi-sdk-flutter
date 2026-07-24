import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('TronGaslessProviderConfig', () {
    test('serializes only documented proxy activation fields', () {
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: 'TProvider',
        requestTimeoutMs: 12000,
        statusPollIntervalMs: 2500,
      );

      expect(config.validate, returnsNormally);
      expect(config.toJson(), {
        'base_url': 'https://provider.example/gasfree',
        'service': 'komodo_proxy',
        'service_provider': 'TProvider',
        'request_timeout_ms': 12000,
        'status_poll_interval_ms': 2500,
      });
    });

    test('supports documented provider discovery when the pin is omitted', () {
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
      );

      expect(config.validate, returnsNormally);
      expect(config.toJson(), isNot(contains('service_provider')));
    });

    test('canonicalizes provider identity whitespace on the wire', () {
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: '  TProvider  ',
      );

      expect(config.toJson(), containsPair('service_provider', 'TProvider'));
    });

    test('round-trips the direct service shape without leaking secrets', () {
      const service = GaslessServiceGasFree(
        apiKey: 'public-key',
        apiSecret: 'top-secret',
      );
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example',
        service: service,
        serviceProvider: 'TProvider',
      );

      expect(config.validate, returnsNormally);
      expect(service.toString(), isNot(contains('public-key')));
      expect(service.toString(), isNot(contains('top-secret')));
      expect(config.toString(), isNot(contains('top-secret')));
      expect(TronGaslessProviderConfig.fromJson(config.toJson()), config);
      expect(config.toJson()['service'], {
        'gas_free': {'api_key': 'public-key', 'api_secret': 'top-secret'},
      });
    });

    test('credential equality remains value-sensitive', () {
      const first = GaslessServiceGasFree(
        apiKey: 'public-key',
        apiSecret: 'top-secret-one',
      );
      const second = GaslessServiceGasFree(
        apiKey: 'different-key',
        apiSecret: 'top-secret-two',
      );

      expect(first, isNot(second));
    });

    test('mirrors KDF transport rules for direct and proxy modes', () {
      const insecureDirect = TronGaslessProviderConfig(
        baseUrl: 'http://provider.example',
        service: GaslessServiceGasFree(apiKey: 'key', apiSecret: 'secret'),
      );
      const directWithPath = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceGasFree(apiKey: 'key', apiSecret: 'secret'),
      );
      const fullHttpProxy = TronGaslessProviderConfig(
        baseUrl: 'http://provider.example/gasfree//relay?network=nile',
        service: GaslessServiceKomodoProxy(),
      );

      expect(insecureDirect.validate, throwsArgumentError);
      expect(directWithPath.validate, throwsArgumentError);
      expect(fullHttpProxy.validate, returnsNormally);
      expect(
        fullHttpProxy.toJson(),
        containsPair(
          'base_url',
          'http://provider.example/gasfree//relay?network=nile',
        ),
      );
    });

    test('accepts the unsigned timeout range without invented SDK bounds', () {
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        requestTimeoutMs: 0,
        statusPollIntervalMs: 100,
      );

      expect(config.validate, returnsNormally);
    });

    test('requires non-empty direct credentials', () {
      const config = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example',
        service: GaslessServiceGasFree(apiKey: '', apiSecret: 'secret'),
      );

      expect(config.validate, throwsArgumentError);
    });
  });
}
