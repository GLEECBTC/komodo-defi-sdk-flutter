import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
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

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RecordingPendingGaslessTransferRepository
    implements PendingGaslessTransferRepository {
  _RecordingPendingGaslessTransferRepository(this.delegate);

  final PendingGaslessTransferRepository delegate;
  final upsertedStates = <GaslessTransferState>[];

  @override
  Future<PendingGaslessTransfer?> find(WalletId walletId, String identity) =>
      delegate.find(walletId, identity);

  @override
  Future<PendingGaslessTransfer?> findByJournalId(
    WalletId walletId,
    String journalId,
  ) => delegate.findByJournalId(walletId, journalId);

  @override
  Future<PendingGaslessTransfer?> findByTraceId(
    WalletId walletId,
    String traceId,
  ) => delegate.findByTraceId(walletId, traceId);

  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) =>
      delegate.list(walletId);

  @override
  Future<void> remove(WalletId walletId, String identity) =>
      delegate.remove(walletId, identity);

  @override
  Future<bool> reserve(WalletId walletId, PendingGaslessTransfer transfer) =>
      delegate.reserve(walletId, transfer);

  @override
  Future<void> upsert(WalletId walletId, PendingGaslessTransfer transfer) {
    upsertedStates.add(transfer.state);
    return delegate.upsert(walletId, transfer);
  }

  @override
  Stream<List<PendingGaslessTransfer>> watch(WalletId walletId) =>
      delegate.watch(walletId);
}

const _coin = 'USDT-TRC20';
const _chainId = '728126428';
const _tokenContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _providerAddress = 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E';
const _sourceAddress = 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC';
const _custodyAddress = 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF';
const _destinationAddress = 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC';
const _verifyingContract = 'TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U';
const _signature =
    '1111111111111111111111111111111111111111111111111111111111111111'
    '111111111111111111111111111111111111111111111111111111111111111111';

const _wallet = WalletId(
  name: 'wallet',
  pubkeyHash: 'wallet-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _otherWallet = WalletId(
  name: 'other-wallet',
  pubkeyHash: 'other-wallet-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);

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
  'coin': _coin,
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': _tokenContract},
  },
  'contract_address': _tokenContract,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

GaslessAccountStatusResponse _availableStatus() =>
    GaslessAccountStatusResponse.parse({
      'mmrpc': '2.0',
      'result': {
        'gasfree_address': _custodyAddress,
        'service_provider': _providerAddress,
        'availability': 'available',
        'active': true,
        'on_chain_balance': '10',
        'frozen_balance': '0',
        'spendable_balance': '10',
        'transfer_fee': '2',
        'activation_fee': null,
        'max_withdrawable': '8',
      },
    });

WithdrawalPreview _gaslessPreview({
  String chainId = _chainId,
  String verifyingContract = _verifyingContract,
}) {
  final amount = Decimal.parse('5');
  return WithdrawResult(
    txJson: {
      'relay_type': TronGasfreeRelayPayload.relayTypeValue,
      'chain_id': chainId,
      'coin': _coin,
      'from_address': _sourceAddress,
      'gasfree_address': _custodyAddress,
      'verifying_contract': verifyingContract,
      'signed_authorization': {
        'token': _tokenContract,
        'service_provider': _providerAddress,
        'user': _sourceAddress,
        'receiver': _destinationAddress,
        'value': '5000000',
        'max_fee': '5000000',
        'deadline': '1999999999',
        'version': '1',
        'nonce': '9',
        'sig': _signature,
      },
      'created_at': '2026-07-24T12:00:00Z',
    },
    txHash: null,
    from: const [_sourceAddress],
    to: const [_destinationAddress],
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-7'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('7'),
      totalAmount: amount,
    ),
    blockHeight: 0,
    timestamp: 0,
    fee: FeeInfo.tronGasless(
      coin: _coin,
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: _custodyAddress,
      transferFee: Decimal.parse('2'),
      totalTokenFee: Decimal.parse('2'),
      signedMaxFee: Decimal.parse('5'),
    ),
    coin: _coin,
  );
}

