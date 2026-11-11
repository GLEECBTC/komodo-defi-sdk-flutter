import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

Map<String, dynamic> platformConfig() => {
  'coin': 'TESTSOL',
  'type': 'SOLANA',
  'fname': 'Solana Devnet',
  'is_testnet': true,
  'wallet_only': true,
  'decimals': 9,
  'derivation_path': "m/44'/501'",
  'protocol': {'type': 'SOLANA', 'protocol_data': <String, dynamic>{}},
  'nodes': [
    {'url': 'https://api.devnet.solana.com'},
  ],
};

Map<String, dynamic> tokenConfig({String? programId}) => {
  'coin': 'TESTUSDC-TESTSOL',
  'type': 'SOLANATOKEN',
  'fname': 'USDC Devnet',
  'parent_coin': 'TESTSOL',
  'is_testnet': true,
  'wallet_only': true,
  'protocol': {
    'type': 'SOLANATOKEN',
    'protocol_data': {
      'platform': 'TESTSOL',
      'decimals': 6,
      'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      'program_id': programId ?? SolanaTokenProtocol.classicTokenProgramId,
    },
  },
};

void main() {
  test(
    'asset metadata retains platform and decimal precision in cached history',
    () {
      final sol = Asset.fromJson(platformConfig());
      final token = Asset.fromJson(tokenConfig(), knownIds: {sol.id});
      expect(sol.id.symbol.configSymbol, 'TESTSOL');
      expect(token.id.symbol.configSymbol, 'TESTUSDC');
      expect(sol.protocol.isTestnet, isTrue);
      expect(token.protocol.isTestnet, isTrue);
      expect(sol.supportsMessageSigning, isTrue);
      expect(token.supportsMessageSigning, isTrue);
      expect(sol.id.chainId.decimals, 9);
      expect(token.id.chainId.decimals, 6);
      expect(token.id.parentId, sol.id);
      final info = TransactionInfo.fromJson({
        'coin': token.id.id,
        'tx_hash': 'SigCaseBase58ABCabc',
        'internal_id': 'internal',
        'from': <String>[],
        'to': ['ATAabcDEF'],
        'my_balance_change': '0.000001',
        'received_by_me': '0.000001',
        'spent_by_me': '0',
        'block_height': 42,
        'confirmations': 1,
        'timestamp': 100,
        'fee_details': {
          'type': 'Solana',
          'fee_amount': '0.000005',
          'rent_amount': '0.00203928',
          'total_amount': '0.00204428',
        },
      });
      final transaction = info.asTransaction(token.id);
      expect(transaction.fee!.coin, sol.id.id);
      expect(transaction.memo, isNull);
      expect(transaction.txHash, 'SigCaseBase58ABCabc');
      final cached = Transaction.fromJson(transaction.toJson());
      expect(cached, transaction);
      expect(cached.assetId.parentId, sol.id);
      expect(cached.assetId.chainId.decimals, 6);
      expect(cached.fee!.coin, 'TESTSOL');
      expect(cached.toJson().containsKey('memo'), isFalse);
    },
  );

  test('native and token protocols retain distinct identities and parent', () {
    expect(CoinSubClass.parse('SOLANA'), CoinSubClass.solana);
    expect(CoinSubClass.parse('SOLANATOKEN'), CoinSubClass.solanaToken);
    expect(
      CoinSubClass.parse(CoinSubClass.solanaToken.formatted),
      CoinSubClass.solanaToken,
    );
    expect(CoinSubClass.solana.canBeParentOf(CoinSubClass.solanaToken), isTrue);
    expect(
      CoinSubClass.solanaToken.canBeParentOf(CoinSubClass.solana),
      isFalse,
    );
    expect(
      CoinSubClass.solanaToken.canBeParentOf(CoinSubClass.solanaToken),
      isFalse,
    );
    final sol = ProtocolClass.fromJson(platformConfig()) as SolanaProtocol;
    final token = ProtocolClass.fromJson(tokenConfig()) as SolanaTokenProtocol;
    expect(sol.decimals, 9);
    expect(sol.requiredConfirmations, 1);
    expect(token.platform, 'TESTSOL');
    expect(token.decimals, 6);
    expect(
      token.contractAddress,
      '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
    );
    expect(token.isToken2022, isFalse);
    expect(ProtocolClass.fromJson(token.toJson()).toJson(), token.toJson());
    expect(ProtocolClass.fromJson(sol.toJson()).toJson(), sol.toJson());
  });

  test('global HD mode does not imply Solana multi-address parameters', () {
    final sol = SolanaProtocol.fromJson(platformConfig());
    final token = SolanaTokenProtocol.fromJson(tokenConfig());
    for (final protocol in [sol, token]) {
      expect(protocol.supportsMultipleAddresses, isFalse);
      expect(protocol.requiresHdWallet, isFalse);
      expect(protocol.isMemoSupported, isTrue);
      expect(
        () => protocol.defaultActivationParams(
          privKeyPolicy: const PrivateKeyPolicy.trezor(),
        ),
        throwsUnsupportedError,
      );
    }
    expect(sol.defaultActivationParams(gapLimit: 10).toRpcParams(), {
      'nodes': [
        {'url': 'https://api.devnet.solana.com'},
      ],
      'tokens_params': <dynamic>[],
      'tx_history': true,
    });
    expect(token.defaultActivationParams(gapLimit: 10).toRpcParams(), isEmpty);
    expect(sol.supportsBalanceStreaming(isChildAsset: false), isTrue);
    expect(token.supportsBalanceStreaming(isChildAsset: true), isFalse);
    expect(token.supportsTxHistoryStreaming(isChildAsset: true), isFalse);
  });

  test('Token-2022 identity uses program ID without changing mint case', () {
    final token = SolanaTokenProtocol.fromJson(
      tokenConfig(programId: SolanaTokenProtocol.token2022ProgramId),
    );
    expect(token.isToken2022, isTrue);
    expect(token.mintAddress, '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU');
    expect(const SolanaCapabilities().enabled, isFalse);
    expect(const SolanaCapabilities().token2022Enabled, isFalse);
  });

  test('inconsistent token parent and malformed decimals are rejected', () {
    expect(
      () => SolanaTokenProtocol.fromJson({
        ...tokenConfig(),
        'parent_coin': 'SOL',
      }),
      throwsFormatException,
    );
    final bad = tokenConfig();
    final protocol = bad['protocol'] as Map<String, dynamic>;
    (protocol['protocol_data'] as Map<String, dynamic>)['decimals'] = -1;
    expect(() => SolanaTokenProtocol.fromJson(bad), throwsFormatException);
  });

  group('Solana fee responses', () {
    const wire = {
      'type': 'Solana',
      'fee_amount': '0.000005022',
      'rent_amount': '0.00148844',
      'total_amount': '0.001493462',
    };
    test('resolves devnet currency and retains exact wire shape', () {
      final fee = FeeInfo.fromJson(wire, feeCoin: 'TESTSOL') as SolanaFeeInfo;
      expect(fee.coin, 'TESTSOL');
      expect(fee.totalFee, Decimal.parse('0.001493462'));
      expect(fee.rentAmount, Decimal.parse('0.00148844'));
      expect(fee.toJson(), wire);
      expect(FeeInfo.fromJson(wire).coin, isEmpty);
    });
    test('reject negative, inconsistent and non-string amounts', () {
      expect(
        () => FeeInfo.fromJson({...wire, 'rent_amount': '-1'}),
        throwsFormatException,
      );
      expect(
        () => FeeInfo.fromJson({...wire, 'total_amount': '1'}),
        throwsFormatException,
      );
      expect(
        () => FeeInfo.fromJson({...wire, 'fee_amount': 0.000005022}),
        throwsFormatException,
      );
    });
  });
}
