import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A refreshed Solana transaction needs another review before it can be sent.
final class SolanaWithdrawalReviewChanged implements Exception {
  /// Carries the replacement that requires explicit confirmation.
  const SolanaWithdrawalReviewChanged(this.preview);

  /// Details associated with the signed transaction.
  final WithdrawalPreview preview;
}

/// The transaction may have reached the network. Never rebuild and retry it.
final class SolanaWithdrawalSubmissionUnknown implements Exception {
  /// Carries the attempted transaction without automatically retrying.
  const SolanaWithdrawalSubmissionUnknown(this.preview);

  /// Details associated with the signed transaction.
  final WithdrawalPreview preview;

  /// Case-sensitive base58 signature for status checks.
  String get transactionHash => preview.txHash!;
}

/// The user-visible contract of a signed Solana withdrawal.
///
/// Signatures, blockhashes and creation timestamps deliberately are not part of
/// the comparison: rebuilding them is the reason for refreshing on confirm.
final class SolanaWithdrawalReview {
  /// Freezes every review-relevant value _from [preview].
  SolanaWithdrawalReview(WithdrawalPreview preview)
    : _coin = preview.coin,
      _from = List.unmodifiable(preview.from),
      _to = List.unmodifiable(preview.to),
      _balanceChanges = preview.balanceChanges,
      _fee = preview.fee,
      _memo = preview.memo?.isEmpty == true ? null : preview.memo,
      _transactionType = preview.transactionType;

  final String _coin;
  final List<String> _from;
  final List<String> _to;
  final BalanceChanges _balanceChanges;
  final FeeInfo _fee;
  final String? _memo;
  final String _transactionType;

  /// Whether fresh signing kept the complete reviewed contract.
  bool matches(WithdrawalPreview preview) =>
      _coin == preview.coin &&
      const ListEquality<String>().equals(_from, preview.from) &&
      const ListEquality<String>().equals(_to, preview.to) &&
      _balanceChanges == preview.balanceChanges &&
      _fee == preview.fee &&
      _memo == (preview.memo?.isEmpty == true ? null : preview.memo) &&
      _transactionType == preview.transactionType;
}

