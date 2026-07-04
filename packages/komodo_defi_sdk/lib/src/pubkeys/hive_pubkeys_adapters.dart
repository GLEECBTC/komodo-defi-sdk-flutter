import 'package:decimal/decimal.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

// Reserve unique typeIds (avoid collisions with other adapters)
const int _hiveStoredPubkeyTypeId = 310;
const int _hiveAssetPubkeysRecordTypeId = 311;

class HiveStoredPubkey {
  HiveStoredPubkey({
    required this.address,
    required this.derivationPath,
    required this.chain,
    required this.spendable,
    required this.unspendable,
    this.gasfreeAddress,
    this.everFunded = false,
  });

  factory HiveStoredPubkey.fromDomain(
    PubkeyInfo info, {
    bool everFunded = false,
  }) => HiveStoredPubkey(
    address: info.address,
    derivationPath: info.derivationPath,
    chain: info.chain,
    spendable: info.balance.spendable.toString(),
    unspendable: info.balance.unspendable.toString(),
    gasfreeAddress: info.gasfreeAddress,
    everFunded: everFunded,
  );

  final String address;
  final String? gasfreeAddress;
  final String? derivationPath;
  final String? chain;
  final String spendable;
  final String unspendable;

  /// Whether this address has ever been observed holding funds. Used by the
  /// TRON gasless phantom-address filter to distinguish never-used addresses
  /// (safe to hide) from used-then-emptied ones (kept so their transaction
  /// history stays reachable).
  final bool everFunded;

  PubkeyInfo toDomain(String coinTicker) => PubkeyInfo(
    address: address,
    derivationPath: derivationPath,
    chain: chain,
    balance: BalanceInfo(
      total: null,
      spendable: Decimal.parse(spendable),
      unspendable: Decimal.parse(unspendable),
    ),
    coinTicker: coinTicker,
    gasfreeAddress: gasfreeAddress,
  );
}

class HiveStoredPubkeyAdapter extends TypeAdapter<HiveStoredPubkey> {
  @override
  final int typeId = _hiveStoredPubkeyTypeId;

  @override
  HiveStoredPubkey read(BinaryReader reader) {
    final address = reader.readString();
    final hasDerivation = reader.readBool();
    final derivation = hasDerivation ? reader.readString() : null;
    final hasChain = reader.readBool();
    final chain = hasChain ? reader.readString() : null;
    final spendable = reader.readString();
    final unspendable = reader.readString();
    final hasGasfreeAddress = reader.readBool();
    final gasfreeAddress = hasGasfreeAddress ? reader.readString() : null;
    final everFunded = reader.readBool();
    return HiveStoredPubkey(
      address: address,
      derivationPath: derivation,
      chain: chain,
      spendable: spendable,
      unspendable: unspendable,
      gasfreeAddress: gasfreeAddress,
      everFunded: everFunded,
    );
  }

  @override
  void write(BinaryWriter writer, HiveStoredPubkey obj) {
    writer
      ..writeString(obj.address)
      ..writeBool(obj.derivationPath != null);
    if (obj.derivationPath != null) writer.writeString(obj.derivationPath!);
    writer.writeBool(obj.chain != null);
    if (obj.chain != null) writer.writeString(obj.chain!);
    writer
      ..writeString(obj.spendable)
      ..writeString(obj.unspendable)
      ..writeBool(obj.gasfreeAddress != null);
    if (obj.gasfreeAddress != null) writer.writeString(obj.gasfreeAddress!);
    writer.writeBool(obj.everFunded);
  }
}

class HiveAssetPubkeysRecord {
  HiveAssetPubkeysRecord({
    required this.available,
    required this.sync,
    required this.keys,
  });

  factory HiveAssetPubkeysRecord.fromDomain(
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses = const {},
  }) => HiveAssetPubkeysRecord(
    available: pubkeys.availableAddressesCount,
    sync: pubkeys.syncStatus.toString(),
    keys: pubkeys.keys
        .map(
          (info) => HiveStoredPubkey.fromDomain(
            info,
            everFunded: everFundedAddresses.contains(info.address),
          ),
        )
        .toList(),
  );

  final int available;
  final String sync;
  final List<HiveStoredPubkey> keys;

  AssetPubkeys toDomain(AssetId assetId) => AssetPubkeys(
    assetId: assetId,
    keys: keys.map((k) => k.toDomain(assetId.id)).toList(),
    availableAddressesCount: available,
    syncStatus: SyncStatusEnum.tryParse(sync) ?? SyncStatusEnum.success,
  );
}

class HiveAssetPubkeysRecordAdapter
    extends TypeAdapter<HiveAssetPubkeysRecord> {
  @override
  final int typeId = _hiveAssetPubkeysRecordTypeId;

  @override
  HiveAssetPubkeysRecord read(BinaryReader reader) {
    final available = reader.readInt();
    final sync = reader.readString();
    final length = reader.readInt();
    final keys = <HiveStoredPubkey>[];
    for (var i = 0; i < length; i++) {
      keys.add(reader.read() as HiveStoredPubkey);
    }
    return HiveAssetPubkeysRecord(available: available, sync: sync, keys: keys);
  }

  @override
  void write(BinaryWriter writer, HiveAssetPubkeysRecord obj) {
    writer
      ..writeInt(obj.available)
      ..writeString(obj.sync)
      ..writeInt(obj.keys.length);
    for (final k in obj.keys) {
      writer.write(k);
    }
  }
}

void registerPubkeysAdapters() {
  if (!Hive.isAdapterRegistered(_hiveStoredPubkeyTypeId)) {
    Hive.registerAdapter(HiveStoredPubkeyAdapter());
  }
  if (!Hive.isAdapterRegistered(_hiveAssetPubkeysRecordTypeId)) {
    Hive.registerAdapter(HiveAssetPubkeysRecordAdapter());
  }
}
