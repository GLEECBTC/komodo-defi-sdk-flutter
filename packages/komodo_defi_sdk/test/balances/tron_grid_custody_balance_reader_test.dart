import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _custody = 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF';

Asset _asset({required bool nile}) {
  final platform = nile ? 'TRXT' : 'TRX';
  final contract = nile
      ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf'
      : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
  final parent = Asset.fromJson({
    'coin': platform,
    'type': 'TRX',
    'name': platform,
    'fname': platform,
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': nile ? 'Nile' : 'Mainnet'},
    },
    'nodes': const <Map<String, dynamic>>[],
  }, knownIds: const {});
  return Asset.fromJson(
    {
      'coin': nile ? 'TESTUSDT-TRC20' : 'USDT-TRC20',
      'type': 'TRC-20',
      'name': 'Tether',
      'fname': 'Tether',
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'protocol': {
        'type': 'TRC20',
        'protocol_data': {'platform': platform, 'contract_address': contract},
      },
      'contract_address': contract,
      'parent_coin': platform,
      'nodes': const <Map<String, dynamic>>[],
    },
    knownIds: {parent.id},
  );
}

void main() {
  for (final nile in [false, true]) {
    test('reads strict ${nile ? 'Nile' : 'mainnet'} custody balance', () async {
      final asset = _asset(nile: nile);
      final contract =
          (asset.protocol as Trc20Protocol).config['contract_address']
              as String;
      late Uri requestUri;
      final reader = TronGridGaslessCustodyBalanceReader(
        client: MockClient((request) async {
          requestUri = request.url;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'trc20': [
                    {contract: '42000000'},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final balance = await reader.readBalance(asset, _custody);

      expect(balance, Decimal.parse('42'));
      expect(requestUri.host, nile ? 'nile.trongrid.io' : 'api.trongrid.io');
      expect(requestUri.queryParameters['only_confirmed'], 'true');
      reader.dispose();
    });
  }

  test('maps explicit empty account states to zero', () async {
    final bodies = [
      jsonEncode({'success': true, 'data': <Object>[]}),
      jsonEncode({
        'success': true,
        'data': [<String, Object>{}],
      }),
    ];
    for (final body in bodies) {
      final reader = TronGridGaslessCustodyBalanceReader(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      expect(
        await reader.readBalance(_asset(nile: false), _custody),
        Decimal.zero,
      );
    }
  });

  test('rejects unsuccessful, malformed, and oversized responses', () async {
    final bodies = <String>[
      jsonEncode({'success': false, 'data': <Object>[]}),
      jsonEncode({'success': true, 'data': 'not-a-list'}),
      'x' * (256 * 1024 + 1),
    ];
    for (final body in bodies) {
      final reader = TronGridGaslessCustodyBalanceReader(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        reader.readBalance(_asset(nile: false), _custody),
        throwsFormatException,
      );
    }
    final invalidUtf8 = TronGridGaslessCustodyBalanceReader(
      client: MockClient((_) async => http.Response.bytes([0xff], 200)),
    );
    await expectLater(
      invalidUtf8.readBalance(_asset(nile: false), _custody),
      throwsFormatException,
    );
  });
}
