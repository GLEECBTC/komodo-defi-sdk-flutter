import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/_activation.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart'
    show ActivationConfigService;
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

const _ethSwapContract = '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1';

// Slimmed coins_config.json entries.
JsonMap _ethConfig() => {
  'coin': 'ETH',
  'type': 'ERC-20',
  'name': 'Ethereum',
  'fname': 'Ethereum',
  'mm2': 1,
  'chain_id': 1,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 1},
  },
  'derivation_path': "m/44'/60'",
  'swap_contract_address': _ethSwapContract,
  'fallback_swap_contract': _ethSwapContract,
  'nodes': [
    {'url': 'https://eth.example'},
  ],
};

JsonMap _erc20Config(String coin, String contract) => {
  ..._ethConfig(),
  'coin': coin,
  'name': coin,
  'fname': coin,
  'decimals': 6,
  'protocol': {
    'type': 'ERC20',
    'protocol_data': {'platform': 'ETH', 'contract_address': contract},
  },
  'contract_address': contract,
  'parent_coin': 'ETH',
};

JsonMap _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <JsonMap>[],
};

JsonMap _trc20Config(String coin, String contract) => {
  ..._trxConfig(),
  'coin': coin,
  'type': 'TRC-20',
  'name': coin,
  'fname': coin,
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': contract},
  },
  'contract_address': contract,
  'parent_coin': 'TRX',
};

JsonMap _irisConfig() => {
  'coin': 'IRIS',
  'type': 'TENDERMINT',
  'name': 'IRISnet',
  'fname': 'IRISnet',
  'mm2': 1,
  'protocol': {
    'type': 'TENDERMINT',
    'protocol_data': {
      'decimals': 6,
      'denom': 'uiris',
      'account_prefix': 'iaa',
      'chain_id': 'irishub-1',
    },
  },
  'derivation_path': "m/44'/118'",
  'rpc_urls': [
    {'url': 'https://rpc.irishub-1.irisnet.org'},
  ],
};

JsonMap _atomIbcIrisConfig() => {
  ..._irisConfig(),
  'coin': 'ATOM-IBC_IRIS',
  'type': 'TENDERMINTTOKEN',
  'name': 'Cosmos',
  'fname': 'Cosmos',
  'protocol': {
    'type': 'TENDERMINTTOKEN',
    'protocol_data': {
      'platform': 'IRIS',
      'decimals': 6,
      'denom':
          'ibc/27394FB092D2ECCD56123C74F36E4C1F926001CEADA9CA97EA622B25F41E5EB2',
    },
  },
  'parent_coin': 'IRIS',
};

JsonMap _kmdConfig() => {
  'coin': 'KMD',
  'type': 'Smart Chain',
  'name': 'Komodo',
  'fname': 'Komodo',
  'mm2': 1,
  'is_testnet': false,
  'protocol': {'type': 'UTXO'},
  'derivation_path': "m/44'/141'",
  'electrum': [
    {'url': 'kmd.electrum1.cipig.net:10001', 'protocol': 'TCP'},
  ],
};

JsonMap _qtumConfig() => {
  'coin': 'QTUM',
  'type': 'QRC-20',
  'name': 'Qtum',
  'fname': 'Qtum',
  'mm2': 1,
  'pubtype': 58,
  'p2shtype': 50,
  'wiftype': 128,
  'txfee': 400000,
  'protocol': {'type': 'QTUM'},
  'derivation_path': "m/44'/2301'",
  'electrum': [
    {'url': 'qtum.electrum1.cipig.net:10050', 'protocol': 'TCP'},
  ],
};

JsonMap _siaConfig() => {
  'coin': 'SC',
  'type': 'SIA',
  'name': 'Siacoin',
  'fname': 'Siacoin',
  'mm2': 1,
  'chain_id': 2024,
  'decimals': 24,
  'nodes': [
    {'url': 'https://api.siascan.com/wallet/api'},
  ],
};

