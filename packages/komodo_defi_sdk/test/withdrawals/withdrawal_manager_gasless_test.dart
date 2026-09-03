import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    hide Bip44Chain;
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

class _MockPendingGaslessTransferRepository extends Mock
    implements PendingGaslessTransferRepository {}

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

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
  Future<List<PendingGaslessTransfer>> listAmbiguousLegacyTransfers(
    WalletId walletId,
  ) => delegate.listAmbiguousLegacyTransfers(walletId);

  @override
  Future<void> remove(WalletId walletId, String identity) =>
      delegate.remove(walletId, identity);

  @override
  Future<GaslessJournalDiscardOutcome> discardUntraced(
    WalletId walletId,
    String identity,
  ) => delegate.discardUntraced(walletId, identity);

  @override
  Future<void> resolveAmbiguousLegacyTransfers(
    WalletId walletId, {
    required Map<String, Set<String>> ownedSourceAddressesByAsset,
  }) => delegate.resolveAmbiguousLegacyTransfers(
    walletId,
    ownedSourceAddressesByAsset: ownedSourceAddressesByAsset,
  );

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
const _hdWallet = WalletId(
  name: 'wallet',
  pubkeyHash: 'wallet-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
);
const _otherWallet = WalletId(
  name: 'other-wallet',
  pubkeyHash: 'other-wallet-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _unverifiedWallet = WalletId(
  name: 'wallet',
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
  'gasless': {'enabled': true},
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
  Map<String, dynamic>? hdFrom,
  DateTime? createdAt,
  int? authorizationDeadline,
  String authorizationMaxFee = '5000000',
  String feeMethod = 'gasless',
  String providerName = 'gasfree',
  String transferFee = '2',
  String? activationFee,
  String totalTokenFee = '2',
  String signedMaxFee = '5',
  String resultCoin = _coin,
  String? txHash,
  String? txHex,
}) {
  final amount = Decimal.parse('5');
  final resolvedCreatedAt = (createdAt ?? DateTime.now()).toUtc();
  final resolvedDeadline =
      authorizationDeadline ??
      resolvedCreatedAt
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
  return WithdrawResult(
    txHex: txHex,
    txJson: {
      'relay_type': TronGasfreeRelayPayload.relayTypeValue,
      'chain_id': chainId,
      'coin': _coin,
      if (hdFrom != null) 'hd_from': hdFrom,
      'from_address': _sourceAddress,
      'gasfree_address': _custodyAddress,
      'verifying_contract': verifyingContract,
      'signed_authorization': {
        'token': _tokenContract,
        'service_provider': _providerAddress,
        'user': _sourceAddress,
        'receiver': _destinationAddress,
        'value': '5000000',
        'max_fee': authorizationMaxFee,
        'deadline': '$resolvedDeadline',
        'version': '1',
        'nonce': '9',
        'sig': _signature,
      },
      'created_at': resolvedCreatedAt.toIso8601String(),
    },
    txHash: txHash,
    from: const [_sourceAddress],
    to: const [_destinationAddress],
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-7'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('7'),
      totalAmount: amount,
    ),
    blockHeight: 0,
    timestamp:
        resolvedCreatedAt.millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond,
    fee: FeeInfo.tronGasless(
      coin: _coin,
      feeMethod: feeMethod,
      providerName: providerName,
      gasfreeAddress: _custodyAddress,
      transferFee: Decimal.parse(transferFee),
      activationFee: activationFee == null
          ? null
          : Decimal.parse(activationFee),
      totalTokenFee: Decimal.parse(totalTokenFee),
      signedMaxFee: Decimal.parse(signedMaxFee),
    ),
    coin: resultCoin,
  );
}

