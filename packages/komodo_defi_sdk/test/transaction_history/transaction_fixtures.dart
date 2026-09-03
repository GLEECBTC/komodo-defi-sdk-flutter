// Shared builders for the transaction-history storage suites.
//
// Deliberately not named `*_test.dart` so `flutter test` does not pick it up
// as a suite of its own.
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Builds a [WalletId] varying only the axes that storage isolation depends on.
WalletId testWallet({
  String name = 'wallet',
  String? pubkeyHash = 'wallet-pubkey',
  DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  bool allowWeakPassword = false,
}) => WalletId(
  name: name,
  pubkeyHash: pubkeyHash,
  authOptions: AuthOptions(
    derivationMethod: derivationMethod,
    allowWeakPassword: allowWeakPassword,
    privKeyPolicy: privKeyPolicy,
  ),
);

/// Builds an [AssetId]. Defaults to the gas-free TRC-20 shape used elsewhere in
/// these suites.
AssetId testAssetId({
  String id = 'USDT-TRC20',
  String name = 'Tether',
  CoinSubClass subClass = CoinSubClass.trc20,
  ChainId? chainId,
  String? derivationPath = "m/44'/195'",
  AssetId? parentId,
  AssetSymbol? symbol,
}) => AssetId(
  id: id,
  name: name,
  symbol: symbol ?? AssetSymbol(assetConfigId: id),
  chainId: chainId ?? AssetChainId(chainId: 728126428, decimalsValue: 6),
  derivationPath: derivationPath,
  subClass: subClass,
  parentId: parentId,
);

/// Builds a [Transaction] with sensible defaults for storage tests.
Transaction testTransaction({
  String internalId = 'tx-1',
  String? id,
  AssetId? assetId,
  DateTime? timestamp,
  int confirmations = 1,
  int blockHeight = 123,
  Decimal? receivedByMe,
  Decimal? spentByMe,
  Decimal? totalAmount,
  List<String> from = const ['from-address'],
  List<String> to = const ['to-address'],
  String? txHash = 'tx-hash',
  FeeInfo? fee,
  String? memo,
}) {
  final received = receivedByMe ?? Decimal.zero;
  final spent = spentByMe ?? Decimal.parse('12.5');
  return Transaction(
    id: id ?? internalId,
    internalId: internalId,
    assetId: assetId ?? testAssetId(),
    balanceChanges: BalanceChanges(
      netChange: received - spent,
      receivedByMe: received,
      spentByMe: spent,
      totalAmount: totalAmount ?? (received > spent ? received : spent),
    ),
    timestamp: timestamp ?? DateTime.utc(2026, 7, 10),
    confirmations: confirmations,
    blockHeight: blockHeight,
    from: from,
    to: to,
    txHash: txHash,
    fee: fee,
    memo: memo,
  );
}