Asset _arrr() => Asset(
  id: AssetId(
    id: 'ARRR',
    name: 'Pirate Chain',
    symbol: AssetSymbol(assetConfigId: 'ARRR'),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.zhtlc,
  ),
  protocol: ZhtlcProtocol.fromJson(const {
    'type': 'ZHTLC',
    'light_wallet_d_servers': ['https://lightd.example'],
    'electrum_servers': [
      {'url': 'electrum.example:50002', 'protocol': 'SSL'},
    ],
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

class _RecordingApiClient implements ApiClient {
  final List<JsonMap> requests = [];

  List<String> get methods => [
    for (final request in requests) request['method'] as String,
  ];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);
    return switch (request['method']) {
      'enable_tendermint_token' => {
        'mmrpc': '2.0',
        'result': {'balances': <String, dynamic>{}, 'platform_coin': 'IRIS'},
      },
      final method => throw StateError('Unexpected RPC $method'),
    };
  }
}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

void main() {
  const contextPrivKey = PrivateKeyPolicy.contextPrivKey();
  const trezor = PrivateKeyPolicy.trezor();

  final eth = Asset.fromJson(_ethConfig(), knownIds: const {});
  final trx = Asset.fromJson(_trxConfig(), knownIds: const {});
  final iris = Asset.fromJson(_irisConfig(), knownIds: const {});
  final atomIbcIris = Asset.fromJson(_atomIbcIrisConfig(), knownIds: {iris.id});
  final customErc20Config = {
    ..._erc20Config('PEPE-ERC20', '0x6982508145454Ce325dDbE47a25d4ec3d2311933'),
    'is_custom_token': true,
  };

  // Asset, then the strategy that activates it for a ContextPrivKey wallet
  // and for a Trezor wallet.
  final routes = <(Asset, Type, Type)>[
    (eth, EthWithTokensActivationStrategy, EthTaskActivationStrategy),
    (
      Asset.fromJson(
        _erc20Config(
          'USDT-ERC20',
          '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        ),
        knownIds: {eth.id},
      ),
      Erc20ActivationStrategy,
      Erc20ActivationStrategy,
    ),
    (
      Asset.fromJson(customErc20Config, knownIds: {eth.id}),
      CustomErc20ActivationStrategy,
      CustomErc20ActivationStrategy,
    ),
    // A custom token read back from storage has no parent until the asset
    // manager restores it.
    (
      Asset.fromJson(customErc20Config),
      CustomErc20ActivationStrategy,
      CustomErc20ActivationStrategy,
    ),
    (trx, EthWithTokensActivationStrategy, EthTaskActivationStrategy),
    (
      Asset.fromJson(
        _trc20Config('USDT-TRC20', 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'),
        knownIds: {trx.id},
      ),
      Erc20ActivationStrategy,
      Erc20ActivationStrategy,
    ),
    (
      Asset.fromJson(
        {
          ..._trc20Config('SUN-TRC20', 'TSSMHYeV2uE9qYH95DqyoCuNCzEL1NvU3S'),
          'is_custom_token': true,
        },
        knownIds: {trx.id},
      ),
      CustomErc20ActivationStrategy,
      CustomErc20ActivationStrategy,
    ),
    (
      iris,
      TendermintWithTokensActivationStrategy,
      TendermintTaskActivationStrategy,
    ),
    (
      atomIbcIris,
      TendermintTokenActivationStrategy,
      TendermintTokenActivationStrategy,
    ),
    (
      Asset.fromJson(_kmdConfig(), knownIds: const {}),
      UtxoActivationStrategy,
      UtxoActivationStrategy,
    ),
    (
      Asset.fromJson(_qtumConfig(), knownIds: const {}),
      QtumActivationStrategy,
      QtumActivationStrategy,
    ),
    (
      Asset.fromJson(_siaConfig(), knownIds: const {}),
      SiaActivationStrategy,
      SiaActivationStrategy,
    ),
    (_arrr(), ZhtlcActivationStrategy, ZhtlcActivationStrategy),
  ];

  List<ProtocolActivationStrategy> chainFor(PrivateKeyPolicy policy) =>
      ActivationStrategyFactory.createProtocolStrategies(
        ApiClientMock(),
        policy,
        _MockConfigService(),
      );

  group('Activation strategy chain', () {
    // CompositeAssetActivator takes the first strategy that can handle an
    // asset. With exactly one per asset, reordering the chain cannot change
    // which strategy activates it.
    for (final policy in const [contextPrivKey, trezor]) {
      test('gives each asset to exactly one strategy for a '
          '${policy.pascalCaseName} wallet', () {
        final chain = chainFor(policy);

        for (final (asset, forContextPrivKey, forTrezor) in routes) {
          expect(
            [
              for (final strategy in chain)
                if (strategy.canHandle(asset)) strategy.runtimeType,
            ],
            [if (policy == trezor) forTrezor else forContextPrivKey],
            reason: '${asset.id}',
          );
        }
      });
    }

    test('routes cover every strategy in the chain', () {
      expect(
        {
          for (final (_, forContextPrivKey, forTrezor) in routes) ...{
            forContextPrivKey,
            forTrezor,
          },
        },
        {
          for (final policy in const [contextPrivKey, trezor])
            for (final strategy in chainFor(policy)) strategy.runtimeType,
        },
      );
    });

    test('asserts that no two strategies take the same asset', () {
      final client = ApiClientMock();
      final chain = CompositeAssetActivator(client, [
        EthWithTokensActivationStrategy(client, contextPrivKey),
        EthWithTokensActivationStrategy(client, contextPrivKey),
      ]);

      expect(
        () => chain.supportsBatchActivationFor(eth),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // KDF refuses Trezor for Tendermint platforms today, so this pins only the
  // routing.
  group('Trezor Tendermint token', () {
    test('adds an IBC token to an active platform via '
        'enable_tendermint_token', () async {
      final client = _RecordingApiClient();
      final cache = _MockActivatedAssetsCache();
      when(cache.getActivatedAssetIds).thenAnswer((_) async => {iris.id});

      final progress = await ActivationStrategyFactory.createStrategy(
        client,
        trezor,
        _MockConfigService(),
        cache,
      ).activate(iris, [atomIbcIris]).toList();

      expect(progress.last.isSuccess, isTrue);
      expect(client.methods, ['enable_tendermint_token']);
      final params = client.requests.single.value<JsonMap>('params');
      expect(params['ticker'], 'ATOM-IBC_IRIS');
    });
  });
}
