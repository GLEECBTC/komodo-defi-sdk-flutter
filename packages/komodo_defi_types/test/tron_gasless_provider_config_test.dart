import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('TronGaslessProviderConfig security', () {
    test(
      'direct credentials are redacted from stringification and equality',
      () {
        const first = GaslessServiceGasFree(
          apiKey: 'public-key',
          apiSecret: 'top-secret-one',
        );
        const second = GaslessServiceGasFree(
          apiKey: 'different-key',
          apiSecret: 'top-secret-two',
        );
        const config = TronGaslessProviderConfig(
          baseUrl: 'https://provider.example',
          service: first,
          serviceProvider: 'TProvider',
        );

        expect(first, second);
        expect(first.toString(), isNot(contains('top-secret-one')));
        expect(first.toString(), isNot(contains('public-key')));
        expect(config.toString(), isNot(contains('top-secret-one')));
        expect(first.toJson().toString(), contains('top-secret-one'));
      },
    );

    test('production validation requires proxy transport and HTTPS', () {
      const proxy = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: 'TProvider',
      );
      const direct = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceGasFree(apiKey: 'key', apiSecret: 'secret'),
        serviceProvider: 'TProvider',
      );
      const insecure = TronGaslessProviderConfig(
        baseUrl: 'http://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: 'TProvider',
      );

      expect(proxy.validate, returnsNormally);
      expect(direct.validate, throwsArgumentError);
      expect(insecure.validate, throwsArgumentError);
    });

    test('discovery and insecure transport require explicit dev opt-ins', () {
      const discovery = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: null,
        allowServiceProviderDiscovery: true,
      );
      const insecure = TronGaslessProviderConfig(
        baseUrl: 'http://localhost:7783/gasfree',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: 'TProvider',
        unsafeAllowInsecureHttp: true,
      );

      expect(discovery.validate, throwsArgumentError);
      expect(
        () => discovery.validate(allowProviderDiscovery: true),
        returnsNormally,
      );
      expect(insecure.validate, throwsArgumentError);
      expect(
        () => insecure.validate(allowInsecureTransport: true),
        returnsNormally,
      );
      expect(
        discovery.toJson(),
        containsPair('allow_service_provider_discovery', true),
      );
      expect(
        insecure.toJson(),
        containsPair('unsafe_allow_insecure_http', true),
      );
    });

    test('direct HMAC and ambiguous paths are rejected by default', () {
      const directDevelopment = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example',
        service: GaslessServiceGasFree(
          apiKey: 'key',
          apiSecret: 'secret',
          unsafeAllowDirectHmac: true,
        ),
        serviceProvider: 'TProvider',
      );
      const ambiguousProxy = TronGaslessProviderConfig(
        baseUrl: 'https://provider.example/gasfree//relay',
        service: GaslessServiceKomodoProxy(),
        serviceProvider: 'TProvider',
      );

      expect(directDevelopment.validate, throwsArgumentError);
      expect(
        () => directDevelopment.validate(allowDirectCredentials: true),
        returnsNormally,
      );
      expect(ambiguousProxy.validate, throwsArgumentError);
      expect(directDevelopment.toJson()['service'], {
        'gas_free': {
          'api_key': 'key',
          'api_secret': 'secret',
          'unsafe_allow_direct_hmac': true,
        },
      });
    });
  });
}
