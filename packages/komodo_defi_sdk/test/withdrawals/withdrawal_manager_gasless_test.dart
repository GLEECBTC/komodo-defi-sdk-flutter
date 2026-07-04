import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAssetProvider extends Mock implements IAssetProvider {}

class _MockFeeManager extends Mock implements FeeManager {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockLegacyWithdrawalManager extends Mock
    implements LegacyWithdrawalManager {}

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

WithdrawalPreview _gaslessPreview() {
  return WithdrawResult(
    txJson: const {
      'relay_type': 'tron_gasfree',
      'chain_id': '728126428',
      'coin': 'USDT-TRC20',
      'from_address': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'verifying_contract': 'THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc',
      'signed_authorization': <String, dynamic>{'sig': '1c8f'},
      'created_at': '2026-04-23T20:47:34Z',
    },
    txHash: '',
    from: const ['TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC'],
    to: const ['TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC'],
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-5'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('5'),
      totalAmount: Decimal.parse('5'),
    ),
    blockHeight: 0,
    timestamp: 0,
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      transferFee: Decimal.parse('2'),
      totalTokenFee: Decimal.parse('2'),
      signedMaxFee: Decimal.parse('5'),
    ),
    coin: 'USDT-TRC20',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('WithdrawalManager gasless flow', () {
    late _MockApiClient client;
    late _MockAssetProvider assetProvider;
    late _MockFeeManager feeManager;
    late _MockActivationCoordinator activationCoordinator;
    late _MockLegacyWithdrawalManager legacyManager;
    late WithdrawalManager manager;
    late Asset trc20Asset;

    setUp(() {
      client = _MockApiClient();
      assetProvider = _MockAssetProvider();
      feeManager = _MockFeeManager();
      activationCoordinator = _MockActivationCoordinator();
      legacyManager = _MockLegacyWithdrawalManager();
      manager = WithdrawalManager(
        client,
        assetProvider,
        feeManager,
        activationCoordinator,
        legacyManager,
      );
      final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
      trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});

      when(
        () => assetProvider.findAssetsByConfigId('USDT-TRC20'),
      ).thenReturn({trc20Asset});
      registerFallbackValue(trc20Asset);
      when(
        () => activationCoordinator.activateAsset(any()),
      ).thenAnswer((_) async => ActivationResult.success(trc20Asset.id));
    });

    test('relays and completes with the on-chain hash and final fee', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        switch (request['method']) {
          case 'send_raw_transaction':
            return {
              'relay_type': 'tron_gasfree',
              'trace_id': 'trace-xyz',
              'state': 'WAITING',
            };
          case 'gasless::trace_status':
            return {
              'mmrpc': '2.0',
              'result': {
                'state': 'confirmed',
                'tx_hash_on_chain': 'onchainhash',
                'block_height': 100,
                'confirmed_at': 123,
                'final_fee': '1.5',
              },
            };
          default:
            throw StateError('Unexpected method: ${request['method']}');
        }
      });

      final progress = await manager
          .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(progress.last.status, WithdrawalStatus.complete);
      expect(progress.last.withdrawalResult?.txHash, 'onchainhash');

      final fee = progress.last.withdrawalResult?.fee;
      expect(fee, isA<FeeInfoTronGasless>());
      final gaslessFee = fee! as FeeInfoTronGasless;
      expect(gaslessFee.totalTokenFee, Decimal.parse('1.5'));
      expect(gaslessFee.traceId, 'trace-xyz');
    });

    test('preview maps the nested GasFree shortfall task error to a structured '
        'SdkError', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        switch (request['method']) {
          case 'task::withdraw::init':
            return {
              'mmrpc': '2.0',
              'result': {'task_id': 7},
            };
          case 'task::withdraw::status':
            // The canonical KDF wire shape: WithdrawError::Gasless(...)
            // adjacently tagged on both levels, no gasfree_address, and
            // the details object is JSON-stringified by the response
            // parser before _typedTaskError re-parses it.
            return {
              'mmrpc': '2.0',
              'result': {
                'status': 'Error',
                'details': {
                  'error':
                      'Not enough USDT-TRC20 in your GasFree deposit '
                      'address: available 0, required 8. Deposit '
                      'USDT-TRC20 into your GasFree address.',
                  'error_path': 'eth_withdraw.withdraw',
                  'error_trace': 'eth_withdraw:348]',
                  'error_type': 'Gasless',
                  'error_data': {
                    'error_type': 'InsufficientGasFreeBalance',
                    'error_data': {
                      'coin': 'USDT-TRC20',
                      'available': '0',
                      'required': '8',
                    },
                  },
                },
              },
            };
          default:
            throw StateError('Unexpected method: ${request['method']}');
        }
      });

      await expectLater(
        manager.previewWithdrawal(
          WithdrawParameters(
            asset: 'USDT-TRC20',
            toAddress: 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
            amount: Decimal.parse('5'),
            fee: FeeInfo.utxoFixed(coin: 'USDT-TRC20', amount: Decimal.one),
          ),
        ),
        throwsA(
          isA<SdkError>()
              .having(
                (e) => e.messageKey,
                'messageKey',
                'withdrawGaslessInsufficientGasFreeBalance',
              )
              .having((e) => e.code, 'code', SdkErrorCode.insufficientFunds)
              .having((e) => e.messageArgs, 'messageArgs', [
                '',
                '0',
                'USDT-TRC20',
                '8',
                'USDT-TRC20',
                'USDT-TRC20',
              ]),
        ),
      );
    });

    test('surfaces a failed gasless transfer as a stream error', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        switch (request['method']) {
          case 'send_raw_transaction':
            return {
              'relay_type': 'tron_gasfree',
              'trace_id': 'trace-xyz',
              'state': 'WAITING',
            };
          case 'gasless::trace_status':
            return {
              'mmrpc': '2.0',
              'result': {'state': 'failed', 'failure_reason': 'rejected'},
            };
          default:
            throw StateError('Unexpected method: ${request['method']}');
        }
      });

      await expectLater(
        manager.executeWithdrawal(_gaslessPreview(), 'USDT-TRC20').toList(),
        throwsA(isA<SdkError>()),
      );
    });
  });
}
