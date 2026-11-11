import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_coordinator.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_journal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/withdrawal_auth_fixture.dart';

class _ManagerAssets extends Mock implements IAssetProvider {}

class _ManagerFees extends Mock implements FeeManager {}

class _ManagerActivation extends Mock implements SharedActivationCoordinator {}

class _ManagerClient implements ApiClient {
  final requests = <Map<String, dynamic>>[];
  Future<void> Function(Map<String, dynamic>)? prepareTransport;

  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    await prepareTransport?.call(request);
    RpcDispatchGuard.ensureCurrent(request['method'] as String);
    requests.add(request);
    return switch (request['method']) {
      'withdraw' => {'mmrpc': '2.0', 'result': _preview().toJson()},
      'send_raw_transaction' => {
        'mmrpc': '2.0',
        'result': {'tx_hash': 'AaFreshSignature'},
      },
      _ => throw StateError('Unexpected Solana manager RPC'),
    };
  }
}

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};
  bool failWrite = false;
  bool failDelete = false;
  void Function()? beforeWrite;
  void Function()? beforeDelete;
  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    beforeWrite?.call();
    if (failWrite) throw StateError('storage write failed');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    beforeDelete?.call();
    if (failDelete) throw StateError('storage delete failed');
    values.remove(key);
  }
}

Asset _solana() => Asset.fromJson(const {
  'coin': 'TESTSOL',
  'type': 'SOLANA',
  'fname': 'Solana Devnet',
  'is_testnet': true,
  'decimals': 9,
  'derivation_path': "m/44'/501'",
  'protocol': {'type': 'SOLANA'},
  'nodes': [
    {'url': 'https://api.devnet.solana.com'},
  ],
});

Asset _token({bool token2022 = false}) {
  final platform = _solana();
  return Asset.fromJson(
    {
      'coin': 'TESTUSDC-TESTSOL',
      'type': 'SOLANATOKEN',
      'fname': 'USDC Devnet',
      'parent_coin': 'TESTSOL',
      'is_testnet': true,
      'protocol': {
        'type': 'SOLANATOKEN',
        'protocol_data': {
          'platform': 'TESTSOL',
          'decimals': 6,
          'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
          'program_id': token2022
              ? SolanaTokenProtocol.token2022ProgramId
              : SolanaTokenProtocol.classicTokenProgramId,
        },
      },
    },
    knownIds: {platform.id},
  );
}

WithdrawParameters _params(
  Asset asset, {
  String? amount = '1',
  bool max = false,
  String? memo,
  WithdrawalSource? from,
}) => WithdrawParameters(
  asset: asset.id.id,
  toAddress: 'recipient',
  amount: max ? null : Decimal.parse(amount!),
  isMax: max,
  memo: memo,
  from: from,
);

WithdrawalPreview _preview({
  String coin = 'TESTSOL',
  String hash = 'AaFreshSignature',
  String hex = 'aabb',
  String amount = '1',
  String fee = '0.000005',
  String rent = '0',
  String to = 'recipient',
  String from = 'sender',
  String? memo,
}) => WithdrawResult(
  coin: coin,
  txHash: hash,
  txHex: hex,
  from: [from],
  to: [to],
  balanceChanges: BalanceChanges(
    netChange: -Decimal.parse(amount),
    receivedByMe: Decimal.zero,
    spentByMe: Decimal.parse(amount),
    totalAmount: Decimal.parse(amount),
  ),
  fee: FeeInfo.solana(
    coin: '',
    feeAmount: Decimal.parse(fee),
    rentAmount: Decimal.parse(rent),
    totalAmount: Decimal.parse(fee) + Decimal.parse(rent),
  ),
  blockHeight: 0,
  timestamp: 123,
  memo: memo,
);

