import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Mixin containing shared HD wallet logic
mixin HDWalletMixin on PubkeyStrategy {
  KdfUser get kdfUser;

  /// The gap KDF enforces when *creating* an address, and the basis for how
  /// many more addresses the UI offers.
  ///
  /// Deliberately NOT the scan gap. `task::get_new_address` refuses once there
  /// are already `gap_limit` unused addresses in a row
  /// (`mm2src/coins/rpc_command/get_new_address.rs:615-617`), so lowering this
  /// would cap how many unused addresses a user may hold - at
  /// `HdGapLimit.newlyGeneratedFirstSignIn` they could create exactly one and
  /// then be refused. Address creation is a user action with no node-load
  /// problem; the repeating scan is the one that needed bounding.
  int get _gapLimit => HdGapLimit.hardware;

  /// The gap used when *scanning* for addresses that already exist on chain.
  ///
  /// Supplied per wallet - see [HdGapLimit]. Defaults to the full BIP-44 gap so
  /// a strategy constructed without one never silently narrows discovery.
  int get scanGapLimit => HdGapLimit.hardware;
  Duration get _scanPollInterval => const Duration(milliseconds: 250);
  Duration get _scanTimeout => const Duration(seconds: 20);
  Duration get _accountBalancePollInterval => const Duration(milliseconds: 100);

  /// Deliberately more generous than [_scanTimeout]: a wallet with many
  /// derived addresses can legitimately take a while. This is a hang guard,
  /// not a latency budget.
  Duration get _accountBalanceTimeout => const Duration(seconds: 60);

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool protocolSupported(ProtocolClass protocol) {
    // HD wallet strategies support protocols that can handle multiple addresses
    // This includes UTXO protocols and EVM protocols
    // Tendermint protocols use single addresses only
    return protocol.supportsMultipleAddresses;
  }

  @override
  Future<AssetPubkeys> getPubkeys(AssetId assetId, ApiClient client) async {
    final balanceInfo = await getAccountBalance(assetId, client);
    return convertBalanceInfoToAssetPubkeys(assetId, balanceInfo);
  }

  @override
  Future<void> scanForNewAddresses(AssetId assetId, ApiClient client) async {
    final initResponse = await client.rpc.hdWallet.scanForNewAddressesInit(
      assetId.id,
      accountId: 0,
      gapLimit: scanGapLimit,
    );

    final startedAt = DateTime.now();
    while (true) {
      final status = await client.rpc.hdWallet.scanForNewAddressesStatus(
        initResponse.taskId,
        forgetIfFinished: false,
      );

      if (status.status == 'Ok') {
        return;
      }

      if (status.status == 'Error') {
        if (status.error != null) {
          throw status.error!;
        }
        throw Exception(
          status.statusDescription ?? 'Failed to scan for new addresses',
        );
      }

      if (DateTime.now().difference(startedAt) >= _scanTimeout) {
        throw TimeoutException(
          'Timed out scanning for new addresses for ${assetId.id}',
        );
      }

      await Future<void>.delayed(_scanPollInterval);
    }
  }

  Future<AccountBalanceInfo> getAccountBalance(
    AssetId assetId,
    ApiClient client,
  ) async {
    final initResponse = await client.rpc.hdWallet.accountBalanceInit(
      coin: assetId.id,
      accountIndex: 0,
    );

    final startedAt = DateTime.now();
    while (true) {
      final status = await client.rpc.hdWallet.accountBalanceStatus(
        taskId: initResponse.taskId,
        forgetIfFinished: false,
      );
      final result = (status.details..throwIfError).data;
      // Return as soon as the task resolves. The delay used to run
      // unconditionally after the assignment, so every call paid an extra
      // 100ms even when the first poll already succeeded - once per asset on
      // every fresh pubkey fetch.
      if (result != null) return result;

      // Guard against a task that never resolves. Without this the loop is
      // unbounded, unlike scanForNewAddresses above.
      if (DateTime.now().difference(startedAt) >= _accountBalanceTimeout) {
        throw TimeoutException(
          'Timed out fetching account balance for ${assetId.id}',
        );
      }

      await Future<void>.delayed(_accountBalancePollInterval);
    }
  }

  Future<AssetPubkeys> convertBalanceInfoToAssetPubkeys(
    AssetId assetId,
    AccountBalanceInfo balanceInfo,
  ) async {
    final addresses = balanceInfo.addresses
        .map(
          (addr) => PubkeyInfo(
            address: addr.address,
            derivationPath: addr.derivationPath,
            chain: addr.chain,
            balance: addr.balance.balanceOf(assetId.id),
            coinTicker: assetId.id,
            gasfreeAddress: addr.gasfreeAddress,
          ),
        )
        .toList();

    return AssetPubkeys(
      assetId: assetId,
      keys: addresses,
      availableAddressesCount: await availableNewAddressesCount(
        addresses,
      ).then((value) => value),
      syncStatus: SyncStatusEnum.success,
    );
  }

  Future<int> availableNewAddressesCount(List<PubkeyInfo> addresses) {
    final gapFromLastUsed =
        addresses.lastIndexWhere((addr) => addr.balance.hasValue) + 1;

    return Future.value((_gapLimit - gapFromLastUsed).clamp(0, _gapLimit));
  }
}

