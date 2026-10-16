import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

// The v2 `best_orders` answer as KDF sends it at 4872ef2
// (lp_ordermatch/best_orders.rs, `BestOrdersV2Response`).
void main() {
  Map<String, dynamic> amount(String decimal, int numer, int denom) => {
    'decimal': decimal,
    'rational': [
      [
        1,
        [numer],
      ],
      [
        1,
        [denom],
      ],
    ],
    'fraction': {'numer': '$numer', 'denom': '$denom'},
  };

  const makerPubkey =
      '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';

  Map<String, dynamic> btcOrder(String coin) => {
    'coin': coin,
    'address': {
      'address_type': 'Transparent',
      'address_data': '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',
    },
    'price': amount('0.00001', 1, 100000),
    'pubkey': makerPubkey,
    'uuid': 'b4f4ae6c-5e2c-4b3a-9f14-2d8c7a1e9d01',
    'is_mine': false,
    'base_max_volume': amount('150', 150, 1),
    'base_min_volume': amount('10', 10, 1),
    'rel_max_volume': amount('0.0015', 3, 2000),
    'rel_min_volume': amount('0.0001', 1, 10000),
    'conf_settings': {
      'base_confs': 2,
      'base_nota': true,
      'rel_confs': 1,
      'rel_nota': false,
    },
  };

  final kdfAnswer = {
    'mmrpc': '2.0',
    'result': {
      'orders': {
        'BTC': [btcOrder('BTC')],
        'BTC-segwit': [btcOrder('BTC-segwit')],
        'ARRR': [
          {
            'coin': 'ARRR',
            'address': {'address_type': 'Shielded'},
            'price': amount('1.25', 5, 4),
            'pubkey': makerPubkey,
            'uuid': '0d6f4c8a-3b1e-4f7a-8c2d-5e9a1b7c3f42',
            'is_mine': false,
            'base_max_volume': amount('80', 80, 1),
            'base_min_volume': amount('8', 8, 1),
            'rel_max_volume': amount('100', 100, 1),
            'rel_min_volume': amount('10', 10, 1),
            'conf_settings': null,
          },
        ],
      },
      'original_tickers': {
        'BTC': ['BTC-segwit'],
        'LTC': ['LTC-segwit'],
      },
    },
    'id': null,
  };

  final request = BestOrdersRequest(
    rpcPass: 'pass',
    coin: 'KMD',
    action: OrderType.buy,
    requestBy: RequestBy.volume('100'),
  );

  test('reads the orders under the coin each one trades against', () {
    final response = request.parseResponseJson(kdfAnswer);

    expect(response.mmrpc, '2.0');
    expect(
      response.orders.keys,
      unorderedEquals(['BTC', 'BTC-segwit', 'ARRR']),
    );
    expect(response.originalTickers, {
      'BTC': ['BTC-segwit'],
      'LTC': ['LTC-segwit'],
    });

    final btc = response.orders['BTC']!.single;
    expect(btc.coin, 'BTC');
    expect(btc.uuid, 'b4f4ae6c-5e2c-4b3a-9f14-2d8c7a1e9d01');
    expect(btc.address?.addressData, '1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH');
    expect(btc.price?.decimal, '0.00001');
    expect(btc.baseMaxVolume?.decimal, '150');
    expect(btc.relMinVolume?.fraction?.denom, '10000');
    expect(btc.confSettings?.baseConfs, 2);

    final arrr = response.orders['ARRR']!.single;
    expect(arrr.address?.addressType, OrderAddressType.shielded);
    expect(arrr.address?.addressData, isNull);
    expect(arrr.confSettings, isNull);
  });

  test('round-trips through toJson', () {
    final json = request.parseResponseJson(kdfAnswer).toJson();
    final result = json['result'] as Map<String, dynamic>;
    final orders = result['orders'] as Map<String, dynamic>;

    expect(json['mmrpc'], '2.0');
    expect(orders.keys, unorderedEquals(['BTC', 'BTC-segwit', 'ARRR']));
    expect(orders['BTC'], [btcOrder('BTC')]);
    expect(result['original_tickers'], {
      'BTC': ['BTC-segwit'],
      'LTC': ['LTC-segwit'],
    });
    expect(BestOrdersResponse.parse(json).toJson(), json);
  });

  test('reads an answer with no orders', () {
    final response = request.parseResponseJson({
      'mmrpc': '2.0',
      'result': {
        'orders': <String, dynamic>{},
        'original_tickers': {
          'BTC': ['BTC-segwit'],
        },
      },
      'id': null,
    });

    expect(response.orders, isEmpty);
    expect(response.originalTickers.keys, ['BTC']);
  });

  test('throws when no relay answers', () {
    expect(
      () => request.parseResponseJson({
        'mmrpc': '2.0',
        'error': 'No response from any peer',
        'error_path': 'best_orders',
        'error_trace': 'best_orders:398]',
        'error_type': 'P2PError',
        'error_data': 'No response from any peer',
        'id': null,
      }),
      throwsA(isA<Exception>()),
    );
  });
}