void main() {
  const enabled = SolanaCapabilities(enabled: true);
  group('Solana withdrawal contract', () {
    test('fails closed before engine support is enabled', () {
      final asset = _solana();
      expect(
        () => validateSolanaWithdrawal(
          _params(asset),
          asset,
          const SolanaCapabilities(),
        ),
        throwsA(
          isA<SdkError>().having(
            (e) => e.messageKey,
            'capability',
            'withdrawSolanaUnavailable',
          ),
        ),
      );
    });
    test('classic token Max and Token-2022 require separate gates', () {
      final token = _token();
      final token2022 = _token(token2022: true);
      expect(
        () =>
            validateSolanaWithdrawal(_params(token, max: true), token, enabled),
        throwsA(
          isA<SdkError>().having(
            (e) => e.messageKey,
            'max',
            'withdrawSolanaTokenMaxUnavailable',
          ),
        ),
      );
      expect(
        () => validateSolanaWithdrawal(_params(token2022), token2022, enabled),
        throwsA(
          isA<SdkError>().having(
            (e) => e.messageKey,
            'program',
            'withdrawSolanaToken2022Unavailable',
          ),
        ),
      );
      validateSolanaWithdrawal(
        _params(token, max: true),
        token,
        const SolanaCapabilities(enabled: true, splMaxEnabled: true),
      );
      validateSolanaWithdrawal(
        _params(token2022),
        token2022,
        const SolanaCapabilities(enabled: true, token2022Enabled: true),
      );
    });
    test('preserves SOL ninth decimal and fractional SPL precision', () {
      for (final (asset, exact, excessive) in [
        (_solana(), '0.000000001', '0.0000000001'),
        (_token(), '0.000001', '0.0000001'),
      ]) {
        validateSolanaWithdrawal(_params(asset, amount: exact), asset, enabled);
        expect(
          () => validateSolanaWithdrawal(
            _params(asset, amount: excessive),
            asset,
            enabled,
          ),
          throwsA(isA<SdkError>()),
        );
      }
    });
    test('memo boundary counts UTF-8 bytes, not characters', () {
      final asset = _solana();
      validateSolanaWithdrawal(_params(asset, memo: '😀' * 64), asset, enabled);
      validateSolanaWithdrawal(_params(asset, memo: 'é' * 128), asset, enabled);
      expect(
        () => validateSolanaWithdrawal(
          _params(asset, memo: '${'😀' * 64}a'),
          asset,
          enabled,
        ),
        throwsA(
          isA<SdkError>().having(
            (e) => e.code,
            'code',
            SdkErrorCode.invalidMemo,
          ),
        ),
      );
    });
    test(
      'HD withdrawal selectors are refused for the single wallet address',
      () {
        final asset = _solana();
        expect(
          () => validateSolanaWithdrawal(
            _params(
              asset,
              from: WithdrawalSource.hdDerivationPath("m/44'/501'/0'/0'"),
            ),
            asset,
            enabled,
          ),
          throwsA(isA<SdkError>()),
        );
      },
    );
    test('token response fees resolve the devnet platform, not the token', () {
      final token = _token();
      final preview = contextualizeSolanaWithdrawal(
        _preview(coin: token.id.id, rent: '0.00203928'),
        token,
      );
      expect(preview.fee.coin, 'TESTSOL');
      expect(
        (preview.fee as SolanaFeeInfo).rentAmount,
        Decimal.parse('0.00203928'),
      );
      expect(
        () => contextualizeSolanaWithdrawal(_preview(coin: 'OTHER'), token),
        throwsFormatException,
      );
      expect(
        () => contextualizeSolanaWithdrawal(_preview(hash: ''), _solana()),
        throwsFormatException,
      );
    });
  });

  group('Solana durable submission journal', () {
    const wallet = WalletId(
      name: 'wallet',
      pubkeyHash: 'verified',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );
    test(
      'restart and wallet rename retain unknown signature without signed bytes',
      () async {
        final storage = _MemoryStorage();
        final first = SecureSolanaWithdrawalJournal(storage: storage);
        final parameters = _params(_solana());
        final preview = contextualizeSolanaWithdrawal(
          _preview(hex: 'signed-secret-bytes'),
          _solana(),
        );
        expect(await first.reserve(wallet, parameters, preview), isNull);
        expect(
          storage.values.values.single,
          isNot(contains('signed-secret-bytes')),
        );
        final restarted = SecureSolanaWithdrawalJournal(storage: storage);
        const renamed = WalletId(
          name: 'renamed',
          pubkeyHash: 'verified',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        );
        final found = await restarted.find(renamed, parameters);
        expect(found?.txHash, 'AaFreshSignature');
        expect(found?.fee.coin, 'TESTSOL');
        expect(
          (await restarted.reserve(
            renamed,
            parameters,
            _preview(hash: 'Replacement'),
          ))?.txHash,
          'AaFreshSignature',
        );
        await restarted.clear(renamed, parameters, 'WrongSignature');
        expect(await restarted.find(renamed, parameters), isNotNull);
        await restarted.clear(renamed, parameters, 'AaFreshSignature');
        expect(await restarted.find(renamed, parameters), isNull);
      },
    );
    test(
      'restart normalizes default flags and exact decimal amounts',
      () async {
        final storage = _MemoryStorage();
        final original = WithdrawParameters(
          asset: 'TESTSOL',
          toAddress: 'RecipientBase58',
          amount: Decimal.parse('1.000000000'),
          memo: 'CaseSensitive 🌍',
        );
        final equivalent = WithdrawParameters(
          asset: 'TESTSOL',
          toAddress: 'RecipientBase58',
          amount: Decimal.one,
          isMax: false,
          ibcTransfer: false,
          feeMethod: WithdrawalFeeMethod.native,
          memo: 'CaseSensitive 🌍',
        );
        await SecureSolanaWithdrawalJournal(storage: storage).reserve(
          wallet,
          original,
          contextualizeSolanaWithdrawal(_preview(), _solana()),
        );
        final restarted = SecureSolanaWithdrawalJournal(storage: storage);
        expect(
          (await restarted.find(wallet, equivalent))?.txHash,
          'AaFreshSignature',
        );
        expect(
          (await restarted.reserve(
            wallet,
            equivalent,
            contextualizeSolanaWithdrawal(_preview(hash: 'Other'), _solana()),
          ))?.txHash,
          'AaFreshSignature',
        );
        expect(storage.values, hasLength(1));
        await restarted.clear(wallet, equivalent, 'AaFreshSignature');
        expect(await restarted.find(wallet, original), isNull);
        expect(
          solanaWithdrawalIntentKey(original),
          isNot(
            solanaWithdrawalIntentKey(
              WithdrawParameters(
                asset: original.asset,
                toAddress: 'recipientBase58',
                amount: original.amount,
                memo: original.memo,
              ),
            ),
          ),
        );
        expect(
          solanaWithdrawalIntentKey(original),
          isNot(
            solanaWithdrawalIntentKey(
              WithdrawParameters(
                asset: original.asset,
                toAddress: original.toAddress,
                amount: original.amount,
                memo: 'casesensitive 🌍',
              ),
            ),
          ),
        );
      },
    );
    test('corruption and missing wallet identity fail closed', () async {
      final storage = _MemoryStorage();
      final journal = SecureSolanaWithdrawalJournal(storage: storage);
      final parameters = _params(_solana());
      await journal.reserve(
        wallet,
        parameters,
        contextualizeSolanaWithdrawal(_preview(), _solana()),
      );
      storage.values[storage.values.keys.single] = 'broken';
      await expectLater(journal.find(wallet, parameters), throwsStateError);
      const unknown = WalletId(
        name: 'wallet',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      await expectLater(journal.find(unknown, parameters), throwsStateError);
    });
    test('concurrent reservations preserve one signature', () async {
      final storage = _MemoryStorage();
      final journal = SecureSolanaWithdrawalJournal(storage: storage);
      final parameters = _params(_solana());
      final results = await Future.wait([
        journal.reserve(
          wallet,
          parameters,
          contextualizeSolanaWithdrawal(_preview(), _solana()),
        ),
        journal.reserve(
          wallet,
          parameters,
          contextualizeSolanaWithdrawal(_preview(hash: 'Other'), _solana()),
        ),
      ]);
      expect(results.first, isNull);
      expect(results.last?.txHash, 'AaFreshSignature');
    });
  });

  group('Solana public withdrawal manager authorization', () {
    for (final method in ['withdraw', 'send_raw_transaction']) {
      test('forwards the caller permit through $method dispatch', () async {
        final asset = _solana();
        const walletId = WalletId(
          name: 'solana',
          pubkeyHash: 'verified-public',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        );
        final auth = WithdrawalAuthFixture(
          walletResolver: () async => walletId,
        );
        final assets = _ManagerAssets();
        when(
          () => assets.findAssetsByConfigId(asset.id.id),
        ).thenReturn({asset});
        final client = _ManagerClient();
        final journal = SecureSolanaWithdrawalJournal(
          storage: _MemoryStorage(),
        );
        final manager = WithdrawalManager(
          client,
          assets,
          _ManagerFees(),
          _ManagerActivation(),
          LegacyWithdrawalManager(client),
          auth: auth,
          solanaCapabilities: enabled,
          solanaWithdrawalJournal: journal,
        );
        addTearDown(manager.dispose);
        final parameters = _params(asset);
        final preview = await manager.previewWithdrawal(parameters);
        final preparing = Completer<void>();
        final release = Completer<void>();
        var authorized = true;
        client.prepareTransport = (request) async {
          if (request['method'] == method) {
            preparing.complete();
            await release.future;
          }
        };
        final pending = manager
            .executeWithdrawal(
              preview,
              asset.id.id,
              beforeBroadcast: () {
                if (!authorized) throw StateError('caller permit revoked');
              },
            )
            .toList();
        final assertion = expectLater(
          pending,
          throwsA(
            method == 'withdraw' ? isA<SdkError>() : isA<RpcDispatchRejected>(),
          ),
        );
        await preparing.future;
        authorized = false;
        release.complete();
        await assertion;
        expect(
          client.requests.where(
            (request) => request['method'] == 'send_raw_transaction',
          ),
          isEmpty,
        );
        expect(
          client.requests.where((request) => request['method'] == 'withdraw'),
          hasLength(method == 'withdraw' ? 1 : 2),
        );
        expect(await journal.find(walletId, parameters), isNull);
        authorized = true;
        client.prepareTransport = null;
        final completed = await manager
            .executeWithdrawal(
              preview,
              asset.id.id,
              beforeBroadcast: () {
                if (!authorized) throw StateError('caller permit revoked');
              },
            )
            .toList();
        expect(completed.last.status, WithdrawalStatus.complete);
      });
    }
  });

  group('Solana explicit confirmation', () {
    late SolanaWithdrawalCoordinator coordinator;
    late Asset asset;
    late WithdrawalAuthFixture auth;
    late _MemoryStorage storage;
    late WalletOperationContext wallet;
    late List<WithdrawParameters> requests;
    late List<String> broadcasts;
    late Future<WithdrawalPreview> Function(WithdrawParameters) respond;
    late Future<SendRawTransactionResponse> Function(String, String) submit;
    var rejectLease = false;

    setUp(() async {
      asset = _solana();
      rejectLease = false;
      const walletId = WalletId(
        name: 'solana',
        pubkeyHash: 'hash',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      auth = WithdrawalAuthFixture(walletResolver: () async => walletId);
      wallet = WalletOperationContext(
        walletId: walletId,
        generation: 0,
        session: await auth.captureSessionContext(),
      );
      storage = _MemoryStorage();
      requests = [];
      broadcasts = [];
      respond = (_) async => _preview();
      submit = (_, __) async =>
          SendRawTransactionResponse(mmrpc: '2.0', txHash: 'AaFreshSignature');
      coordinator = SolanaWithdrawalCoordinator(
        capabilities: enabled,
        journal: SecureSolanaWithdrawalJournal(storage: storage),
        createPreview: (params) {
          requests.add(params);
          return respond(params);
        },
        broadcast: (coin, hex) {
          broadcasts.add(hex);
          return submit(coin, hex);
        },
        captureWallet: () async => wallet,
        requireWalletCurrent: (context) async =>
            auth.ensureSessionContextCurrent(context.session),
        ensureSessionCurrent: (context) =>
            auth.ensureSessionContextCurrent(context.session),
        ensureAllowed: (_) {},
        runWithSession: <T>(context, dispatch) async {
          if (rejectLease) throw const AuthSessionChangedException();
          return auth.runWithSession<T>(context.session, dispatch);
        },
      );
    });

    test(
      'unchanged review broadcasts only the freshly signed transaction',
      () async {
        final parameters = _params(asset, amount: '0.000000001', memo: '🌍');
        respond = (_) async => _preview(hex: 'old', hash: 'OldSignature');
        final preview = await coordinator.previewWithdrawal(parameters, asset);
        respond = (_) async => _preview(hex: 'fresh');
        final progress = await coordinator
            .executeWithdrawal(preview, asset)
            .toList();
        expect(broadcasts, ['fresh']);
        expect(requests, [parameters, parameters]);
        expect(requests.last.from, isNull);
        expect(progress.last.withdrawalResult?.txHash, 'AaFreshSignature');
        expect(progress.last.withdrawalResult?.confirmedAt, isNull);
      },
    );

    for (final (label, changed) in <(String, WithdrawalPreview Function())>[
      ('fee', () => _preview(fee: '0.000006')),
      ('rent', () => _preview(rent: '0.00203928')),
      ('amount', () => _preview(amount: '0.9')),
      ('recipient', () => _preview(to: 'other')),
      ('sender', () => _preview(from: 'other')),
      ('memo', () => _preview(memo: 'changed')),
    ]) {
      test('changed $label requires a fresh review before sending', () async {
        final preview = await coordinator.previewWithdrawal(
          _params(asset),
          asset,
        );
        respond = (_) async => changed();
        WithdrawalPreview? refreshed;
        try {
          await coordinator.executeWithdrawal(preview, asset).toList();
        } on SolanaWithdrawalReviewChanged catch (e) {
          refreshed = e.preview;
        }
        expect(refreshed, isNotNull);
        expect(broadcasts, isEmpty);
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(isA<SolanaWithdrawalReviewChanged>()),
        );
        await coordinator.executeWithdrawal(refreshed!, asset).toList();
        expect(broadcasts, ['aabb']);
      });
    }
    test(
      'ambiguous submission retains case-sensitive signature and blocks retry',
      () async {
        final parameters = _params(asset);
        final preview = await coordinator.previewWithdrawal(parameters, asset);
        submit = (_, __) async => throw TimeoutException('lost response');
        final ambiguous = isA<SolanaWithdrawalSubmissionUnknown>().having(
          (e) => e.transactionHash,
          'signature',
          'AaFreshSignature',
        );
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(ambiguous),
        );
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(ambiguous),
        );
        await expectLater(
          coordinator.previewWithdrawal(parameters, asset),
          throwsA(ambiguous),
        );
        expect(broadcasts, hasLength(1));
        expect(requests, hasLength(2));
      },
    );
    test('default variants cannot bypass an ambiguous submission', () async {
      final original = _params(asset);
      final equivalent = WithdrawParameters(
        asset: asset.id.id,
        toAddress: original.toAddress,
        amount: Decimal.parse('1.000'),
        ibcTransfer: false,
        feeMethod: WithdrawalFeeMethod.native,
        memo: '',
      );
      final preview = await coordinator.previewWithdrawal(original, asset);
      submit = (_, __) async => throw TimeoutException('response lost');
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
      );
      await expectLater(
        coordinator.previewWithdrawal(equivalent, asset),
        throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
      );
      expect(broadcasts, hasLength(1));
      expect(requests, hasLength(2));
    });

    test(
      'equivalent concurrent previews share the in-memory reservation',
      () async {
        final original = _params(asset);
        final equivalent = WithdrawParameters(
          asset: asset.id.id,
          toAddress: original.toAddress,
          amount: Decimal.parse('1.0'),
          ibcTransfer: false,
        );
        final firstPreview = await coordinator.previewWithdrawal(
          original,
          asset,
        );
        final secondPreview = await coordinator.previewWithdrawal(
          equivalent,
          asset,
        );
        final refresh = Completer<WithdrawalPreview>();
        final started = Completer<void>();
        respond = (_) {
          if (!started.isCompleted) started.complete();
          return refresh.future;
        };
        final first = coordinator
            .executeWithdrawal(firstPreview, asset)
            .toList();
        await started.future;
        await expectLater(
          coordinator.executeWithdrawal(secondPreview, asset).toList(),
          throwsStateError,
        );
        expect(requests, hasLength(3));
        refresh.complete(_preview());
        await first;
        expect(broadcasts, hasLength(1));
      },
    );
    test('concurrent and repeated confirmations cannot double-send', () async {
      final preview = await coordinator.previewWithdrawal(
        _params(asset),
        asset,
      );
      final response = Completer<WithdrawalPreview>();
      final started = Completer<void>();
      respond = (_) {
        started.complete();
        return response.future;
      };
      final first = coordinator.executeWithdrawal(preview, asset).toList();
      await started.future;
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsStateError,
      );
      response.complete(_preview());
      await first;
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
      );
      expect(broadcasts, hasLength(1));
    });
    test(
      'canceling before refresh releases the intent for later confirmation',
      () async {
        final preview = await coordinator.previewWithdrawal(
          _params(asset),
          asset,
        );
        final confirmation = StreamIterator(
          coordinator.executeWithdrawal(preview, asset),
        );
        expect(await confirmation.moveNext(), isTrue);
        await confirmation.cancel();
        // Browser Web Lock release callbacks run through the event queue.
        await Future<void>.delayed(Duration.zero);
        expect(requests, hasLength(1));
        expect(broadcasts, isEmpty);
        expect(storage.values, isEmpty);
        final progress = await coordinator
            .executeWithdrawal(preview, asset)
            .toList();
        expect(progress.last.status, WithdrawalStatus.complete);
        expect(requests, hasLength(2));
        expect(broadcasts, hasLength(1));
      },
    );
    test(
      'overlapping managers cannot send again after the first succeeds',
      () async {
        final other = SolanaWithdrawalCoordinator(
          capabilities: enabled,
          journal: SecureSolanaWithdrawalJournal(storage: storage),
          createPreview: coordinator.createPreview,
          broadcast: coordinator.broadcast,
          captureWallet: coordinator.captureWallet,
          requireWalletCurrent: coordinator.requireWalletCurrent,
          ensureSessionCurrent: coordinator.ensureSessionCurrent,
          ensureAllowed: coordinator.ensureAllowed,
          runWithSession: coordinator.runWithSession,
        );
        final firstPreview = await coordinator.previewWithdrawal(
          _params(asset),
          asset,
        );
        final otherPreview = await other.previewWithdrawal(
          _params(asset),
          asset,
        );
        final firstRefresh = Completer<WithdrawalPreview>();
        final otherRefresh = Completer<WithdrawalPreview>();
        final started = Completer<void>();
        respond = (_) {
          if (!started.isCompleted) {
            started.complete();
            return firstRefresh.future;
          }
          return otherRefresh.future;
        };
        final first = coordinator
            .executeWithdrawal(firstPreview, asset)
            .toList();
        await started.future;
        final overlapping = other
            .executeWithdrawal(otherPreview, asset)
            .toList();
        final refused = expectLater(overlapping, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        firstRefresh.complete(_preview());
        await first;
        // A late refresh used to reserve after the first success removed the
        // durable record, then broadcast the same user intent a second time.
        otherRefresh.complete(_preview());
        await refused;
        expect(requests, hasLength(3));
        expect(broadcasts, hasLength(1));
        expect(storage.values, isEmpty);
      },
    );
    test(
      'persisted unknown is loaded before a new preview can be signed',
      () async {
        final parameters = _params(asset);
        await coordinator.journal!.reserve(
          wallet.walletId,
          parameters,
          contextualizeSolanaWithdrawal(_preview(), asset),
        );
        await expectLater(
          coordinator.previewWithdrawal(parameters, asset),
          throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
        );
        expect(requests, isEmpty);
        expect(broadcasts, isEmpty);
      },
    );
    test(
      'session cleanup revokes previews but preserves unknown reservations',
      () async {
        final parameters = _params(asset);
        final preview = await coordinator.previewWithdrawal(parameters, asset);
        submit = (_, __) async => throw TimeoutException('response lost');
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
        );
        coordinator.clearSession();
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsFormatException,
        );
        await expectLater(
          coordinator.previewWithdrawal(parameters, asset),
          throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
        );
        expect(
          (await coordinator.journal!.find(
            wallet.walletId,
            parameters,
          ))?.txHash,
          'AaFreshSignature',
        );
        expect(broadcasts, hasLength(1));
        expect(requests, hasLength(2));
      },
    );
    test(
      'refused engine lease clears only the unsubmitted reservation',
      () async {
        final parameters = _params(asset);
        final preview = await coordinator.previewWithdrawal(parameters, asset);
        storage.beforeWrite = () => rejectLease = true;
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(isA<RpcDispatchRejected>()),
        );
        expect(broadcasts, isEmpty);
        expect(
          await coordinator.journal!.find(wallet.walletId, parameters),
          isNull,
        );
        rejectLease = false;
        storage.beforeWrite = null;
        await coordinator.executeWithdrawal(preview, asset).toList();
        expect(broadcasts, hasLength(1));
      },
    );
    test('failed durable reservation prevents dispatch', () async {
      final preview = await coordinator.previewWithdrawal(
        _params(asset),
        asset,
      );
      storage.failWrite = true;
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsStateError,
      );
      expect(broadcasts, isEmpty);
    });
    test('successful broadcast with failed cleanup retains signature '
        'and blocks retry', () async {
      final parameters = _params(asset);
      final preview = await coordinator.previewWithdrawal(parameters, asset);
      storage.failDelete = true;
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
      );
      expect(broadcasts, hasLength(1));
      expect(
        (await coordinator.journal!.find(wallet.walletId, parameters))?.txHash,
        'AaFreshSignature',
      );
      await expectLater(
        coordinator.previewWithdrawal(parameters, asset),
        throwsA(isA<SolanaWithdrawalSubmissionUnknown>()),
      );
      expect(broadcasts, hasLength(1));
    });
    test('wallet changes after dispatch preserve journal '
        'without exposing old signature', () async {
      final parameters = _params(asset);
      final preview = await coordinator.previewWithdrawal(parameters, asset);
      submit = (_, __) async {
        auth.runtimeSessions.observe(null);
        return SendRawTransactionResponse(
          mmrpc: '2.0',
          txHash: 'AaFreshSignature',
        );
      };
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsA(isNot(isA<SolanaWithdrawalSubmissionUnknown>())),
      );
      expect(
        (await coordinator.journal!.find(wallet.walletId, parameters))?.txHash,
        'AaFreshSignature',
      );
      expect(broadcasts, hasLength(1));
    });
    test(
      'wallet changes during an uncertain dispatch do not expose its signature',
      () async {
        final parameters = _params(asset);
        final preview = await coordinator.previewWithdrawal(parameters, asset);
        submit = (_, __) async {
          auth.runtimeSessions.invalidate();
          throw TimeoutException('response lost after wallet changed');
        };
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(
          (await coordinator.journal!.find(
            wallet.walletId,
            parameters,
          ))?.txHash,
          'AaFreshSignature',
        );
        expect(broadcasts, hasLength(1));
      },
    );
    test(
      'wallet changes during successful journal cleanup suppress completion',
      () async {
        final preview = await coordinator.previewWithdrawal(
          _params(asset),
          asset,
        );
        storage.beforeDelete = auth.runtimeSessions.invalidate;
        final progress = <WithdrawalProgress>[];
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).forEach(progress.add),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(
          progress.where((event) => event.status == WithdrawalStatus.complete),
          isEmpty,
        );
        expect(broadcasts, hasLength(1));
      },
    );
    test(
      'authorization is rechecked after refresh and before dispatch',
      () async {
        final preview = await coordinator.previewWithdrawal(
          _params(asset),
          asset,
        );
        respond = (_) async {
          auth.runtimeSessions.invalidate();
          return _preview();
        };
        await expectLater(
          coordinator.executeWithdrawal(preview, asset).toList(),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(broadcasts, isEmpty);
      },
    );
    for (final method in ['withdraw', 'send_raw_transaction']) {
      test(
        'revoked caller authorization refuses $method at transport dispatch',
        () async {
          final parameters = _params(asset);
          final preview = await coordinator.previewWithdrawal(
            parameters,
            asset,
          );
          final preparing = Completer<void>();
          final release = Completer<void>();
          var authorized = true;
          var reachedEngine = false;
          Future<void> prepareTransport() async {
            preparing.complete();
            await release.future;
            RpcDispatchGuard.ensureCurrent(method);
            reachedEngine = true;
          }

          if (method == 'withdraw') {
            respond = (_) async {
              await prepareTransport();
              return _preview();
            };
          } else {
            submit = (_, __) async {
              await prepareTransport();
              return SendRawTransactionResponse(
                mmrpc: '2.0',
                txHash: 'AaFreshSignature',
              );
            };
          }
          final pending = coordinator
              .executeWithdrawal(
                preview,
                asset,
                beforeBroadcast: () {
                  if (!authorized) throw StateError('caller permit revoked');
                },
              )
              .toList();
          final assertion = expectLater(
            pending,
            throwsA(isA<RpcDispatchRejected>()),
          );
          await preparing.future;
          authorized = false;
          release.complete();
          await assertion;
          expect(reachedEngine, isFalse);
          expect(
            await coordinator.journal!.find(wallet.walletId, parameters),
            isNull,
          );

          // This request was never sent. A later explicit confirmation may
          // proceed under fresh caller authorization.
          authorized = true;
          respond = (_) async => _preview();
          submit = (_, __) async => SendRawTransactionResponse(
            mmrpc: '2.0',
            txHash: 'AaFreshSignature',
          );
          final retried = await coordinator
              .executeWithdrawal(
                preview,
                asset,
                beforeBroadcast: () {
                  if (!authorized) throw StateError('caller permit revoked');
                },
              )
              .toList();
          expect(retried.last.status, WithdrawalStatus.complete);
        },
      );
    }
    test('malformed refresh and unbound previews never broadcast', () async {
      await expectLater(
        coordinator.executeWithdrawal(_preview(), asset).toList(),
        throwsFormatException,
      );
      final preview = await coordinator.previewWithdrawal(
        _params(asset),
        asset,
      );
      respond = (_) async => _preview(hash: '');
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsFormatException,
      );
      expect(broadcasts, isEmpty);
    });
  });
}
