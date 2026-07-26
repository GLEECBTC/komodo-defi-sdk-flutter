import 'package:decimal/decimal.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

// Reserve unique typeIds (avoid collisions with other adapters)
const int _legacyHiveStoredPubkeyTypeId = 310;
const int _legacyHiveAssetPubkeysRecordTypeId = 311;
const int _hiveStoredPubkeyTypeId = 312;
const int _hiveAssetPubkeysRecordTypeId = 313;

enum LegacyPubkeysSchema { v1, v3 }

var _legacyPubkeysSchema = LegacyPubkeysSchema.v1;

/// Reader-only representation of the historical cache schemas. All migrated
/// addresses are conservatively treated as previously used.
class LegacyHiveStoredPubkey {
  LegacyHiveStoredPubkey({
    required this.address,
    required this.derivationPath,
    required this.chain,
    required this.spendable,
    required this.unspendable,
    this.gasfreeAddress,
  });

  final String address;
  final String? derivationPath;
  final String? chain;
  final String spendable;
  final String unspendable;
  final String? gasfreeAddress;

  HiveStoredPubkey toCurrent() => HiveStoredPubkey(
    address: address,
    derivationPath: derivationPath,
    chain: chain,
    spendable: spendable,
    unspendable: unspendable,
    gasfreeAddress: gasfreeAddress,
    everFunded: true,
  );
}

class LegacyHiveAssetPubkeysRecord {
  LegacyHiveAssetPubkeysRecord({
    required this.available,
    required this.sync,
    required this.keys,
  });

  final int available;
  final String sync;
  final List<LegacyHiveStoredPubkey> keys;
}

class LegacyHiveStoredPubkeyAdapter
    extends TypeAdapter<LegacyHiveStoredPubkey> {
  @override
  final int typeId = _legacyHiveStoredPubkeyTypeId;

  @override
  LegacyHiveStoredPubkey read(BinaryReader reader) {
    final address = reader.readString();
    final derivation = reader.readBool() ? reader.readString() : null;
    final chain = reader.readBool() ? reader.readString() : null;
    final spendable = reader.readString();
    final unspendable = reader.readString();
    String? gasfreeAddress;
    if (_legacyPubkeysSchema == LegacyPubkeysSchema.v3) {
      gasfreeAddress = reader.readBool() ? reader.readString() : null;
      // Read and intentionally ignore the historical ever-funded value. Every
      // migrated address is retained, including used-then-empty addresses.
      reader.readBool();
    }
    return LegacyHiveStoredPubkey(
      address: address,
      derivationPath: derivation,
      chain: chain,
      spendable: spendable,
      unspendable: unspendable,
      gasfreeAddress: gasfreeAddress,
    );
  }

  @override
  void write(BinaryWriter writer, LegacyHiveStoredPubkey obj) {
    writer
      ..writeString(obj.address)
      ..writeBool(obj.derivationPath != null);
    if (obj.derivationPath != null) writer.writeString(obj.derivationPath!);
    writer.writeBool(obj.chain != null);
    if (obj.chain != null) writer.writeString(obj.chain!);
    writer
      ..writeString(obj.spendable)
      ..writeString(obj.unspendable);
    if (_legacyPubkeysSchema == LegacyPubkeysSchema.v3) {
      writer.writeBool(obj.gasfreeAddress != null);
      if (obj.gasfreeAddress != null) writer.writeString(obj.gasfreeAddress!);
      writer.writeBool(true);
    }
  }
}

class LegacyHiveAssetPubkeysRecordAdapter
    extends TypeAdapter<LegacyHiveAssetPubkeysRecord> {
  @override
  final int typeId = _legacyHiveAssetPubkeysRecordTypeId;

  @override
  LegacyHiveAssetPubkeysRecord read(BinaryReader reader) {
    final available = reader.readInt();
    final sync = reader.readString();
    final length = reader.readInt();
    final keys = <LegacyHiveStoredPubkey>[];
    for (var i = 0; i < length; i++) {
      keys.add(reader.read() as LegacyHiveStoredPubkey);
    }
    return LegacyHiveAssetPubkeysRecord(
      available: available,
      sync: sync,
      keys: keys,
    );
  }

  @override
  void write(BinaryWriter writer, LegacyHiveAssetPubkeysRecord obj) {
    writer
      ..writeInt(obj.available)
      ..writeString(obj.sync)
      ..writeInt(obj.keys.length);
    for (final key in obj.keys) {
      writer.write(key);
    }
  }
}

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

  /// Whether this address has ever been observed holding funds.
  ///
  /// Retained for backward compatibility with the wallet-scoped pubkey cache
  /// schema; it does not alter which typed KDF addresses the SDK exposes.
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

final _legacyStoredPubkeyAdapter = LegacyHiveStoredPubkeyAdapter();

void setLegacyPubkeysSchema(LegacyPubkeysSchema schema) {
  _legacyPubkeysSchema = schema;
}

void registerPubkeysAdapters() {
  if (!Hive.isAdapterRegistered(_legacyHiveStoredPubkeyTypeId)) {
    Hive.registerAdapter(_legacyStoredPubkeyAdapter);
  }
  if (!Hive.isAdapterRegistered(_legacyHiveAssetPubkeysRecordTypeId)) {
    Hive.registerAdapter(LegacyHiveAssetPubkeysRecordAdapter());
  }
  if (!Hive.isAdapterRegistered(_hiveStoredPubkeyTypeId)) {
    Hive.registerAdapter(HiveStoredPubkeyAdapter());
  }
  if (!Hive.isAdapterRegistered(_hiveAssetPubkeysRecordTypeId)) {
    Hive.registerAdapter(HiveAssetPubkeysRecordAdapter());
  }
}
