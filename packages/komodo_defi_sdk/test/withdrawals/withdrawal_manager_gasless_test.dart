import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
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

class _MockTransactionHistoryManager extends Mock
    implements TransactionHistoryManager {}

class _FakePendingGaslessTransfer extends Fake
    implements PendingGaslessTransfer {}

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RejectAcceptedTraceStorage extends _MemoryStorage {
  @override
  Future<void> write(String key, String value) async {
    if (value.contains('trace-storage-failure')) {
      throw StateError('secure storage contention');
    }
    await super.write(key, value);
  }
}

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

const _requestId = '123e4567-e89b-42d3-a456-426614174000';
const _tokenContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _providerAddress = 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E';
const _authorizationSignature =
    '1111111111111111111111111111111111111111111111111111111111111111'
    '111111111111111111111111111111111111111111111111111111111111111111';
const _authorizationFingerprint =
    '0d9b716d06b54e026b6f5050ec9f70cdd2dab72f818af4616e8a2b2182eea5c9';

WithdrawalPreview _gaslessPreview({
  String deadline = '1999999999',
  String requestId = _requestId,
  String chainId = '728126428',
  String authorizationValue = '5000000',
  String authorizationMaxFee = '5000000',
  String authorizationToken = _tokenContract,
  String authorizationProvider = _providerAddress,
  String authorizationSignature = _authorizationSignature,
  String feeSignedMaxFee = '5',
  String feeRequestId = _requestId,
  String feeProviderAddress = _providerAddress,
  String feeAuthorizationFingerprint = _authorizationFingerprint,
  String? feeAuthorizationDeadline,
}) {
  return WithdrawResult(
    txJson: {
      'relay_type': 'tron_gasfree',
      'request_id': requestId,
      'chain_id': chainId,
      'coin': 'USDT-TRC20',
      'from_address': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'verifying_contract': 'THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc',
      'signed_authorization': <String, dynamic>{
        'token': authorizationToken,
        'service_provider': authorizationProvider,
        'user': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
        'receiver': 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
        'value': authorizationValue,
        'max_fee': authorizationMaxFee,
        'deadline': deadline,
        'version': '1',
        'nonce': '9',
        'sig': authorizationSignature,
      },
      'authorization_fingerprint': _authorizationFingerprint,
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
      signedMaxFee: Decimal.parse(feeSignedMaxFee),
      providerAddress: feeProviderAddress,
      authorizationDeadline: int.parse(feeAuthorizationDeadline ?? deadline),
      requestId: feeRequestId,
      authorizationFingerprint: feeAuthorizationFingerprint,
    ),
    coin: 'USDT-TRC20',
  );
}

WithdrawalPreview _legacyGaslessPreview() {
  final bound = _gaslessPreview();
  final txJson = Map<String, dynamic>.from(bound.txJson!)
    ..remove('request_id')
    ..remove('authorization_fingerprint');
  final fee = bound.fee as FeeInfoTronGasless;
  return WithdrawResult(
    txJson: txJson,
    txHash: bound.txHash,
    from: bound.from,
    to: bound.to,
    balanceChanges: bound.balanceChanges,
    blockHeight: bound.blockHeight,
    timestamp: bound.timestamp,
    fee: FeeInfo.tronGasless(
      coin: fee.coin,
      feeMethod: fee.feeMethod,
      providerName: fee.providerName,
      gasfreeAddress: fee.gasfreeAddress,
      transferFee: fee.transferFee,
      totalTokenFee: fee.totalTokenFee,
      activationFee: fee.activationFee,
      signedMaxFee: fee.signedMaxFee,
    ),
    coin: bound.coin,
  );
}

