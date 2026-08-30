import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// High-level helpers for chain rewards.
class RewardsManager {
  /// Creates a [RewardsManager].
  RewardsManager({
    required ApiClient client,
    required WithdrawalManager withdrawalManager,
  }) : _client = client,
       _withdrawalManager = withdrawalManager;

  final ApiClient _client;
  final WithdrawalManager _withdrawalManager;

  /// Fetches rewardable KMD UTXOs and their accrual status.
  Future<List<KmdRewardInfo>> kmdRewardsInfo() async {
    final response = await _client.rpc.rewards.kmdRewardsInfo();
    return response.rewards;
  }

  /// Previews a KMD rewards claim withdrawal.
  ///
  /// KDF expects a max KMD withdrawal back to the caller's KMD address with the
  /// KMD rewards parameters included. The lower-level withdrawal RPC model
  /// already adds those KMD-specific parameters.
  Future<WithdrawalPreview> previewKmdRewardsClaim({
    required String toAddress,
  }) {
    return _withdrawalManager.previewWithdrawal(
      WithdrawParameters(
        asset: 'KMD',
        toAddress: toAddress,
        amount: null,
        isMax: true,
      ),
    );
  }

  /// Claims KMD rewards by previewing and broadcasting the signed transaction.
  Future<WithdrawalResult> claimKmdRewards({required String toAddress}) async {
    final preview = await previewKmdRewardsClaim(toAddress: toAddress);
    WithdrawalResult? result;

    await for (final progress in _withdrawalManager.executeWithdrawal(
      preview,
      'KMD',
    )) {
      if (progress.withdrawalResult != null) {
        result = progress.withdrawalResult;
      }
    }

    final finalResult = result;
    if (finalResult == null) {
      throw StateError(
        'KMD rewards claim completed without a withdrawal result',
      );
    }
    return finalResult;
  }
}