WithdrawalPreview _standardPreview({
  String? txHex = 'deadbeef',
  Map<String, dynamic>? txJson,
}) => WithdrawResult(
  txHex: txHex,
  txJson: txJson,
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
  final authorizationDeadline =
      DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;
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
    authorizationDeadline: BigInt.from(authorizationDeadline),
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
  'error': 'GasFree endpoint error',
  'error_type': errorType,
  'error_data': _coin,
};

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<String, Set<String>>{});
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
    late List<StreamController<KdfEvent>> defaultTraceStreams;

    setUp(() {
      client = _MockApiClient();
      assetProvider = _MockAssetProvider();
      feeManager = _MockFeeManager();
      activationCoordinator = _MockActivationCoordinator();
      legacyManager = _MockLegacyWithdrawalManager();
      eventStreamingManager = _MockEventStreamingManager();
      defaultTraceStreams = <StreamController<KdfEvent>>[];
      pendingRepository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );

      final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
      trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});
      gaslessCapabilities = GaslessCapabilityRegistry(
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
      when(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).thenAnswer((_) async {
        final stream = StreamController<KdfEvent>();
        defaultTraceStreams.add(stream);
        return stream.stream.listen(null);
      });
    });

    tearDown(() async {
      for (final stream in defaultTraceStreams) {
        if (!stream.isClosed) await stream.close();
      }
    });

    WithdrawalManager makeManager({
      EventStreamingManager? streams,
      bool includeStreams = true,
      PendingGaslessTransferRepository? repository,
      GaslessCapabilityRegistry? capabilities,
      Future<Set<String>> Function(Asset asset)? freshSourceAddressResolver,
      Future<WalletId?> Function()? walletResolver,
      Stream<KdfUser?>? authStateChanges,
    }) => WithdrawalManager(
      client,
      assetProvider,
      feeManager,
      activationCoordinator,
      legacyManager,
      gaslessCapabilities: capabilities ?? gaslessCapabilities,
      pendingGaslessTransfers: repository ?? pendingRepository,
      eventStreamingManager: includeStreams
          ? streams ?? eventStreamingManager
          : null,
      freshSourceAddressResolver: freshSourceAddressResolver,
      walletIdResolver: walletResolver ?? () async => _wallet,
      authStateChanges: authStateChanges,
    );

    test(
      'forwards the KDF relay domain without a generic network allowlist',
      () async {
        const alternateChainId = '9876543210';
        const alternateVerifier = 'TQghdCeVDA6CnuNVTUhfaAyPfTetqZWNpm';
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return switch (request['method']) {
            'send_raw_transaction' => {
              'relay_type': TronGasfreeRelayPayload.relayTypeValue,
              'trace_id': 'trace-alternate-domain',
              'state': 'WAITING',
            },
            'gasless::trace_status' => _traceStatus(state: 'confirmed'),
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });

        final progress = await makeManager()
            .executeWithdrawal(
              _gaslessPreview(
                chainId: alternateChainId,
                verifyingContract: alternateVerifier,
              ),
              _coin,
            )
            .toList();

        final send = requests.singleWhere(
          (request) => request['method'] == 'send_raw_transaction',
        );
        final payload = send['tx_json'] as Map<String, dynamic>;
        expect(payload['chain_id'], alternateChainId);
        expect(payload['verifying_contract'], alternateVerifier);
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    for (final invalidFee in const [
      (transferFee: '-1', activationFee: null, totalTokenFee: '-1'),
      (transferFee: '2', activationFee: '1', totalTokenFee: '2'),
      (transferFee: '2', activationFee: null, totalTokenFee: '6'),
    ]) {
      test('rejects an invalid GasFree fee breakdown $invalidFee', () async {
        await expectLater(
          makeManager(streams: eventStreamingManager)
              .executeWithdrawal(
                _gaslessPreview(
                  transferFee: invalidFee.transferFee,
                  activationFee: invalidFee.activationFee,
                  totalTokenFee: invalidFee.totalTokenFee,
                ),
                _coin,
              )
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.source,
              'source',
              isA<GaslessTransferException>().having(
                (error) => error.code,
                'code',
                GaslessTransferErrorCode.invalidSignedPreview,
              ),
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      });
    }

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

        final accepted = progress.firstWhere(
          (item) =>
              item.submission?.traceId == 'trace-accepted' &&
              item.gaslessState == null,
        );
        expect(accepted.submission?.journalId, isNotEmpty);
        expect(accepted.withdrawalResult?.txHash, isNull);
        expect(accepted.withdrawalResult?.confirmationBlockHeight, isNull);
        expect(accepted.withdrawalResult?.confirmedAt, isNull);
        final result = progress.last;
        expect(result.status, WithdrawalStatus.complete);
        expect(result.withdrawalResult?.txHash, 'on-chain-hash');
        expect(result.withdrawalResult?.gaslessFinalFee, Decimal.parse('1.5'));
        expect(result.withdrawalResult?.gaslessTraceId, 'trace-accepted');
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'terminal stream poll error exits live tracking and reconciles once',
      () async {
        final events = StreamController<KdfEvent>();
        final recordingRepository = _RecordingPendingGaslessTransferRepository(
          pendingRepository,
        );
        var traceQueries = 0;
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
                    error:
                        'network down; stopped polling after 200 consecutive '
                        'trace status errors',
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
            'gasless::trace_status' => () {
              traceQueries++;
              return traceQueries == 1
                  ? _traceStatus(state: 'on_chain', txHash: 'monotonic-hash')
                  : _traceStatus(
                      state: 'confirmed',
                      txHash: 'monotonic-hash',
                      blockHeight: 321,
                      confirmedAt: 1784894400,
                      finalFee: '1.25',
                    );
            }(),
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
        expect(traceQueries, 2);
        final onChainIndex = progress.indexWhere(
          (item) => item.gaslessState == GaslessTraceState.onChain,
        );
        expect(onChainIndex, greaterThanOrEqualTo(0));
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

    test('terminal stream poll error retains the journal when status is '
        'unavailable', () async {
      final events = StreamController<KdfEvent>();
      var traceQueries = 0;
      when(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).thenAnswer((_) async => events.stream.listen(null));
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        return switch (request['method']) {
          'send_raw_transaction' => () {
            events.add(
              const GaslessTraceErrorEvent(
                coin: _coin,
                traceId: 'trace-poll-limit',
                error:
                    'network down; stopped polling after 200 consecutive '
                    'trace status errors',
              ),
            );
            return {
              'relay_type': TronGasfreeRelayPayload.relayTypeValue,
              'trace_id': 'trace-poll-limit',
              'state': 'WAITING',
            };
          }(),
          'gasless::trace_status' => () {
            traceQueries++;
            if (traceQueries == 1) return _traceStatus();
            throw StateError('status unavailable');
          }(),
          _ => throw StateError('Unexpected RPC ${request['method']}'),
        };
      });

      final progress = await makeManager(streams: eventStreamingManager)
          .executeWithdrawal(_gaslessPreview(), _coin)
          .toList()
          .timeout(const Duration(seconds: 2));
      await events.close();

      expect(traceQueries, 2);
      expect(progress.last.status, WithdrawalStatus.inProgress);
      expect(
        progress.last.gaslessTransferState,
        GaslessTransferState.submittedPending,
      );
      final retained = await pendingRepository.list(_wallet);
      expect(retained, hasLength(1));
      expect(retained.single.traceId, 'trace-poll-limit');
      expect(retained.single.state, GaslessTransferState.submittedPending);
    });

    test(
      'malformed streamed fee falls back to one exact trace-status read',
      () async {
        final events = StreamController<KdfEvent>();
        final firstTraceQuerySeen = Completer<void>();
        var traceQueries = 0;
        when(
          () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
        ).thenAnswer((_) async => events.stream.listen(null));
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          return switch (request['method']) {
            'send_raw_transaction' => {
              'relay_type': TronGasfreeRelayPayload.relayTypeValue,
              'trace_id': 'trace-malformed-stream',
              'state': 'WAITING',
            },
            'gasless::trace_status' => () {
              traceQueries++;
              if (traceQueries == 1) {
                firstTraceQuerySeen.complete();
                return _traceStatus();
              }
              return _traceStatus(state: 'confirmed', finalFee: '1');
            }(),
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });

        final progressFuture = makeManager(
          streams: eventStreamingManager,
        ).executeWithdrawal(_gaslessPreview(), _coin).toList();
        await firstTraceQuerySeen.future;
        events.add(
          const GaslessTraceEvent(
            coin: _coin,
            traceId: 'trace-malformed-stream',
            state: GaslessTraceEventState.confirmed,
            finalFee: 'not-a-decimal',
          ),
        );

        final progress = await progressFuture.timeout(
          const Duration(seconds: 2),
        );
        await events.close();

        expect(traceQueries, 2);
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(progress.last.withdrawalResult?.gaslessFinalFee, Decimal.one);
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

    test(
      'missing trace manager blocks before relay and clears reserve',
      () async {
        await expectLater(
          makeManager(
            includeStreams: false,
          ).executeWithdrawal(_gaslessPreview(), _coin).toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.source,
              'source',
              isA<GaslessTransferException>()
                  .having(
                    (error) => error.code,
                    'code',
                    GaslessTransferErrorCode.traceUnavailable,
                  )
                  .having(
                    (error) => error.stage,
                    'stage',
                    GaslessTransferStage.submission,
                  )
                  .having((error) => error.retryable, 'retryable', isTrue)
                  .having((error) => error.terminal, 'terminal', isFalse),
            ),
          ),
        );

        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test('stream attachment failure blocks before relay', () async {
      when(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).thenThrow(StateError('streaming is unavailable'));

      await expectLater(
        makeManager(
          streams: eventStreamingManager,
        ).executeWithdrawal(_gaslessPreview(), _coin).toList(),
        throwsA(
          isA<SdkError>().having(
            (error) => error.source,
            'source',
            isA<GaslessTransferException>()
                .having(
                  (error) => error.stage,
                  'stage',
                  GaslessTransferStage.submission,
                )
                .having((error) => error.retryable, 'retryable', isTrue)
                .having((error) => error.terminal, 'terminal', isFalse),
          ),
        ),
      );

      verify(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).called(1);
      verifyNever(() => client.executeRpc(any()));
      expect(await pendingRepository.list(_wallet), isEmpty);
    });

    for (final fixture in const [
      (
        type: GaslessTraceStreamingRequestErrorType.enableError,
        code: GaslessTransferErrorCode.traceStreamEnableError,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: true,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStreamingRequestErrorType.coinNotFound,
        code: GaslessTransferErrorCode.coinNotFound,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStreamingRequestErrorType.coinNotSupported,
        code: GaslessTransferErrorCode.coinNotSupported,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_token_unsupported',
      ),
      (
        type: GaslessTraceStreamingRequestErrorType.gaslessNotConfigured,
        code: GaslessTransferErrorCode.gaslessNotConfigured,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStreamingRequestErrorType.internal,
        code: GaslessTransferErrorCode.traceStreamInternal,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
    ]) {
      test(
        'maps exact trace-stream enable error ${fixture.type.wireValue}',
        () async {
          when(
            () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
          ).thenThrow(
            GaslessTraceStreamingRequestException(
              type: fixture.type,
              message: 'KDF trace-stream enable error',
            ),
          );

          await expectLater(
            makeManager(
              streams: eventStreamingManager,
            ).executeWithdrawal(_gaslessPreview(), _coin).toList(),
            throwsA(
              isA<SdkError>().having(
                (error) => error.source,
                'source',
                isA<GaslessTransferException>()
                    .having((error) => error.code, 'code', fixture.code)
                    .having((error) => error.kind, 'kind', fixture.kind)
                    .having(
                      (error) => error.stage,
                      'stage',
                      GaslessTransferStage.submission,
                    )
                    .having(
                      (error) => error.localizationKey,
                      'localizationKey',
                      fixture.localizationKey,
                    )
                    .having(
                      (error) => error.retryable,
                      'retryable',
                      fixture.retryable,
                    )
                    .having((error) => error.terminal, 'terminal', isFalse),
              ),
            ),
          );

          verify(
            () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
          ).called(1);
          verifyNever(() => client.executeRpc(any()));
          expect(await pendingRepository.list(_wallet), isEmpty);
        },
      );
    }

    test('stream disconnect before relay blocks and clears reserve', () async {
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
                  (error) => error.stage,
                  'stage',
                  GaslessTransferStage.submission,
                )
                .having((error) => error.retryable, 'retryable', isTrue)
                .having((error) => error.terminal, 'terminal', isFalse),
          ),
        ),
      );

      verify(
        () => eventStreamingManager.subscribeToGaslessTrace(coin: _coin),
      ).called(1);
      verifyNever(() => client.executeRpc(any()));
      expect(await pendingRepository.list(_wallet), isEmpty);
    });

    test('fixed KDF failure reason remains internal to progress', () async {
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
            failureReason: 'unknown',
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
      expect(failure.message, 'Gas-free transfer failed');
      expect(
        (failure.sdkError?.source as GaslessTransferException).code,
        GaslessTransferErrorCode.relayFailedFinal,
      );
      expect(failure.toString(), isNot(contains('failure_reason')));
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
      'confirmed trace remains terminal when timestamp is not representable',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async =>
              _traceStatus(state: 'confirmed', confirmedAt: 8640000000001),
        );

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        expect(progress.last.status, WithdrawalStatus.complete);
        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.confirmed,
        );
        expect(progress.last.withdrawalResult?.confirmedAt, isNull);
        expect(progress.last.withdrawalResult?.txHash, isNull);
        expect(progress.last.withdrawalResult?.gaslessFinalFee, isNull);
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );

    test(
      'negative optional confirmation timestamp stays recoverable',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => _traceStatus(state: 'confirmed', confirmedAt: -1),
        );

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        expect(progress.last.status, WithdrawalStatus.inProgress);
        expect(
          progress.last.gaslessTransferState,
          GaslessTransferState.submittedPending,
        );
        expect(
          (progress.last.sdkError?.source as GaslessTransferException).code,
          GaslessTransferErrorCode.responseMismatch,
        );
        expect(
          await pendingRepository.findByTraceId(_wallet, 'trace-recovery'),
          isNotNull,
        );
      },
    );

    for (final fixture in const [
      (
        type: GaslessTraceStatusErrorType.traceNotFound,
        code: GaslessTransferErrorCode.traceNotFound,
        kind: GaslessTransferErrorKind.invalidTrace,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      ),
      (
        type: GaslessTraceStatusErrorType.invalidTraceId,
        code: GaslessTransferErrorCode.invalidTraceId,
        kind: GaslessTransferErrorKind.invalidTrace,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      ),
      (
        type: GaslessTraceStatusErrorType.coinNotFound,
        code: GaslessTransferErrorCode.coinNotFound,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStatusErrorType.notEthCoin,
        code: GaslessTransferErrorCode.notEthCoin,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStatusErrorType.coinNotSupported,
        code: GaslessTransferErrorCode.coinNotSupported,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_token_unsupported',
      ),
      (
        type: GaslessTraceStatusErrorType.gaslessNotConfigured,
        code: GaslessTransferErrorCode.gaslessNotConfigured,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessTraceStatusErrorType.providerError,
        code: GaslessTransferErrorCode.providerError,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: true,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
      ),
      (
        type: GaslessTraceStatusErrorType.internalError,
        code: GaslessTransferErrorCode.internalError,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
      ),
    ]) {
      test('maps exact trace-status error ${fixture.type.wireValue}', () async {
        await pendingRepository.upsert(_wallet, _pending());
        when(() => client.executeRpc(any())).thenThrow(
          GaslessTraceStatusException(
            type: fixture.type,
            message: 'KDF trace status error',
          ),
        );

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        final source =
            progress.last.sdkError!.source! as GaslessTransferException;
        expect(source.code, fixture.code);
        expect(source.kind, fixture.kind);
        expect(source.stage, GaslessTransferStage.status);
        expect(source.localizationKey, fixture.localizationKey);
        expect(source.retryable, fixture.retryable);
        expect(source.terminal, isFalse);
        expect(source.traceId, 'trace-recovery');
        expect(progress.last.status, WithdrawalStatus.inProgress);
        final retained = await pendingRepository.findByTraceId(
          _wallet,
          'trace-recovery',
        );
        expect(retained?.state, GaslessTransferState.submittedPending);
      });
    }

    test(
      'trace timeout only advertises status reconciliation as retryable',
      () async {
        await pendingRepository.upsert(_wallet, _pending());
        when(
          () => client.executeRpc(any()),
        ).thenThrow(TimeoutException('trace status timed out'));

        final progress = await makeManager()
            .resumePendingGaslessTransfer('trace-recovery')
            .toList();

        final source =
            progress.last.sdkError!.source! as GaslessTransferException;
        expect(source.code, GaslessTransferErrorCode.providerTimeout);
        expect(source.stage, GaslessTransferStage.status);
        expect(source.retryable, isTrue);
        expect(source.terminal, isFalse);
        expect(
          await pendingRepository.findByTraceId(_wallet, 'trace-recovery'),
          isNotNull,
        );
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
          isA<GaslessTransferException>()
              .having(
                (error) => error.code,
                'code',
                GaslessTransferErrorCode.traceUnavailable,
              )
              .having((error) => error.retryable, 'retryable', isFalse)
              .having((error) => error.terminal, 'terminal', isFalse),
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
      'journal paths report capability-not-ready before unverified access',
      () async {
        final repository = _MockPendingGaslessTransferRepository();
        final manager = makeManager(
          repository: repository,
          walletResolver: () async => _unverifiedWallet,
        );
        final capabilityError = isA<GaslessTransferException>()
            .having(
              (error) => error.kind,
              'kind',
              GaslessTransferErrorKind.capabilityNotReady,
            )
            .having((error) => error.retryable, 'retryable', isTrue)
            .having((error) => error.terminal, 'terminal', isFalse);

        await expectLater(
          manager.listPendingGaslessTransfers(),
          throwsA(capabilityError),
        );
        await expectLater(
          manager.watchPendingGaslessTransfers().toList(),
          throwsA(capabilityError),
        );
        await expectLater(
          manager.resumePendingGaslessTransfer('trace-unverified').toList(),
          throwsA(capabilityError),
        );

        verifyNever(
          () => repository.listAmbiguousLegacyTransfers(_unverifiedWallet),
        );
        verifyNever(() => repository.list(_unverifiedWallet));
        verifyNever(() => repository.watch(_unverifiedWallet));
        verifyNever(
          () => repository.find(_unverifiedWallet, 'trace-unverified'),
        );
      },
    );

    test(
      'proves legacy journal source ownership with fresh KDF addresses',
      () async {
        final repository = _MockPendingGaslessTransferRepository();
        final pending = _pending();
        Map<String, Set<String>>? ownershipProof;
        when(
          () => repository.listAmbiguousLegacyTransfers(_wallet),
        ).thenAnswer((_) async => [pending]);
        when(
          () => repository.resolveAmbiguousLegacyTransfers(
            _wallet,
            ownedSourceAddressesByAsset: any(
              named: 'ownedSourceAddressesByAsset',
            ),
          ),
        ).thenAnswer((invocation) async {
          ownershipProof =
              invocation.namedArguments[#ownedSourceAddressesByAsset]
                  as Map<String, Set<String>>;
        });
        when(() => repository.list(_wallet)).thenAnswer((_) async => [pending]);

        final transfers = await makeManager(
          repository: repository,
          freshSourceAddressResolver: (asset) async {
            expect(asset.id.id, _coin);
            return const {'  $_sourceAddress  ', ''};
          },
        ).listPendingGaslessTransfers();

        expect(transfers, [pending]);
        expect(ownershipProof, {
          _coin: {_sourceAddress},
        });
        verify(() => repository.list(_wallet)).called(1);
      },
    );

    test(
      'legacy journal remains blocked when fresh ownership proof fails',
      () async {
        final repository = _MockPendingGaslessTransferRepository();
        when(
          () => repository.listAmbiguousLegacyTransfers(_wallet),
        ).thenAnswer((_) async => [_pending()]);

        await expectLater(
          makeManager(
            repository: repository,
            freshSourceAddressResolver: (_) async =>
                throw StateError('fresh KDF pubkeys unavailable'),
          ).listPendingGaslessTransfers(),
          throwsA(isA<GaslessTransferLegacyResolutionException>()),
        );

        verifyNever(
          () => repository.resolveAmbiguousLegacyTransfers(
            _wallet,
            ownedSourceAddressesByAsset: any(
              named: 'ownedSourceAddressesByAsset',
            ),
          ),
        );
        verifyNever(() => repository.list(_wallet));
      },
    );

    test(
      'wallet switch during fresh legacy proof cannot resolve the journal',
      () async {
        final repository = _MockPendingGaslessTransferRepository();
        final resolverStarted = Completer<void>();
        final resolverResult = Completer<Set<String>>();
        var currentWallet = _wallet;
        when(
          () => repository.listAmbiguousLegacyTransfers(_wallet),
        ).thenAnswer((_) async => [_pending()]);
        final result = makeManager(
          repository: repository,
          walletResolver: () async => currentWallet,
          freshSourceAddressResolver: (_) {
            resolverStarted.complete();
            return resolverResult.future;
          },
        ).listPendingGaslessTransfers();

        await resolverStarted.future;
        currentWallet = _otherWallet;
        resolverResult.complete(const {_sourceAddress});

        await expectLater(
          result,
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        verifyNever(
          () => repository.resolveAmbiguousLegacyTransfers(
            _wallet,
            ownedSourceAddressesByAsset: any(
              named: 'ownedSourceAddressesByAsset',
            ),
          ),
        );
        verifyNever(() => repository.list(_wallet));
      },
    );

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
      'same-name hash downgrade invalidates A work before B enrichment',
      () async {
        const nameOnlyWallet = WalletId(
          name: 'wallet',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        );
        const replacementWallet = WalletId(
          name: 'wallet',
          pubkeyHash: 'replacement-wallet-hash',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        );
        await pendingRepository.upsert(_wallet, _pending());
        var currentWallet = _wallet;
        final authChanges = StreamController<KdfUser?>(sync: true);
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
        expect(gaslessCapabilities.isReady(trc20Asset.id), isTrue);
        final capabilityGeneration = gaslessCapabilities.sessionGeneration;

        currentWallet = nameOnlyWallet;
        authChanges.add(
          const KdfUser(walletId: nameOnlyWallet, isBip39Seed: false),
        );

        await done.future.timeout(const Duration(seconds: 2));
        expect(snapshots.first, hasLength(1));
        expect(snapshots.last, isEmpty);
        expect(gaslessCapabilities.sessionGeneration, capabilityGeneration + 1);
        expect(gaslessCapabilities.isReady(trc20Asset.id), isFalse);

        currentWallet = replacementWallet;
        authChanges.add(
          const KdfUser(walletId: replacementWallet, isBip39Seed: false),
        );

        expect(await manager.listPendingGaslessTransfers(), isEmpty);
        expect(await pendingRepository.list(_wallet), hasLength(1));
        expect(await pendingRepository.list(replacementWallet), isEmpty);
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

    for (final fixture in const [
      (
        type: GaslessAccountStatusErrorType.providerIdentityMismatch,
        code: GaslessTransferErrorCode.serviceProviderMismatch,
        kind: GaslessTransferErrorKind.providerResponse,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      ),
      (
        type: GaslessAccountStatusErrorType.gasfreeAddressMismatch,
        code: GaslessTransferErrorCode.custodyAddressMismatch,
        kind: GaslessTransferErrorKind.providerResponse,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      ),
      (
        type: GaslessAccountStatusErrorType.tokenDecimalMismatch,
        code: GaslessTransferErrorCode.tokenDecimalMismatch,
        kind: GaslessTransferErrorKind.providerResponse,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      ),
      (
        type: GaslessAccountStatusErrorType.coinNotFound,
        code: GaslessTransferErrorCode.coinNotFound,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessAccountStatusErrorType.notEthCoin,
        code: GaslessTransferErrorCode.notEthCoin,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessAccountStatusErrorType.coinNotSupported,
        code: GaslessTransferErrorCode.coinNotSupported,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_token_unsupported',
      ),
      (
        type: GaslessAccountStatusErrorType.gaslessNotConfigured,
        code: GaslessTransferErrorCode.gaslessNotConfigured,
        kind: GaslessTransferErrorKind.configuration,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      ),
      (
        type: GaslessAccountStatusErrorType.tronRpcUnavailable,
        code: GaslessTransferErrorCode.tronRpcUnavailable,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: true,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
      ),
      (
        type: GaslessAccountStatusErrorType.providerError,
        code: GaslessTransferErrorCode.providerError,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: true,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
      ),
      (
        type: GaslessAccountStatusErrorType.internalError,
        code: GaslessTransferErrorCode.internalError,
        kind: GaslessTransferErrorKind.traceUnavailable,
        retryable: false,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
      ),
    ]) {
      test(
        'maps exact account-status error ${fixture.type.wireValue}',
        () async {
          when(
            () => client.executeRpc(any()),
          ).thenAnswer((_) async => _errorEnvelope(fixture.type.wireValue));

          await expectLater(
            makeManager().gaslessAccountStatus(trc20Asset.id),
            throwsA(
              isA<GaslessTransferException>()
                  .having((error) => error.code, 'code', fixture.code)
                  .having((error) => error.kind, 'kind', fixture.kind)
                  .having(
                    (error) => error.retryable,
                    'retryable',
                    fixture.retryable,
                  )
                  .having(
                    (error) => error.terminal,
                    'terminal',
                    !fixture.retryable,
                  )
                  .having(
                    (error) => error.localizationKey,
                    'localizationKey',
                    fixture.localizationKey,
                  ),
            ),
          );
        },
      );
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
      'untyped GasFree preview failure stays generic without text inference',
      () async {
        const untypedError =
            'insufficient funds with invalid address and fee failure';
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 10},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {'status': 'Error', 'details': untypedError},
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
                .having((error) => error.code, 'code', SdkErrorCode.general)
                .having(
                  (error) => error.source,
                  'source',
                  isA<WithdrawalException>()
                      .having(
                        (source) => source.code,
                        'code',
                        WithdrawalErrorCode.unknownError,
                      )
                      .having(
                        (source) => source.message,
                        'message',
                        'GasFree withdrawal preview failed',
                      ),
                )
                .having(
                  (error) => error.fallbackMessage,
                  'fallbackMessage',
                  isNot(contains(untypedError)),
                ),
          ),
        );
      },
    );

    test(
      'rejects a GasFree response for an explicit Standard request',
      () async {
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 21},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': _gaslessPreview().toJson()},
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
              feeMethod: WithdrawalFeeMethod.native,
            ),
          ),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.responseMismatch.name,
            ),
          ),
        );
      },
    );

    test('rejects a negative GasFree max fee before invoking KDF', () async {
      await expectLater(
        makeManager().previewWithdrawal(
          WithdrawParameters(
            asset: _coin,
            toAddress: _destinationAddress,
            amount: Decimal.parse('5'),
            feeMethod: WithdrawalFeeMethod.gasless,
            gaslessOptions: GaslessWithdrawalOptions(
              maxFee: Decimal.parse('-0.1'),
            ),
          ),
        ),
        throwsA(
          isA<SdkError>().having(
            (error) => error.context?.extra['gaslessCode'],
            'gaslessCode',
            GaslessTransferErrorCode.configurationInvalid.name,
          ),
        ),
      );
      verifyNever(() => client.executeRpc(any()));
    });

    for (final deadlineSeconds in const [0, -1]) {
      test(
        'rejects deadline_seconds $deadlineSeconds before invoking KDF',
        () async {
          await expectLater(
            makeManager().previewWithdrawal(
              WithdrawParameters(
                asset: _coin,
                toAddress: _destinationAddress,
                amount: Decimal.parse('5'),
                feeMethod: WithdrawalFeeMethod.gasless,
                gaslessOptions: GaslessWithdrawalOptions(
                  deadlineSeconds: deadlineSeconds,
                ),
              ),
            ),
            throwsA(
              isA<SdkError>().having(
                (error) => error.context?.extra['gaslessCode'],
                'gaslessCode',
                GaslessTransferErrorCode.configurationInvalid.name,
              ),
            ),
          );
          verifyNever(() => client.executeRpc(any()));
        },
      );
    }

    for (final feeFixture in const [
      (label: 'fee_method case', feeMethod: 'Gasless', providerName: 'gasfree'),
      (label: 'provider_name', feeMethod: 'gasless', providerName: 'gas_free'),
    ]) {
      test('rejects an inexact KDF ${feeFixture.label}', () async {
        await expectLater(
          makeManager()
              .executeWithdrawal(
                _gaslessPreview(
                  feeMethod: feeFixture.feeMethod,
                  providerName: feeFixture.providerName,
                ),
                _coin,
              )
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.invalidSignedPreview.name,
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      });
    }

    for (final previewFixture in [
      (
        label: 'result coin',
        preview: _gaslessPreview(resultCoin: 'OTHER-TRC20'),
      ),
      (label: 'preview transaction hash', preview: _gaslessPreview(txHash: '')),
      (label: 'preview transaction hex', preview: _gaslessPreview(txHex: '00')),
    ]) {
      test('rejects an inexact KDF ${previewFixture.label}', () async {
        await expectLater(
          makeManager()
              .executeWithdrawal(previewFixture.preview, _coin)
              .toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.invalidSignedPreview.name,
            ),
          ),
        );
        verifyNever(() => client.executeRpc(any()));
        expect(await pendingRepository.list(_wallet), isEmpty);
      });
    }

    test(
      'binds the signed fee cap and permit lifetime to the request',
      () async {
        var response = _gaslessPreview();
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 22},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': response.toJson()},
            },
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });
        final manager = makeManager();

        await expectLater(
          manager.previewWithdrawal(
            WithdrawParameters(
              asset: _coin,
              toAddress: _destinationAddress,
              amount: Decimal.parse('5'),
              feeMethod: WithdrawalFeeMethod.gasless,
              gaslessOptions: GaslessWithdrawalOptions(
                maxFee: Decimal.parse('4'),
                deadlineSeconds: 300,
              ),
            ),
          ),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.invalidSignedPreview.name,
            ),
          ),
        );

        final createdAt = DateTime.now().toUtc();
        response = _gaslessPreview(
          createdAt: createdAt,
          authorizationDeadline:
              createdAt
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond,
        );
        await expectLater(
          manager.previewWithdrawal(
            WithdrawParameters(
              asset: _coin,
              toAddress: _destinationAddress,
              amount: Decimal.parse('5'),
              feeMethod: WithdrawalFeeMethod.gasless,
              gaslessOptions: const GaslessWithdrawalOptions(
                deadlineSeconds: 60,
              ),
            ),
          ),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.invalidSignedPreview.name,
            ),
          ),
        );

        // KDF accepts any positive deadline_seconds; the generic SDK must bind
        // the response to the caller's value without inventing a smaller
        // provider maximum.
        response = _gaslessPreview(
          createdAt: createdAt,
          authorizationDeadline:
              createdAt
                  .add(const Duration(minutes: 11))
                  .millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond,
        );
        final longDeadlinePreview = await manager.previewWithdrawal(
          WithdrawParameters(
            asset: _coin,
            toAddress: _destinationAddress,
            amount: Decimal.parse('5'),
            feeMethod: WithdrawalFeeMethod.gasless,
            gaslessOptions: const GaslessWithdrawalOptions(
              deadlineSeconds: 660,
            ),
          ),
        );
        expect(
          longDeadlinePreview.gaslessRelayPayload?.signedAuthorization.deadline,
          response.gaslessRelayPayload?.signedAuthorization.deadline,
        );
      },
    );

    test('accepts KDF zero-fee previews and a zero caller cap', () async {
      final response = _gaslessPreview(
        authorizationMaxFee: '0',
        transferFee: '0',
        totalTokenFee: '0',
        signedMaxFee: '0',
      );
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        return switch (request['method']) {
          'task::withdraw::init' => {
            'mmrpc': '2.0',
            'result': {'task_id': 26},
          },
          'task::withdraw::status' => {
            'mmrpc': '2.0',
            'result': {'status': 'Ok', 'details': response.toJson()},
          },
          _ => throw StateError('Unexpected RPC ${request['method']}'),
        };
      });

      final preview = await makeManager().previewWithdrawal(
        WithdrawParameters(
          asset: _coin,
          toAddress: _destinationAddress,
          amount: Decimal.parse('5'),
          feeMethod: WithdrawalFeeMethod.gasless,
          gaslessOptions: GaslessWithdrawalOptions(
            maxFee: Decimal.zero,
            fallbackToNative: false,
          ),
        ),
      );

      final fee = preview.fee as FeeInfoTronGasless;
      expect(fee.transferFee, Decimal.zero);
      expect(fee.totalTokenFee, Decimal.zero);
      expect(fee.signedMaxFee, Decimal.zero);
      expect(preview.gaslessRelayPayload?.signedAuthorization.maxFee, '0');
    });

    test(
      'supports an exact arbitrary HD selector without a status snapshot',
      () async {
        final source = WithdrawalSource.hdWalletId(
          accountId: 3,
          addressId: 7,
          chain: Bip44Chain.internal,
        );
        final selector = source.toRpcParams();
        final response = _gaslessPreview(hdFrom: selector);
        final requests = <Map<String, dynamic>>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.single as Map<String, dynamic>;
          requests.add(request);
          return switch (request['method']) {
            'task::withdraw::init' => {
              'mmrpc': '2.0',
              'result': {'task_id': 24},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': response.toJson()},
            },
            'send_raw_transaction' => {
              'relay_type': TronGasfreeRelayPayload.relayTypeValue,
              'trace_id': 'trace-arbitrary-hd',
              'state': 'WAITING',
            },
            'gasless::trace_status' => _traceStatus(state: 'confirmed'),
            _ => throw StateError('Unexpected RPC ${request['method']}'),
          };
        });
        final configuredWithoutStatus = GaslessCapabilityRegistry(
          pinnedProviderAddress: _providerAddress,
        );
        final manager = makeManager(
          capabilities: configuredWithoutStatus,
          walletResolver: () async => _hdWallet,
        );
        final parameters = WithdrawParameters(
          asset: _coin,
          toAddress: _destinationAddress,
          amount: Decimal.parse('5'),
          from: source,
          feeMethod: WithdrawalFeeMethod.gasless,
          gaslessOptions: const GaslessWithdrawalOptions(
            fallbackToNative: false,
          ),
        );

        final preview = await manager.previewWithdrawal(parameters);
        final progress = await manager
            .executeWithdrawal(preview, _coin)
            .toList();

        final init = requests.firstWhere(
          (request) => request['method'] == 'task::withdraw::init',
        );
        expect((init['params'] as Map<String, dynamic>)['from'], selector);
        final send = requests.firstWhere(
          (request) => request['method'] == 'send_raw_transaction',
        );
        expect((send['tx_json'] as Map<String, dynamic>)['hd_from'], selector);
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(progress.last.withdrawalResult?.txHash, isNull);
        expect(progress.last.withdrawalResult?.gaslessFinalFee, isNull);
        expect(
          requests.where(
            (request) => request['method'] == 'gasless::account_status',
          ),
          isEmpty,
        );
        expect(await pendingRepository.list(_hdWallet), isEmpty);
      },
    );

    test('rejects a relay HD selector that differs from the request', () async {
      final source = WithdrawalSource.hdWalletId(
        accountId: 3,
        addressId: 7,
        chain: Bip44Chain.internal,
      );
      final response = _gaslessPreview(
        hdFrom: {'account_id': 3, 'address_id': 8, 'chain': 'Internal'},
      );
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        return switch (request['method']) {
          'task::withdraw::init' => {
            'mmrpc': '2.0',
            'result': {'task_id': 25},
          },
          'task::withdraw::status' => {
            'mmrpc': '2.0',
            'result': {'status': 'Ok', 'details': response.toJson()},
          },
          _ => throw StateError('Unexpected RPC ${request['method']}'),
        };
      });

      await expectLater(
        makeManager(walletResolver: () async => _hdWallet).previewWithdrawal(
          WithdrawParameters(
            asset: _coin,
            toAddress: _destinationAddress,
            amount: Decimal.parse('5'),
            from: source,
            feeMethod: WithdrawalFeeMethod.gasless,
            gaslessOptions: const GaslessWithdrawalOptions(
              fallbackToNative: false,
            ),
          ),
        ),
        throwsA(
          isA<SdkError>().having(
            (error) => error.context?.extra['gaslessCode'],
            'gaslessCode',
            GaslessTransferErrorCode.invalidSignedPreview.name,
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
      'deprecated one-call withdrawal lets KDF preflight stale status',
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
              'result': {'task_id': 23},
            },
            'task::withdraw::status' => {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': _gaslessPreview().toJson()},
            },
            'send_raw_transaction' => {
              'relay_type': TronGasfreeRelayPayload.relayTypeValue,
              'trace_id': 'trace-after-stale-status',
              'state': 'WAITING',
            },
            'gasless::trace_status' => _traceStatus(state: 'confirmed'),
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
                  fallbackToNative: false,
                ),
              ),
            )
            .toList();

        expect(progress.last.status, WithdrawalStatus.complete);
        expect(progress.last.submission?.traceId, 'trace-after-stale-status');
        expect(requests.map((request) => request['method']), [
          'task::withdraw::init',
          'task::withdraw::status',
          'send_raw_transaction',
          'gasless::trace_status',
        ]);
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

    test(
      'raw GasFree relay marker cannot select the typed GasFree rail',
      () async {
        final inconsistentPreview = _standardPreview(
          txHex: null,
          txJson: _gaslessPreview().txJson,
        );

        await expectLater(
          makeManager().executeWithdrawal(inconsistentPreview, _coin).toList(),
          throwsA(
            isA<SdkError>().having(
              (error) => error.context?.extra['gaslessCode'],
              'gaslessCode',
              GaslessTransferErrorCode.responseMismatch.name,
            ),
          ),
        );

        verifyNever(() => client.executeRpc(any()));
        verifyNever(
          () => eventStreamingManager.subscribeToGaslessTrace(
            coin: any(named: 'coin'),
          ),
        );
        expect(await pendingRepository.list(_wallet), isEmpty);
      },
    );
  });
}