WithdrawalPreview _standardPreview() => WithdrawResult(
  txHex: 'deadbeef',
  txHash: '',
  from: const [_sourceAddress],
  to: const [_destinationAddress],
  balanceChanges: BalanceChanges(
    netChange: Decimal.parse('-5.1'),
    receivedByMe: Decimal.zero,
    spentByMe: Decimal.parse('5.1'),
    totalAmount: Decimal.parse('5'),
  ),
  blockHeight: 0,
  timestamp: 0,
  fee: FeeInfo.tron(
    coin: 'TRX',
    bandwidthUsed: 1,
    energyUsed: 1,
    bandwidthFee: Decimal.parse('0.05'),
    energyFee: Decimal.parse('0.05'),
    totalFeeAmount: Decimal.parse('0.1'),
  ),
  coin: _coin,
);

PendingGaslessTransfer _pending({
  String journalId = '123e4567-e89b-42d3-a456-426614174000',
  String? traceId = 'trace-recovery',
  GaslessTransferState state = GaslessTransferState.submittedPending,
}) {
  final timestamp = DateTime.utc(2026, 7, 24, 12);
  return PendingGaslessTransfer(
    journalId: journalId,
    traceId: traceId,
    assetId: _coin,
    network: _chainId,
    sourceAddress: _sourceAddress,
    custodyAddress: _custodyAddress,
    destinationAddress: _destinationAddress,
    requestedAmount: Decimal.parse('5'),
    signedMaxFee: Decimal.parse('5'),
    authorizationDeadline: 1999999999,
    balanceChanges: _gaslessPreview().balanceChanges,
    fee: _gaslessPreview().fee,
    acceptedAt: timestamp,
    updatedAt: timestamp,
    state: state,
  );
}

Map<String, dynamic> _traceStatus({
  String state = 'submitted',
  String? txHash,
  int? blockHeight,
  int? confirmedAt,
  String? finalFee,
  String? failureReason,
}) => {
  'mmrpc': '2.0',
  'result': {
    'state': state,
    'tx_hash_on_chain': txHash,
    'block_height': blockHeight,
    'confirmed_at': confirmedAt,
    'final_fee': finalFee,
    'failure_reason': failureReason,
  },
};

