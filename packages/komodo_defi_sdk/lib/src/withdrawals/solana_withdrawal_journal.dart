import 'dart:convert';

import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_support.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// Durable reservations prevent rebuilding a possibly submitted Solana send.
abstract interface class SolanaWithdrawalJournal {
  /// Looks up an unresolved intent for this authenticated wallet.
  Future<WithdrawalPreview?> find(
    WalletId wallet,
    WithdrawParameters parameters,
  );

  /// Reserves before dispatch; returns an existing record without replacing it.
  Future<WithdrawalPreview?> reserve(
    WalletId wallet,
    WithdrawParameters parameters,
    WithdrawalPreview preview,
  );

  /// Clears only the matching signature after a conclusive dispatch result.
  Future<void> clear(
    WalletId wallet,
    WithdrawParameters parameters,
    String signature,
  );
}

/// Encrypted wallet-scoped reservations, shared by native and browser builds.
///
/// Only review details and signatures are persisted, never signed transaction
/// bytes. An unreadable or unverified record blocks new submissions. Explicit
/// recovery can use authoritative signature reconciliation.
final class SecureSolanaWithdrawalJournal implements SolanaWithdrawalJournal {
  /// Reuses encrypted wallet storage under a separate prefix.
  SecureSolanaWithdrawalJournal({GaslessTransferKeyValueStorage? storage})
    : _storage = storage ?? SecureGaslessTransferStorage();

  final GaslessTransferKeyValueStorage _storage;
  static final _mutex = Mutex();

  String _key(WalletId wallet, WithdrawParameters parameters) {
    if (wallet.pubkeyHash?.trim().isNotEmpty != true) {
      throw StateError('Solana submission requires verified wallet identity');
    }
    final intent = solanaWithdrawalIntentKey(parameters);
    return 'solana_pending_v1_${walletStorageNamespace(wallet)}_$intent';
  }

  Future<T> _protect<T>(Future<T> Function() action) =>
      _mutex.protect(() => withGaslessTransferLock(action));

  Future<WithdrawalPreview?> _read(String key) async {
    final exists = await _storage.containsKey(key);
    final value = await _storage.read(key);
    if (value == null) {
      if (exists) throw StateError('Solana submission record is unreadable');
      return null;
    }
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException();
      final preview = WithdrawResult.fromJson(
        data['preview'] as Map<String, dynamic>,
      );
      final fee = preview.fee;
      if (preview.txHash?.isNotEmpty != true ||
          fee is! SolanaFeeInfo ||
          data['fee_coin'] is! String ||
          (data['fee_coin'] as String).isEmpty) {
        throw const FormatException();
      }
      return WithdrawResult(
        txHash: preview.txHash,
        txHex: '',
        from: preview.from,
        to: preview.to,
        balanceChanges: preview.balanceChanges,
        blockHeight: preview.blockHeight,
        timestamp: preview.timestamp,
        fee: fee.copyWith(coin: data['fee_coin'] as String),
        coin: preview.coin,
        memo: preview.memo,
        transactionType: preview.transactionType,
      );
    } on Object {
      throw StateError('Solana submission record is invalid');
    }
  }

  @override
  Future<WithdrawalPreview?> find(
    WalletId wallet,
    WithdrawParameters parameters,
  ) => _protect(() => _read(_key(wallet, parameters)));

  @override
  Future<WithdrawalPreview?> reserve(
    WalletId wallet,
    WithdrawParameters parameters,
    WithdrawalPreview preview,
  ) => _protect(() async {
    final key = _key(wallet, parameters);
    final existing = await _read(key);
    if (existing != null) return existing;
    final details = preview.toJson()
      ..remove('tx_json')
      ..['tx_hex'] = '';
    details['transaction_type'] = preview.transactionType;
    await _storage.write(
      key,
      jsonEncode({
        'version': 1,
        'fee_coin': preview.fee.coin,
        'preview': details,
      }),
    );
    if ((await _read(key))?.txHash != preview.txHash) {
      throw StateError('Solana submission reservation was not verified');
    }
    return null;
  });

  @override
  Future<void> clear(
    WalletId wallet,
    WithdrawParameters parameters,
    String signature,
  ) => _protect(() async {
    final key = _key(wallet, parameters);
    if ((await _read(key))?.txHash == signature) await _storage.delete(key);
  });
}