Map<String, dynamic> _expectedAuthorizationJson({
  String requestId = _requestId,
}) => {
  'request_id': requestId,
  'account': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
  'custody_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  'provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
  'receiver': 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
  'token': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'amount': '5000000',
  'max_fee': '5000000',
  'deadline': '1999999999',
  'version': '1',
  'nonce': '9',
  'signature_fingerprint': _authorizationFingerprint,
};

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakePendingGaslessTransfer());
  });

  group('WithdrawalManager gasless flow', () {
    late _MockApiClient client;
    late _MockAssetProvider assetProvider;
    late _MockFeeManager feeManager;
    late _MockActivationCoordinator activationCoordinator;
    late _MockLegacyWithdrawalManager legacyManager;
    late _MockTransactionHistoryManager transactionHistoryManager;
    late WithdrawalManager manager;
    late Asset trc20Asset;
    late SecurePendingGaslessTransferRepository pendingRepository;
    late _MemoryStorage pendingStorage;
    late GaslessCapabilityRegistry gaslessCapabilities;

    const walletId = WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    );

    setUp(() {
      client = _MockApiClient();
      assetProvider = _MockAssetProvider();
      feeManager = _MockFeeManager();
      activationCoordinator = _MockActivationCoordinator();
      legacyManager = _MockLegacyWithdrawalManager();
      transactionHistoryManager = _MockTransactionHistoryManager();
      pendingStorage = _MemoryStorage();
      pendingRepository = SecurePendingGaslessTransferRepository(
        storage: pendingStorage,
      );
      final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
      trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});
      gaslessCapabilities =
          GaslessCapabilityRegistry(
            configuredAssetIds: const {'USDT-TRC20'},
            pinnedProviderAddress: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
          )..markReadyFor(
            trc20Asset,
            GaslessCapabilityIdentity(
              assetId: trc20Asset.id,
              platform: 'TRX',
              contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
              providerAddress: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
              walletPubkeyHash: walletId.pubkeyHash!,
              walletType: GaslessWalletType.softwareIguana,
              derivationPath: '',
            ),
          );
      manager = WithdrawalManager(
        client,
        assetProvider,
        feeManager,
        activationCoordinator,
        legacyManager,
        gaslessCapabilities: gaslessCapabilities,
        pendingGaslessTransfers: pendingRepository,
        transactionHistoryManager: transactionHistoryManager,
        walletIdResolver: () async => walletId,
        gaslessPollInterval: Duration.zero,
      );
      when(
        () => assetProvider.findAssetsByConfigId('USDT-TRC20'),
      ).thenReturn({trc20Asset});
      registerFallbackValue(trc20Asset);
      when(
        () => activationCoordinator.activateAsset(any()),
      ).thenAnswer((_) async => ActivationResult.success(trc20Asset.id));
      when(
        () => transactionHistoryManager.verifyGaslessTransferOnChain(
          any(),
          any(),
          any(),
        ),
      ).thenAnswer((_) async => GaslessOnChainVerification.verified);
    });

    void enableLegacyRecovery() {
      final identity = GaslessCapabilityIdentity(
        assetId: trc20Asset.id,
        platform: 'TRX',
        contractAddress: _tokenContract,
        providerAddress: _providerAddress,
        walletPubkeyHash: walletId.pubkeyHash!,
        walletType: GaslessWalletType.softwareIguana,
        derivationPath: '',
      );
      expect(
        gaslessCapabilities.markProvisionalFor(trc20Asset, identity),
        isTrue,
      );
      expect(
        gaslessCapabilities.proveLegacyReadyFromSignedPreview(
          trc20Asset.id,
          chainId: '728126428',
          tokenContract: _tokenContract,
          providerAddress: _providerAddress,
          walletPubkeyHash: walletId.pubkeyHash!,
        ),
        isTrue,
      );
    }

    test(
      'literal PR #9 preview proves recovery without enabling receive',
      () async {
        final identity = GaslessCapabilityIdentity(
          assetId: trc20Asset.id,
          platform: 'TRX',
          contractAddress: _tokenContract,
          providerAddress: _providerAddress,
          walletPubkeyHash: walletId.pubkeyHash!,
          walletType: GaslessWalletType.softwareIguana,
          derivationPath: '',
        );
        gaslessCapabilities.markProvisionalFor(trc20Asset, identity);
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 7},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {
                'status': 'Ok',
                'details': _legacyGaslessPreview().toJson(),
              },
            },
            _ => throw StateError('Unexpected method: ${request['method']}'),
          };
        });

        final preview = await manager.previewWithdrawal(
          WithdrawParameters(
            asset: 'USDT-TRC20',
            toAddress: 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
            amount: Decimal.parse('5'),
            feeMethod: WithdrawalFeeMethod.gasless,
          ),
        );

        expect(preview.txJson, isNot(contains('request_id')));
        expect(preview.txJson, isNot(contains('authorization_fingerprint')));
        expect(gaslessCapabilities.isReady(trc20Asset.id), isTrue);
        expect(gaslessCapabilities.canReceiveGasless(trc20Asset.id), isFalse);
        expect(await manager.listPendingGaslessTransfers(), isEmpty);
      },
    );

    test('relays and completes with the on-chain hash and final fee', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        switch (request['method']) {
          case 'send_raw_transaction':
            expect(pendingStorage.values, isNotEmpty);
            return {
              'relay_type': 'tron_gasfree',
              'request_id': '123e4567-e89b-42d3-a456-426614174000',
              'trace_id': 'trace-xyz',
              'state': 'WAITING',
              'expected_authorization': _expectedAuthorizationJson(),
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
      expect(gaslessFee.totalTokenFee, Decimal.parse('2'));
      expect(gaslessFee.finalFee, Decimal.parse('1.5'));
      expect(gaslessFee.totalFee, Decimal.parse('1.5'));
      expect(gaslessFee.traceId, 'trace-xyz');
      expect(progress.last.withdrawalResult?.confirmationBlockHeight, 100);
      expect(
        progress.last.withdrawalResult?.confirmedAt,
        DateTime.fromMillisecondsSinceEpoch(123000, isUtc: true),
      );
      expect(
        progress.any(
          (event) =>
              event.taskId == 'trace-xyz' &&
              event.submission?.type == WithdrawalSubmissionType.gaslessRelay,
        ),
        isTrue,
      );
      expect(await manager.listPendingGaslessTransfers(), isEmpty);
    });

    test('confirmation waits for an authoritative final fee', () async {
      var traceCalls = 0;
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        if (request['method'] == 'send_raw_transaction') {
          return {
            'relay_type': 'tron_gasfree',
            'request_id': _requestId,
            'trace_id': 'trace-fee-pending',
            'state': 'WAITING',
            'expected_authorization': _expectedAuthorizationJson(),
          };
        }
        traceCalls++;
        return {
          'mmrpc': '2.0',
          'result': {
            'state': 'confirmed',
            'tx_hash_on_chain': 'onchainhash',
            if (traceCalls > 1) 'final_fee': '1.5',
          },
        };
      });

      final progress = await manager
          .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(traceCalls, 2);
      expect(
        progress.any(
          (event) =>
              event.gaslessTransferState == GaslessTransferState.confirming &&
              event.message.contains('final gas-free fee'),
        ),
        isTrue,
      );
      expect(progress.last.status, WithdrawalStatus.complete);
    });

    test(
      'legacy relay keeps tx_json strict and confirms only after history match',
      () async {
        enableLegacyRecovery();
        Map<String, dynamic>? sentPayload;
        Map<String, dynamic>? traceParams;
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          switch (request['method']) {
            case 'send_raw_transaction':
              sentPayload = Map<String, dynamic>.from(
                request['tx_json'] as Map<String, dynamic>,
              );
              return {
                'relay_type': 'tron_gasfree',
                'trace_id': 'legacy-trace',
                'state': 'WAITING',
              };
            case 'gasless::trace_status':
              traceParams = Map<String, dynamic>.from(
                request['params'] as Map<String, dynamic>,
              );
              return {
                'mmrpc': '2.0',
                'result': {
                  'state': 'confirmed',
                  'tx_hash_on_chain': 'legacy-onchain-hash',
                  'final_fee': '1.5',
                },
              };
            default:
              throw StateError('Unexpected method: ${request['method']}');
          }
        });

        final progress = await manager
            .executeWithdrawal(_legacyGaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(sentPayload, isNot(contains('request_id')));
        expect(sentPayload, isNot(contains('authorization_fingerprint')));
        expect(traceParams, isNot(contains('expected_authorization')));
        expect(progress.last.status, WithdrawalStatus.complete);
        verify(
          () => transactionHistoryManager.verifyGaslessTransferOnChain(
            trc20Asset,
            any(),
            'legacy-onchain-hash',
          ),
        ).called(1);
        expect(await manager.listPendingGaslessTransfers(), isEmpty);
      },
    );

    test('legacy relay failure remains non-retryable and durable', () async {
      enableLegacyRecovery();
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        if (request['method'] == 'send_raw_transaction') {
          return {
            'relay_type': 'tron_gasfree',
            'trace_id': 'legacy-failed',
            'state': 'WAITING',
          };
        }
        return {
          'mmrpc': '2.0',
          'result': {'state': 'failed', 'failure_reason': 'provider text'},
        };
      });

      final progress = await manager
          .executeWithdrawal(_legacyGaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(progress.last.status, WithdrawalStatus.inProgress);
      expect(
        progress.last.gaslessTransferState,
        GaslessTransferState.submittedUnknown,
      );
      expect(progress.last.sdkError?.retryable, isFalse);
      final pending = await manager.listPendingGaslessTransfers();
      expect(pending.single.traceId, 'legacy-failed');
      expect(
        pending.single.verificationMode,
        GaslessVerificationMode.legacyOnChain,
      );
      expect(pending.single.requestId, isNot('legacy-failed'));
      expect(
        pending.single.requestId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(
        pending.single.authorizationFingerprint,
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });

    test(
      'legacy on-chain mismatch remains durable for support review',
      () async {
        enableLegacyRecovery();
        when(
          () => transactionHistoryManager.verifyGaslessTransferOnChain(
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => GaslessOnChainVerification.mismatch);
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          if (request['method'] == 'send_raw_transaction') {
            return {
              'relay_type': 'tron_gasfree',
              'trace_id': 'legacy-mismatch',
              'state': 'WAITING',
            };
          }
          return {
            'mmrpc': '2.0',
            'result': {
              'state': 'confirmed',
              'tx_hash_on_chain': 'mismatched-hash',
              'final_fee': '1.5',
            },
          };
        });

        final progress = await manager
            .executeWithdrawal(_legacyGaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(progress.last.sdkError?.retryable, isFalse);
        expect(await manager.listPendingGaslessTransfers(), hasLength(1));
      },
    );

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

    test(
      'surfaces an authoritative terminal failure without raw reason',
      () async {
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          switch (request['method']) {
            case 'send_raw_transaction':
              return {
                'relay_type': 'tron_gasfree',
                'request_id': '123e4567-e89b-42d3-a456-426614174000',
                'trace_id': 'trace-xyz',
                'state': 'WAITING',
                'expected_authorization': _expectedAuthorizationJson(),
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

        final progress = await manager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(progress.last.status, WithdrawalStatus.error);
        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.failedFinal,
        );
        expect(
          progress.last.sdkError?.fallbackMessage,
          isNot(contains('rejected')),
        );
        expect(await manager.listPendingGaslessTransfers(), isEmpty);
      },
    );

    test('deterministic trace failure remains durable and unknown', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        switch (request['method']) {
          case 'send_raw_transaction':
            return {
              'relay_type': 'tron_gasfree',
              'request_id': '123e4567-e89b-42d3-a456-426614174000',
              'trace_id': 'trace-unknown',
              'state': 'WAITING',
              'expected_authorization': _expectedAuthorizationJson(),
            };
          case 'gasless::trace_status':
            return {
              'mmrpc': '2.0',
              'error': 'GasFree runtime is not configured',
              'error_type': 'GaslessNotConfigured',
              'error_data': 'USDT-TRC20',
            };
          default:
            throw StateError('Unexpected method: ${request['method']}');
        }
      });

      final progress = await manager
          .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(progress.last.status, WithdrawalStatus.inProgress);
      expect(
        progress.last.gaslessTransferState,
        GaslessTransferState.submittedUnknown,
      );
      expect(progress.last.taskId, 'trace-unknown');
      final pending = await manager.listPendingGaslessTransfers();
      expect(pending.single.traceId, 'trace-unknown');
      expect(pending.single.state, GaslessTransferState.submittedUnknown);
    });

    test(
      'submit transport ambiguity remains durable and cannot be retried',
      () async {
        when(() => client.executeRpc(any())).thenThrow(
          StateError('connection closed after request body was sent'),
        );

        final progress = await manager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(progress.last.status, WithdrawalStatus.inProgress);
        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(progress.last.sdkError?.retryable, isFalse);
        final pending = await manager.listPendingGaslessTransfers();
        expect(
          pending.single.requestId,
          '123e4567-e89b-42d3-a456-426614174000',
        );
        expect(pending.single.traceId, isNull);
      },
    );

    test(
      'typed KDF pre-relay rejection maps without display-text parsing',
      () async {
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'error': 'GasFree relay submission failed',
            'error_type': 'GaslessRelaySubmission',
            'error_data': {
              'code': 'authorization_expired',
              'stage': 'submission',
              'retryable': true,
              'terminal': true,
              'relay_accepted': false,
            },
          },
        );

        final progress = await manager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.rejectedBeforeRelay,
        );
        expect(progress.last.sdkError?.retryable, isTrue);
        expect(
          (progress.last.sdkError!.source as GaslessTransferException?)?.code,
          GaslessTransferErrorCode.authorizationExpired,
        );
        expect(await manager.listPendingGaslessTransfers(), isEmpty);
      },
    );

    test(
      'typed KDF ambiguous submission keeps the request-only lock',
      () async {
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'error': 'GasFree relay submission failed',
            'error_type': 'GaslessRelaySubmission',
            'error_data': {
              'code': 'submission_outcome_unknown',
              'stage': 'submission',
              'retryable': false,
              'terminal': false,
            },
          },
        );

        final progress = await manager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        final pending = await manager.listPendingGaslessTransfers();
        expect(
          pending.single.requestId,
          _gaslessPreview().txJson!['request_id'],
        );
        expect(pending.single.traceId, isNull);
      },
    );

    test('typed accepted mismatch persists the correlated trace', () async {
      when(() => client.executeRpc(any())).thenAnswer(
        (_) async => {
          'error': 'GasFree relay submission failed',
          'error_type': 'GaslessRelaySubmission',
          'error_data': {
            'code': 'accepted_response_mismatch',
            'stage': 'submission',
            'retryable': false,
            'terminal': false,
            'relay_accepted': true,
            'request_id': '123e4567-e89b-42d3-a456-426614174000',
            'trace_id': 'trace-typed-mismatch',
            'field': 'targetAddress',
          },
        },
      );

      final progress = await manager
          .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(progress.last.submission?.traceId, 'trace-typed-mismatch');
      final pending = await manager.listPendingGaslessTransfers();
      expect(pending.single.traceId, 'trace-typed-mismatch');
    });

    test(
      'accepted trace storage failure stops before status polling',
      () async {
        final storage = _RejectAcceptedTraceStorage();
        final repository = SecurePendingGaslessTransferRepository(
          storage: storage,
        );
        final durabilityManager = WithdrawalManager(
          client,
          assetProvider,
          feeManager,
          activationCoordinator,
          legacyManager,
          gaslessCapabilities: gaslessCapabilities,
          pendingGaslessTransfers: repository,
          walletIdResolver: () async => walletId,
          gaslessPollInterval: Duration.zero,
        );
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'relay_type': 'tron_gasfree',
            'request_id': _requestId,
            'trace_id': 'trace-storage-failure',
            'state': 'WAITING',
            'expected_authorization': _expectedAuthorizationJson(),
          },
        );

        final progress = await durabilityManager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(progress.last.submission?.traceId, 'trace-storage-failure');
        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        verify(() => client.executeRpc(any())).called(1);
        expect((await repository.list(walletId)).single.traceId, isNull);
        await durabilityManager.dispose();
      },
    );

    test(
      'relay request-id mismatch is retained as a security unknown',
      () async {
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'relay_type': 'tron_gasfree',
            'request_id': '123e4567-e89b-42d3-b456-426614174999',
            'trace_id': 'trace-mismatch',
            'state': 'WAITING',
            'expected_authorization': _expectedAuthorizationJson(
              requestId: '123e4567-e89b-42d3-b456-426614174999',
            ),
          },
        );

        final progress = await manager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(progress.last.sdkError?.code, SdkErrorCode.invalidResponse);
        final pending = await manager.listPendingGaslessTransfers();
        expect(pending.single.traceId, 'trace-mismatch');
        verify(() => client.executeRpc(any())).called(1);
      },
    );

    test('accepted response mismatch persists its correlated trace', () async {
      when(() => client.executeRpc(any())).thenThrow(
        StateError(
          'GASFREE_RELAY_ACCEPTED_RESPONSE_MISMATCH '
          'request_id=123e4567-e89b-42d3-a456-426614174000 '
          'trace_id=trace-accepted-mismatch field=amount',
        ),
      );

      final progress = await manager
          .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
          .toList();

      expect(
        progress.last.gaslessTransferState,
        GaslessTransferState.submittedUnknown,
      );
      expect(progress.last.sdkError?.retryable, isFalse);
      expect(progress.last.submission?.traceId, 'trace-accepted-mismatch');
      final pending = await manager.listPendingGaslessTransfers();
      expect(pending.single.traceId, 'trace-accepted-mismatch');
    });

    for (final testCase in <({String name, WithdrawalPreview preview})>[
      (
        name: 'signed maximum fee',
        preview: _gaslessPreview(authorizationMaxFee: '6000000'),
      ),
      (
        name: 'signed recipient amount',
        preview: _gaslessPreview(authorizationValue: '6000000'),
      ),
      (
        name: 'token contract',
        preview: _gaslessPreview(
          authorizationToken: 'TInvalidTokenContract1111111111111111',
        ),
      ),
      (
        name: 'provider identity',
        preview: _gaslessPreview(
          authorizationProvider: 'TInvalidProvider11111111111111111111',
          feeProviderAddress: 'TInvalidProvider11111111111111111111',
        ),
      ),
      (name: 'network chain', preview: _gaslessPreview(chainId: '3448148188')),
      (
        name: 'fee request ID',
        preview: _gaslessPreview(
          feeRequestId: '123e4567-e89b-42d3-b456-426614174999',
        ),
      ),
      (
        name: 'fee authorization deadline',
        preview: _gaslessPreview(feeAuthorizationDeadline: '1999999998'),
      ),
      (
        name: 'signature fingerprint',
        preview: _gaslessPreview(
          authorizationSignature:
              '${_authorizationSignature.substring(0, 128)}10',
        ),
      ),
    ]) {
      test(
        'rejects a preview with mismatched ${testCase.name} before relay',
        () async {
          await expectLater(
            manager.executeWithdrawal(testCase.preview, 'USDT-TRC20').toList(),
            throwsA(
              isA<SdkError>().having(
                (error) => error.messageKey,
                'messageKey',
                'sdk_errors.gasless_preview_invalid',
              ),
            ),
          );
          verifyNever(() => client.executeRpc(any()));
          expect(await manager.listPendingGaslessTransfers(), isEmpty);
        },
      );
    }

    test('expired authorization is rejected before relay submission', () async {
      await expectLater(
        manager
            .executeWithdrawal(
              _gaslessPreview(deadline: '1000000000'),
              'USDT-TRC20',
            )
            .toList(),
        throwsA(
          isA<SdkError>().having(
            (error) => error.messageKey,
            'messageKey',
            'sdk_errors.gasless_authorization_expired',
          ),
        ),
      );
      verifyNever(() => client.executeRpc(any()));
    });

    test(
      'wallet switch stops polling and retains the original journal',
      () async {
        const switchedWallet = WalletId(
          name: 'switched',
          pubkeyHash: 'switched-wallet-hash',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        );
        WalletId? currentWallet = walletId;
        final switchingManager = WithdrawalManager(
          client,
          assetProvider,
          feeManager,
          activationCoordinator,
          legacyManager,
          gaslessCapabilities: gaslessCapabilities,
          pendingGaslessTransfers: pendingRepository,
          walletIdResolver: () async => currentWallet,
          gaslessPollInterval: Duration.zero,
        );
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          if (request['method'] == 'send_raw_transaction') {
            return {
              'relay_type': 'tron_gasfree',
              'request_id': '123e4567-e89b-42d3-a456-426614174000',
              'trace_id': 'trace-wallet-switch',
              'state': 'WAITING',
              'expected_authorization': _expectedAuthorizationJson(),
            };
          }
          currentWallet = switchedWallet;
          return {
            'mmrpc': '2.0',
            'result': {
              'state': 'confirmed',
              'tx_hash_on_chain': 'must-not-be-surfaced',
              'final_fee': '1.5',
            },
          };
        });

        final progress = await switchingManager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(progress.last.status, WithdrawalStatus.inProgress);
        final original = await pendingRepository.list(walletId);
        expect(original.single.traceId, 'trace-wallet-switch');
        expect(await pendingRepository.list(switchedWallet), isEmpty);
        await switchingManager.dispose();
      },
    );

    test(
      'wallet switch before relay clears the preparing reservation',
      () async {
        const switchedWallet = WalletId(
          name: 'switched-before-submit',
          pubkeyHash: 'switched-before-submit-hash',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        );
        var resolveCalls = 0;
        final switchingManager = WithdrawalManager(
          client,
          assetProvider,
          feeManager,
          activationCoordinator,
          legacyManager,
          gaslessCapabilities: gaslessCapabilities,
          pendingGaslessTransfers: pendingRepository,
          walletIdResolver: () async {
            resolveCalls++;
            return resolveCalls >= 4 ? switchedWallet : walletId;
          },
        );

        final progress = await switchingManager
            .executeWithdrawal(_gaslessPreview(), 'USDT-TRC20')
            .toList();

        expect(progress, hasLength(1));
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(walletId), isEmpty);
        expect(await pendingRepository.list(switchedWallet), isEmpty);
        await switchingManager.dispose();
      },
    );
  });
}