Map<String, dynamic> _errorEnvelope(String errorType) => {
  'mmrpc': '2.0',
  'result': {
    'status': 'Error',
    'details': {
      'error': 'GasFree endpoint error',
      'error_type': errorType,
      'error_data': _coin,
    },
  },
};

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('WithdrawalManager final GasFree contract', () {
    late _MockApiClient client;
    late _MockAssetProvider assetProvider;
    late _MockFeeManager feeManager;
    late _MockActivationCoordinator activationCoordinator;
    late _MockLegacyWithdrawalManager legacyManager;
    late _MockEventStreamingManager eventStreamingManager;
    late SecurePendingGaslessTransferRepository pendingRepository;
    late Asset trc20Asset;
    late GaslessCapabilityRegistry gaslessCapabilities;

    setUp(() {
      client = _MockApiClient();
      assetProvider = _MockAssetProvider();
      feeManager = _MockFeeManager();
      activationCoordinator = _MockActivationCoordinator();
      legacyManager = _MockLegacyWithdrawalManager();
      eventStreamingManager = _MockEventStreamingManager();
      pendingRepository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );

      final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
      trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});
      gaslessCapabilities = GaslessCapabilityRegistry(
        configuredAssetIds: const {_coin},
        pinnedProviderAddress: _providerAddress,
      );
      final recorded = gaslessCapabilities.recordAccountStatus(
        trc20Asset,
        GaslessCapabilityIdentity(
          assetId: trc20Asset.id,
          platform: 'TRX',
          contractAddress: _tokenContract,
          providerAddress: _providerAddress,
          walletPubkeyHash: _wallet.pubkeyHash!,
          walletType: GaslessWalletType.softwareIguana,
          derivationPath: '',
        ),
        _availableStatus(),
      );
      expect(recorded, isTrue);

      when(
        () => assetProvider.findAssetsByConfigId(_coin),
      ).thenReturn({trc20Asset});
      when(() => assetProvider.fromId(trxParent.id)).thenReturn(trxParent);
      when(
        () => activationCoordinator.activateAsset(trc20Asset),
      ).thenAnswer((_) async => ActivationResult.success(trc20Asset.id));
    });

    WithdrawalManager makeManager({
      EventStreamingManager? streams,
      PendingGaslessTransferRepository? repository,
      Future<WalletId?> Function()? walletResolver,
      Stream<KdfUser?>? authStateChanges,
    }) => WithdrawalManager(
      client,
      assetProvider,
      feeManager,
      activationCoordinator,
      legacyManager,
      gaslessCapabilities: gaslessCapabilities,
      pendingGaslessTransfers: repository ?? pendingRepository,
      eventStreamingManager: streams,
      walletIdResolver: walletResolver ?? () async => _wallet,
      authStateChanges: authStateChanges,
    );

    test(
      'rejects a relay chain mismatch before reservation or submission',
      () async {
        final manager = makeManager(streams: eventStreamingManager);

        await expectLater(
          manager
              .executeWithdrawal(_gaslessPreview(chainId: '3448148188'), _coin)
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.source,
              'source',
              isA<GaslessTransferException>()
                  .having(
                    (error) => error.code,
                    'code',
                    GaslessTransferErrorCode.chainIdMismatch,
                  )
                  .having(
                    (error) => error.stage,
                    'stage',
                    GaslessTransferStage.preview,
                  ),
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'rejects a relay verifier mismatch before reservation or submission',
      () async {
        final manager = makeManager(streams: eventStreamingManager);

        await expectLater(
          manager
              .executeWithdrawal(
                _gaslessPreview(
                  verifyingContract: 'THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc',
                ),
                _coin,
              )
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.source,
              'source',
              isA<GaslessTransferException>()
                  .having(
                    (error) => error.code,
                    'code',
                    GaslessTransferErrorCode.verifyingContractMismatch,
                  )
                  .having(
                    (error) => error.stage,
                    'stage',
                    GaslessTransferStage.preview,
                  ),
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'attaches stream before relay, submits exact payload, then follows trace',
      () async {
        final events = StreamController<KdfEvent>();
        final traceQuerySeen = Completer<void>();
        final timeline = <String>[];
        final requests = <Map<String, dynamic>>[];

        when(
          () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
        ).thenAnswer((_) async {
          timeline.add('stream');
          return events.stream.listen(null);
        });
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          switch (request['method']) {
            case 'send_raw_transaction':
              timeline.add('relay');
              return {
                'relay_type': TronGasfreeRelayPayload.relayTypeValue,
                'trace_id': 'trace-accepted',
                'state': 'WAITING',
              };
            case 'gasless::trace_status':
              if (!traceQuerySeen.isCompleted) traceQuerySeen.complete();
              return _traceStatus();
            default:
              throw StateError('Unexpected RPC ${request['method']}');
          }
        });

        final preview = _gaslessPreview();
        final progressFuture = makeManager(
          streams: eventStreamingManager,
        ).executeWithdrawal(preview, _coin).toList();

        await traceQuerySeen.future;
        events
          ..add(
            const GaslessTraceErrorEvent(
              coin: _coin,
              traceId: 'trace-accepted',
              error: 'provider temporarily unreachable',
            ),
          )
          ..add(
            const GaslessTraceEvent(
              coin: _coin,
              traceId: 'trace-other',
              state: GaslessTraceEventState.confirmed,
              txHashOnChain: 'wrong-hash',
              blockHeight: 1,
              confirmedAt: 1,
              finalFee: '1',
            ),
          )
          ..add(
            const GaslessTraceEvent(
              coin: _coin,
              traceId: 'trace-accepted',
              state: GaslessTraceEventState.confirmed,
              txHashOnChain: 'on-chain-hash',
              blockHeight: 123,
              confirmedAt: 1784894400,
              finalFee: '1.5',
            ),
          );

        final progress = await progressFuture.timeout(
          const Duration(seconds: 2),
        );
        await events.close();

        expect(timeline.take(2), ['stream', 'relay']);
        final sendRequest = requests.singleWhere(
          (request) => request['method'] == 'send_raw_transaction',
        );
        final sentPayload = sendRequest['tx_json'] as Map<String, dynamic>;
        expect(sentPayload, preview.gaslessRelayPayload!.toJson());
        expect(sentPayload, isNot(contains('journal_id')));
        expect(sentPayload, isNot(contains('request_id')));
        expect(
          requests.where(
            (request) => request['method'] == 'gasless::trace_status',
          ),
          hasLength(1),
        );
        expect(
          progress.any(
            (item) =>
                item.sdkError?.source is GaslessTransferException &&
                item.gaslessTransferState ==
                    GaslessTransferState.submittedPending,
          ),
          isTrue,
        );

        final accepted = progress.firstWhere(
          (item) =>
              item.submission?.traceId == 'trace-accepted' &&
              item.gaslessState == null,
        );
        expect(accepted.submission?.journalId, isNotEmpty);
        final result = progress.last;
        expect(result.status, WithdrawalStatus.complete);
        expect(result.withdrawalResult?.txHash, 'on-chain-hash');
        expect(result.withdrawalResult?.gaslessFinalFee, Decimal.parse('1.5'));
        expect(result.withdrawalResult?.gaslessTraceId, 'trace-accepted');
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'buffered error and older trace cannot regress one-shot on-chain state',
      () async {
        final events = StreamController<KdfEvent>();
        final recordingRepository = _RecordingPendingGaslessTransferRepository(
          pendingRepository,
        );
        when(
          () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
        ).thenAnswer((_) async => events.stream.listen(null));
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          return switch (request['method']) {
            'send_raw_transaction' => () {
              events
                ..add(
                  const GaslessTraceErrorEvent(
                    coin: _coin,
                    traceId: 'trace-monotonic',
                    error: 'provider temporarily unreachable',
                  ),
                )
                ..add(
                  const GaslessTraceEvent(
                    coin: _coin,
                    traceId: 'trace-monotonic',
                    state: GaslessTraceEventState.pending,
                  ),
                )
                ..add(
                  const GaslessTraceEvent(
                    coin: _coin,
                    traceId: 'trace-monotonic',
                    state: GaslessTraceEventState.confirmed,
                    txHashOnChain: 'monotonic-hash',
                    blockHeight: 321,
                    confirmedAt: 1784894400,
                    finalFee: '1.25',
                  ),
                );
              return {
                'relay_type': TronGasfreeRelayPayload.relayTypeValue,
                'trace_id': 'trace-monotonic',
                'state': 'WAITING',
              };
            }(),
            'gasless::trace_status' => _traceStatus(
              state: 'on_chain',
              txHash: 'monotonic-hash',
            ),
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });

        final progress = await makeManager(
          streams: eventStreamingManager,
          repository: recordingRepository,
        ).executeWithdrawal(_gaslessPreview(), _coin).toList();
        await events.close();

        expect(recordingRepository.upsertedStates, [
          GaslessTransferState.submittedPending,
          GaslessTransferState.confirming,
        ]);
        final onChainIndex = progress.indexWhere(
          (item) => item.gaslessState == GaslessTraceState.onChain,
        );
        expect(onChainIndex, greaterThanOrEqualTo(0));
        expect(
          progress
              .skip(onChainIndex + 1)
              .any(
                (item) =>
                    item.sdkError?.source is GaslessTransferException &&
                    item.gaslessTransferState ==
                        GaslessTransferState.confirming,
              ),
          isTrue,
        );
        expect(
          progress
              .skip(onChainIndex + 1)
              .map((item) => item.gaslessState)
              .whereType<GaslessTraceState>(),
          isNot(contains(GaslessTraceState.pending)),
        );
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(progress.last.withdrawalResult?.txHash, 'monotonic-hash');
      },
    );

    test(
      'plain-string relay failure becomes durable unknown without guessing',
      () async {
        final events = StreamController<KdfEvent>();
        when(
          () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
        ).thenAnswer((_) async => events.stream.listen(null));
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          if (request['method'] == 'send_raw_transaction') {
            throw Exception('FAILED retry terminal');
          }
          throw StateError('Unexpected RPC ${request['method']}');
        });

        final progress = await makeManager(
          streams: eventStreamingManager,
        ).executeWithdrawal(_gaslessPreview(), _coin).toList();
        await events.close();

        final unknown = progress.last;
        expect(
          unknown.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(unknown.submission?.traceId, isNull);
        expect(unknown.submission?.journalId, isNotEmpty);
        expect(
          (unknown.sdkError?.source as GaslessTransferException).code,
          GaslessTransferErrorCode.submissionOutcomeUnknown,
        );
        final persisted = await pendingRepository.list(_wallet);
        expect(persisted, hasLength(1));
        expect(persisted.single.traceId, isNull);
        expect(persisted.single.state, GaslessTransferState.submittedUnknown);
        verify(() => client.executeRpc(any())).called(1);
      },
    );

    test('missing trace manager fails before relay and clears reservation', () {
      final manager = makeManager();

      expectLater(
        manager.executeWithdrawal(_gaslessPreview(), _coin).toList(),
        throwsA(isA<SdkError>()),
      ).then((_) async {
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      });
    });

    test(
      'stream disconnect before relay aborts submission and clears reservation',
      () async {
        final events = StreamController<KdfEvent>();
        var streamAttached = false;
        when(
          () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
        ).thenAnswer((_) async {
          streamAttached = true;
          return events.stream.listen(null);
        });

        Future<WalletId?> walletResolver() async {
          if (streamAttached && !events.isClosed) {
            await events.close();
          }
          return _wallet;
        }

        await expectLater(
          makeManager(
            streams: eventStreamingManager,
            walletResolver: walletResolver,
          ).executeWithdrawal(_gaslessPreview(), _coin).toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.source,
              'source',
              isA<GaslessTransferException>()
                  .having(
                    (source) => source.code,
                    'code',
                    GaslessTransferErrorCode.traceUnavailable,
                  )
                  .having(
                    (source) => source.stage,
                    'stage',
                    GaslessTransferStage.submission,
                  ),
            ),
          ),
        );

        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test('terminal trace reason never enters SDK errors or progress', () async {
      const sensitiveReason =
          'authorization=secret-material recipient=$_destinationAddress';
      final events = StreamController<KdfEvent>();
      when(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).thenAnswer((_) async => events.stream.listen(null));
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        return switch (request['method']) {
          'send_raw_transaction' => {
            'relay_type': TronGasfreeRelayPayload.relayTypeValue,
            'trace_id': 'trace-failed',
            'state': 'WAITING',
          },
          'gasless::trace_status' => _traceStatus(
            state: 'failed',
            failureReason: sensitiveReason,
          ),
          _ => throw StateError('Unexpected RPC ${request['method']}'),
        };
      });

      final progress = await makeManager(
        streams: eventStreamingManager,
      ).executeWithdrawal(_gaslessPreview(), _coin).toList();
      await events.close();

      final failure = progress.last;
      expect(failure.status, WithdrawalStatus.error);
      expect(
        failure.sdkError?.fallbackMessage,
        isNot(contains(sensitiveReason)),
      );
      expect(
        failure.sdkError?.source.toString(),
        isNot(contains(sensitiveReason)),
      );
      expect(failure.toString(), isNot(contains(sensitiveReason)));
      expect(failure.toString(), isNot(contains(_destinationAddress)));
      expect(await pendingRepository.list(_wallet), isEmpty);
    });

    test(
      'restart recovery reconciles an accepted trace exactly once',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return _traceStatus(
            state: 'confirmed',
            txHash: 'recovered-hash',
            blockHeight: 456,
            confirmedAt: 1784894400,
            finalFee: '1.25',
          );
        });

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        expect(requests, hasLength(1));
        expect(requests.single['method'], 'gasless::trace_status');
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(progress.last.withdrawalResult?.txHash, 'recovered-hash');
        expect(
          progress.last.withdrawalResult?.gaslessTraceId,
          'trace-recovery',
        );
        expect(
          progress.last.withdrawalResult?.gaslessFinalFee,
          Decimal.parse('1.25'),
        );
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'recovery status outage preserves an established on-chain state',
      () async {
        await pendingRepository.upsert(
          _wallet,
          _pending(state: GaslessTransferState.confirming),
        );
        when(
          () => client.executeRpc(any()),
        ).thenThrow(Exception('trace status temporarily unavailable'));

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.confirming,
        );
        expect(
          progress.last.sdkError?.source,
          isA<GaslessTransferException>().having(
            (error) => error.code,
            'code',
            GaslessTransferErrorCode.traceUnavailable,
          ),
        );
        final retained = await pendingRepository.findByTraceId(
          _wallet,
          'trace-recovery',
        );
        expect(retained?.state, GaslessTransferState.confirming);
      },
    );

    test('journal without trace stays unknown and never invokes KDF', () async {
      final pending = _pending(
        traceId: null,
        state: GaslessTransferState.submittedUnknown,
      );
      await pendingRepository.upsert(_wallet, pending);

      final progress = await makeManager()
          .resumePendingGaslessTransfer(pending.journalId)
          .toList();

      expect(progress, hasLength(1));
      expect(
        progress.single.gaslessTransferState,
        GaslessTransferState.submittedUnknown,
      );
      expect(progress.single.submission?.traceId, isNull);
      expect(progress.single.submission?.journalId, pending.journalId);
      verifyNever(() => client.executeRpc(any()));
      expect(await pendingRepository.list(_wallet), [pending]);
    });

    test(
      'wallet switch during recovery cannot update another journal',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        var currentWallet = _wallet;
        final requestSeen = Completer<void>();
        final response = Completer<Map<String, dynamic>>();
        when(() => client.executeRpc(any())).thenAnswer((_) {
          requestSeen.complete();
          return response.future;
        });
        final manager = makeManager(walletResolver: () async => currentWallet);

        final recovery = manager
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();
        await requestSeen.future;
        currentWallet = _otherWallet;
        response.complete(_traceStatus());

        await expectLater(
          recovery,
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        expect(await pendingRepository.list(_wallet), hasLength(1));
        expect(await pendingRepository.list(_otherWallet), isEmpty);
      },
    );

    test(
      'pending watch clears and terminates immediately on wallet switch',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        var currentWallet = _wallet;
        final authChanges = StreamController<KdfUser?>();
        final manager = makeManager(
          walletResolver: () async => currentWallet,
          authStateChanges: authChanges.stream,
        );
        final firstSnapshot = Completer<void>();
        final done = Completer<void>();
        final snapshots = <List<PendingGaslessTransfer>>[];
        manager.watchPendingGaslessTransfers().listen(
          (transfers) {
            snapshots.add(transfers);
            if (!firstSnapshot.isCompleted) firstSnapshot.complete();
          },
          onError: done.completeError,
          onDone: done.complete,
        );
        await firstSnapshot.future;

        currentWallet = _otherWallet;
        authChanges.add(
          const KdfUser(walletId: _otherWallet, isBip39Seed: false),
        );

        await done.future.timeout(const Duration(seconds: 2));
        expect(snapshots.first, hasLength(1));
        expect(snapshots.last, isEmpty);
        await authChanges.close();
        await manager.dispose();
      },
    );

    test(
      'pending watch also clears when the resolver detects the wallet switch',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        var currentWallet = _wallet;
        final manager = makeManager(walletResolver: () async => currentWallet);
        final firstSnapshot = Completer<void>();
        final done = Completer<void>();
        final snapshots = <List<PendingGaslessTransfer>>[];
        manager.watchPendingGaslessTransfers().listen(
          (transfers) {
            snapshots.add(transfers);
            if (!firstSnapshot.isCompleted) firstSnapshot.complete();
          },
          onError: done.completeError,
          onDone: done.complete,
        );
        await firstSnapshot.future;

        currentWallet = _otherWallet;
        // Any subsequent wallet-scoped operation observes the stable wallet
        // change and invalidates the existing journal watch even when an auth
        // stream is not available to the embedding application.
        expect(await manager.listPendingGaslessTransfers(), isEmpty);

        await done.future.timeout(const Duration(seconds: 2));
        expect(snapshots.first, hasLength(1));
        expect(snapshots.last, isEmpty);
        await manager.dispose();
      },
    );

    for (final entry in const {
      'ProviderIdentityMismatch':
          GaslessTransferErrorCode.serviceProviderMismatch,
      'GasfreeAddressMismatch': GaslessTransferErrorCode.custodyAddressMismatch,
      'TokenDecimalMismatch': GaslessTransferErrorCode.tokenMismatch,
    }.entries) {
      test('maps exact account-status error ${entry.key}', () async {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) async => _errorEnvelope(entry.key));

        await expectLater(
          makeManager().gaslessAccountStatus(trc20Asset.id),
          throwsA(
            isA<GaslessTransferException>().having(
              (error) => error.code,
              'code',
              entry.value,
            ),
          ),
        );
      });
    }

    test(
      'malformed account-status shape is a hard response mismatch',
      () async {
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'mmrpc': '2.0',
            'result': {
              'gasfree_address': _custodyAddress,
              'availability': 'available',
              'on_chain_balance': '10',
            },
          },
        );

        await expectLater(
          makeManager().gaslessAccountStatus(trc20Asset.id),
          throwsA(
            isA<GaslessTransferException>()
                .having(
                  (error) => error.code,
                  'code',
                  GaslessTransferErrorCode.responseMismatch,
                )
                .having((error) => error.retryable, 'retryable', isFalse)
                .having((error) => error.terminal, 'terminal', isTrue),
          ),
        );
      },
    );

    test('maps task-boundary GasFree errors by endpoint enum', () async {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        return switch (request['method']) {
          'task::withdraw::init' => {
            'mmrpc': '2.0',
            'result': {'task_id': 9},
          },
          'task::withdraw::status' => {
            'mmrpc': '2.0',
            'result': {
              'status': 'Error',
              'details': jsonEncode({
                'error': 'A GasFree transfer is already pending',
                'error_type': 'Gasless',
                'error_data': {
                  'error_type': 'PendingTransfer',
                  'error_data': null,
                },
              }),
            },
          },
          _ => throw StateError('Unexpected RPC ${request['method']}'),
        };
      });

      await expectLater(
        makeManager().previewWithdrawal(
          WithdrawParameters(
            asset: _coin,
            toAddress: _destinationAddress,
            amount: Decimal.parse('5'),
            feeMethod: WithdrawalFeeMethod.gasless,
            gaslessOptions: const GaslessWithdrawalOptions(
              fallbackToNative: false,
            ),
          ),
        ),
        throwsA(
          isA<SdkError>()
              .having(
                (error) => error.context?.extra['gaslessCode'],
                'gaslessCode',
                GaslessTransferErrorCode.pendingTransfer.name,
              )
              .having((error) => error.retryable, 'retryable', isTrue)
              .having(
                (error) => error.source,
                'source',
                isA<GaslessTransferException>().having(
                  (source) => source.code,
                  'code',
                  GaslessTransferErrorCode.pendingTransfer,
                ),
              ),
        ),
      );
    });

    test(
      'generic native fallback returns and executes the actual rail',
      () async {
        gaslessCapabilities.markTemporarilyUnavailable(trc20Asset.id);
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 7},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {
                'status': 'Ok',
                'details': _standardPreview().toJson(),
              },
            },
            'send_raw_transaction' => {'tx_hash': 'fallback-hash'},
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });
        final manager = makeManager();
        const options = GaslessWithdrawalOptions(
          maxFee: null,
          deadlineSeconds: 300,
          fallbackToNative: true,
        );

        final preview = await manager.previewWithdrawal(
          WithdrawParameters(
            asset: _coin,
            toAddress: _destinationAddress,
            amount: Decimal.parse('5'),
            feeMethod: WithdrawalFeeMethod.gasless,
            gaslessOptions: options,
          ),
        );
        final progress = await manager
            .executeWithdrawal(preview, _coin)
            .toList();

        expect(preview.gaslessRelayPayload, isNull);
        expect(preview.txHex, 'deadbeef');
        final init = requests.firstWhere(
          (request) => request['method'] == 'task::withdraw::init',
        );
        expect(init['params'], containsPair('fee_method', 'gasless'));
        expect((init['params'] as Map<String, dynamic>)['gasless'], {
          'deadline_seconds': 300,
          'fallback_to_native': true,
        });
        expect(
          progress.last.submission,
          const WithdrawalSubmission.onChain(txHash: 'fallback-hash'),
        );
      },
    );

    test(
      'deprecated one-call withdrawal preserves generic native fallback',
      () async {
        gaslessCapabilities.markTemporarilyUnavailable(trc20Asset.id);
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 17},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {
                'status': 'Ok',
                'details': _standardPreview().toJson(),
              },
            },
            'send_raw_transaction' => {'tx_hash': 'one-call-fallback-hash'},
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });

        // This regression intentionally exercises the compatibility API.
        // ignore: deprecated_member_use_from_same_package
        final progress = await makeManager()
            .withdraw(
              WithdrawParameters(
                asset: _coin,
                toAddress: _destinationAddress,
                amount: Decimal.parse('5'),
                feeMethod: WithdrawalFeeMethod.gasless,
                gaslessOptions: const GaslessWithdrawalOptions(
                  deadlineSeconds: 300,
                  fallbackToNative: true,
                ),
              ),
            )
            .toList();

        final init = requests.firstWhere(
          (request) => request['method'] == 'task::withdraw::init',
        );
        expect((init['params'] as Map<String, dynamic>)['gasless'], {
          'deadline_seconds': 300,
          'fallback_to_native': true,
        });
        expect(
          progress.last.submission,
          const WithdrawalSubmission.onChain(txHash: 'one-call-fallback-hash'),
        );
        expect(
          requests.where(
            (request) => request['method'] == 'send_raw_transaction',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'deprecated one-call withdrawal requires readiness without fallback',
      () async {
        gaslessCapabilities.markTemporarilyUnavailable(trc20Asset.id);

        // This regression intentionally exercises the compatibility API.
        // ignore: deprecated_member_use_from_same_package
        await expectLater(
          makeManager()
              .withdraw(
                WithdrawParameters(
                  asset: _coin,
                  toAddress: _destinationAddress,
                  amount: Decimal.parse('5'),
                  feeMethod: WithdrawalFeeMethod.gasless,
                  gaslessOptions: const GaslessWithdrawalOptions(
                    fallbackToNative: false,
                  ),
                ),
              )
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.capabilityNotReady.name,
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
      },
    );

    test(
      'deprecated one-call withdrawal rejects an unexpected native rail',
      () async {
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 18},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {
                'status': 'Ok',
                'details': _standardPreview().toJson(),
              },
            },
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });

        // This regression intentionally exercises the compatibility API.
        // ignore: deprecated_member_use_from_same_package
        await expectLater(
          makeManager()
              .withdraw(
                WithdrawParameters(
                  asset: _coin,
                  toAddress: _destinationAddress,
                  amount: Decimal.parse('5'),
                  feeMethod: WithdrawalFeeMethod.gasless,
                  gaslessOptions: const GaslessWithdrawalOptions(
                    fallbackToNative: false,
                  ),
                ),
              )
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.responseMismatch.name,
            ),
          ),
        );
        expect(
          requests.where(
            (request) => request['method'] == 'task::withdraw::status',
          ),
          hasLength(1),
        );
        expect(
          requests.where(
            (request) => request['method'] == 'send_raw_transaction',
          ),
          isEmpty,
        );
      },
    );

    test('standard withdrawal remains on the native broadcast rail', () async {
      Map<String, dynamic>? request;
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        request = invocation.positionalArguments.single as Map<String, dynamic>;
        return {'tx_hash': 'standard-hash'};
      });

      final progress = await makeManager()
          .executeWithdrawal(_standardPreview(), _coin)
          .toList();

      expect(request?['method'], 'send_raw_transaction');
      expect(request?['tx_hex'], 'deadbeef');
      expect(request, isNot(contains('tx_json')));
      expect(progress.last.status, WithdrawalStatus.complete);
      expect(
        progress.last.submission,
        const WithdrawalSubmission.onChain(txHash: 'standard-hash'),
      );
      expect(progress.last.withdrawalResult?.txHash, 'standard-hash');
      expect(progress.last.withdrawalResult?.gaslessTraceId, isNull);
      expect(await pendingRepository.list(_wallet), isEmpty);
    });
  });
}