/// HD wallet strategy for context private key wallets
class ContextPrivKeyHDWalletStrategy extends PubkeyStrategy with HDWalletMixin {
  ContextPrivKeyHDWalletStrategy({
    required this.kdfUser,
    this.scanGapLimit = HdGapLimit.hardware,
  });

  @override
  final KdfUser kdfUser;

  @override
  final int scanGapLimit;

  @override
  /// Get the new address for the given asset ID and client.
  ///
  /// Filters out balances that are not for the given asset ID.
  // TODO: Refactor to create a domain model with onlt a single balance entry.
  // Currently we are bound to the RPC response data structure.
  Future<PubkeyInfo> getNewAddress(AssetId assetId, ApiClient client) async {
    final newAddress = (await client.rpc.hdWallet.getNewAddress(
      assetId.id,
      accountId: 0,
      chain: 'External',
      gapLimit: _gapLimit,
    )).newAddress;

    // Get the balance for the specific coin, or use the first balance if not
    // found
    final coinBalance =
        newAddress.getBalanceForCoin(assetId.id) ?? BalanceInfo.zero();

    return PubkeyInfo(
      address: newAddress.address,
      derivationPath: newAddress.derivationPath,
      chain: newAddress.chain,
      balance: coinBalance,
      coinTicker: assetId.id,
      gasfreeAddress: newAddress.gasfreeAddress,
    );
  }

  @override
  Stream<NewAddressState> getNewAddressStream(
    AssetId assetId,
    ApiClient client,
  ) async* {
    try {
      yield const NewAddressState(status: NewAddressStatus.processing);
      final info = await getNewAddress(assetId, client);
      yield NewAddressState.completed(info);
    } catch (e) {
      yield NewAddressState.error('Failed to generate address: $e');
    }
  }
}

/// HD wallet strategy for Trezor wallets
class TrezorHDWalletStrategy extends PubkeyStrategy with HDWalletMixin {
  /// No `scanGapLimit` parameter: hardware wallets always use the full BIP-44
  /// gap. Their seed is expected to have been used by other software, which is
  /// exactly the history a short gap fails to find.
  TrezorHDWalletStrategy({required this.kdfUser});

  @override
  final KdfUser kdfUser;

  @override
  Future<PubkeyInfo> getNewAddress(AssetId assetId, ApiClient client) async {
    final newAddress = await _getNewAddressTask(assetId, client);

    return PubkeyInfo(
      address: newAddress.address,
      derivationPath: newAddress.derivationPath,
      chain: newAddress.chain,
      balance: newAddress.balance,
      coinTicker: assetId.id,
      gasfreeAddress: newAddress.gasfreeAddress,
    );
  }

  @override
  Stream<NewAddressState> getNewAddressStream(
    AssetId assetId,
    ApiClient client, {
    Duration pollingInterval = const Duration(milliseconds: 200),
  }) async* {
    try {
      final initResponse = await client.rpc.hdWallet.getNewAddressTaskInit(
        coin: assetId.id,
        accountId: 0,
        chain: 'External',
        gapLimit: _gapLimit,
      );

      var finished = false;
      while (!finished) {
        final status = await client.rpc.hdWallet.getNewAddressTaskStatus(
          taskId: initResponse.taskId,
          forgetIfFinished: false,
        );

        final state = status.toNewAddressState(initResponse.taskId, assetId.id);
        yield state;

        if (state.status == NewAddressStatus.completed ||
            state.status == NewAddressStatus.error ||
            state.status == NewAddressStatus.cancelled) {
          finished = true;
        } else {
          await Future<void>.delayed(pollingInterval);
        }
      }
    } catch (e) {
      yield NewAddressState.error('Failed to generate address: $e');
    }
  }

  Future<NewAddressInfo> _getNewAddressTask(
    AssetId assetId,
    ApiClient client, {
    Duration pollingInterval = const Duration(milliseconds: 200),
  }) async {
    final initResponse = await client.rpc.hdWallet.getNewAddressTaskInit(
      coin: assetId.id,
      accountId: 0,
      chain: 'External',
      gapLimit: _gapLimit,
    );

    NewAddressInfo? result;
    while (result == null) {
      final status = await client.rpc.hdWallet.getNewAddressTaskStatus(
        taskId: initResponse.taskId,
        forgetIfFinished: false,
      );
      result = (status.details..throwIfError).data;

      await Future<void>.delayed(pollingInterval);
    }
    return result;
  }
}