/// Stable identity of a validated Solana transfer, shared by memory and storage.
///
/// Optional default flags and decimal formatting do not change an intent.
/// Addresses and nonempty memos remain byte-for-byte case sensitive. Automatic
/// fees are the only supported rail; unsupported selectors are rejected before
/// this key is used and must never create a second reservation namespace.
String solanaWithdrawalIntentKey(WithdrawParameters parameters) {
  final isMax = parameters.isMax ?? false;
  final canonical = <String, Object?>{
    'coin': parameters.asset,
    'to': parameters.toAddress,
    'max': isMax,
    'amount': isMax ? null : parameters.amount?.toString(),
    'memo': parameters.memo ?? '',
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

/// Whether this asset uses native Solana or SPL withdrawals.
bool isSolanaWithdrawalAsset(Asset asset) =>
    asset.protocol is SolanaProtocol || asset.protocol is SolanaTokenProtocol;

/// Gives Solana funding failures their platform-currency meaning. KDF reports
/// token account creation and rent-minimum shortfalls in the same fee error.
SdkError? contextualizeSolanaWithdrawalError(Object error, Asset asset) {
  final cause = error is SdkError ? error.source : error;
  if (cause is WithdrawErrorNotSufficientPlatformBalanceForFeeException) {
    return SdkError(
      code: SdkErrorCode.insufficientFeeBalance,
      category: SdkErrorCategory.funds,
      messageKey: 'withdrawSolanaInsufficientPlatformBalance',
      messageArgs: [asset.id.parentId?.id ?? asset.id.id],
      fallbackMessage:
          'Add SOL to cover the network fee, account creation '
          'and any required minimum remaining balance.',
      source: cause,
    );
  }
  if (cause is WithdrawErrorInvalidAddressException &&
      asset.protocol is SolanaTokenProtocol) {
    return SdkError(
      code: SdkErrorCode.invalidAddress,
      category: SdkErrorCategory.validation,
      messageKey: 'withdrawSolanaInvalidTokenRecipient',
      fallbackMessage:
          'Enter a Solana wallet address or a token account '
          'for this token mint.',
      source: cause,
    );
  }
  return null;
}

/// Checks the release capabilities before generating any signed transaction.
void validateSolanaWithdrawal(
  WithdrawParameters parameters,
  Asset asset,
  SolanaCapabilities capabilities,
) {
  if (!isSolanaWithdrawalAsset(asset)) return;
  if (parameters.asset != asset.id.id) {
    throw const FormatException('Solana withdrawal asset does not match');
  }

  Never unsupported(String key, String message) => throw SdkError(
    code: SdkErrorCode.notSupported,
    category: SdkErrorCategory.unsupported,
    messageKey: key,
    fallbackMessage: message,
    context: SdkErrorContext(
      operation: 'withdrawal.solana.validate',
      assetId: parameters.asset,
    ),
  );

  if (!capabilities.enabled) {
    unsupported(
      'withdrawSolanaUnavailable',
      'Solana transfers are not enabled in this build.',
    );
  }
  final protocol = asset.protocol;
  final decimals = protocol is SolanaTokenProtocol ? protocol.decimals : 9;
  if (parameters.amount case final Decimal amount) {
    if (amount <= Decimal.zero || amount.scale > decimals) {
      throw SdkError(
        code: SdkErrorCode.general,
        category: SdkErrorCategory.validation,
        messageKey: 'withdrawSolanaInvalidAmount',
        fallbackMessage:
            'Enter a positive amount with at most $decimals decimal places.',
        context: SdkErrorContext(
          operation: 'withdrawal.solana.validate',
          assetId: parameters.asset,
        ),
      );
    }
  }
  if (protocol is SolanaTokenProtocol) {
    if (protocol.programId != SolanaTokenProtocol.classicTokenProgramId &&
        protocol.programId != SolanaTokenProtocol.token2022ProgramId) {
      unsupported(
        'withdrawSolanaOptionsUnsupported',
        'This Solana token program is not supported.',
      );
    }
    if (protocol.isToken2022 && !capabilities.token2022Enabled) {
      unsupported(
        'withdrawSolanaToken2022Unavailable',
        'Token-2022 transfers are awaiting engine validation.',
      );
    }
    if (parameters.isMax == true && !capabilities.splMaxEnabled) {
      unsupported(
        'withdrawSolanaTokenMaxUnavailable',
        'Maximum token transfers are awaiting engine validation. '
            'Enter an exact amount.',
      );
    }
  }
  if (parameters.from != null ||
      parameters.fee != null ||
      parameters.feePriority != null ||
      parameters.expirationSeconds != null ||
      parameters.ibcTransfer == true ||
      parameters.ibcSourceChannel != null ||
      parameters.feeMethod == WithdrawalFeeMethod.gasless ||
      parameters.gaslessOptions != null) {
    unsupported(
      'withdrawSolanaOptionsUnsupported',
      'Solana uses one wallet address and automatic network fees.',
    );
  }
  if (utf8.encode(parameters.memo ?? '').length > 256) {
    throw SdkError(
      code: SdkErrorCode.invalidMemo,
      category: SdkErrorCategory.validation,
      messageKey: 'withdrawSolanaMemoTooLong',
      fallbackMessage: 'The Solana memo must be at most 256 UTF-8 bytes.',
      context: SdkErrorContext(
        operation: 'withdrawal.solana.validate',
        assetId: parameters.asset,
      ),
    );
  }
}

/// Solana's fee payload has no currency field, including for SPL withdrawals.
WithdrawalPreview contextualizeSolanaWithdrawal(
  WithdrawalPreview preview,
  Asset asset,
) {
  final fee = preview.fee;
  final feeCoin = asset.id.parentId?.id ?? asset.id.id;
  if (fee is! SolanaFeeInfo ||
      preview.coin != asset.id.id ||
      preview.txHex?.isNotEmpty != true ||
      preview.txHash?.isNotEmpty != true ||
      preview.from.isEmpty ||
      preview.to.length != 1 ||
      (fee.coin.isNotEmpty && fee.coin != feeCoin) ||
      fee.feeAmount < Decimal.zero ||
      fee.rentAmount < Decimal.zero ||
      fee.totalAmount != fee.feeAmount + fee.rentAmount) {
    throw const FormatException('Invalid Solana withdrawal response');
  }
  return WithdrawResult(
    txHash: preview.txHash,
    txHex: preview.txHex,
    txJson: preview.txJson,
    from: List.unmodifiable(preview.from),
    to: List.unmodifiable(preview.to),
    balanceChanges: preview.balanceChanges,
    blockHeight: preview.blockHeight,
    timestamp: preview.timestamp,
    fee: fee.copyWith(coin: feeCoin),
    coin: preview.coin,
    internalId: preview.internalId,
    kmdRewards: preview.kmdRewards,
    memo: preview.memo,
    transactionType: preview.transactionType,
  );
}
