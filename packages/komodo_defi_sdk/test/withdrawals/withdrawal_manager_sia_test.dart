import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/withdrawal_auth_fixture.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAssetProvider extends Mock implements IAssetProvider {}

class _MockFeeManager extends Mock implements FeeManager {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockLegacyWithdrawalManager extends Mock
    implements LegacyWithdrawalManager {}

Asset _createSiaAsset() {
  return Asset.fromJson(const {
    'coin': 'SC',
    'type': 'SIA',
    'name': 'Siacoin',
    'fname': 'Siacoin',
    'wallet_only': false,
    'mm2': 1,
    'chain_id': 2024,
    'decimals': 24,
    'required_confirmations': 1,
    'nodes': [
      {'url': 'https://api.siascan.com/wallet/api'},
    ],
  });
}

WithdrawalPreview _siaPreview() {
  return WithdrawResult(
    txJson: const {
      'siacoinInputs': <Map<String, dynamic>>[],
      'siacoinOutputs': <Map<String, dynamic>>[],
      'minerFee': '10000000000000000000',
    },
    txHash: '0xabc',
    from: const ['sender'],
    to: const ['recipient'],
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-1'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.one,
      totalAmount: Decimal.one,
    ),
    blockHeight: 1,
    timestamp: 123456,
    fee: FeeInfo.sia(
      coin: 'SC',
      amount: Decimal.parse('0.000010000000000000000000'),
      policy: 'Fixed',
    ),
    coin: 'SC',
  );
}

void main() {
  group('WithdrawalManager SIA behavior', () {
    late ApiClient client;
    late IAssetProvider assetProvider;
    late FeeManager feeManager;
    late SharedActivationCoordinator activationCoordinator;
    late LegacyWithdrawalManager legacyManager;
    late WithdrawalManager manager;
    late Asset siaAsset;

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
        auth: WithdrawalAuthFixture(),
      );
      addTearDown(manager.dispose);
      siaAsset = _createSiaAsset();

      when(
        () => assetProvider.findAssetsByConfigId('SC'),
      ).thenReturn({siaAsset});
    });

    test('preview rejects SIA source selection params', () async {
      final params = WithdrawParameters(
        asset: 'SC',
        toAddress: 'recipient',
        amount: Decimal.one,
        from: WithdrawalSource.hdDerivationPath("m/44'/141'/0'/0/0"),
      );

      await expectLater(
        manager.previewWithdrawal(params),
        throwsA(
          isA<SdkError>().having(
            (error) => error.code,
            'code',
            SdkErrorCode.notSupported,
          ),
        ),
      );

      verifyNever(() => legacyManager.previewWithdrawal(params));
    });

    test('withdraw rejects SIA source selection params', () async {
      final params = WithdrawParameters(
        asset: 'SC',
        toAddress: 'recipient',
        amount: Decimal.one,
        from: WithdrawalSource.hdDerivationPath("m/44'/141'/0'/0/0"),
      );

      await expectLater(
        manager.withdraw(params).toList(),
        throwsA(
          isA<SdkError>().having(
            (error) => error.code,
            'code',
            SdkErrorCode.notSupported,
          ),
        ),
      );

      verifyNever(() => legacyManager.withdraw(params));
    });

    test('preview delegates SIA flow to legacy manager', () async {
      final params = WithdrawParameters(
        asset: 'SC',
        toAddress: 'recipient',
        amount: Decimal.one,
      );
      final preview = _siaPreview();
      when(
        () => legacyManager.previewWithdrawal(params),
      ).thenAnswer((_) async => preview);

      final result = await manager.previewWithdrawal(params);

      expect(result, same(preview));
      verify(() => legacyManager.previewWithdrawal(params)).called(1);
    });

    Stream<WithdrawalProgress> Function(Invocation) recordGuard(
      List<void Function()> guards,
    ) => (invocation) {
      guards.add(
        invocation.namedArguments[#beforeBroadcast] as void Function(),
      );
      return const Stream<WithdrawalProgress>.empty();
    };

    test('execute delegates SIA flow to legacy manager', () async {
      final preview = _siaPreview();
      when(
        () => legacyManager.executeWithdrawal(
          preview,
          'SC',
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).thenAnswer((_) => const Stream<WithdrawalProgress>.empty());

      await manager.executeWithdrawal(preview, 'SC').drain<void>();

      verify(
        () => legacyManager.executeWithdrawal(
          preview,
          'SC',
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).called(1);
      verifyNever(() => activationCoordinator.activateAsset(siaAsset));
    });

    test(
      'a restricted SIA asset is not withdrawn by the legacy flow',
      () async {
        final preview = _siaPreview();
        final params = WithdrawParameters(
          asset: 'SC',
          toAddress: 'recipient',
          amount: Decimal.one,
        );
        when(
          () => activationCoordinator.ensureActiveAssetAllowed(siaAsset.id),
        ).thenThrow(
          ActivationPolicyException(siaAsset.id, ActivationPolicyStatus.ready),
        );
        when(
          () => legacyManager.executeWithdrawal(
            preview,
            'SC',
            beforeBroadcast: any(named: 'beforeBroadcast'),
          ),
        ).thenAnswer((_) => const Stream<WithdrawalProgress>.empty());
        when(
          () => legacyManager.withdraw(
            params,
            beforeBroadcast: any(named: 'beforeBroadcast'),
          ),
        ).thenAnswer((_) => const Stream<WithdrawalProgress>.empty());

        final restricted = throwsA(
          isA<SdkError>().having(
            (error) => error.source,
            'source',
            isA<ActivationPolicyException>(),
          ),
        );
        await expectLater(
          manager.executeWithdrawal(preview, 'SC').drain<void>(),
          restricted,
        );
        await expectLater(manager.withdraw(params).drain<void>(), restricted);
        verifyNever(
          () => legacyManager.executeWithdrawal(
            preview,
            'SC',
            beforeBroadcast: any(named: 'beforeBroadcast'),
          ),
        );
        verifyNever(
          () => legacyManager.withdraw(
            params,
            beforeBroadcast: any(named: 'beforeBroadcast'),
          ),
        );
      },
    );

    test('the legacy broadcast guard rechecks the restriction', () async {
      final preview = _siaPreview();
      final params = WithdrawParameters(
        asset: 'SC',
        toAddress: 'recipient',
        amount: Decimal.one,
      );
      final guards = <void Function()>[];
      when(
        () => legacyManager.executeWithdrawal(
          preview,
          'SC',
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).thenAnswer(recordGuard(guards));
      when(
        () => legacyManager.withdraw(
          params,
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).thenAnswer(recordGuard(guards));

      await manager.executeWithdrawal(preview, 'SC').drain<void>();
      await manager.withdraw(params).drain<void>();
      when(
        () => activationCoordinator.ensureActiveAssetAllowed(siaAsset.id),
      ).thenThrow(
        ActivationPolicyException(siaAsset.id, ActivationPolicyStatus.ready),
      );

      expect(guards, hasLength(2));
      for (final guard in guards) {
        expect(guard, throwsA(isA<ActivationPolicyException>()));
      }
    });

    test('one-shot withdraw delegates SIA flow to legacy manager', () async {
      final params = WithdrawParameters(
        asset: 'SC',
        toAddress: 'recipient',
        amount: Decimal.one,
      );
      when(
        () => legacyManager.withdraw(
          params,
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).thenAnswer((_) => const Stream<WithdrawalProgress>.empty());

      await manager.withdraw(params).drain<void>();

      verify(
        () => legacyManager.withdraw(
          params,
          beforeBroadcast: any(named: 'beforeBroadcast'),
        ),
      ).called(1);
    });
  });
}
