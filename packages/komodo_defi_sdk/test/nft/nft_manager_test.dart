import 'dart:collection';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _QueueApiClient implements ApiClient {
  _QueueApiClient({required Map<String, List<JsonMap>> responsesByMethod})
    : _responsesByMethod = {
        for (final entry in responsesByMethod.entries)
          entry.key: Queue<JsonMap>.from(entry.value),
      };

  final Map<String, Queue<JsonMap>> _responsesByMethod;
  final requests = <JsonMap>[];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);

    final method = request.value<String>('method');
    final queue = _responsesByMethod[method];
    if (queue == null || queue.isEmpty) {
      throw StateError('No queued response for method $method');
    }

    return queue.removeFirst();
  }
}

class _EnrichingDetailsProvider implements NftTransactionDetailsProvider {
  int calls = 0;

  @override
  Future<List<NftTransfer>> enrichTransfers(List<NftTransfer> transfers) async {
    calls++;
    return transfers
        .map(
          (transfer) => transfer.copyWith(
            confirmations: 99,
            feeDetails: const NftFeeDetails(type: 'EthGas', coin: 'ETH'),
          ),
        )
        .toList();
  }
}

void main() {
  group('NftManager', () {
    test(
      'optionally enriches transfer history via app-provided provider',
      () async {
        final client = _QueueApiClient(
          responsesByMethod: {
            'get_nft_transfers': [
              {
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
                      'verified': true,
                      'possible_spam': false,
                    },
                  ],
                },
              },
            ],
          },
        );
        final provider = _EnrichingDetailsProvider();
        final manager = NftManager(
          client: client,
          transactionDetailsProvider: provider,
        );

        final transfers = await manager.getNftTransfers(
          chains: ['ETH'],
          withAdditionalDetails: true,
        );

        expect(client.requests.single['method'], 'get_nft_transfers');
        expect(provider.calls, 1);
        expect(transfers.single.transactionHash, '0xhash');
        expect(transfers.single.confirmations, 99);
        expect(transfers.single.feeDetails?.coin, 'ETH');
      },
    );
  });
}
