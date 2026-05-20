import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  group('SDK capability expansion RPC models', () {
    test('max_maker_vol uses v2 params and parses numeric values', () {
      final request = MaxMakerVolumeRequest(rpcPass: 'pass', coin: 'KMD');

      expect(request.toJson(), {
        'method': 'max_maker_vol',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'params': {'coin': 'KMD'},
      });

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'coin': 'KMD',
          'volume': {'decimal': '12.5'},
          'balance': {'decimal': '15'},
        },
      });

      expect(response.coin, 'KMD');
      expect(response.volume.decimal, '12.5');
      expect(response.balance.decimal, '15');
    });

    test('order_status keeps legacy uuid envelope and raw order payload', () {
      final request = OrderStatusRequest(rpcPass: 'pass', uuid: 'order-uuid');

      expect(request.toJson(), {
        'method': 'order_status',
        'rpc_pass': 'pass',
        'uuid': 'order-uuid',
      });

      final response = request.parse({
        'type': 'Maker',
        'order': {'base': 'KMD', 'rel': 'BTC'},
        'cancellation_reason': 'UserCancelled',
      });

      expect(response.type, 'Maker');
      expect(response.order, {'base': 'KMD', 'rel': 'BTC'});
      expect(response.cancellationReason, 'UserCancelled');
    });

    test('recover_funds_of_swap uses v2 params and parses tx details', () {
      final request = RecoverFundsOfSwapRequest(
        rpcPass: 'pass',
        uuid: 'swap-uuid',
      );

      expect(request.toJson(), {
        'method': 'recover_funds_of_swap',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'params': {'uuid': 'swap-uuid'},
      });

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'action': 'RefundedMyPayment',
          'coin': 'KMD',
          'tx_hash': '0xhash',
          'tx_hex': '0xhex',
        },
      });

      expect(response.result.action, 'RefundedMyPayment');
      expect(response.result.coin, 'KMD');
      expect(response.result.txHash, '0xhash');
      expect(response.result.txHex, '0xhex');
    });

    test('import_swaps keeps legacy top-level swaps array', () {
      final request = ImportSwapsRequest(
        rpcPass: 'pass',
        swaps: [
          {'uuid': 'swap-uuid'},
        ],
      );

      expect(request.toJson(), {
        'method': 'import_swaps',
        'rpc_pass': 'pass',
        'swaps': [
          {'uuid': 'swap-uuid'},
        ],
      });

      final response = request.parse({
        'result': {
          'imported': ['swap-uuid'],
          'skipped': {'old-uuid': 'already exists'},
        },
      });

      expect(response.result.imported, ['swap-uuid']);
      expect(response.result.skipped, {'old-uuid': 'already exists'});
    });

    test('simple market maker bot start and stop serialize legacy cfg', () {
      const pair = MarketMakerBotTradePairConfig(
        name: 'KMD/BTC',
        base: 'KMD',
        rel: 'BTC',
        spread: '1.04',
        minVolume: MarketMakerBotTradeVolume.percentage(25),
        maxVolume: MarketMakerBotTradeVolume.usd(100),
        baseConfs: 1,
        baseNota: false,
      );
      final start = MarketMakerBotRequest(
        rpcPass: 'pass',
        id: 0,
        methodType: MarketMakerBotMethod.start,
        botParameters: const MarketMakerBotParameters(
          priceUrl: 'https://prices.example',
          botRefreshRate: 60,
          tradeCoinPairs: {'KMD/BTC': pair},
        ),
      );

      expect(start.toJson(), {
        'method': 'start_simple_market_maker_bot',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'id': 0,
        'params': {
          'price_url': 'https://prices.example',
          'bot_refresh_rate': 60,
          'cfg': {
            'KMD/BTC': {
              'name': 'KMD/BTC',
              'base': 'KMD',
              'rel': 'BTC',
              'spread': '1.04',
              'min_volume': {'percentage': '25.0'},
              'max_volume': {'usd': '100.0'},
              'base_confs': 1,
              'base_nota': false,
              'enable': true,
            },
          },
        },
      });

      final stop = MarketMakerBotRequest(
        rpcPass: 'pass',
        id: 0,
        methodType: MarketMakerBotMethod.stop,
      );

      expect(stop.toJson(), {
        'method': 'stop_simple_market_maker_bot',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'id': 0,
        'params': <String, dynamic>{},
      });
    });

    test('NFT list defaults preserve spam and phishing filters', () {
      final request = GetNftListRequest(rpcPass: 'pass', chains: ['ETH']);

      expect(request.toJson(), {
        'method': 'get_nft_list',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'params': {
          'chains': ['ETH'],
          'max': true,
          'protect_from_spam': true,
          'filters': {'exclude_spam': true, 'exclude_phishing': true},
        },
      });

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'nfts': [
            {
              'chain': 'ETH',
              'token_address': '0xcontract',
              'token_id': '1',
              'amount': '1',
              'owner_of': '0xowner',
              'contract_type': 'ERC721',
              'possible_spam': false,
              'possible_phishing': false,
            },
          ],
        },
      });

      expect(response.nfts.single.chain, 'ETH');
      expect(response.nfts.single.tokenAddress, '0xcontract');
      expect(response.nfts.single.possibleSpam, isFalse);
    });

    test('NFT metadata requests always serialize indexer URLs', () {
      final updateRequest = UpdateNftRequest(
        rpcPass: 'pass',
        chains: ['ETH'],
        url: 'https://nft.example',
        urlAntispam: 'https://spam.example',
      );
      final refreshRequest = RefreshNftMetadataRequest(
        rpcPass: 'pass',
        chain: 'ETH',
        tokenAddress: '0xcontract',
        tokenId: '1',
        url: 'https://nft.example',
        urlAntispam: 'https://spam.example',
      );

      expect(updateRequest.toJson()['params'], {
        'chains': ['ETH'],
        'url': 'https://nft.example',
        'url_antispam': 'https://spam.example',
      });
      expect(refreshRequest.toJson()['params'], {
        'chain': 'ETH',
        'token_address': '0xcontract',
        'token_id': '1',
        'url': 'https://nft.example',
        'url_antispam': 'https://spam.example',
      });
    });

    test('withdraw_nft serializes data and parses transaction details', () {
      final request = WithdrawNftRequest(
        rpcPass: 'pass',
        type: NftWithdrawType.erc721,
        withdrawData: const WithdrawNftData(
          chain: 'ETH',
          to: '0xto',
          tokenAddress: '0xcontract',
          tokenId: '1',
        ),
      );

      expect(request.toJson(), {
        'method': 'withdraw_nft',
        'mmrpc': '2.0',
        'rpc_pass': 'pass',
        'params': {
          'type': 'withdraw_erc721',
          'withdraw_data': {
            'chain': 'ETH',
            'to': '0xto',
            'token_address': '0xcontract',
            'token_id': '1',
          },
        },
      });

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'tx_hex': '0xhex',
          'tx_hash': '0xhash',
          'from': ['0xfrom'],
          'to': ['0xto'],
          'contract_type': 'ERC721',
          'token_address': '0xcontract',
          'token_id': ['1'],
          'amount': ['1'],
          'fee_details': {'type': 'EthGas', 'coin': 'ETH'},
          'coin': 'ETH',
          'block_height': 0,
          'timestamp': 123,
          'internal_id': 7,
          'transaction_type': 'NftTransfer',
        },
      });

      expect(response.result.txHash, '0xhash');
      expect(response.result.tokenId, '1');
      expect(response.result.amount, '1');
      expect(response.result.feeDetails.coin, 'ETH');
    });

    test('NFT transfers parse optional enrichment fields', () {
      final request = GetNftTransfersRequest(rpcPass: 'pass', chains: ['ETH']);

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'transfer_history': [
            {
              'chain': 'ETH',
              'block_number': 100,
              'block_timestamp': 123,
              'transaction_hash': '0xhash',
              'contract_type': 'ERC721',
              'token_address': '0xcontract',
              'token_id': '1',
              'from_address': '0xfrom',
              'to_address': '0xto',
              'amount': '1',
              'verified': 1,
              'possible_spam': false,
              'confirmations': 12,
              'fee_details': {'type': 'EthGas', 'coin': 'ETH'},
            },
          ],
        },
      });

      expect(response.transfers.single.verified, 1);
      expect(response.transfers.single.confirmations, 12);
      expect(response.transfers.single.feeDetails?.coin, 'ETH');
    });

    test('NFT transfers tolerate missing verified field', () {
      final request = GetNftTransfersRequest(rpcPass: 'pass', chains: ['ETH']);

      final response = request.parse({
        'mmrpc': '2.0',
        'result': {
          'transfer_history': [
            {
              'chain': 'ETH',
              'block_number': 100,
              'block_timestamp': 123,
              'transaction_hash': '0xhash',
              'contract_type': 'ERC721',
              'token_address': '0xcontract',
              'token_id': '1',
              'from_address': '0xfrom',
              'to_address': '0xto',
              'amount': '1',
              'possible_spam': false,
            },
          ],
        },
      });

      expect(response.transfers.single.verified, isNull);
    });

    test('kmd_rewards_info parses accrued and not-accrued reward entries', () {
      final request = KmdRewardsInfoRequest(rpcPass: 'pass');

      final response = request.parse({
        'result': [
          {
            'tx_hash': 'rewarded',
            'amount': '10',
            'accrued_rewards': {'Accrued': '0.01'},
          },
          {
            'tx_hash': 'too-small',
            'amount': '1',
            'accrued_rewards': {'NotAccruedReason': 'Amount too small'},
          },
        ],
      });

      expect(response.rewards.first.accruedReward, '0.01');
      expect(response.rewards.last.notAccruedReason, 'Amount too small');
    });

    test('diagnostic and lifecycle requests preserve legacy envelopes', () {
      expect(DisableCoinRequest(rpcPass: 'pass', coin: 'KMD').toJson(), {
        'method': 'disable_coin',
        'rpc_pass': 'pass',
        'coin': 'KMD',
      });

      final peers = GetDirectlyConnectedPeersRequest(rpcPass: 'pass').parse({
        'result': {
          'peer-id': ['/ip4/127.0.0.1/tcp/7783'],
        },
      });
      expect(peers.peers.single.peerId, 'peer-id');
      expect(peers.peers.single.peerAddresses.single, contains('127.0.0.1'));

      final version = KdfVersionRequest(
        rpcPass: 'pass',
      ).parse({'result': '2.3.4'});
      expect(version.version, '2.3.4');
    });
  });
}
