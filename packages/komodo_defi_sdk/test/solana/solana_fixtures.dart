import 'package:komodo_defi_types/komodo_defi_types.dart';

Asset solanaAsset() => Asset.fromJson(const {
  'coin': 'SOL-DEV',
  'type': 'SOLANA',
  'fname': 'Solana Devnet',
  'is_testnet': true,
  'decimals': 9,
  'protocol': {'type': 'SOLANA'},
  'nodes': [
    {'url': 'https://api.devnet.solana.com'},
  ],
});

Asset solanaToken(Asset parent, {bool token2022 = false}) => Asset.fromJson(
  {
    'coin': token2022 ? 'TOKEN2022-SOL-DEV' : 'USDC-SOL-DEV',
    'type': 'SOLANATOKEN',
    'fname': 'Solana Token',
    'parent_coin': parent.id.id,
    'is_testnet': true,
    'decimals': 6,
    'protocol': {
      'type': 'SOLANATOKEN',
      'protocol_data': {
        'platform': parent.id.id,
        'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        'program_id': token2022
            ? SolanaTokenProtocol.token2022ProgramId
            : SolanaTokenProtocol.classicTokenProgramId,
        'decimals': 6,
      },
    },
  },
  knownIds: {parent.id},
);

Map<String, dynamic> solanaHistoryRow({String coin = 'USDC-SOL-DEV'}) => {
  'coin': coin,
  'tx_hash': 'AbCdeF123Base58Signature',
  'internal_id': 'AbCdeF123Base58Signature',
  'block_height': 42,
  'timestamp': 1730000000,
  'confirmations': 1,
  'from': ['SenderBase58'],
  'to': ['RecipientBase58'],
  'my_balance_change': '-1.234567',
  'spent_by_me': '1.234567',
  'received_by_me': '0',
  'total_amount': '1.234567',
  'fee_details': {
    'type': 'Solana',
    'fee_amount': '0.000005',
    'rent_amount': '0.00203928',
    'total_amount': '0.00204428',
  },
};
