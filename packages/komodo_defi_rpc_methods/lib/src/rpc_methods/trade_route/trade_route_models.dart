import 'dart:convert';

import 'package:komodo_defi_rpc_methods/src/models/base_response.dart';
import 'package:meta/meta.dart';

typedef RouteJson = Map<String, dynamic>;

abstract interface class WireNamed {
  String get wireName;
}

/// A typed wire enum that retains future values instead of guessing.
@immutable
final class WireEnumValue<T extends Enum> {
  WireEnumValue.known(T value)
    : knownValue = value,
      rawValue = (value as WireNamed).wireName;

  const WireEnumValue.unknown(this.rawValue) : knownValue = null;

  final T? knownValue;
  final String rawValue;

  bool get isKnown => knownValue != null;
  bool get isExecutable => isKnown;

  @override
  bool operator ==(Object other) =>
      other is WireEnumValue<T> && other.rawValue == rawValue;

  @override
  int get hashCode => rawValue.hashCode;

  @override
  String toString() => rawValue;
}

enum ChainFamily implements WireNamed {
  evm('evm'),
  utxo('utxo'),
  svm('svm'),
  tvm('tvm'),
  mvm('mvm'),
  sui('sui');

  const ChainFamily(this.wireName);
  @override
  final String wireName;
}

enum AssetKind implements WireNamed {
  native('native'),
  token('token');

  const AssetKind(this.wireName);
  @override
  final String wireName;
}

enum RouteBip44Chain implements WireNamed {
  external('External'),
  internal('Internal');

  const RouteBip44Chain(this.wireName);
  @override
  final String wireName;
}

enum ExternalProvider implements WireNamed {
  lifi('lifi'),
  oneInch('one_inch');

  const ExternalProvider(this.wireName);
  @override
  final String wireName;
}

enum ExecutionMode implements WireNamed {
  signOnly('sign_only'),
  signAndBroadcast('sign_and_broadcast');

  const ExecutionMode(this.wireName);
  @override
  final String wireName;
}

enum FeeType implements WireNamed {
  provider('provider'),
  bridge('bridge'),
  exchange('exchange'),
  network('network'),
  kdf('kdf');

  const FeeType(this.wireName);
  @override
  final String wireName;
}

enum ValuationCurrency implements WireNamed {
  usd('USD');

  const ValuationCurrency(this.wireName);
  @override
  final String wireName;
}

enum ValuationSource implements WireNamed {
  walletMarketData('wallet_market_data');

  const ValuationSource(this.wireName);
  @override
  final String wireName;
}

enum AtomicSide implements WireNamed {
  takeAsk('take_ask'),
  takeBid('take_bid');

  const AtomicSide(this.wireName);
  @override
  final String wireName;
}

enum RouteSource implements WireNamed {
  kdf('kdf'),
  lifi('lifi'),
  mixed('mixed');

  const RouteSource(this.wireName);
  @override
  final String wireName;
}

enum RouteWarning implements WireNamed {
  notAtomicEndToEnd('not_atomic_end_to_end'),
  makerOrderNotReserved('maker_order_not_reserved'),
  clientMaterializedTransaction('client_materialized_transaction'),
  bridgeRecoveryRequired('bridge_recovery_required'),
  intermediateAssetPossible('intermediate_asset_possible'),
  unrankableFees('unrankable_fees');

  const RouteWarning(this.wireName);
  @override
  final String wireName;
}

enum RankStatus implements WireNamed {
  ranked('ranked'),
  unrankable('unrankable');

  const RankStatus(this.wireName);
  @override
  final String wireName;
}

enum CandidateSource implements WireNamed {
  kdfAtomic('kdf_atomic'),
  external('external');

  const CandidateSource(this.wireName);
  @override
  final String wireName;
}

enum PreparedExecutionStageKind implements WireNamed {
  kdfAtomic('kdf_atomic'),
  externalLiquidity('external_liquidity');

  const PreparedExecutionStageKind(this.wireName);
  @override
  final String wireName;
}

enum RankingPolicy implements WireNamed {
  maximumNetMinimumReceive('maximum_net_minimum_receive');

  const RankingPolicy(this.wireName);
  @override
  final String wireName;
}

enum RouteActivityConsentType implements WireNamed {
  activityReattachment('activity_reattachment');

  const RouteActivityConsentType(this.wireName);
  @override
  final String wireName;
}

enum ProviderMaterialization implements WireNamed {
  simpleQuote('simple_quote'),
  advancedStep('advanced_step');

  const ProviderMaterialization(this.wireName);
  @override
  final String wireName;
}

enum CapabilityUnavailableReason implements WireNamed {
  assetNotActivated('asset_not_activated'),
  tradeRoleUnsupported('trade_role_unsupported'),
  providerPairUnavailable('provider_pair_unavailable'),
  sourceExecutorUnavailable('source_executor_unavailable'),
  signerPolicyUnsupported('signer_policy_unsupported');

  const CapabilityUnavailableReason(this.wireName);
  @override
  final String wireName;
}

enum PendingUserActionReason implements WireNamed {
  quoteChanged('quote_changed'),
  nonNetworkFeeLimitExceeded('non_network_fee_limit_exceeded'),
  networkFeeCapExceeded('network_fee_cap_exceeded'),
  recoveryRequired('recovery_required');

  const PendingUserActionReason(this.wireName);
  @override
  final String wireName;
}

enum AllowedUserAction implements WireNamed {
  acceptReplacement('accept_replacement'),
  rejectChange('reject_change'),
  selectRecoveryRoute('select_recovery_route'),
  stopAfterCurrent('stop_after_current');

  const AllowedUserAction(this.wireName);
  @override
  final String wireName;
}

final class AllowedUserActionValue {
  AllowedUserActionValue.known(AllowedUserAction value)
    : knownValue = value,
      rawValue = value.wireName;

  const AllowedUserActionValue.unknown(this.rawValue) : knownValue = null;

  factory AllowedUserActionValue.fromWire(String rawValue) {
    final known = AllowedUserAction.values.where(
      (value) => value.wireName == rawValue,
    );
    return known.isEmpty
        ? AllowedUserActionValue.unknown(rawValue)
        : AllowedUserActionValue.known(known.single);
  }

  final AllowedUserAction? knownValue;
  final String rawValue;

  bool get isKnown => knownValue != null;
  bool get isExecutable => isKnown;
}

enum ChainTxStatus implements WireNamed {
  notFound('not_found'),
  pending('pending'),
  confirmed('confirmed'),
  reverted('reverted');

  const ChainTxStatus(this.wireName);
  @override
  final String wireName;
}

enum ExecutionPhase implements WireNamed {
  planned('planned'),
  awaitingApproval('awaiting_approval'),
  approvalPending('approval_pending'),
  awaitingUserAction('awaiting_user_action'),
  awaitingSignature('awaiting_signature'),
  signed('signed'),
  broadcasting('broadcasting'),
  sourcePending('source_pending'),
  sourceConfirmed('source_confirmed'),
  bridgePending('bridge_pending'),
  destinationConfirmed('destination_confirmed'),
  refundPending('refund_pending'),
  partial('partial'),
  refunded('refunded'),
  manualIntervention('manual_intervention'),
  failed('failed'),
  cancelled('cancelled');

  const ExecutionPhase(this.wireName);
  @override
  final String wireName;
}

enum RoutePhase implements WireNamed {
  validating('validating'),
  executingStage('executing_stage'),
  waitingSourceReceipt('waiting_source_receipt'),
  waitingDestination('waiting_destination'),
  atomicFill('atomic_fill'),
  awaitingUserAction('awaiting_user_action'),
  stopAfterCurrent('stop_after_current'),
  manualIntervention('manual_intervention'),
  partial('partial'),
  refundPending('refund_pending'),
  refunded('refunded'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const RoutePhase(this.wireName);
  @override
  final String wireName;
}

enum ApprovalRecoveryInstruction implements WireNamed {
  revokeAllowanceBeforeRetry('revoke_allowance_before_retry'),
  noAllowanceRemains('no_allowance_remains');

  const ApprovalRecoveryInstruction(this.wireName);
  @override
  final String wireName;
}

enum CancelOutcomeKind implements WireNamed {
  cancelled('cancelled'),
  stopAfterCurrent('stop_after_current'),
  reconciliationOnly('reconciliation_only');

  const CancelOutcomeKind(this.wireName);
  @override
  final String wireName;
}

enum SourceTransactionEvidenceState implements WireNamed {
  broadcast('broadcast'),
  confirmed('confirmed');

  const SourceTransactionEvidenceState(this.wireName);
  @override
  final String wireName;
}

enum AtomicSwapEvidenceState implements WireNamed {
  published('published'),
  temporarilyUnavailable('temporarily_unavailable'),
  invalidEvidence('invalid_evidence'),
  failed('failed'),
  completed('completed');

  const AtomicSwapEvidenceState(this.wireName);
  @override
  final String wireName;
}

enum RouteActivityState implements WireNamed {
  active('active'),
  attentionRequired('attention_required'),
  completed('completed'),
  cancelled('cancelled'),
  failed('failed');

  const RouteActivityState(this.wireName);
  @override
  final String wireName;
}

WireEnumValue<T> _wireEnum<T extends Enum>(
  Object? raw,
  List<T> values,
  String path,
) {
  final value = _string(raw, path);
  for (final candidate in values) {
    if ((candidate as WireNamed).wireName == value) {
      return WireEnumValue<T>.known(candidate);
    }
  }
  return WireEnumValue<T>.unknown(value);
}

RouteJson _object(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be a JSON object.');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _strictKeys(
  RouteJson json,
  String path, {
  required Set<String> required,
  Set<String> optional = const {},
}) {
  final missing = required.difference(json.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException('$path is missing ${missing.join(', ')}.');
  }
  final unknown = json.keys.toSet().difference({...required, ...optional});
  if (unknown.isNotEmpty) {
    throw FormatException(
      '$path contains unknown fields: ${unknown.join(', ')}.',
    );
  }
}

String _string(Object? value, String path) {
  if (value is! String) throw FormatException('$path must be a string.');
  return value;
}

String? _nullableString(Object? value, String path) =>
    value == null ? null : _string(value, path);

int _integer(Object? value, String path) {
  if (value is! int) throw FormatException('$path must be an integer.');
  return value;
}

int? _nullableInteger(Object? value, String path) =>
    value == null ? null : _integer(value, path);

bool _boolean(Object? value, String path) {
  if (value is! bool) throw FormatException('$path must be a boolean.');
  return value;
}

DateTime _timestamp(Object? value, String path) {
  final raw = _string(value, path);
  final timestamp = DateTime.tryParse(raw);
  if (timestamp == null || !timestamp.isUtc) {
    throw FormatException('$path must be an RFC 3339 UTC timestamp.');
  }
  return timestamp;
}

DateTime? _nullableTimestamp(Object? value, String path) =>
    value == null ? null : _timestamp(value, path);

List<T> _list<T>(
  Object? value,
  String path,
  T Function(Object? value, String path) parse,
) {
  if (value is! List) throw FormatException('$path must be a JSON array.');
  return List<T>.unmodifiable([
    for (var index = 0; index < value.length; index++)
      parse(value[index], '$path[$index]'),
  ]);
}

List<String> _strings(Object? value, String path) =>
    _list(value, path, _string);

String _uuid(Object? value, String path) {
  final raw = _string(value, path);
  if (!RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(raw)) {
    throw FormatException('$path must be a UUID.');
  }
  return raw;
}

String _amount(Object? value, String path, {bool allowZero = true}) {
  final raw = _string(value, path);
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw) ||
      (!allowZero && raw == '0')) {
    throw FormatException('$path must be a canonical unsigned integer string.');
  }
  return raw;
}

String _decimal(Object? value, String path) {
  final raw = _string(value, path);
  if (!RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(raw)) {
    throw FormatException('$path must be a non-negative plain decimal string.');
  }
  return raw;
}

String _dateJson(DateTime value) => value.toUtc().toIso8601String();

Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      _object(
        value,
        'payload',
      ).map((key, nested) => MapEntry(key, _freezeJson(nested))),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw const FormatException('payload contains a non-JSON value.');
}

RouteJson _cloneJsonMap(RouteJson value) =>
    jsonDecode(jsonEncode(value)) as RouteJson;

void _requireKnown<T extends Enum>(WireEnumValue<T> value, String path) {
  if (!value.isExecutable) {
    throw StateError('$path has unsupported value "${value.rawValue}".');
  }
}

final class RouteAsset {
  RouteAsset({
    required this.ticker,
    required ChainFamily chainFamily,
    required this.chainId,
    required AssetKind assetKind,
    required this.contractAddress,
    required this.decimals,
  }) : chainFamilyValue = WireEnumValue.known(chainFamily),
       assetKindValue = WireEnumValue.known(assetKind) {
    _validate();
  }

  RouteAsset._({
    required this.ticker,
    required this.chainFamilyValue,
    required this.chainId,
    required this.assetKindValue,
    required this.contractAddress,
    required this.decimals,
  });

  factory RouteAsset.fromJson(RouteJson json, [String path = 'asset']) {
    _strictKeys(
      json,
      path,
      required: {
        'ticker',
        'chain_family',
        'chain_id',
        'asset_kind',
        'contract_address',
        'decimals',
      },
    );
    final result = RouteAsset._(
      ticker: _string(json['ticker'], '$path.ticker'),
      chainFamilyValue: _wireEnum(
        json['chain_family'],
        ChainFamily.values,
        '$path.chain_family',
      ),
      chainId: _string(json['chain_id'], '$path.chain_id'),
      assetKindValue: _wireEnum(
        json['asset_kind'],
        AssetKind.values,
        '$path.asset_kind',
      ),
      contractAddress: _nullableString(
        json['contract_address'],
        '$path.contract_address',
      ),
      decimals: _integer(json['decimals'], '$path.decimals'),
    );
    if (result.chainFamilyValue.isKnown && result.assetKindValue.isKnown) {
      result._validate();
    }
    return result;
  }

  final String ticker;
  final WireEnumValue<ChainFamily> chainFamilyValue;
  final String chainId;
  final WireEnumValue<AssetKind> assetKindValue;
  final String? contractAddress;
  final int decimals;

  ChainFamily? get chainFamily => chainFamilyValue.knownValue;
  AssetKind? get assetKind => assetKindValue.knownValue;
  bool get isExecutable =>
      chainFamilyValue.isExecutable && assetKindValue.isExecutable;

  void _validate() {
    if (ticker.isEmpty || ticker.trim() != ticker || ticker.length > 64) {
      throw ArgumentError.value(
        ticker,
        'ticker',
        'must be trimmed and non-empty',
      );
    }
    if (chainId.isEmpty || chainId.trim() != chainId || chainId.length > 128) {
      throw ArgumentError.value(
        chainId,
        'chainId',
        'must be trimmed and non-empty',
      );
    }
    if (decimals < 0 || decimals > 255) {
      throw RangeError.range(decimals, 0, 255, 'decimals');
    }
    switch (assetKindValue.knownValue) {
      case AssetKind.native when contractAddress != null:
        throw ArgumentError.value(
          contractAddress,
          'contractAddress',
          'must be null for native assets',
        );
      case AssetKind.token
          when contractAddress == null ||
              contractAddress!.isEmpty ||
              contractAddress!.trim() != contractAddress:
        throw ArgumentError.value(
          contractAddress,
          'contractAddress',
          'is required for token assets',
        );
      case AssetKind.native:
      case AssetKind.token:
      case null:
        break;
    }
  }

  RouteJson toJson() => {
    'ticker': ticker,
    'chain_family': chainFamilyValue.rawValue,
    'chain_id': chainId,
    'asset_kind': assetKindValue.rawValue,
    'contract_address': contractAddress,
    'decimals': decimals,
  };

  RouteJson toRequestJson() {
    _requireKnown(chainFamilyValue, 'asset.chain_family');
    _requireKnown(assetKindValue, 'asset.asset_kind');
    _validate();
    return toJson();
  }
}

sealed class SourceAddressSelector {
  const SourceAddressSelector();

  factory SourceAddressSelector.active() = ActiveSourceAddressSelector;

  factory SourceAddressSelector.hdAddress({
    required int accountId,
    required RouteBip44Chain chain,
    required int addressId,
  }) = HdAddressIdSourceSelector;

  factory SourceAddressSelector.hdDerivationPath({
    required String derivationPath,
  }) = HdDerivationPathSourceSelector;

  factory SourceAddressSelector.fromJson(
    RouteJson json, [
    String path = 'source_address',
  ]) {
    final discriminator = _string(json['selector_type'], '$path.selector_type');
    return switch (discriminator) {
      'active' => ActiveSourceAddressSelector.fromJson(json, path),
      'hd' => _parseHdSourceSelector(json, path),
      _ => UnknownSourceAddressSelector(discriminator, json),
    };
  }

  String get selectorType;
  bool get isExecutable;
  RouteJson toJson();

  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('Unsupported source selector "$selectorType".');
    }
    return toJson();
  }
}

final class ActiveSourceAddressSelector extends SourceAddressSelector {
  const ActiveSourceAddressSelector();

  factory ActiveSourceAddressSelector.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'selector_type'});
    return const ActiveSourceAddressSelector();
  }

  @override
  String get selectorType => 'active';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {'selector_type': selectorType};
}

final class HdAddressIdSourceSelector extends SourceAddressSelector {
  HdAddressIdSourceSelector({
    required this.accountId,
    required RouteBip44Chain chain,
    required this.addressId,
  }) : chainValue = WireEnumValue.known(chain) {
    if (accountId < 0 || addressId < 0) {
      throw RangeError('HD address indexes must be non-negative.');
    }
  }

  HdAddressIdSourceSelector._({
    required this.accountId,
    required this.chainValue,
    required this.addressId,
  });

  final int accountId;
  final WireEnumValue<RouteBip44Chain> chainValue;
  final int addressId;

  @override
  String get selectorType => 'hd';
  @override
  bool get isExecutable => chainValue.isExecutable;

  @override
  RouteJson toJson() => {
    'selector_type': selectorType,
    'selector': {
      'account_id': accountId,
      'chain': chainValue.rawValue,
      'address_id': addressId,
    },
  };
}

final class HdDerivationPathSourceSelector extends SourceAddressSelector {
  HdDerivationPathSourceSelector({required this.derivationPath}) {
    if (derivationPath.isEmpty || derivationPath.trim() != derivationPath) {
      throw ArgumentError.value(derivationPath, 'derivationPath');
    }
  }

  final String derivationPath;

  @override
  String get selectorType => 'hd';
  @override
  bool get isExecutable => true;

  @override
  RouteJson toJson() => {
    'selector_type': selectorType,
    'selector': {'derivation_path': derivationPath},
  };
}

final class UnknownSourceAddressSelector extends SourceAddressSelector {
  UnknownSourceAddressSelector(this.selectorType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));

  @override
  final String selectorType;
  final RouteJson rawPayload;

  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

SourceAddressSelector _parseHdSourceSelector(RouteJson json, String path) {
  _strictKeys(json, path, required: {'selector_type', 'selector'});
  final selector = _object(json['selector'], '$path.selector');
  if (selector.containsKey('derivation_path')) {
    _strictKeys(selector, '$path.selector', required: {'derivation_path'});
    return HdDerivationPathSourceSelector(
      derivationPath: _string(
        selector['derivation_path'],
        '$path.selector.derivation_path',
      ),
    );
  }
  _strictKeys(
    selector,
    '$path.selector',
    required: {'account_id', 'chain', 'address_id'},
  );
  return HdAddressIdSourceSelector._(
    accountId: _integer(selector['account_id'], '$path.selector.account_id'),
    chainValue: _wireEnum(
      selector['chain'],
      RouteBip44Chain.values,
      '$path.selector.chain',
    ),
    addressId: _integer(selector['address_id'], '$path.selector.address_id'),
  );
}

final class ToolFilter {
  ToolFilter({
    List<String> allow = const [],
    List<String> deny = const [],
    List<String> prefer = const [],
  }) : allow = List.unmodifiable(allow),
       deny = List.unmodifiable(deny),
       prefer = List.unmodifiable(prefer);

  factory ToolFilter.fromJson(RouteJson json, [String path = 'tool_filter']) {
    _strictKeys(
      json,
      path,
      required: {},
      optional: {'allow', 'deny', 'prefer'},
    );
    return ToolFilter(
      allow: json.containsKey('allow')
          ? _strings(json['allow'], '$path.allow')
          : const [],
      deny: json.containsKey('deny')
          ? _strings(json['deny'], '$path.deny')
          : const [],
      prefer: json.containsKey('prefer')
          ? _strings(json['prefer'], '$path.prefer')
          : const [],
    );
  }

  final List<String> allow;
  final List<String> deny;
  final List<String> prefer;

  RouteJson toJson() => {'allow': allow, 'deny': deny, 'prefer': prefer};
}

final class ToolPolicy {
  ToolPolicy({ToolFilter? bridges, ToolFilter? exchanges})
    : bridges = bridges ?? ToolFilter(),
      exchanges = exchanges ?? ToolFilter();

  factory ToolPolicy.fromJson(RouteJson json, [String path = 'tool_policy']) {
    _strictKeys(json, path, required: {'bridges', 'exchanges'});
    return ToolPolicy(
      bridges: ToolFilter.fromJson(
        _object(json['bridges'], '$path.bridges'),
        '$path.bridges',
      ),
      exchanges: ToolFilter.fromJson(
        _object(json['exchanges'], '$path.exchanges'),
        '$path.exchanges',
      ),
    );
  }

  final ToolFilter bridges;
  final ToolFilter exchanges;
  RouteJson toJson() => {
    'bridges': bridges.toJson(),
    'exchanges': exchanges.toJson(),
  };
}

final class SelectedTools {
  SelectedTools({
    List<String> bridges = const [],
    List<String> exchanges = const [],
  }) : bridges = List.unmodifiable(bridges),
       exchanges = List.unmodifiable(exchanges);

  factory SelectedTools.fromJson(
    RouteJson json, [
    String path = 'selected_tools',
  ]) {
    _strictKeys(json, path, required: {'bridges', 'exchanges'});
    return SelectedTools(
      bridges: _strings(json['bridges'], '$path.bridges'),
      exchanges: _strings(json['exchanges'], '$path.exchanges'),
    );
  }

  final List<String> bridges;
  final List<String> exchanges;
  RouteJson toJson() => {'bridges': bridges, 'exchanges': exchanges};
}

final class TradeIntent {
  TradeIntent({
    required this.fromAsset,
    required this.toAsset,
    required String sourceAmount,
    required this.sourceAddress,
    required this.recipient,
    required this.toolPolicy,
    required this.consentExpiresAt,
    this.minimumReceive,
    this.slippageBps,
  }) : sourceAmount = _amount(sourceAmount, 'sourceAmount', allowZero: false) {
    if (minimumReceive != null) _amount(minimumReceive, 'minimumReceive');
    if (slippageBps != null && (slippageBps! < 0 || slippageBps! > 10000)) {
      throw RangeError.range(slippageBps!, 0, 10000, 'slippageBps');
    }
  }

  factory TradeIntent.fromJson(RouteJson json, [String path = 'intent']) {
    _strictKeys(
      json,
      path,
      required: {
        'from_asset',
        'to_asset',
        'source_amount',
        'minimum_receive',
        'slippage_bps',
        'source_address',
        'recipient',
        'tool_policy',
        'consent_expires_at',
      },
    );
    return TradeIntent(
      fromAsset: RouteAsset.fromJson(
        _object(json['from_asset'], '$path.from_asset'),
        '$path.from_asset',
      ),
      toAsset: RouteAsset.fromJson(
        _object(json['to_asset'], '$path.to_asset'),
        '$path.to_asset',
      ),
      sourceAmount: _amount(
        json['source_amount'],
        '$path.source_amount',
        allowZero: false,
      ),
      minimumReceive: json['minimum_receive'] == null
          ? null
          : _amount(json['minimum_receive'], '$path.minimum_receive'),
      slippageBps: _nullableInteger(json['slippage_bps'], '$path.slippage_bps'),
      sourceAddress: SourceAddressSelector.fromJson(
        _object(json['source_address'], '$path.source_address'),
        '$path.source_address',
      ),
      recipient: _string(json['recipient'], '$path.recipient'),
      toolPolicy: ToolPolicy.fromJson(
        _object(json['tool_policy'], '$path.tool_policy'),
        '$path.tool_policy',
      ),
      consentExpiresAt: _timestamp(
        json['consent_expires_at'],
        '$path.consent_expires_at',
      ),
    );
  }

  final RouteAsset fromAsset;
  final RouteAsset toAsset;
  final String sourceAmount;
  final String? minimumReceive;
  final int? slippageBps;
  final SourceAddressSelector sourceAddress;
  final String recipient;
  final ToolPolicy toolPolicy;
  final DateTime consentExpiresAt;

  bool get isExecutable =>
      fromAsset.isExecutable &&
      toAsset.isExecutable &&
      sourceAddress.isExecutable;

  RouteJson toJson() => {
    'from_asset': fromAsset.toJson(),
    'to_asset': toAsset.toJson(),
    'source_amount': sourceAmount,
    'minimum_receive': minimumReceive,
    'slippage_bps': slippageBps,
    'source_address': sourceAddress.toJson(),
    'recipient': recipient,
    'tool_policy': toolPolicy.toJson(),
    'consent_expires_at': _dateJson(consentExpiresAt),
  };

  RouteJson toRequestJson() {
    if (!isExecutable) throw StateError('TradeIntent is not executable.');
    final result = toJson();
    result['from_asset'] = fromAsset.toRequestJson();
    result['to_asset'] = toAsset.toRequestJson();
    result['source_address'] = sourceAddress.toRequestJson();
    return result;
  }
}

final class FeeValuation {
  FeeValuation({
    required ValuationCurrency currency,
    required String amount,
    required ValuationSource source,
    required this.observedAt,
  }) : currencyValue = WireEnumValue.known(currency),
       amount = _decimal(amount, 'amount'),
       sourceValue = WireEnumValue.known(source);

  FeeValuation._({
    required this.currencyValue,
    required this.amount,
    required this.sourceValue,
    required this.observedAt,
  });

  factory FeeValuation.fromJson(
    RouteJson json, [
    String path = 'fee_valuation',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'currency', 'amount', 'source', 'observed_at'},
    );
    return FeeValuation._(
      currencyValue: _wireEnum(
        json['currency'],
        ValuationCurrency.values,
        '$path.currency',
      ),
      amount: _decimal(json['amount'], '$path.amount'),
      sourceValue: _wireEnum(
        json['source'],
        ValuationSource.values,
        '$path.source',
      ),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
    );
  }

  final WireEnumValue<ValuationCurrency> currencyValue;
  final String amount;
  final WireEnumValue<ValuationSource> sourceValue;
  final DateTime observedAt;

  bool get isExecutable =>
      currencyValue.isExecutable && sourceValue.isExecutable;
  RouteJson toJson() => {
    'currency': currencyValue.rawValue,
    'amount': amount,
    'source': sourceValue.rawValue,
    'observed_at': _dateJson(observedAt),
  };
}

final class FeeComponent {
  FeeComponent({
    required FeeType feeType,
    required this.asset,
    required String amount,
    required this.included,
    this.valuation,
  }) : feeTypeValue = WireEnumValue.known(feeType),
       amount = _amount(amount, 'amount');

  FeeComponent._({
    required this.feeTypeValue,
    required this.asset,
    required this.amount,
    required this.included,
    required this.valuation,
  });

  factory FeeComponent.fromJson(RouteJson json, [String path = 'fee']) {
    _strictKeys(
      json,
      path,
      required: {'fee_type', 'asset', 'amount', 'included', 'valuation'},
    );
    return FeeComponent._(
      feeTypeValue: _wireEnum(
        json['fee_type'],
        FeeType.values,
        '$path.fee_type',
      ),
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      amount: _amount(json['amount'], '$path.amount'),
      included: _boolean(json['included'], '$path.included'),
      valuation: json['valuation'] == null
          ? null
          : FeeValuation.fromJson(
              _object(json['valuation'], '$path.valuation'),
              '$path.valuation',
            ),
    );
  }

  final WireEnumValue<FeeType> feeTypeValue;
  final RouteAsset asset;
  final String amount;
  final bool included;
  final FeeValuation? valuation;

  bool get isExecutable =>
      feeTypeValue.isExecutable &&
      asset.isExecutable &&
      (valuation?.isExecutable ?? true);
  RouteJson toJson() => {
    'fee_type': feeTypeValue.rawValue,
    'asset': asset.toJson(),
    'amount': amount,
    'included': included,
    'valuation': valuation?.toJson(),
  };
}

final class FeeLimit {
  FeeLimit({
    required FeeType feeType,
    required this.asset,
    required String maxAmount,
  }) : feeTypeValue = WireEnumValue.known(feeType),
       maxAmount = _amount(maxAmount, 'maxAmount');

  FeeLimit._({
    required this.feeTypeValue,
    required this.asset,
    required this.maxAmount,
  });

  factory FeeLimit.fromJson(RouteJson json, [String path = 'fee_limit']) {
    _strictKeys(json, path, required: {'fee_type', 'asset', 'max_amount'});
    return FeeLimit._(
      feeTypeValue: _wireEnum(
        json['fee_type'],
        FeeType.values,
        '$path.fee_type',
      ),
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      maxAmount: _amount(json['max_amount'], '$path.max_amount'),
    );
  }

  final WireEnumValue<FeeType> feeTypeValue;
  final RouteAsset asset;
  final String maxAmount;
  bool get isExecutable => feeTypeValue.isExecutable && asset.isExecutable;
  RouteJson toJson() => {
    'fee_type': feeTypeValue.rawValue,
    'asset': asset.toJson(),
    'max_amount': maxAmount,
  };
}

final class FeeCap {
  FeeCap({required this.asset, required String amount})
    : amount = _amount(amount, 'amount');

  factory FeeCap.fromJson(RouteJson json, [String path = 'fee_cap']) {
    _strictKeys(json, path, required: {'asset', 'amount'});
    return FeeCap(
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      amount: _amount(json['amount'], '$path.amount'),
    );
  }

  final RouteAsset asset;
  final String amount;
  bool get isExecutable => asset.isExecutable;
  RouteJson toJson() => {'asset': asset.toJson(), 'amount': amount};
}

final class PrepareExecutionStageLimits {
  PrepareExecutionStageLimits({
    required String stageId,
    required this.maxExpectedReceiveDegradationBps,
    required List<FeeLimit> nonNetworkFeeLimits,
    required this.maxTotalNetworkFee,
  }) : stageId = _uuid(stageId, 'stageId'),
       nonNetworkFeeLimits = List.unmodifiable(nonNetworkFeeLimits) {
    if (maxExpectedReceiveDegradationBps < 0 ||
        maxExpectedReceiveDegradationBps > 10000) {
      throw RangeError.range(
        maxExpectedReceiveDegradationBps,
        0,
        10000,
        'maxExpectedReceiveDegradationBps',
      );
    }
  }

  factory PrepareExecutionStageLimits.fromJson(
    RouteJson json, [
    String path = 'stage_limits',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'stage_id',
        'max_expected_receive_degradation_bps',
        'non_network_fee_limits',
        'max_total_network_fee',
      },
    );
    return PrepareExecutionStageLimits(
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      maxExpectedReceiveDegradationBps: _integer(
        json['max_expected_receive_degradation_bps'],
        '$path.max_expected_receive_degradation_bps',
      ),
      nonNetworkFeeLimits: _list(
        json['non_network_fee_limits'],
        '$path.non_network_fee_limits',
        (value, itemPath) =>
            FeeLimit.fromJson(_object(value, itemPath), itemPath),
      ),
      maxTotalNetworkFee: FeeCap.fromJson(
        _object(json['max_total_network_fee'], '$path.max_total_network_fee'),
        '$path.max_total_network_fee',
      ),
    );
  }

  final String stageId;
  final int maxExpectedReceiveDegradationBps;
  final List<FeeLimit> nonNetworkFeeLimits;
  final FeeCap maxTotalNetworkFee;

  bool get isExecutable =>
      nonNetworkFeeLimits.every((limit) => limit.isExecutable) &&
      maxTotalNetworkFee.isExecutable;

  RouteJson toJson() => {
    'stage_id': stageId,
    'max_expected_receive_degradation_bps': maxExpectedReceiveDegradationBps,
    'non_network_fee_limits': nonNetworkFeeLimits
        .map((limit) => limit.toJson())
        .toList(growable: false),
    'max_total_network_fee': maxTotalNetworkFee.toJson(),
  };

  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('Prepare-execution stage limits are not executable.');
    }
    return toJson();
  }
}

sealed class PreparedApproval {
  const PreparedApproval();

  factory PreparedApproval.fromJson(
    RouteJson json, [
    String path = 'approval',
  ]) {
    final discriminator = _string(json['approval_type'], '$path.approval_type');
    return switch (discriminator) {
      'not_applicable' => NotApplicablePreparedApproval.fromJson(json, path),
      'sufficient_allowance' => SufficientAllowancePreparedApproval.fromJson(
        json,
        path,
      ),
      'exact_approval_required' =>
        ExactApprovalRequiredPreparedApproval.fromJson(json, path),
      _ => UnknownPreparedApproval(discriminator, json),
    };
  }

  String get approvalType;
  bool get isExecutable;
  RouteJson toJson();
}

final class NotApplicablePreparedApproval extends PreparedApproval {
  const NotApplicablePreparedApproval();

  factory NotApplicablePreparedApproval.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'approval_type'});
    return const NotApplicablePreparedApproval();
  }

  @override
  String get approvalType => 'not_applicable';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {'approval_type': approvalType};
}

final class SufficientAllowancePreparedApproval extends PreparedApproval {
  SufficientAllowancePreparedApproval({
    required this.token,
    required this.spender,
    required String currentAllowance,
    required String requiredAmount,
  }) : currentAllowance = _amount(currentAllowance, 'currentAllowance'),
       requiredAmount = _amount(requiredAmount, 'requiredAmount');

  factory SufficientAllowancePreparedApproval.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'approval_type',
        'token',
        'spender',
        'current_allowance',
        'required_amount',
      },
    );
    return SufficientAllowancePreparedApproval(
      token: RouteAsset.fromJson(
        _object(json['token'], '$path.token'),
        '$path.token',
      ),
      spender: _string(json['spender'], '$path.spender'),
      currentAllowance: _amount(
        json['current_allowance'],
        '$path.current_allowance',
      ),
      requiredAmount: _amount(json['required_amount'], '$path.required_amount'),
    );
  }

  final RouteAsset token;
  final String spender;
  final String currentAllowance;
  final String requiredAmount;

  @override
  String get approvalType => 'sufficient_allowance';
  @override
  bool get isExecutable => token.isExecutable;
  @override
  RouteJson toJson() => {
    'approval_type': approvalType,
    'token': token.toJson(),
    'spender': spender,
    'current_allowance': currentAllowance,
    'required_amount': requiredAmount,
  };
}

final class ExactApprovalRequiredPreparedApproval extends PreparedApproval {
  ExactApprovalRequiredPreparedApproval({
    required this.token,
    required this.spender,
    required String currentAllowance,
    required String requiredAmount,
    required this.resetRequired,
  }) : currentAllowance = _amount(currentAllowance, 'currentAllowance'),
       requiredAmount = _amount(requiredAmount, 'requiredAmount');

  factory ExactApprovalRequiredPreparedApproval.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'approval_type',
        'token',
        'spender',
        'current_allowance',
        'required_amount',
        'reset_required',
      },
    );
    return ExactApprovalRequiredPreparedApproval(
      token: RouteAsset.fromJson(
        _object(json['token'], '$path.token'),
        '$path.token',
      ),
      spender: _string(json['spender'], '$path.spender'),
      currentAllowance: _amount(
        json['current_allowance'],
        '$path.current_allowance',
      ),
      requiredAmount: _amount(json['required_amount'], '$path.required_amount'),
      resetRequired: _boolean(json['reset_required'], '$path.reset_required'),
    );
  }

  final RouteAsset token;
  final String spender;
  final String currentAllowance;
  final String requiredAmount;
  final bool resetRequired;

  @override
  String get approvalType => 'exact_approval_required';
  @override
  bool get isExecutable => token.isExecutable;
  @override
  RouteJson toJson() => {
    'approval_type': approvalType,
    'token': token.toJson(),
    'spender': spender,
    'current_allowance': currentAllowance,
    'required_amount': requiredAmount,
    'reset_required': resetRequired,
  };
}

final class UnknownPreparedApproval extends PreparedApproval {
  UnknownPreparedApproval(this.approvalType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));

  @override
  final String approvalType;
  final RouteJson rawPayload;

  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class PreparedStageExecution {
  const PreparedStageExecution({
    required this.resolvedSourceAddress,
    required this.approval,
    required this.requiredMaxNetworkFee,
  });

  factory PreparedStageExecution.fromJson(
    RouteJson json, [
    String path = 'prepared_execution',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'resolved_source_address',
        'approval',
        'required_max_network_fee',
      },
    );
    return PreparedStageExecution(
      resolvedSourceAddress: _string(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      approval: PreparedApproval.fromJson(
        _object(json['approval'], '$path.approval'),
        '$path.approval',
      ),
      requiredMaxNetworkFee: FeeCap.fromJson(
        _object(
          json['required_max_network_fee'],
          '$path.required_max_network_fee',
        ),
        '$path.required_max_network_fee',
      ),
    );
  }

  final String resolvedSourceAddress;
  final PreparedApproval approval;
  final FeeCap requiredMaxNetworkFee;

  bool get isExecutable =>
      approval.isExecutable && requiredMaxNetworkFee.isExecutable;

  RouteJson toJson() => {
    'resolved_source_address': resolvedSourceAddress,
    'approval': approval.toJson(),
    'required_max_network_fee': requiredMaxNetworkFee.toJson(),
  };
}

final class AssetAmount {
  AssetAmount({required this.asset, required String amount})
    : amount = _amount(amount, 'amount');

  factory AssetAmount.fromJson(RouteJson json, [String path = 'asset_amount']) {
    _strictKeys(json, path, required: {'asset', 'amount'});
    return AssetAmount(
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      amount: _amount(json['amount'], '$path.amount'),
    );
  }

  final RouteAsset asset;
  final String amount;
  bool get isExecutable => asset.isExecutable;
  RouteJson toJson() => {'asset': asset.toJson(), 'amount': amount};
}

final class AssetValuationPrice {
  AssetValuationPrice({
    required this.asset,
    required String price,
    required this.observedAt,
  }) : price = _decimal(price, 'price');

  factory AssetValuationPrice.fromJson(
    RouteJson json, [
    String path = 'price',
  ]) {
    _strictKeys(json, path, required: {'asset', 'price', 'observed_at'});
    return AssetValuationPrice(
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      price: _decimal(json['price'], '$path.price'),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
    );
  }

  final RouteAsset asset;
  final String price;
  final DateTime observedAt;
  bool get isExecutable => asset.isExecutable;
  RouteJson toJson() => {
    'asset': asset.toJson(),
    'price': price,
    'observed_at': _dateJson(observedAt),
  };
}

final class ValuationSnapshot {
  ValuationSnapshot({
    required ValuationCurrency currency,
    required ValuationSource source,
    required this.observedAt,
    required this.validUntil,
    required List<AssetValuationPrice> prices,
  }) : currencyValue = WireEnumValue.known(currency),
       sourceValue = WireEnumValue.known(source),
       prices = List.unmodifiable(prices);

  ValuationSnapshot._({
    required this.currencyValue,
    required this.sourceValue,
    required this.observedAt,
    required this.validUntil,
    required this.prices,
  });

  factory ValuationSnapshot.fromJson(
    RouteJson json, [
    String path = 'valuation_snapshot',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'currency', 'source', 'observed_at', 'valid_until', 'prices'},
    );
    return ValuationSnapshot._(
      currencyValue: _wireEnum(
        json['currency'],
        ValuationCurrency.values,
        '$path.currency',
      ),
      sourceValue: _wireEnum(
        json['source'],
        ValuationSource.values,
        '$path.source',
      ),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      validUntil: _timestamp(json['valid_until'], '$path.valid_until'),
      prices: _list(json['prices'], '$path.prices', (value, itemPath) {
        return AssetValuationPrice.fromJson(_object(value, itemPath), itemPath);
      }),
    );
  }

  final WireEnumValue<ValuationCurrency> currencyValue;
  final WireEnumValue<ValuationSource> sourceValue;
  final DateTime observedAt;
  final DateTime validUntil;
  final List<AssetValuationPrice> prices;

  bool get isExecutable =>
      currencyValue.isExecutable &&
      sourceValue.isExecutable &&
      prices.every((price) => price.isExecutable);
  RouteJson toJson() => {
    'currency': currencyValue.rawValue,
    'source': sourceValue.rawValue,
    'observed_at': _dateJson(observedAt),
    'valid_until': _dateJson(validUntil),
    'prices': prices.map((price) => price.toJson()).toList(growable: false),
  };
}

final class ProviderTokenIdentifiers {
  const ProviderTokenIdentifiers({
    required this.fromToken,
    required this.toToken,
  });

  factory ProviderTokenIdentifiers.fromJson(
    RouteJson json, [
    String path = 'provider_tokens',
  ]) {
    _strictKeys(json, path, required: {'from_token', 'to_token'});
    return ProviderTokenIdentifiers(
      fromToken: _string(json['from_token'], '$path.from_token'),
      toToken: _string(json['to_token'], '$path.to_token'),
    );
  }

  final String fromToken;
  final String toToken;
  RouteJson toJson() => {'from_token': fromToken, 'to_token': toToken};
}

final class ProviderChainIdentifiers {
  const ProviderChainIdentifiers({
    required this.fromChain,
    required this.toChain,
  });

  factory ProviderChainIdentifiers.fromJson(
    RouteJson json, [
    String path = 'provider_chain_ids',
  ]) {
    _strictKeys(json, path, required: {'from_chain', 'to_chain'});
    return ProviderChainIdentifiers(
      fromChain: _string(json['from_chain'], '$path.from_chain'),
      toChain: _string(json['to_chain'], '$path.to_chain'),
    );
  }

  final String fromChain;
  final String toChain;
  RouteJson toJson() => {'from_chain': fromChain, 'to_chain': toChain};
}

final class RouteStageCommon {
  RouteStageCommon({
    required String stageId,
    required this.fromAsset,
    required this.toAsset,
    required String sourceAmount,
    required String expectedReceive,
    required String minimumReceive,
    required this.recipient,
    required this.expiresAt,
    required List<FeeComponent> fees,
    required List<RouteWarning> warnings,
  }) : stageId = _uuid(stageId, 'stageId'),
       sourceAmount = _amount(sourceAmount, 'sourceAmount'),
       expectedReceive = _amount(expectedReceive, 'expectedReceive'),
       minimumReceive = _amount(minimumReceive, 'minimumReceive'),
       fees = List.unmodifiable(fees),
       warningValues = List.unmodifiable(
         warnings.map(WireEnumValue<RouteWarning>.known),
       );

  RouteStageCommon._({
    required this.stageId,
    required this.fromAsset,
    required this.toAsset,
    required this.sourceAmount,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.recipient,
    required this.expiresAt,
    required this.fees,
    required this.warningValues,
  });

  static const fieldNames = {
    'stage_id',
    'from_asset',
    'to_asset',
    'source_amount',
    'expected_receive',
    'minimum_receive',
    'recipient',
    'expires_at',
    'fees',
    'warnings',
  };

  // ignore: sort_constructors_first
  factory RouteStageCommon.fromJson(RouteJson json, String path) {
    return RouteStageCommon._(
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      fromAsset: RouteAsset.fromJson(
        _object(json['from_asset'], '$path.from_asset'),
        '$path.from_asset',
      ),
      toAsset: RouteAsset.fromJson(
        _object(json['to_asset'], '$path.to_asset'),
        '$path.to_asset',
      ),
      sourceAmount: _amount(json['source_amount'], '$path.source_amount'),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      recipient: _string(json['recipient'], '$path.recipient'),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
      fees: _list(json['fees'], '$path.fees', (value, itemPath) {
        return FeeComponent.fromJson(_object(value, itemPath), itemPath);
      }),
      warningValues: _list(json['warnings'], '$path.warnings', (
        value,
        itemPath,
      ) {
        return _wireEnum(value, RouteWarning.values, itemPath);
      }),
    );
  }

  final String stageId;
  final RouteAsset fromAsset;
  final RouteAsset toAsset;
  final String sourceAmount;
  final String expectedReceive;
  final String minimumReceive;
  final String recipient;
  final DateTime expiresAt;
  final List<FeeComponent> fees;
  final List<WireEnumValue<RouteWarning>> warningValues;

  List<RouteWarning> get warnings => List.unmodifiable(
    warningValues.map((value) => value.knownValue).whereType<RouteWarning>(),
  );

  bool get isExecutable =>
      fromAsset.isExecutable &&
      toAsset.isExecutable &&
      fees.every((fee) => fee.isExecutable) &&
      warningValues.every((warning) => warning.isExecutable);

  RouteJson toJson() => {
    'stage_id': stageId,
    'from_asset': fromAsset.toJson(),
    'to_asset': toAsset.toJson(),
    'source_amount': sourceAmount,
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'recipient': recipient,
    'expires_at': _dateJson(expiresAt),
    'fees': fees.map((fee) => fee.toJson()).toList(growable: false),
    'warnings': warningValues.map((warning) => warning.rawValue).toList(),
  };
}

sealed class RouteStage {
  const RouteStage();

  factory RouteStage.fromJson(RouteJson json, [String path = 'stage']) {
    final discriminator = _string(json['stage_type'], '$path.stage_type');
    return switch (discriminator) {
      'kdf_atomic' => KdfAtomicRouteStage.fromJson(json, path),
      'external_liquidity' => ExternalLiquidityRouteStage.fromJson(json, path),
      _ => UnknownRouteStage(discriminator, json),
    };
  }

  String get stageType;
  bool get isExecutable;
  RouteJson toJson();

  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('Route stage "$stageType" is not executable.');
    }
    return toJson();
  }
}

final class KdfAtomicRouteStage extends RouteStage {
  KdfAtomicRouteStage({
    required this.common,
    required String tradeSourceAmount,
    required String requestedVolume,
    required String orderUuid,
    required AtomicSide side,
    required String price,
    required String minimumVolume,
    required String maximumVolume,
    required this.orderSnapshotAt,
  }) : tradeSourceAmount = _amount(tradeSourceAmount, 'tradeSourceAmount'),
       requestedVolume = _decimal(requestedVolume, 'requestedVolume'),
       orderUuid = _uuid(orderUuid, 'orderUuid'),
       sideValue = WireEnumValue.known(side),
       price = _decimal(price, 'price'),
       minimumVolume = _decimal(minimumVolume, 'minimumVolume'),
       maximumVolume = _decimal(maximumVolume, 'maximumVolume');

  KdfAtomicRouteStage._({
    required this.common,
    required this.tradeSourceAmount,
    required this.requestedVolume,
    required this.orderUuid,
    required this.sideValue,
    required this.price,
    required this.minimumVolume,
    required this.maximumVolume,
    required this.orderSnapshotAt,
  });

  factory KdfAtomicRouteStage.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'stage_type',
        ...RouteStageCommon.fieldNames,
        'trade_source_amount',
        'requested_volume',
        'order_uuid',
        'side',
        'price',
        'minimum_volume',
        'maximum_volume',
        'order_snapshot_at',
      },
    );
    return KdfAtomicRouteStage._(
      common: RouteStageCommon.fromJson(json, path),
      tradeSourceAmount: _amount(
        json['trade_source_amount'],
        '$path.trade_source_amount',
      ),
      requestedVolume: _decimal(
        json['requested_volume'],
        '$path.requested_volume',
      ),
      orderUuid: _uuid(json['order_uuid'], '$path.order_uuid'),
      sideValue: _wireEnum(json['side'], AtomicSide.values, '$path.side'),
      price: _decimal(json['price'], '$path.price'),
      minimumVolume: _decimal(json['minimum_volume'], '$path.minimum_volume'),
      maximumVolume: _decimal(json['maximum_volume'], '$path.maximum_volume'),
      orderSnapshotAt: _timestamp(
        json['order_snapshot_at'],
        '$path.order_snapshot_at',
      ),
    );
  }

  final RouteStageCommon common;
  final String tradeSourceAmount;
  final String requestedVolume;
  final String orderUuid;
  final WireEnumValue<AtomicSide> sideValue;
  final String price;
  final String minimumVolume;
  final String maximumVolume;
  final DateTime orderSnapshotAt;

  @override
  String get stageType => 'kdf_atomic';
  @override
  bool get isExecutable => common.isExecutable && sideValue.isExecutable;

  @override
  RouteJson toJson() => {
    'stage_type': stageType,
    ...common.toJson(),
    'trade_source_amount': tradeSourceAmount,
    'requested_volume': requestedVolume,
    'order_uuid': orderUuid,
    'side': sideValue.rawValue,
    'price': price,
    'minimum_volume': minimumVolume,
    'maximum_volume': maximumVolume,
    'order_snapshot_at': _dateJson(orderSnapshotAt),
  };
}

final class ExternalLiquidityRouteStage extends RouteStage {
  ExternalLiquidityRouteStage({
    required this.common,
    required ExternalProvider provider,
    required this.providerRouteId,
    required this.toolPolicy,
    required this.selectedTools,
    required this.providerStepDigest,
    this.externalCandidateId,
    this.providerTokens,
    this.providerChainIds,
  }) : providerValue = WireEnumValue.known(provider);

  ExternalLiquidityRouteStage._({
    required this.common,
    required this.providerValue,
    required this.providerRouteId,
    required this.externalCandidateId,
    required this.toolPolicy,
    required this.selectedTools,
    required this.providerTokens,
    required this.providerChainIds,
    required this.providerStepDigest,
  });

  factory ExternalLiquidityRouteStage.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'stage_type',
        ...RouteStageCommon.fieldNames,
        'provider',
        'provider_route_id',
        'tool_policy',
        'selected_tools',
        'provider_step_digest',
      },
      optional: {
        'external_candidate_id',
        'provider_tokens',
        'provider_chain_ids',
      },
    );
    return ExternalLiquidityRouteStage._(
      common: RouteStageCommon.fromJson(json, path),
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      providerRouteId: _string(
        json['provider_route_id'],
        '$path.provider_route_id',
      ),
      externalCandidateId: _nullableString(
        json['external_candidate_id'],
        '$path.external_candidate_id',
      ),
      toolPolicy: ToolPolicy.fromJson(
        _object(json['tool_policy'], '$path.tool_policy'),
        '$path.tool_policy',
      ),
      selectedTools: SelectedTools.fromJson(
        _object(json['selected_tools'], '$path.selected_tools'),
        '$path.selected_tools',
      ),
      providerTokens: json['provider_tokens'] == null
          ? null
          : ProviderTokenIdentifiers.fromJson(
              _object(json['provider_tokens'], '$path.provider_tokens'),
              '$path.provider_tokens',
            ),
      providerChainIds: json['provider_chain_ids'] == null
          ? null
          : ProviderChainIdentifiers.fromJson(
              _object(json['provider_chain_ids'], '$path.provider_chain_ids'),
              '$path.provider_chain_ids',
            ),
      providerStepDigest: _string(
        json['provider_step_digest'],
        '$path.provider_step_digest',
      ),
    );
  }

  final RouteStageCommon common;
  final WireEnumValue<ExternalProvider> providerValue;
  final String providerRouteId;
  final String? externalCandidateId;
  final ToolPolicy toolPolicy;
  final SelectedTools selectedTools;
  final ProviderTokenIdentifiers? providerTokens;
  final ProviderChainIdentifiers? providerChainIds;
  final String providerStepDigest;

  @override
  String get stageType => 'external_liquidity';
  @override
  bool get isExecutable => common.isExecutable && providerValue.isExecutable;

  @override
  RouteJson toJson() => {
    'stage_type': stageType,
    ...common.toJson(),
    'provider': providerValue.rawValue,
    'provider_route_id': providerRouteId,
    if (externalCandidateId != null)
      'external_candidate_id': externalCandidateId,
    'tool_policy': toolPolicy.toJson(),
    'selected_tools': selectedTools.toJson(),
    if (providerTokens != null) 'provider_tokens': providerTokens!.toJson(),
    if (providerChainIds != null)
      'provider_chain_ids': providerChainIds!.toJson(),
    'provider_step_digest': providerStepDigest,
  };
}

final class UnknownRouteStage extends RouteStage {
  UnknownRouteStage(this.stageType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));

  @override
  final String stageType;
  final RouteJson rawPayload;

  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class TradeRouteCandidate {
  TradeRouteCandidate({
    required String candidateId,
    required this.candidateDigest,
    required RouteSource routeSource,
    required List<RouteStage> stages,
    required String expectedReceive,
    required String minimumReceive,
    required List<FeeComponent> fees,
    required RankStatus rankStatus,
    required this.quoteObservedAt,
    required this.expiresAt,
    required List<RouteWarning> warnings,
    this.netReceiveValue,
    this.valuationObservedAt,
    this.rank,
    this.estimatedDurationSeconds,
  }) : candidateId = _uuid(candidateId, 'candidateId'),
       routeSourceValue = WireEnumValue.known(routeSource),
       stages = List.unmodifiable(stages),
       expectedReceive = _amount(expectedReceive, 'expectedReceive'),
       minimumReceive = _amount(minimumReceive, 'minimumReceive'),
       fees = List.unmodifiable(fees),
       rankStatusValue = WireEnumValue.known(rankStatus),
       warningValues = List.unmodifiable(
         warnings.map(WireEnumValue<RouteWarning>.known),
       ) {
    if (netReceiveValue != null) _decimal(netReceiveValue, 'netReceiveValue');
  }

  TradeRouteCandidate._({
    required this.candidateId,
    required this.candidateDigest,
    required this.routeSourceValue,
    required this.stages,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.fees,
    required this.netReceiveValue,
    required this.valuationObservedAt,
    required this.rankStatusValue,
    required this.rank,
    required this.estimatedDurationSeconds,
    required this.quoteObservedAt,
    required this.expiresAt,
    required this.warningValues,
  });

  factory TradeRouteCandidate.fromJson(
    RouteJson json, [
    String path = 'candidate',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'candidate_id',
        'candidate_digest',
        'route_source',
        'stages',
        'expected_receive',
        'minimum_receive',
        'fees',
        'net_receive_value',
        'valuation_observed_at',
        'rank_status',
        'rank',
        'estimated_duration_seconds',
        'quote_observed_at',
        'expires_at',
        'warnings',
      },
    );
    final netReceiveValue = _nullableString(
      json['net_receive_value'],
      '$path.net_receive_value',
    );
    if (netReceiveValue != null) {
      _decimal(netReceiveValue, '$path.net_receive_value');
    }
    return TradeRouteCandidate._(
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      candidateDigest: _string(
        json['candidate_digest'],
        '$path.candidate_digest',
      ),
      routeSourceValue: _wireEnum(
        json['route_source'],
        RouteSource.values,
        '$path.route_source',
      ),
      stages: _list(json['stages'], '$path.stages', (value, itemPath) {
        return RouteStage.fromJson(_object(value, itemPath), itemPath);
      }),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      fees: _list(json['fees'], '$path.fees', (value, itemPath) {
        return FeeComponent.fromJson(_object(value, itemPath), itemPath);
      }),
      netReceiveValue: netReceiveValue,
      valuationObservedAt: _nullableTimestamp(
        json['valuation_observed_at'],
        '$path.valuation_observed_at',
      ),
      rankStatusValue: _wireEnum(
        json['rank_status'],
        RankStatus.values,
        '$path.rank_status',
      ),
      rank: _nullableInteger(json['rank'], '$path.rank'),
      estimatedDurationSeconds: _nullableInteger(
        json['estimated_duration_seconds'],
        '$path.estimated_duration_seconds',
      ),
      quoteObservedAt: _timestamp(
        json['quote_observed_at'],
        '$path.quote_observed_at',
      ),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
      warningValues: _list(json['warnings'], '$path.warnings', (
        value,
        itemPath,
      ) {
        return _wireEnum(value, RouteWarning.values, itemPath);
      }),
    );
  }

  final String candidateId;
  final String candidateDigest;
  final WireEnumValue<RouteSource> routeSourceValue;
  final List<RouteStage> stages;
  final String expectedReceive;
  final String minimumReceive;
  final List<FeeComponent> fees;
  final String? netReceiveValue;
  final DateTime? valuationObservedAt;
  final WireEnumValue<RankStatus> rankStatusValue;
  final int? rank;
  final int? estimatedDurationSeconds;
  final DateTime quoteObservedAt;
  final DateTime expiresAt;
  final List<WireEnumValue<RouteWarning>> warningValues;

  bool get isExecutable =>
      routeSourceValue.isExecutable &&
      stages.every((stage) => stage.isExecutable) &&
      fees.every((fee) => fee.isExecutable) &&
      rankStatusValue.isExecutable &&
      warningValues.every((warning) => warning.isExecutable);

  RouteJson toJson() => {
    'candidate_id': candidateId,
    'candidate_digest': candidateDigest,
    'route_source': routeSourceValue.rawValue,
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'fees': fees.map((fee) => fee.toJson()).toList(growable: false),
    'net_receive_value': netReceiveValue,
    'valuation_observed_at': valuationObservedAt == null
        ? null
        : _dateJson(valuationObservedAt!),
    'rank_status': rankStatusValue.rawValue,
    'rank': rank,
    'estimated_duration_seconds': estimatedDurationSeconds,
    'quote_observed_at': _dateJson(quoteObservedAt),
    'expires_at': _dateJson(expiresAt),
    'warnings': warningValues.map((warning) => warning.rawValue).toList(),
  };
}

sealed class PreparedExecutionStageReview {
  const PreparedExecutionStageReview();

  factory PreparedExecutionStageReview.fromJson(
    RouteJson json, [
    String path = 'prepared_stage',
  ]) {
    final discriminator = _string(json['stage_kind'], '$path.stage_kind');
    return switch (discriminator) {
      'kdf_atomic' || 'external_liquidity' =>
        KnownPreparedExecutionStageReview.fromJson(json, path),
      _ => UnknownPreparedExecutionStageReview(discriminator, json),
    };
  }

  String get stageKind;
  bool get isExecutable;
  RouteJson toJson();
}

final class KnownPreparedExecutionStageReview
    extends PreparedExecutionStageReview {
  KnownPreparedExecutionStageReview({
    required this.stageIndex,
    required String stageId,
    required this.kind,
    required this.fromAsset,
    required this.toAsset,
    required String sourceAmount,
    required String expectedReceive,
    required String minimumReceive,
    required this.recipient,
    required List<FeeComponent> fees,
    required List<RouteWarning> warnings,
    this.selectedTools,
    List<FeeLimit> nonNetworkFeeLimits = const [],
    this.maxTotalNetworkFee,
    this.requiredMaxNetworkFee,
    this.resolvedSourceAddress,
    this.approval,
  }) : stageId = _uuid(stageId, 'stageId'),
       sourceAmount = _amount(sourceAmount, 'sourceAmount'),
       expectedReceive = _amount(expectedReceive, 'expectedReceive'),
       minimumReceive = _amount(minimumReceive, 'minimumReceive'),
       fees = List.unmodifiable(fees),
       warningValues = List.unmodifiable(
         warnings.map(WireEnumValue<RouteWarning>.known),
       ),
       nonNetworkFeeLimits = List.unmodifiable(nonNetworkFeeLimits) {
    if (stageIndex < 0) {
      throw RangeError.value(stageIndex, 'stageIndex', 'must be non-negative');
    }
  }

  KnownPreparedExecutionStageReview._({
    required this.stageIndex,
    required this.stageId,
    required this.kind,
    required this.fromAsset,
    required this.toAsset,
    required this.sourceAmount,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.recipient,
    required this.fees,
    required this.warningValues,
    required this.selectedTools,
    required this.nonNetworkFeeLimits,
    required this.maxTotalNetworkFee,
    required this.requiredMaxNetworkFee,
    required this.resolvedSourceAddress,
    required this.approval,
  });

  factory KnownPreparedExecutionStageReview.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'stage_index',
        'stage_id',
        'stage_kind',
        'from_asset',
        'to_asset',
        'source_amount',
        'expected_receive',
        'minimum_receive',
        'recipient',
        'fees',
        'warnings',
      },
      optional: {
        'selected_tools',
        'non_network_fee_limits',
        'max_total_network_fee',
        'required_max_network_fee',
        'resolved_source_address',
        'approval',
      },
    );
    final stageIndex = _integer(json['stage_index'], '$path.stage_index');
    if (stageIndex < 0) {
      throw FormatException('$path.stage_index must be non-negative.');
    }
    final kindValue = _wireEnum(
      json['stage_kind'],
      PreparedExecutionStageKind.values,
      '$path.stage_kind',
    );
    final kind = kindValue.knownValue;
    if (kind == null) {
      throw FormatException('$path.stage_kind is not a known stage kind.');
    }
    return KnownPreparedExecutionStageReview._(
      stageIndex: stageIndex,
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      kind: kind,
      fromAsset: RouteAsset.fromJson(
        _object(json['from_asset'], '$path.from_asset'),
        '$path.from_asset',
      ),
      toAsset: RouteAsset.fromJson(
        _object(json['to_asset'], '$path.to_asset'),
        '$path.to_asset',
      ),
      sourceAmount: _amount(json['source_amount'], '$path.source_amount'),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      recipient: _string(json['recipient'], '$path.recipient'),
      fees: _list(json['fees'], '$path.fees', (value, itemPath) {
        return FeeComponent.fromJson(_object(value, itemPath), itemPath);
      }),
      warningValues: _list(json['warnings'], '$path.warnings', (
        value,
        itemPath,
      ) {
        return _wireEnum(value, RouteWarning.values, itemPath);
      }),
      selectedTools: json['selected_tools'] == null
          ? null
          : SelectedTools.fromJson(
              _object(json['selected_tools'], '$path.selected_tools'),
              '$path.selected_tools',
            ),
      nonNetworkFeeLimits: json.containsKey('non_network_fee_limits')
          ? _list(
              json['non_network_fee_limits'],
              '$path.non_network_fee_limits',
              (value, itemPath) =>
                  FeeLimit.fromJson(_object(value, itemPath), itemPath),
            )
          : const [],
      maxTotalNetworkFee: json['max_total_network_fee'] == null
          ? null
          : FeeCap.fromJson(
              _object(
                json['max_total_network_fee'],
                '$path.max_total_network_fee',
              ),
              '$path.max_total_network_fee',
            ),
      requiredMaxNetworkFee: json['required_max_network_fee'] == null
          ? null
          : FeeCap.fromJson(
              _object(
                json['required_max_network_fee'],
                '$path.required_max_network_fee',
              ),
              '$path.required_max_network_fee',
            ),
      resolvedSourceAddress: _nullableString(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      approval: json['approval'] == null
          ? null
          : PreparedApproval.fromJson(
              _object(json['approval'], '$path.approval'),
              '$path.approval',
            ),
    );
  }

  final int stageIndex;
  final String stageId;
  final PreparedExecutionStageKind kind;
  final RouteAsset fromAsset;
  final RouteAsset toAsset;
  final String sourceAmount;
  final String expectedReceive;
  final String minimumReceive;
  final String recipient;
  final List<FeeComponent> fees;
  final List<WireEnumValue<RouteWarning>> warningValues;
  final SelectedTools? selectedTools;
  final List<FeeLimit> nonNetworkFeeLimits;
  final FeeCap? maxTotalNetworkFee;
  final FeeCap? requiredMaxNetworkFee;
  final String? resolvedSourceAddress;
  final PreparedApproval? approval;

  List<RouteWarning> get warnings => List.unmodifiable(
    warningValues
        .map((warning) => warning.knownValue)
        .whereType<RouteWarning>(),
  );

  @override
  String get stageKind => kind.wireName;

  @override
  bool get isExecutable =>
      fromAsset.isExecutable &&
      toAsset.isExecutable &&
      fees.every((fee) => fee.isExecutable) &&
      warningValues.every((warning) => warning.isExecutable) &&
      nonNetworkFeeLimits.every((limit) => limit.isExecutable) &&
      (maxTotalNetworkFee?.isExecutable ?? true) &&
      (requiredMaxNetworkFee?.isExecutable ?? true) &&
      (approval?.isExecutable ?? true);

  @override
  RouteJson toJson() => {
    'stage_index': stageIndex,
    'stage_id': stageId,
    'stage_kind': stageKind,
    'from_asset': fromAsset.toJson(),
    'to_asset': toAsset.toJson(),
    'source_amount': sourceAmount,
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'recipient': recipient,
    'fees': fees.map((fee) => fee.toJson()).toList(growable: false),
    'warnings': warningValues
        .map((warning) => warning.rawValue)
        .toList(growable: false),
    if (selectedTools != null) 'selected_tools': selectedTools!.toJson(),
    if (nonNetworkFeeLimits.isNotEmpty)
      'non_network_fee_limits': nonNetworkFeeLimits
          .map((limit) => limit.toJson())
          .toList(growable: false),
    if (maxTotalNetworkFee != null)
      'max_total_network_fee': maxTotalNetworkFee!.toJson(),
    if (requiredMaxNetworkFee != null)
      'required_max_network_fee': requiredMaxNetworkFee!.toJson(),
    if (resolvedSourceAddress != null)
      'resolved_source_address': resolvedSourceAddress,
    if (approval != null) 'approval': approval!.toJson(),
  };
}

final class UnknownPreparedExecutionStageReview
    extends PreparedExecutionStageReview {
  UnknownPreparedExecutionStageReview(this.stageKind, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));

  @override
  final String stageKind;
  final RouteJson rawPayload;

  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class PreparedExecutionReview {
  PreparedExecutionReview({
    required this.reviewVersion,
    required this.preparedAt,
    required String evaluationId,
    required String candidateId,
    required this.candidateDigest,
    required RouteSource routeSource,
    required this.sourceAsset,
    required this.destinationAsset,
    required String sourceAmount,
    required this.sourceAddressSelector,
    required this.resolvedSourceAddress,
    required this.recipient,
    required String expectedReceive,
    required String minimumReceive,
    required List<FeeComponent> fees,
    required List<RouteWarning> warnings,
    required this.expiresAt,
    required List<PreparedExecutionStageReview> stages,
    this.estimatedDurationSeconds,
  }) : evaluationId = _uuid(evaluationId, 'evaluationId'),
       candidateId = _uuid(candidateId, 'candidateId'),
       routeSourceValue = WireEnumValue.known(routeSource),
       sourceAmount = _amount(sourceAmount, 'sourceAmount'),
       expectedReceive = _amount(expectedReceive, 'expectedReceive'),
       minimumReceive = _amount(minimumReceive, 'minimumReceive'),
       fees = List.unmodifiable(fees),
       warningValues = List.unmodifiable(
         warnings.map(WireEnumValue<RouteWarning>.known),
       ),
       stages = List.unmodifiable(stages) {
    if (reviewVersion < 0 || reviewVersion > 255) {
      throw RangeError.range(reviewVersion, 0, 255, 'reviewVersion');
    }
    if (estimatedDurationSeconds != null && estimatedDurationSeconds! < 0) {
      throw RangeError.value(
        estimatedDurationSeconds!,
        'estimatedDurationSeconds',
        'must be non-negative',
      );
    }
  }

  PreparedExecutionReview._({
    required this.reviewVersion,
    required this.preparedAt,
    required this.evaluationId,
    required this.candidateId,
    required this.candidateDigest,
    required this.routeSourceValue,
    required this.sourceAsset,
    required this.destinationAsset,
    required this.sourceAmount,
    required this.sourceAddressSelector,
    required this.resolvedSourceAddress,
    required this.recipient,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.fees,
    required this.estimatedDurationSeconds,
    required this.warningValues,
    required this.expiresAt,
    required this.stages,
  });

  factory PreparedExecutionReview.fromJson(
    RouteJson json, [
    String path = 'review',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'review_version',
        'prepared_at',
        'evaluation_id',
        'candidate_id',
        'candidate_digest',
        'route_source',
        'source_asset',
        'destination_asset',
        'source_amount',
        'source_address_selector',
        'resolved_source_address',
        'recipient',
        'expected_receive',
        'minimum_receive',
        'fees',
        'estimated_duration_seconds',
        'warnings',
        'expires_at',
        'stages',
      },
    );
    final reviewVersion = _integer(
      json['review_version'],
      '$path.review_version',
    );
    if (reviewVersion < 0 || reviewVersion > 255) {
      throw FormatException('$path.review_version must be an unsigned byte.');
    }
    final estimatedDurationSeconds = _nullableInteger(
      json['estimated_duration_seconds'],
      '$path.estimated_duration_seconds',
    );
    if (estimatedDurationSeconds != null && estimatedDurationSeconds < 0) {
      throw FormatException(
        '$path.estimated_duration_seconds must be non-negative.',
      );
    }
    return PreparedExecutionReview._(
      reviewVersion: reviewVersion,
      preparedAt: _timestamp(json['prepared_at'], '$path.prepared_at'),
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      candidateDigest: _string(
        json['candidate_digest'],
        '$path.candidate_digest',
      ),
      routeSourceValue: _wireEnum(
        json['route_source'],
        RouteSource.values,
        '$path.route_source',
      ),
      sourceAsset: RouteAsset.fromJson(
        _object(json['source_asset'], '$path.source_asset'),
        '$path.source_asset',
      ),
      destinationAsset: RouteAsset.fromJson(
        _object(json['destination_asset'], '$path.destination_asset'),
        '$path.destination_asset',
      ),
      sourceAmount: _amount(json['source_amount'], '$path.source_amount'),
      sourceAddressSelector: SourceAddressSelector.fromJson(
        _object(
          json['source_address_selector'],
          '$path.source_address_selector',
        ),
        '$path.source_address_selector',
      ),
      resolvedSourceAddress: _string(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      recipient: _string(json['recipient'], '$path.recipient'),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      fees: _list(json['fees'], '$path.fees', (value, itemPath) {
        return FeeComponent.fromJson(_object(value, itemPath), itemPath);
      }),
      estimatedDurationSeconds: estimatedDurationSeconds,
      warningValues: _list(json['warnings'], '$path.warnings', (
        value,
        itemPath,
      ) {
        return _wireEnum(value, RouteWarning.values, itemPath);
      }),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
      stages: _list(json['stages'], '$path.stages', (value, itemPath) {
        return PreparedExecutionStageReview.fromJson(
          _object(value, itemPath),
          itemPath,
        );
      }),
    );
  }

  final int reviewVersion;
  final DateTime preparedAt;
  final String evaluationId;
  final String candidateId;
  final String candidateDigest;
  final WireEnumValue<RouteSource> routeSourceValue;
  final RouteAsset sourceAsset;
  final RouteAsset destinationAsset;
  final String sourceAmount;
  final SourceAddressSelector sourceAddressSelector;
  final String resolvedSourceAddress;
  final String recipient;
  final String expectedReceive;
  final String minimumReceive;
  final List<FeeComponent> fees;
  final int? estimatedDurationSeconds;
  final List<WireEnumValue<RouteWarning>> warningValues;
  final DateTime expiresAt;
  final List<PreparedExecutionStageReview> stages;

  List<RouteWarning> get warnings => List.unmodifiable(
    warningValues
        .map((warning) => warning.knownValue)
        .whereType<RouteWarning>(),
  );

  bool get isExecutable =>
      routeSourceValue.isExecutable &&
      sourceAsset.isExecutable &&
      destinationAsset.isExecutable &&
      sourceAddressSelector.isExecutable &&
      fees.every((fee) => fee.isExecutable) &&
      warningValues.every((warning) => warning.isExecutable) &&
      stages.every((stage) => stage.isExecutable);

  RouteJson toJson() => {
    'review_version': reviewVersion,
    'prepared_at': _dateJson(preparedAt),
    'evaluation_id': evaluationId,
    'candidate_id': candidateId,
    'candidate_digest': candidateDigest,
    'route_source': routeSourceValue.rawValue,
    'source_asset': sourceAsset.toJson(),
    'destination_asset': destinationAsset.toJson(),
    'source_amount': sourceAmount,
    'source_address_selector': sourceAddressSelector.toJson(),
    'resolved_source_address': resolvedSourceAddress,
    'recipient': recipient,
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'fees': fees.map((fee) => fee.toJson()).toList(growable: false),
    'estimated_duration_seconds': estimatedDurationSeconds,
    'warnings': warningValues
        .map((warning) => warning.rawValue)
        .toList(growable: false),
    'expires_at': _dateJson(expiresAt),
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
  };
}

final class ExternalProviderCandidate {
  ExternalProviderCandidate({
    required this.externalCandidateId,
    required ExternalProvider provider,
    required this.providerRouteId,
    required this.observedAt,
    required this.expiresAt,
    required List<RouteStage> stages,
    this.estimatedDurationSeconds,
  }) : providerValue = WireEnumValue.known(provider),
       stages = List.unmodifiable(stages);

  ExternalProviderCandidate._({
    required this.externalCandidateId,
    required this.providerValue,
    required this.providerRouteId,
    required this.observedAt,
    required this.expiresAt,
    required this.estimatedDurationSeconds,
    required this.stages,
  });

  factory ExternalProviderCandidate.fromJson(
    RouteJson json, [
    String path = 'external_candidate',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'external_candidate_id',
        'provider',
        'provider_route_id',
        'observed_at',
        'expires_at',
        'stages',
      },
      optional: {'estimated_duration_seconds'},
    );
    return ExternalProviderCandidate._(
      externalCandidateId: _string(
        json['external_candidate_id'],
        '$path.external_candidate_id',
      ),
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      providerRouteId: _string(
        json['provider_route_id'],
        '$path.provider_route_id',
      ),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
      estimatedDurationSeconds: _nullableInteger(
        json['estimated_duration_seconds'],
        '$path.estimated_duration_seconds',
      ),
      stages: _list(json['stages'], '$path.stages', (value, itemPath) {
        return RouteStage.fromJson(_object(value, itemPath), itemPath);
      }),
    );
  }

  final String externalCandidateId;
  final WireEnumValue<ExternalProvider> providerValue;
  final String providerRouteId;
  final DateTime observedAt;
  final DateTime expiresAt;
  final int? estimatedDurationSeconds;
  final List<RouteStage> stages;

  bool get isExecutable =>
      providerValue.isExecutable && stages.every((stage) => stage.isExecutable);
  RouteJson toJson() => {
    'external_candidate_id': externalCandidateId,
    'provider': providerValue.rawValue,
    'provider_route_id': providerRouteId,
    'observed_at': _dateJson(observedAt),
    'expires_at': _dateJson(expiresAt),
    if (estimatedDurationSeconds != null)
      'estimated_duration_seconds': estimatedDurationSeconds,
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
  };

  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('External provider candidate is not executable.');
    }
    final result = toJson();
    result['stages'] = stages
        .map((stage) => stage.toRequestJson())
        .toList(growable: false);
    return result;
  }
}

final class ProviderPair {
  const ProviderPair({
    required this.from,
    required this.to,
    required this.providerTokens,
    required this.providerChainIds,
  });

  factory ProviderPair.fromJson(RouteJson json, [String path = 'pair']) {
    _strictKeys(
      json,
      path,
      required: {'from', 'to', 'provider_tokens', 'provider_chain_ids'},
    );
    return ProviderPair(
      from: RouteAsset.fromJson(
        _object(json['from'], '$path.from'),
        '$path.from',
      ),
      to: RouteAsset.fromJson(_object(json['to'], '$path.to'), '$path.to'),
      providerTokens: ProviderTokenIdentifiers.fromJson(
        _object(json['provider_tokens'], '$path.provider_tokens'),
        '$path.provider_tokens',
      ),
      providerChainIds: ProviderChainIdentifiers.fromJson(
        _object(json['provider_chain_ids'], '$path.provider_chain_ids'),
        '$path.provider_chain_ids',
      ),
    );
  }

  final RouteAsset from;
  final RouteAsset to;
  final ProviderTokenIdentifiers providerTokens;
  final ProviderChainIdentifiers providerChainIds;
  bool get isExecutable => from.isExecutable && to.isExecutable;
  RouteJson toJson() => {
    'from': from.toJson(),
    'to': to.toJson(),
    'provider_tokens': providerTokens.toJson(),
    'provider_chain_ids': providerChainIds.toJson(),
  };
}

final class ProviderMetadataSnapshot {
  ProviderMetadataSnapshot({
    required ExternalProvider provider,
    required this.observedAt,
    required List<ProviderPair> pairs,
  }) : providerValue = WireEnumValue.known(provider),
       pairs = List.unmodifiable(pairs);

  ProviderMetadataSnapshot._({
    required this.providerValue,
    required this.observedAt,
    required this.pairs,
  });

  factory ProviderMetadataSnapshot.fromJson(
    RouteJson json, [
    String path = 'provider_snapshot',
  ]) {
    _strictKeys(json, path, required: {'provider', 'observed_at', 'pairs'});
    return ProviderMetadataSnapshot._(
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      pairs: _list(json['pairs'], '$path.pairs', (value, itemPath) {
        return ProviderPair.fromJson(_object(value, itemPath), itemPath);
      }),
    );
  }

  final WireEnumValue<ExternalProvider> providerValue;
  final DateTime observedAt;
  final List<ProviderPair> pairs;
  bool get isExecutable =>
      providerValue.isExecutable && pairs.every((pair) => pair.isExecutable);
  RouteJson toJson() => {
    'provider': providerValue.rawValue,
    'observed_at': _dateJson(observedAt),
    'pairs': pairs.map((pair) => pair.toJson()).toList(growable: false),
  };
}

final class CapabilityRecord {
  CapabilityRecord._({
    required this.providerValue,
    required this.from,
    required this.to,
    required this.routeSupported,
    required this.executor,
    required this.supportedModeValues,
    required this.unavailableReasonValue,
  });

  factory CapabilityRecord.fromJson(
    RouteJson json, [
    String path = 'capability',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'provider',
        'from',
        'to',
        'route_supported',
        'executor',
        'supported_modes',
        'unavailable_reason',
      },
    );
    final result = CapabilityRecord._(
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      from: RouteAsset.fromJson(
        _object(json['from'], '$path.from'),
        '$path.from',
      ),
      to: RouteAsset.fromJson(_object(json['to'], '$path.to'), '$path.to'),
      routeSupported: _boolean(
        json['route_supported'],
        '$path.route_supported',
      ),
      executor: _nullableString(json['executor'], '$path.executor'),
      supportedModeValues: _list(
        json['supported_modes'],
        '$path.supported_modes',
        (value, itemPath) => _wireEnum(value, ExecutionMode.values, itemPath),
      ),
      unavailableReasonValue: json['unavailable_reason'] == null
          ? null
          : _wireEnum(
              json['unavailable_reason'],
              CapabilityUnavailableReason.values,
              '$path.unavailable_reason',
            ),
    );
    if (result.routeSupported) {
      if (result.executor == null ||
          result.supportedModeValues.isEmpty ||
          result.unavailableReasonValue != null) {
        throw FormatException('$path has an invalid supported capability.');
      }
    } else if (result.executor != null ||
        result.supportedModeValues.isNotEmpty ||
        result.unavailableReasonValue == null) {
      throw FormatException('$path has an invalid unsupported capability.');
    }
    return result;
  }

  final WireEnumValue<ExternalProvider> providerValue;
  final RouteAsset from;
  final RouteAsset to;
  final bool routeSupported;
  final String? executor;
  final List<WireEnumValue<ExecutionMode>> supportedModeValues;
  final WireEnumValue<CapabilityUnavailableReason>? unavailableReasonValue;

  bool get isExecutable =>
      routeSupported &&
      providerValue.isExecutable &&
      from.isExecutable &&
      to.isExecutable &&
      supportedModeValues.every((mode) => mode.isExecutable) &&
      (unavailableReasonValue?.isExecutable ?? true);
  RouteJson toJson() => {
    'provider': providerValue.rawValue,
    'from': from.toJson(),
    'to': to.toJson(),
    'route_supported': routeSupported,
    'executor': executor,
    'supported_modes': supportedModeValues
        .map((mode) => mode.rawValue)
        .toList(growable: false),
    'unavailable_reason': unavailableReasonValue?.rawValue,
  };
}

final class CandidateReference {
  CandidateReference({
    required String evaluationId,
    required String candidateId,
    required this.candidateDigest,
    required String stageId,
  }) : evaluationId = _uuid(evaluationId, 'evaluationId'),
       candidateId = _uuid(candidateId, 'candidateId'),
       stageId = _uuid(stageId, 'stageId');

  factory CandidateReference.fromJson(
    RouteJson json, [
    String path = 'candidate_reference',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'evaluation_id',
        'candidate_id',
        'candidate_digest',
        'stage_id',
      },
    );
    return CandidateReference(
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      candidateDigest: _string(
        json['candidate_digest'],
        '$path.candidate_digest',
      ),
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
    );
  }

  final String evaluationId;
  final String candidateId;
  final String candidateDigest;
  final String stageId;
  RouteJson toJson() => {
    'evaluation_id': evaluationId,
    'candidate_id': candidateId,
    'candidate_digest': candidateDigest,
    'stage_id': stageId,
  };
}

final class ProviderStepReference {
  ProviderStepReference({
    required String evaluationId,
    required String candidateId,
    required String stageId,
    required this.providerStepDigest,
  }) : evaluationId = _uuid(evaluationId, 'evaluationId'),
       candidateId = _uuid(candidateId, 'candidateId'),
       stageId = _uuid(stageId, 'stageId');

  factory ProviderStepReference.fromJson(
    RouteJson json, [
    String path = 'provider_step_reference',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'evaluation_id',
        'candidate_id',
        'stage_id',
        'provider_step_digest',
      },
    );
    return ProviderStepReference(
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      providerStepDigest: _string(
        json['provider_step_digest'],
        '$path.provider_step_digest',
      ),
    );
  }

  final String evaluationId;
  final String candidateId;
  final String stageId;
  final String providerStepDigest;
  RouteJson toJson() => {
    'evaluation_id': evaluationId,
    'candidate_id': candidateId,
    'stage_id': stageId,
    'provider_step_digest': providerStepDigest,
  };
}

final class StageExecutionIntent {
  StageExecutionIntent({
    required this.routeIntentDigest,
    required String stageId,
    required this.fromAsset,
    required this.toAsset,
    required String sourceAmount,
    required String acceptedExpectedReceive,
    required String minimumReceive,
    required this.maxExpectedReceiveDegradationBps,
    required this.sourceAddress,
    required this.recipient,
    required this.toolPolicy,
    required this.selectedTools,
    required this.providerTokens,
    required this.providerChainIds,
    required List<FeeLimit> nonNetworkFeeLimits,
    required this.maxTotalNetworkFee,
    required this.consentExpiresAt,
    this.slippageBps,
  }) : stageId = _uuid(stageId, 'stageId'),
       sourceAmount = _amount(sourceAmount, 'sourceAmount'),
       acceptedExpectedReceive = _amount(
         acceptedExpectedReceive,
         'acceptedExpectedReceive',
       ),
       minimumReceive = _amount(minimumReceive, 'minimumReceive'),
       nonNetworkFeeLimits = List.unmodifiable(nonNetworkFeeLimits) {
    if (maxExpectedReceiveDegradationBps < 0 ||
        maxExpectedReceiveDegradationBps > 10000) {
      throw RangeError.range(
        maxExpectedReceiveDegradationBps,
        0,
        10000,
        'maxExpectedReceiveDegradationBps',
      );
    }
  }

  factory StageExecutionIntent.fromJson(
    RouteJson json, [
    String path = 'stage_intent',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'route_intent_digest',
        'stage_id',
        'from_asset',
        'to_asset',
        'source_amount',
        'accepted_expected_receive',
        'minimum_receive',
        'max_expected_receive_degradation_bps',
        'slippage_bps',
        'source_address',
        'recipient',
        'tool_policy',
        'selected_tools',
        'provider_tokens',
        'provider_chain_ids',
        'non_network_fee_limits',
        'max_total_network_fee',
        'consent_expires_at',
      },
    );
    return StageExecutionIntent(
      routeIntentDigest: _string(
        json['route_intent_digest'],
        '$path.route_intent_digest',
      ),
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      fromAsset: RouteAsset.fromJson(
        _object(json['from_asset'], '$path.from_asset'),
        '$path.from_asset',
      ),
      toAsset: RouteAsset.fromJson(
        _object(json['to_asset'], '$path.to_asset'),
        '$path.to_asset',
      ),
      sourceAmount: _amount(json['source_amount'], '$path.source_amount'),
      acceptedExpectedReceive: _amount(
        json['accepted_expected_receive'],
        '$path.accepted_expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      maxExpectedReceiveDegradationBps: _integer(
        json['max_expected_receive_degradation_bps'],
        '$path.max_expected_receive_degradation_bps',
      ),
      slippageBps: _nullableInteger(json['slippage_bps'], '$path.slippage_bps'),
      sourceAddress: SourceAddressSelector.fromJson(
        _object(json['source_address'], '$path.source_address'),
        '$path.source_address',
      ),
      recipient: _string(json['recipient'], '$path.recipient'),
      toolPolicy: ToolPolicy.fromJson(
        _object(json['tool_policy'], '$path.tool_policy'),
        '$path.tool_policy',
      ),
      selectedTools: SelectedTools.fromJson(
        _object(json['selected_tools'], '$path.selected_tools'),
        '$path.selected_tools',
      ),
      providerTokens: ProviderTokenIdentifiers.fromJson(
        _object(json['provider_tokens'], '$path.provider_tokens'),
        '$path.provider_tokens',
      ),
      providerChainIds: ProviderChainIdentifiers.fromJson(
        _object(json['provider_chain_ids'], '$path.provider_chain_ids'),
        '$path.provider_chain_ids',
      ),
      nonNetworkFeeLimits: _list(
        json['non_network_fee_limits'],
        '$path.non_network_fee_limits',
        (value, itemPath) =>
            FeeLimit.fromJson(_object(value, itemPath), itemPath),
      ),
      maxTotalNetworkFee: FeeCap.fromJson(
        _object(json['max_total_network_fee'], '$path.max_total_network_fee'),
        '$path.max_total_network_fee',
      ),
      consentExpiresAt: _timestamp(
        json['consent_expires_at'],
        '$path.consent_expires_at',
      ),
    );
  }

  final String routeIntentDigest;
  final String stageId;
  final RouteAsset fromAsset;
  final RouteAsset toAsset;
  final String sourceAmount;
  final String acceptedExpectedReceive;
  final String minimumReceive;
  final int maxExpectedReceiveDegradationBps;
  final int? slippageBps;
  final SourceAddressSelector sourceAddress;
  final String recipient;
  final ToolPolicy toolPolicy;
  final SelectedTools selectedTools;
  final ProviderTokenIdentifiers providerTokens;
  final ProviderChainIdentifiers providerChainIds;
  final List<FeeLimit> nonNetworkFeeLimits;
  final FeeCap maxTotalNetworkFee;
  final DateTime consentExpiresAt;

  bool get isExecutable =>
      fromAsset.isExecutable &&
      toAsset.isExecutable &&
      sourceAddress.isExecutable &&
      nonNetworkFeeLimits.every((limit) => limit.isExecutable) &&
      maxTotalNetworkFee.isExecutable;
  RouteJson toJson() => {
    'route_intent_digest': routeIntentDigest,
    'stage_id': stageId,
    'from_asset': fromAsset.toJson(),
    'to_asset': toAsset.toJson(),
    'source_amount': sourceAmount,
    'accepted_expected_receive': acceptedExpectedReceive,
    'minimum_receive': minimumReceive,
    'max_expected_receive_degradation_bps': maxExpectedReceiveDegradationBps,
    'slippage_bps': slippageBps,
    'source_address': sourceAddress.toJson(),
    'recipient': recipient,
    'tool_policy': toolPolicy.toJson(),
    'selected_tools': selectedTools.toJson(),
    'provider_tokens': providerTokens.toJson(),
    'provider_chain_ids': providerChainIds.toJson(),
    'non_network_fee_limits': nonNetworkFeeLimits
        .map((limit) => limit.toJson())
        .toList(growable: false),
    'max_total_network_fee': maxTotalNetworkFee.toJson(),
    'consent_expires_at': _dateJson(consentExpiresAt),
  };
}

sealed class EvmFeeHint {
  const EvmFeeHint();

  factory EvmFeeHint.legacy({required String gasPrice}) = LegacyEvmFeeHint;
  factory EvmFeeHint.eip1559({
    required String maxFeePerGas,
    required String maxPriorityFeePerGas,
  }) = Eip1559EvmFeeHint;

  factory EvmFeeHint.fromJson(RouteJson json, [String path = 'fee_hint']) {
    final discriminator = _string(json['fee_model'], '$path.fee_model');
    return switch (discriminator) {
      'legacy' => LegacyEvmFeeHint.fromJson(json, path),
      'eip1559' => Eip1559EvmFeeHint.fromJson(json, path),
      _ => UnknownEvmFeeHint(discriminator, json),
    };
  }

  String get feeModel;
  bool get isExecutable;
  RouteJson toJson();
}

final class LegacyEvmFeeHint extends EvmFeeHint {
  LegacyEvmFeeHint({required String gasPrice})
    : gasPrice = _amount(gasPrice, 'gasPrice');

  factory LegacyEvmFeeHint.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'fee_model', 'gas_price'});
    return LegacyEvmFeeHint(
      gasPrice: _amount(json['gas_price'], '$path.gas_price'),
    );
  }

  final String gasPrice;
  @override
  String get feeModel => 'legacy';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {'fee_model': feeModel, 'gas_price': gasPrice};
}

final class Eip1559EvmFeeHint extends EvmFeeHint {
  Eip1559EvmFeeHint({
    required String maxFeePerGas,
    required String maxPriorityFeePerGas,
  }) : maxFeePerGas = _amount(maxFeePerGas, 'maxFeePerGas'),
       maxPriorityFeePerGas = _amount(
         maxPriorityFeePerGas,
         'maxPriorityFeePerGas',
       );

  factory Eip1559EvmFeeHint.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {'fee_model', 'max_fee_per_gas', 'max_priority_fee_per_gas'},
    );
    return Eip1559EvmFeeHint(
      maxFeePerGas: _amount(json['max_fee_per_gas'], '$path.max_fee_per_gas'),
      maxPriorityFeePerGas: _amount(
        json['max_priority_fee_per_gas'],
        '$path.max_priority_fee_per_gas',
      ),
    );
  }

  final String maxFeePerGas;
  final String maxPriorityFeePerGas;
  @override
  String get feeModel => 'eip1559';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {
    'fee_model': feeModel,
    'max_fee_per_gas': maxFeePerGas,
    'max_priority_fee_per_gas': maxPriorityFeePerGas,
  };
}

final class UnknownEvmFeeHint extends EvmFeeHint {
  UnknownEvmFeeHint(this.feeModel, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String feeModel;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

sealed class ClientMaterializedTransaction {
  const ClientMaterializedTransaction();

  factory ClientMaterializedTransaction.evm({
    required String chainId,
    required String from,
    required String to,
    required String data,
    required String value,
    required String gasLimit,
    EvmFeeHint? feeHint,
  }) = ClientMaterializedEvmTransaction;

  factory ClientMaterializedTransaction.fromJson(
    RouteJson json, [
    String path = 'transaction',
  ]) {
    final discriminator = _string(json['chain_family'], '$path.chain_family');
    return switch (discriminator) {
      'evm' => ClientMaterializedEvmTransaction.fromJson(json, path),
      _ => UnknownClientMaterializedTransaction(discriminator, json),
    };
  }

  String get chainFamily;
  bool get isExecutable;
  RouteJson toJson();
}

final class ClientMaterializedEvmTransaction
    extends ClientMaterializedTransaction {
  ClientMaterializedEvmTransaction({
    required this.chainId,
    required this.from,
    required this.to,
    required this.data,
    required String value,
    required String gasLimit,
    this.feeHint,
  }) : value = _amount(value, 'value'),
       gasLimit = _amount(gasLimit, 'gasLimit');

  factory ClientMaterializedEvmTransaction.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'chain_family',
        'chain_id',
        'from',
        'to',
        'data',
        'value',
        'gas_limit',
        'fee_hint',
      },
    );
    return ClientMaterializedEvmTransaction(
      chainId: _string(json['chain_id'], '$path.chain_id'),
      from: _string(json['from'], '$path.from'),
      to: _string(json['to'], '$path.to'),
      data: _string(json['data'], '$path.data'),
      value: _amount(json['value'], '$path.value'),
      gasLimit: _amount(json['gas_limit'], '$path.gas_limit'),
      feeHint: json['fee_hint'] == null
          ? null
          : EvmFeeHint.fromJson(
              _object(json['fee_hint'], '$path.fee_hint'),
              '$path.fee_hint',
            ),
    );
  }

  @override
  String get chainFamily => 'evm';
  final String chainId;
  final String from;
  final String to;
  final String data;
  final String value;
  final String gasLimit;
  final EvmFeeHint? feeHint;
  @override
  bool get isExecutable => feeHint?.isExecutable ?? true;
  @override
  RouteJson toJson() => {
    'chain_family': chainFamily,
    'chain_id': chainId,
    'from': from,
    'to': to,
    'data': data,
    'value': value,
    'gas_limit': gasLimit,
    'fee_hint': feeHint?.toJson(),
  };
}

final class UnknownClientMaterializedTransaction
    extends ClientMaterializedTransaction {
  UnknownClientMaterializedTransaction(this.chainFamily, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String chainFamily;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

sealed class ExternalExecutionSource {
  const ExternalExecutionSource();

  factory ExternalExecutionSource.providerIntent({
    required ExternalProvider provider,
    required ProviderMaterialization materialization,
    required DateTime providerObservedAt,
    Object? providerStep,
    ProviderStepReference? providerStepReference,
    String? providerStepDigest,
  }) = ProviderIntentExecutionSource;

  factory ExternalExecutionSource.clientMaterializedTransaction({
    required ExternalProvider provider,
    required DateTime providerObservedAt,
    required ClientMaterializedTransaction transaction,
  }) = ClientMaterializedExecutionSource;

  factory ExternalExecutionSource.fromJson(
    RouteJson json, [
    String path = 'execution_source',
  ]) {
    final discriminator = _string(json['source_type'], '$path.source_type');
    return switch (discriminator) {
      'provider_intent' => ProviderIntentExecutionSource.fromJson(json, path),
      'client_materialized_transaction' =>
        ClientMaterializedExecutionSource.fromJson(json, path),
      _ => UnknownExternalExecutionSource(discriminator, json),
    };
  }

  String get sourceType;
  bool get isExecutable;
  RouteJson toJson();

  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('Execution source "$sourceType" is not executable.');
    }
    return toJson();
  }
}

final class ProviderIntentExecutionSource extends ExternalExecutionSource {
  ProviderIntentExecutionSource({
    required ExternalProvider provider,
    required ProviderMaterialization materialization,
    required this.providerObservedAt,
    Object? providerStep,
    this.providerStepReference,
    this.providerStepDigest,
  }) : providerValue = WireEnumValue.known(provider),
       materializationValue = WireEnumValue.known(materialization),
       providerStep = _freezeJson(providerStep);

  ProviderIntentExecutionSource._({
    required this.providerValue,
    required this.materializationValue,
    required this.providerObservedAt,
    required this.providerStep,
    required this.providerStepReference,
    required this.providerStepDigest,
  });

  factory ProviderIntentExecutionSource.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'source_type',
        'provider',
        'materialization',
        'provider_observed_at',
        'provider_step',
        'provider_step_reference',
        'provider_step_digest',
      },
    );
    return ProviderIntentExecutionSource._(
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      materializationValue: _wireEnum(
        json['materialization'],
        ProviderMaterialization.values,
        '$path.materialization',
      ),
      providerObservedAt: _timestamp(
        json['provider_observed_at'],
        '$path.provider_observed_at',
      ),
      providerStep: _freezeJson(json['provider_step']),
      providerStepReference: json['provider_step_reference'] == null
          ? null
          : ProviderStepReference.fromJson(
              _object(
                json['provider_step_reference'],
                '$path.provider_step_reference',
              ),
              '$path.provider_step_reference',
            ),
      providerStepDigest: _nullableString(
        json['provider_step_digest'],
        '$path.provider_step_digest',
      ),
    );
  }

  @override
  String get sourceType => 'provider_intent';
  final WireEnumValue<ExternalProvider> providerValue;
  final WireEnumValue<ProviderMaterialization> materializationValue;
  final DateTime providerObservedAt;
  final Object? providerStep;
  final ProviderStepReference? providerStepReference;
  final String? providerStepDigest;
  @override
  bool get isExecutable =>
      providerValue.isExecutable && materializationValue.isExecutable;
  @override
  RouteJson toJson() => {
    'source_type': sourceType,
    'provider': providerValue.rawValue,
    'materialization': materializationValue.rawValue,
    'provider_observed_at': _dateJson(providerObservedAt),
    'provider_step': providerStep,
    'provider_step_reference': providerStepReference?.toJson(),
    'provider_step_digest': providerStepDigest,
  };
}

final class ClientMaterializedExecutionSource extends ExternalExecutionSource {
  ClientMaterializedExecutionSource({
    required ExternalProvider provider,
    required this.providerObservedAt,
    required this.transaction,
  }) : providerValue = WireEnumValue.known(provider);

  ClientMaterializedExecutionSource._({
    required this.providerValue,
    required this.providerObservedAt,
    required this.transaction,
  });

  factory ClientMaterializedExecutionSource.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'source_type',
        'provider',
        'provider_observed_at',
        'transaction',
      },
    );
    return ClientMaterializedExecutionSource._(
      providerValue: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      providerObservedAt: _timestamp(
        json['provider_observed_at'],
        '$path.provider_observed_at',
      ),
      transaction: ClientMaterializedTransaction.fromJson(
        _object(json['transaction'], '$path.transaction'),
        '$path.transaction',
      ),
    );
  }

  @override
  String get sourceType => 'client_materialized_transaction';
  final WireEnumValue<ExternalProvider> providerValue;
  final DateTime providerObservedAt;
  final ClientMaterializedTransaction transaction;
  @override
  bool get isExecutable =>
      providerValue.isExecutable && transaction.isExecutable;
  @override
  RouteJson toJson() => {
    'source_type': sourceType,
    'provider': providerValue.rawValue,
    'provider_observed_at': _dateJson(providerObservedAt),
    'transaction': transaction.toJson(),
  };
}

final class UnknownExternalExecutionSource extends ExternalExecutionSource {
  UnknownExternalExecutionSource(this.sourceType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String sourceType;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class AtomicOrderGuard {
  AtomicOrderGuard({
    required this.guardVersion,
    required this.routeIntentDigest,
    required String orderUuid,
    required AtomicSide side,
    required this.baseTicker,
    required this.relTicker,
    required String limitPrice,
    required String requestedVolume,
    required String minimumFillVolume,
    required String maximumFillVolume,
    required this.orderSnapshotAt,
    required this.expiresAt,
  }) : orderUuid = _uuid(orderUuid, 'orderUuid'),
       sideValue = WireEnumValue.known(side),
       limitPrice = _decimal(limitPrice, 'limitPrice'),
       requestedVolume = _decimal(requestedVolume, 'requestedVolume'),
       minimumFillVolume = _decimal(minimumFillVolume, 'minimumFillVolume'),
       maximumFillVolume = _decimal(maximumFillVolume, 'maximumFillVolume');

  AtomicOrderGuard._({
    required this.guardVersion,
    required this.routeIntentDigest,
    required this.orderUuid,
    required this.sideValue,
    required this.baseTicker,
    required this.relTicker,
    required this.limitPrice,
    required this.requestedVolume,
    required this.minimumFillVolume,
    required this.maximumFillVolume,
    required this.orderSnapshotAt,
    required this.expiresAt,
  });

  factory AtomicOrderGuard.fromJson(
    RouteJson json, [
    String path = 'atomic_order_guard',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'guard_version',
        'route_intent_digest',
        'order_uuid',
        'side',
        'base_ticker',
        'rel_ticker',
        'limit_price',
        'requested_volume',
        'minimum_fill_volume',
        'maximum_fill_volume',
        'order_snapshot_at',
        'expires_at',
      },
    );
    return AtomicOrderGuard._(
      guardVersion: _integer(json['guard_version'], '$path.guard_version'),
      routeIntentDigest: _string(
        json['route_intent_digest'],
        '$path.route_intent_digest',
      ),
      orderUuid: _uuid(json['order_uuid'], '$path.order_uuid'),
      sideValue: _wireEnum(json['side'], AtomicSide.values, '$path.side'),
      baseTicker: _string(json['base_ticker'], '$path.base_ticker'),
      relTicker: _string(json['rel_ticker'], '$path.rel_ticker'),
      limitPrice: _decimal(json['limit_price'], '$path.limit_price'),
      requestedVolume: _decimal(
        json['requested_volume'],
        '$path.requested_volume',
      ),
      minimumFillVolume: _decimal(
        json['minimum_fill_volume'],
        '$path.minimum_fill_volume',
      ),
      maximumFillVolume: _decimal(
        json['maximum_fill_volume'],
        '$path.maximum_fill_volume',
      ),
      orderSnapshotAt: _timestamp(
        json['order_snapshot_at'],
        '$path.order_snapshot_at',
      ),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
    );
  }

  final int guardVersion;
  final String routeIntentDigest;
  final String orderUuid;
  final WireEnumValue<AtomicSide> sideValue;
  final String baseTicker;
  final String relTicker;
  final String limitPrice;
  final String requestedVolume;
  final String minimumFillVolume;
  final String maximumFillVolume;
  final DateTime orderSnapshotAt;
  final DateTime expiresAt;
  bool get isExecutable => sideValue.isExecutable;
  RouteJson toJson() => {
    'guard_version': guardVersion,
    'route_intent_digest': routeIntentDigest,
    'order_uuid': orderUuid,
    'side': sideValue.rawValue,
    'base_ticker': baseTicker,
    'rel_ticker': relTicker,
    'limit_price': limitPrice,
    'requested_volume': requestedVolume,
    'minimum_fill_volume': minimumFillVolume,
    'maximum_fill_volume': maximumFillVolume,
    'order_snapshot_at': _dateJson(orderSnapshotAt),
    'expires_at': _dateJson(expiresAt),
  };
}

final class StageConsent {
  StageConsent({
    required this.digestVersion,
    required this.candidateReference,
    required this.routeIntent,
    required this.stageIntent,
    required this.executionSource,
    required ExecutionMode mode,
    required this.consentDigest,
    this.atomicOrderGuard,
    this.preparedExecution,
  }) : modeValue = WireEnumValue.known(mode);

  StageConsent._({
    required this.digestVersion,
    required this.candidateReference,
    required this.routeIntent,
    required this.stageIntent,
    required this.executionSource,
    required this.modeValue,
    required this.atomicOrderGuard,
    required this.preparedExecution,
    required this.consentDigest,
  });

  factory StageConsent.fromJson(
    RouteJson json, [
    String path = 'stage_consent',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'digest_version',
        'candidate_reference',
        'route_intent',
        'stage_intent',
        'execution_source',
        'mode',
        'atomic_order_guard',
        'consent_digest',
      },
      optional: {'prepared_execution'},
    );
    return StageConsent._(
      digestVersion: _integer(json['digest_version'], '$path.digest_version'),
      candidateReference: CandidateReference.fromJson(
        _object(json['candidate_reference'], '$path.candidate_reference'),
        '$path.candidate_reference',
      ),
      routeIntent: TradeIntent.fromJson(
        _object(json['route_intent'], '$path.route_intent'),
        '$path.route_intent',
      ),
      stageIntent: StageExecutionIntent.fromJson(
        _object(json['stage_intent'], '$path.stage_intent'),
        '$path.stage_intent',
      ),
      executionSource: ExternalExecutionSource.fromJson(
        _object(json['execution_source'], '$path.execution_source'),
        '$path.execution_source',
      ),
      modeValue: _wireEnum(json['mode'], ExecutionMode.values, '$path.mode'),
      atomicOrderGuard: json['atomic_order_guard'] == null
          ? null
          : AtomicOrderGuard.fromJson(
              _object(json['atomic_order_guard'], '$path.atomic_order_guard'),
              '$path.atomic_order_guard',
            ),
      preparedExecution: json['prepared_execution'] == null
          ? null
          : PreparedStageExecution.fromJson(
              _object(json['prepared_execution'], '$path.prepared_execution'),
              '$path.prepared_execution',
            ),
      consentDigest: _string(json['consent_digest'], '$path.consent_digest'),
    );
  }

  final int digestVersion;
  final CandidateReference candidateReference;
  final TradeIntent routeIntent;
  final StageExecutionIntent stageIntent;
  final ExternalExecutionSource executionSource;
  final WireEnumValue<ExecutionMode> modeValue;
  final AtomicOrderGuard? atomicOrderGuard;
  final PreparedStageExecution? preparedExecution;
  final String consentDigest;

  bool get isExecutable =>
      routeIntent.isExecutable &&
      stageIntent.isExecutable &&
      executionSource.isExecutable &&
      modeValue.isExecutable &&
      (atomicOrderGuard?.isExecutable ?? true) &&
      (preparedExecution?.isExecutable ?? true);
  RouteJson toJson() => {
    'digest_version': digestVersion,
    'candidate_reference': candidateReference.toJson(),
    'route_intent': routeIntent.toJson(),
    'stage_intent': stageIntent.toJson(),
    'execution_source': executionSource.toJson(),
    'mode': modeValue.rawValue,
    'atomic_order_guard': atomicOrderGuard?.toJson(),
    if (preparedExecution != null)
      'prepared_execution': preparedExecution!.toJson(),
    'consent_digest': consentDigest,
  };

  RouteJson toRequestJson() {
    if (!isExecutable) throw StateError('StageConsent is not executable.');
    final result = toJson();
    result['route_intent'] = routeIntent.toRequestJson();
    result['execution_source'] = executionSource.toRequestJson();
    return result;
  }
}

abstract interface class TradeRouteInitConsent {
  bool get isExecutable;
  RouteJson toRequestJson();
}

final class RouteConsent implements TradeRouteInitConsent {
  RouteConsent({
    required this.digestVersion,
    required String evaluationId,
    required String candidateId,
    required this.candidateDigest,
    required this.routeIntent,
    required List<StageConsent> externalStageConsents,
    required List<AtomicOrderGuard> atomicOrderGuards,
    required ExecutionMode mode,
    required this.consentExpiresAt,
    required this.routeConsentDigest,
    this.preparedAt,
    this.preparedReviewDigest,
  }) : evaluationId = _uuid(evaluationId, 'evaluationId'),
       candidateId = _uuid(candidateId, 'candidateId'),
       externalStageConsents = List.unmodifiable(externalStageConsents),
       atomicOrderGuards = List.unmodifiable(atomicOrderGuards),
       modeValue = WireEnumValue.known(mode);

  RouteConsent._({
    required this.digestVersion,
    required this.evaluationId,
    required this.candidateId,
    required this.candidateDigest,
    required this.routeIntent,
    required this.externalStageConsents,
    required this.atomicOrderGuards,
    required this.modeValue,
    required this.consentExpiresAt,
    required this.preparedAt,
    required this.preparedReviewDigest,
    required this.routeConsentDigest,
  });

  factory RouteConsent.fromJson(
    RouteJson json, [
    String path = 'route_consent',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'digest_version',
        'evaluation_id',
        'candidate_id',
        'candidate_digest',
        'route_intent',
        'external_stage_consents',
        'atomic_order_guards',
        'mode',
        'consent_expires_at',
        'route_consent_digest',
      },
      optional: {'prepared_at', 'prepared_review_digest'},
    );
    return RouteConsent._(
      digestVersion: _integer(json['digest_version'], '$path.digest_version'),
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      candidateDigest: _string(
        json['candidate_digest'],
        '$path.candidate_digest',
      ),
      routeIntent: TradeIntent.fromJson(
        _object(json['route_intent'], '$path.route_intent'),
        '$path.route_intent',
      ),
      externalStageConsents: _list(
        json['external_stage_consents'],
        '$path.external_stage_consents',
        (value, itemPath) =>
            StageConsent.fromJson(_object(value, itemPath), itemPath),
      ),
      atomicOrderGuards: _list(
        json['atomic_order_guards'],
        '$path.atomic_order_guards',
        (value, itemPath) =>
            AtomicOrderGuard.fromJson(_object(value, itemPath), itemPath),
      ),
      modeValue: _wireEnum(json['mode'], ExecutionMode.values, '$path.mode'),
      consentExpiresAt: _timestamp(
        json['consent_expires_at'],
        '$path.consent_expires_at',
      ),
      preparedAt: _nullableTimestamp(json['prepared_at'], '$path.prepared_at'),
      preparedReviewDigest: _nullableString(
        json['prepared_review_digest'],
        '$path.prepared_review_digest',
      ),
      routeConsentDigest: _string(
        json['route_consent_digest'],
        '$path.route_consent_digest',
      ),
    );
  }

  final int digestVersion;
  final String evaluationId;
  final String candidateId;
  final String candidateDigest;
  final TradeIntent routeIntent;
  final List<StageConsent> externalStageConsents;
  final List<AtomicOrderGuard> atomicOrderGuards;
  final WireEnumValue<ExecutionMode> modeValue;
  final DateTime consentExpiresAt;
  final DateTime? preparedAt;
  final String? preparedReviewDigest;
  final String routeConsentDigest;

  @override
  bool get isExecutable =>
      routeIntent.isExecutable &&
      externalStageConsents.every((consent) => consent.isExecutable) &&
      atomicOrderGuards.every((guard) => guard.isExecutable) &&
      modeValue.isExecutable;
  RouteJson toJson() => {
    'digest_version': digestVersion,
    'evaluation_id': evaluationId,
    'candidate_id': candidateId,
    'candidate_digest': candidateDigest,
    'route_intent': routeIntent.toJson(),
    'external_stage_consents': externalStageConsents
        .map((consent) => consent.toJson())
        .toList(growable: false),
    'atomic_order_guards': atomicOrderGuards
        .map((guard) => guard.toJson())
        .toList(growable: false),
    'mode': modeValue.rawValue,
    'consent_expires_at': _dateJson(consentExpiresAt),
    if (preparedAt != null) 'prepared_at': _dateJson(preparedAt!),
    if (preparedReviewDigest != null)
      'prepared_review_digest': preparedReviewDigest,
    'route_consent_digest': routeConsentDigest,
  };

  @override
  RouteJson toRequestJson() {
    if (!isExecutable) throw StateError('RouteConsent is not executable.');
    final result = toJson();
    result['route_intent'] = routeIntent.toRequestJson();
    result['external_stage_consents'] = externalStageConsents
        .map((consent) => consent.toRequestJson())
        .toList(growable: false);
    return result;
  }
}

sealed class ExternalExecutionUserAction {
  const ExternalExecutionUserAction();

  factory ExternalExecutionUserAction.acceptReplacement({
    required String actionId,
    required int expectedStateRevision,
    required String proposalDigest,
    required StageConsent replacementStageConsent,
  }) = ExternalAcceptReplacementAction;

  factory ExternalExecutionUserAction.rejectChange({
    required String actionId,
    required int expectedStateRevision,
  }) = ExternalRejectChangeAction;

  factory ExternalExecutionUserAction.stopAfterCurrent({
    required String actionId,
    required int expectedStateRevision,
  }) = ExternalStopAfterCurrentAction;

  String get actionType;
  String get actionId;
  int get expectedStateRevision;
  RouteJson toJson();
}

sealed class RouteExecutionUserAction {
  const RouteExecutionUserAction();

  factory RouteExecutionUserAction.acceptReplacement({
    required String actionId,
    required int expectedStateRevision,
    required String proposalDigest,
    required StageConsent replacementStageConsent,
  }) = RouteAcceptReplacementAction;

  factory RouteExecutionUserAction.rejectChange({
    required String actionId,
    required int expectedStateRevision,
  }) = RouteRejectChangeAction;

  factory RouteExecutionUserAction.stopAfterCurrent({
    required String actionId,
    required int expectedStateRevision,
  }) = RouteStopAfterCurrentAction;

  factory RouteExecutionUserAction.selectRecoveryRoute({
    required String actionId,
    required int expectedStateRevision,
    required RouteConsent recoveryRouteConsent,
  }) = RouteSelectRecoveryRouteAction;

  String get actionType;
  String get actionId;
  int get expectedStateRevision;
  RouteJson toJson();
}

mixin _ActionIdentity {
  String get actionId;
  int get expectedStateRevision;

  RouteJson identityJson(String actionType) => {
    'action_id': actionId,
    'expected_state_revision': expectedStateRevision,
    'action_type': actionType,
  };
}

final class ExternalAcceptReplacementAction extends ExternalExecutionUserAction
    with _ActionIdentity {
  ExternalAcceptReplacementAction({
    required String actionId,
    required this.expectedStateRevision,
    required this.proposalDigest,
    required this.replacementStageConsent,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  final String proposalDigest;
  final StageConsent replacementStageConsent;
  @override
  String get actionType => 'accept_replacement';
  @override
  RouteJson toJson() => {
    ...identityJson(actionType),
    'proposal_digest': proposalDigest,
    'replacement_stage_consent': replacementStageConsent.toRequestJson(),
  };
}

final class ExternalRejectChangeAction extends ExternalExecutionUserAction
    with _ActionIdentity {
  ExternalRejectChangeAction({
    required String actionId,
    required this.expectedStateRevision,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  @override
  String get actionType => 'reject_change';
  @override
  RouteJson toJson() => identityJson(actionType);
}

final class ExternalStopAfterCurrentAction extends ExternalExecutionUserAction
    with _ActionIdentity {
  ExternalStopAfterCurrentAction({
    required String actionId,
    required this.expectedStateRevision,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  @override
  String get actionType => 'stop_after_current';
  @override
  RouteJson toJson() => identityJson(actionType);
}

final class RouteAcceptReplacementAction extends RouteExecutionUserAction
    with _ActionIdentity {
  RouteAcceptReplacementAction({
    required String actionId,
    required this.expectedStateRevision,
    required this.proposalDigest,
    required this.replacementStageConsent,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  final String proposalDigest;
  final StageConsent replacementStageConsent;
  @override
  String get actionType => 'accept_replacement';
  @override
  RouteJson toJson() => {
    ...identityJson(actionType),
    'proposal_digest': proposalDigest,
    'replacement_stage_consent': replacementStageConsent.toRequestJson(),
  };
}

final class RouteRejectChangeAction extends RouteExecutionUserAction
    with _ActionIdentity {
  RouteRejectChangeAction({
    required String actionId,
    required this.expectedStateRevision,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  @override
  String get actionType => 'reject_change';
  @override
  RouteJson toJson() => identityJson(actionType);
}

final class RouteStopAfterCurrentAction extends RouteExecutionUserAction
    with _ActionIdentity {
  RouteStopAfterCurrentAction({
    required String actionId,
    required this.expectedStateRevision,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  @override
  String get actionType => 'stop_after_current';
  @override
  RouteJson toJson() => identityJson(actionType);
}

final class RouteSelectRecoveryRouteAction extends RouteExecutionUserAction
    with _ActionIdentity {
  RouteSelectRecoveryRouteAction({
    required String actionId,
    required this.expectedStateRevision,
    required this.recoveryRouteConsent,
  }) : actionId = _uuid(actionId, 'actionId');
  @override
  final String actionId;
  @override
  final int expectedStateRevision;
  final RouteConsent recoveryRouteConsent;
  @override
  String get actionType => 'select_recovery_route';
  @override
  RouteJson toJson() => {
    ...identityJson(actionType),
    'recovery_route_consent': recoveryRouteConsent.toRequestJson(),
  };
}

final class ChainTxReceipt {
  ChainTxReceipt._({
    required this.chainFamilyValue,
    required this.chainId,
    required this.txHash,
    required this.statusValue,
    required this.confirmations,
    required this.blockHash,
    required this.blockHeight,
    required this.gasUsed,
    required this.effectiveGasPrice,
    required this.networkFee,
    required this.revertReason,
    required this.observedAt,
  });

  factory ChainTxReceipt.fromJson(RouteJson json, [String path = 'receipt']) {
    _strictKeys(
      json,
      path,
      required: {
        'chain_family',
        'chain_id',
        'tx_hash',
        'status',
        'confirmations',
        'block_hash',
        'block_height',
        'gas_used',
        'effective_gas_price',
        'network_fee',
        'revert_reason',
        'observed_at',
      },
    );
    return ChainTxReceipt._(
      chainFamilyValue: _wireEnum(
        json['chain_family'],
        ChainFamily.values,
        '$path.chain_family',
      ),
      chainId: _string(json['chain_id'], '$path.chain_id'),
      txHash: _string(json['tx_hash'], '$path.tx_hash'),
      statusValue: _wireEnum(
        json['status'],
        ChainTxStatus.values,
        '$path.status',
      ),
      confirmations: _integer(json['confirmations'], '$path.confirmations'),
      blockHash: _nullableString(json['block_hash'], '$path.block_hash'),
      blockHeight: _nullableString(json['block_height'], '$path.block_height'),
      gasUsed: _nullableString(json['gas_used'], '$path.gas_used'),
      effectiveGasPrice: _nullableString(
        json['effective_gas_price'],
        '$path.effective_gas_price',
      ),
      networkFee: json['network_fee'] == null
          ? null
          : AssetAmount.fromJson(
              _object(json['network_fee'], '$path.network_fee'),
              '$path.network_fee',
            ),
      revertReason: _nullableString(
        json['revert_reason'],
        '$path.revert_reason',
      ),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
    );
  }

  final WireEnumValue<ChainFamily> chainFamilyValue;
  final String chainId;
  final String txHash;
  final WireEnumValue<ChainTxStatus> statusValue;
  final int confirmations;
  final String? blockHash;
  final String? blockHeight;
  final String? gasUsed;
  final String? effectiveGasPrice;
  final AssetAmount? networkFee;
  final String? revertReason;
  final DateTime observedAt;

  bool get isExecutable =>
      chainFamilyValue.isExecutable &&
      statusValue.isExecutable &&
      (networkFee?.isExecutable ?? true);
  RouteJson toJson() => {
    'chain_family': chainFamilyValue.rawValue,
    'chain_id': chainId,
    'tx_hash': txHash,
    'status': statusValue.rawValue,
    'confirmations': confirmations,
    'block_hash': blockHash,
    'block_height': blockHeight,
    'gas_used': gasUsed,
    'effective_gas_price': effectiveGasPrice,
    'network_fee': networkFee?.toJson(),
    'revert_reason': revertReason,
    'observed_at': _dateJson(observedAt),
  };
}

sealed class ApprovalPlanAction {
  const ApprovalPlanAction();

  factory ApprovalPlanAction.fromJson(
    RouteJson json, [
    String path = 'approval_action',
  ]) {
    final discriminator = _string(json['action_type'], '$path.action_type');
    return switch (discriminator) {
      'reset_allowance' => ResetAllowanceApprovalAction.fromJson(json, path),
      'set_exact_allowance' => SetExactAllowanceApprovalAction.fromJson(
        json,
        path,
      ),
      _ => UnknownApprovalPlanAction(discriminator, json),
    };
  }

  String get actionType;
  bool get isExecutable;
  RouteJson toJson();
}

final class ResetAllowanceApprovalAction extends ApprovalPlanAction {
  ResetAllowanceApprovalAction({required String amount})
    : amount = _amount(amount, 'amount');
  factory ResetAllowanceApprovalAction.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'action_type', 'amount'});
    return ResetAllowanceApprovalAction(
      amount: _amount(json['amount'], '$path.amount'),
    );
  }
  final String amount;
  @override
  String get actionType => 'reset_allowance';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {'action_type': actionType, 'amount': amount};
}

final class SetExactAllowanceApprovalAction extends ApprovalPlanAction {
  SetExactAllowanceApprovalAction({required String amount})
    : amount = _amount(amount, 'amount');
  factory SetExactAllowanceApprovalAction.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(json, path, required: {'action_type', 'amount'});
    return SetExactAllowanceApprovalAction(
      amount: _amount(json['amount'], '$path.amount'),
    );
  }
  final String amount;
  @override
  String get actionType => 'set_exact_allowance';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {'action_type': actionType, 'amount': amount};
}

final class UnknownApprovalPlanAction extends ApprovalPlanAction {
  UnknownApprovalPlanAction(this.actionType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String actionType;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class ApprovalRecovery {
  ApprovalRecovery._({
    required this.token,
    required this.validatedSpender,
    required this.remainingAllowance,
    required this.instructionValue,
  });

  factory ApprovalRecovery.fromJson(
    RouteJson json, [
    String path = 'approval_recovery',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'token',
        'validated_spender',
        'remaining_allowance',
        'instruction',
      },
    );
    return ApprovalRecovery._(
      token: RouteAsset.fromJson(
        _object(json['token'], '$path.token'),
        '$path.token',
      ),
      validatedSpender: _string(
        json['validated_spender'],
        '$path.validated_spender',
      ),
      remainingAllowance: _amount(
        json['remaining_allowance'],
        '$path.remaining_allowance',
      ),
      instructionValue: _wireEnum(
        json['instruction'],
        ApprovalRecoveryInstruction.values,
        '$path.instruction',
      ),
    );
  }

  final RouteAsset token;
  final String validatedSpender;
  final String remainingAllowance;
  final WireEnumValue<ApprovalRecoveryInstruction> instructionValue;
  bool get isExecutable => token.isExecutable && instructionValue.isExecutable;
  RouteJson toJson() => {
    'token': token.toJson(),
    'validated_spender': validatedSpender,
    'remaining_allowance': remainingAllowance,
    'instruction': instructionValue.rawValue,
  };
}

sealed class RouteRpcError {
  const RouteRpcError();

  factory RouteRpcError.fromJson(RouteJson json, [String path = 'error']) {
    _strictKeys(json, path, required: {'error_type', 'error_data'});
    final discriminator = _string(json['error_type'], '$path.error_type');
    if (!_knownRouteErrorTypes.contains(discriminator)) {
      return UnknownRouteRpcError(
        rawDiscriminator: discriminator,
        rawData: _freezeJson(json['error_data']),
        rawPayload: json,
      );
    }
    _validateRouteErrorData(discriminator, json['error_data'], path);
    return KnownRouteRpcError(
      type: discriminator,
      data: _freezeJson(json['error_data']),
    );
  }

  String get rawDiscriminator;
  Object? get rawData;
  bool get isKnown;
  bool get isExecutable => false;
  RouteJson toJson();
}

final class KnownRouteRpcError extends RouteRpcError {
  const KnownRouteRpcError({required this.type, required this.data});
  final String type;
  final Object? data;
  @override
  String get rawDiscriminator => type;
  @override
  Object? get rawData => data;
  @override
  bool get isKnown => true;
  @override
  RouteJson toJson() => {'error_type': type, 'error_data': data};
}

final class UnknownRouteRpcError extends RouteRpcError {
  UnknownRouteRpcError({
    required this.rawDiscriminator,
    required this.rawData,
    required RouteJson rawPayload,
  }) : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String rawDiscriminator;
  @override
  final Object? rawData;
  final RouteJson rawPayload;
  @override
  bool get isKnown => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

const _knownRouteErrorTypes = {
  'InvalidRequest',
  'AssetNotActivated',
  'UnsupportedCapability',
  'AddressSelectionError',
  'ChainMismatch',
  'SenderMismatch',
  'RecipientMismatch',
  'AssetMismatch',
  'AmountMismatch',
  'ApprovalSpenderMismatch',
  'QuoteExpired',
  'EvaluationNotFound',
  'ConsentDigestMismatch',
  'ProviderTransport',
  'ProviderRateLimited',
  'ProviderRejected',
  'ProviderResponseInvalid',
  'SimulationFailed',
  'ApprovalFailed',
  'SigningFailed',
  'BroadcastFailed',
  'TransactionReverted',
  'ApprovalRequired',
  'QuoteChanged',
  'FeeLimitExceeded',
  'NetworkFeeCapExceeded',
  'IdempotencyConflict',
  'ActionRevisionConflict',
  'InvalidUserActionState',
  'NoSuchTask',
  'ExecutionNotFound',
  'RouteNotFound',
  'CandidateChanged',
  'ProviderStepMismatch',
  'OrderUnavailable',
  'AtomicGuardMismatch',
  'AtomicFillNotReady',
  'ChainTransport',
  'ChainResponseInvalid',
  'PersistenceError',
  'RecoveryRequired',
  'Internal',
};

void _validateRouteErrorData(String type, Object? rawData, String path) {
  final dataPath = '$path.error_data';
  if (type == 'NoSuchTask') {
    _integer(rawData, dataPath);
    return;
  }
  if (type == 'Internal') {
    _string(rawData, dataPath);
    return;
  }
  final data = _object(rawData, dataPath);
  void fields(Set<String> required, {Set<String> optional = const {}}) =>
      _strictKeys(data, dataPath, required: required, optional: optional);
  void strings(Set<String> names) {
    for (final name in names) {
      _string(data[name], '$dataPath.$name');
    }
  }

  switch (type) {
    case 'InvalidRequest':
    case 'AddressSelectionError':
      fields({'field', 'reason'});
      strings({'field', 'reason'});
    case 'UnsupportedCapability':
      fields({'provider', 'operation', 'reason'});
      strings({'provider', 'operation', 'reason'});
    case 'AssetNotActivated':
      fields({'ticker'});
      strings({'ticker'});
    case 'ChainMismatch':
    case 'SenderMismatch':
    case 'RecipientMismatch':
    case 'AssetMismatch':
    case 'AmountMismatch':
    case 'ApprovalSpenderMismatch':
    case 'ConsentDigestMismatch':
    case 'QuoteChanged':
    case 'NetworkFeeCapExceeded':
    case 'CandidateChanged':
    case 'ProviderStepMismatch':
      fields({'expected', 'actual'});
      strings({'expected', 'actual'});
    case 'QuoteExpired':
      fields({'expires_at'});
      strings({'expires_at'});
    case 'EvaluationNotFound':
      fields({'evaluation_id'});
      _uuid(data['evaluation_id'], '$dataPath.evaluation_id');
    case 'ProviderTransport':
    case 'ProviderRateLimited':
    case 'ProviderRejected':
    case 'ProviderResponseInvalid':
      fields({'provider', 'operation', 'code', 'retry_after_seconds'});
      strings({'provider', 'operation'});
      if (data['code'] != null) _integer(data['code'], '$dataPath.code');
      if (data['retry_after_seconds'] != null) {
        _integer(data['retry_after_seconds'], '$dataPath.retry_after_seconds');
      }
    case 'SimulationFailed':
    case 'RecoveryRequired':
      fields({'reason'});
      strings({'reason'});
    case 'ApprovalFailed':
      fields({'action', 'tx_hash'});
      strings({'action', 'tx_hash'});
    case 'SigningFailed':
    case 'ChainTransport':
    case 'ChainResponseInvalid':
    case 'PersistenceError':
      fields({'operation'});
      strings({'operation'});
    case 'BroadcastFailed':
      fields({'operation', 'code', 'retryable'});
      strings({'operation'});
      if (data['code'] != null) _string(data['code'], '$dataPath.code');
      _boolean(data['retryable'], '$dataPath.retryable');
    case 'TransactionReverted':
      fields({'tx_hash'});
      strings({'tx_hash'});
    case 'ApprovalRequired':
      fields({
        'token',
        'current_allowance',
        'required_amount',
        'validated_spender',
        'approval_plan',
      });
      RouteAsset.fromJson(
        _object(data['token'], '$dataPath.token'),
        '$dataPath.token',
      );
      strings({'current_allowance', 'required_amount', 'validated_spender'});
      _list(data['approval_plan'], '$dataPath.approval_plan', (
        value,
        itemPath,
      ) {
        return ApprovalPlanAction.fromJson(_object(value, itemPath), itemPath);
      });
    case 'FeeLimitExceeded':
      fields({'fee_type', 'expected', 'actual'});
      strings({'fee_type', 'expected', 'actual'});
    case 'IdempotencyConflict':
      fields({'identifier_kind', 'identifier_value'});
      strings({'identifier_kind', 'identifier_value'});
    case 'ActionRevisionConflict':
      fields({'action_id', 'expected_revision', 'actual_revision'});
      _uuid(data['action_id'], '$dataPath.action_id');
      _integer(data['expected_revision'], '$dataPath.expected_revision');
      _integer(data['actual_revision'], '$dataPath.actual_revision');
    case 'InvalidUserActionState':
      fields({'action', 'phase'});
      strings({'action', 'phase'});
    case 'ExecutionNotFound':
      fields({'execution_id'});
      _uuid(data['execution_id'], '$dataPath.execution_id');
    case 'RouteNotFound':
      fields({'route_execution_id'});
      _uuid(data['route_execution_id'], '$dataPath.route_execution_id');
    case 'OrderUnavailable':
      fields({'order_uuid', 'reason'});
      _uuid(data['order_uuid'], '$dataPath.order_uuid');
      _string(data['reason'], '$dataPath.reason');
    case 'AtomicGuardMismatch':
      fields({'guard_id'});
      _uuid(data['guard_id'], '$dataPath.guard_id');
    case 'AtomicFillNotReady':
      fields({'guard_id', 'reason'});
      _uuid(data['guard_id'], '$dataPath.guard_id');
      _string(data['reason'], '$dataPath.reason');
  }
}

final class ReplacementSummary {
  ReplacementSummary._({
    required this.proposalDigest,
    required this.stageId,
    required this.providerStepDigest,
    required this.changedFields,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.fees,
    required this.requiredTotalNetworkFee,
    required this.selectedTools,
    required this.expiresAt,
    required this.replacementStageConsent,
  });

  factory ReplacementSummary.fromJson(
    RouteJson json, [
    String path = 'replacement_summary',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'proposal_digest',
        'stage_id',
        'provider_step_digest',
        'changed_fields',
        'expected_receive',
        'minimum_receive',
        'fees',
        'required_total_network_fee',
        'selected_tools',
        'expires_at',
      },
      optional: {'replacement_stage_consent'},
    );
    return ReplacementSummary._(
      proposalDigest: _string(json['proposal_digest'], '$path.proposal_digest'),
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      providerStepDigest: _nullableString(
        json['provider_step_digest'],
        '$path.provider_step_digest',
      ),
      changedFields: _strings(json['changed_fields'], '$path.changed_fields'),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      fees: _list(json['fees'], '$path.fees', (value, itemPath) {
        return FeeComponent.fromJson(_object(value, itemPath), itemPath);
      }),
      requiredTotalNetworkFee: json['required_total_network_fee'] == null
          ? null
          : AssetAmount.fromJson(
              _object(
                json['required_total_network_fee'],
                '$path.required_total_network_fee',
              ),
              '$path.required_total_network_fee',
            ),
      selectedTools: SelectedTools.fromJson(
        _object(json['selected_tools'], '$path.selected_tools'),
        '$path.selected_tools',
      ),
      expiresAt: _timestamp(json['expires_at'], '$path.expires_at'),
      replacementStageConsent: json['replacement_stage_consent'] == null
          ? null
          : StageConsent.fromJson(
              _object(
                json['replacement_stage_consent'],
                '$path.replacement_stage_consent',
              ),
              '$path.replacement_stage_consent',
            ),
    );
  }

  final String proposalDigest;
  final String stageId;
  final String? providerStepDigest;
  final List<String> changedFields;
  final String expectedReceive;
  final String minimumReceive;
  final List<FeeComponent> fees;
  final AssetAmount? requiredTotalNetworkFee;
  final SelectedTools selectedTools;
  final DateTime expiresAt;
  final StageConsent? replacementStageConsent;
  bool get isExecutable =>
      (replacementStageConsent?.isExecutable ?? false) &&
      fees.every((fee) => fee.isExecutable) &&
      (requiredTotalNetworkFee?.isExecutable ?? true);
  RouteJson toJson() => {
    'proposal_digest': proposalDigest,
    'stage_id': stageId,
    'provider_step_digest': providerStepDigest,
    'changed_fields': changedFields,
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'fees': fees.map((fee) => fee.toJson()).toList(growable: false),
    'required_total_network_fee': requiredTotalNetworkFee?.toJson(),
    'selected_tools': selectedTools.toJson(),
    'expires_at': _dateJson(expiresAt),
    if (replacementStageConsent != null)
      'replacement_stage_consent': replacementStageConsent!.toJson(),
  };
}

final class PendingUserAction {
  PendingUserAction._({
    required this.actionId,
    required this.reason,
    required this.allowedActions,
    required this.replacementSummary,
  });

  factory PendingUserAction.fromJson(
    RouteJson json, [
    String path = 'pending_user_action',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'action_id',
        'reason',
        'allowed_actions',
        'replacement_summary',
      },
    );
    return PendingUserAction._(
      actionId: _uuid(json['action_id'], '$path.action_id'),
      reason: _wireEnum(
        json['reason'],
        PendingUserActionReason.values,
        '$path.reason',
      ),
      allowedActions: _list(
        json['allowed_actions'],
        '$path.allowed_actions',
        (value, itemPath) =>
            AllowedUserActionValue.fromWire(_string(value, itemPath)),
      ),
      replacementSummary: json['replacement_summary'] == null
          ? null
          : ReplacementSummary.fromJson(
              _object(json['replacement_summary'], '$path.replacement_summary'),
              '$path.replacement_summary',
            ),
    );
  }

  final String actionId;
  final WireEnumValue<PendingUserActionReason> reason;
  final List<AllowedUserActionValue> allowedActions;
  final ReplacementSummary? replacementSummary;

  bool get isExecutable =>
      reason.isExecutable &&
      allowedActions.every((action) => action.isExecutable) &&
      (replacementSummary?.isExecutable ?? true);
  RouteJson toJson() => {
    'action_id': actionId,
    'reason': reason.rawValue,
    'allowed_actions': allowedActions
        .map((action) => action.rawValue)
        .toList(growable: false),
    'replacement_summary': replacementSummary?.toJson(),
  };
}

final class ActionExecutionDigestRecord {
  ActionExecutionDigestRecord({
    required String actionId,
    required this.planRevision,
    required this.actionExecutionDigest,
    required this.txHash,
    required this.signedAt,
  }) : actionId = _uuid(actionId, 'actionId');

  factory ActionExecutionDigestRecord.fromJson(
    RouteJson json, [
    String path = 'action_execution_digest',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'action_id',
        'plan_revision',
        'action_execution_digest',
        'tx_hash',
        'signed_at',
      },
    );
    return ActionExecutionDigestRecord(
      actionId: _uuid(json['action_id'], '$path.action_id'),
      planRevision: _integer(json['plan_revision'], '$path.plan_revision'),
      actionExecutionDigest: _string(
        json['action_execution_digest'],
        '$path.action_execution_digest',
      ),
      txHash: _string(json['tx_hash'], '$path.tx_hash'),
      signedAt: _timestamp(json['signed_at'], '$path.signed_at'),
    );
  }

  final String actionId;
  final int planRevision;
  final String actionExecutionDigest;
  final String txHash;
  final DateTime signedAt;
  RouteJson toJson() => {
    'action_id': actionId,
    'plan_revision': planRevision,
    'action_execution_digest': actionExecutionDigest,
    'tx_hash': txHash,
    'signed_at': _dateJson(signedAt),
  };
}

sealed class AtomicFillGuardOwner {
  const AtomicFillGuardOwner();

  factory AtomicFillGuardOwner.fromJson(
    RouteJson json, [
    String path = 'atomic_fill_guard_reference',
  ]) {
    final discriminator = _string(json['owner_type'], '$path.owner_type');
    return switch (discriminator) {
      'external_execution' => ExternalExecutionGuardOwner.fromJson(json, path),
      'trade_route' => TradeRouteGuardOwner.fromJson(json, path),
      _ => UnknownAtomicFillGuardOwner(discriminator, json),
    };
  }

  String get ownerType;
  bool get isExecutable;
  RouteJson ownerJson();
}

final class ExternalExecutionGuardOwner extends AtomicFillGuardOwner {
  ExternalExecutionGuardOwner({
    required String sourceExecutionId,
    required this.stageConsentDigest,
  }) : sourceExecutionId = _uuid(sourceExecutionId, 'sourceExecutionId');

  factory ExternalExecutionGuardOwner.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'guard_id',
        'guard_digest',
        'owner_type',
        'source_execution_id',
        'stage_consent_digest',
      },
    );
    return ExternalExecutionGuardOwner(
      sourceExecutionId: _uuid(
        json['source_execution_id'],
        '$path.source_execution_id',
      ),
      stageConsentDigest: _string(
        json['stage_consent_digest'],
        '$path.stage_consent_digest',
      ),
    );
  }

  @override
  String get ownerType => 'external_execution';
  final String sourceExecutionId;
  final String stageConsentDigest;
  @override
  bool get isExecutable => true;
  @override
  RouteJson ownerJson() => {
    'owner_type': ownerType,
    'source_execution_id': sourceExecutionId,
    'stage_consent_digest': stageConsentDigest,
  };
}

final class TradeRouteGuardOwner extends AtomicFillGuardOwner {
  TradeRouteGuardOwner({
    required String routeExecutionId,
    required this.stageIndex,
    required this.routeConsentDigest,
  }) : routeExecutionId = _uuid(routeExecutionId, 'routeExecutionId');

  factory TradeRouteGuardOwner.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'guard_id',
        'guard_digest',
        'owner_type',
        'route_execution_id',
        'stage_index',
        'route_consent_digest',
      },
    );
    return TradeRouteGuardOwner(
      routeExecutionId: _uuid(
        json['route_execution_id'],
        '$path.route_execution_id',
      ),
      stageIndex: _integer(json['stage_index'], '$path.stage_index'),
      routeConsentDigest: _string(
        json['route_consent_digest'],
        '$path.route_consent_digest',
      ),
    );
  }

  @override
  String get ownerType => 'trade_route';
  final String routeExecutionId;
  final int stageIndex;
  final String routeConsentDigest;
  @override
  bool get isExecutable => true;
  @override
  RouteJson ownerJson() => {
    'owner_type': ownerType,
    'route_execution_id': routeExecutionId,
    'stage_index': stageIndex,
    'route_consent_digest': routeConsentDigest,
  };
}

final class UnknownAtomicFillGuardOwner extends AtomicFillGuardOwner {
  UnknownAtomicFillGuardOwner(this.ownerType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String ownerType;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson ownerJson() => _cloneJsonMap(rawPayload);
}

final class AtomicFillGuardReference {
  AtomicFillGuardReference({
    required String guardId,
    required this.guardDigest,
    required this.owner,
  }) : guardId = _uuid(guardId, 'guardId');

  factory AtomicFillGuardReference.fromJson(
    RouteJson json, [
    String path = 'atomic_fill_guard_reference',
  ]) {
    if (!json.containsKey('guard_id') || !json.containsKey('guard_digest')) {
      throw FormatException('$path is missing guard identity fields.');
    }
    return AtomicFillGuardReference(
      guardId: _uuid(json['guard_id'], '$path.guard_id'),
      guardDigest: _string(json['guard_digest'], '$path.guard_digest'),
      owner: AtomicFillGuardOwner.fromJson(json, path),
    );
  }

  final String guardId;
  final String guardDigest;
  final AtomicFillGuardOwner owner;
  bool get isExecutable => owner.isExecutable;
  RouteJson toJson() => {
    'guard_id': guardId,
    'guard_digest': guardDigest,
    ...owner.ownerJson(),
  };
}

class ExternalExecutionState {
  ExternalExecutionState._({
    required this.executionId,
    required this.phase,
    required this.stateRevision,
    required this.transactionActionId,
    required this.planRevision,
    required this.actionPlanDigest,
    required this.actionExecutionDigests,
    required this.pendingUserAction,
    required this.stopAfterCurrent,
    required this.atomicFillGuardReference,
    required this.txHashes,
    required this.sourceReceipt,
    required this.updatedAt,
  });

  static const fieldNames = {
    'execution_id',
    'phase',
    'state_revision',
    'transaction_action_id',
    'plan_revision',
    'action_plan_digest',
    'action_execution_digests',
    'pending_user_action',
    'stop_after_current',
    'atomic_fill_guard_reference',
    'tx_hashes',
    'source_receipt',
    'updated_at',
  };

  // ignore: sort_constructors_first, avoid_positional_boolean_parameters
  factory ExternalExecutionState.fromJson(
    RouteJson json, [
    String path = 'details',
    // ignore: avoid_positional_boolean_parameters
    bool strict = true,
  ]) {
    if (strict) _strictKeys(json, path, required: fieldNames);
    return ExternalExecutionState._(
      executionId: _uuid(json['execution_id'], '$path.execution_id'),
      phase: _wireEnum(json['phase'], ExecutionPhase.values, '$path.phase'),
      stateRevision: _integer(json['state_revision'], '$path.state_revision'),
      transactionActionId: json['transaction_action_id'] == null
          ? null
          : _uuid(json['transaction_action_id'], '$path.transaction_action_id'),
      planRevision: _nullableInteger(
        json['plan_revision'],
        '$path.plan_revision',
      ),
      actionPlanDigest: _nullableString(
        json['action_plan_digest'],
        '$path.action_plan_digest',
      ),
      actionExecutionDigests: _list(
        json['action_execution_digests'],
        '$path.action_execution_digests',
        (value, itemPath) => ActionExecutionDigestRecord.fromJson(
          _object(value, itemPath),
          itemPath,
        ),
      ),
      pendingUserAction: json['pending_user_action'] == null
          ? null
          : PendingUserAction.fromJson(
              _object(json['pending_user_action'], '$path.pending_user_action'),
              '$path.pending_user_action',
            ),
      stopAfterCurrent: _boolean(
        json['stop_after_current'],
        '$path.stop_after_current',
      ),
      atomicFillGuardReference: json['atomic_fill_guard_reference'] == null
          ? null
          : AtomicFillGuardReference.fromJson(
              _object(
                json['atomic_fill_guard_reference'],
                '$path.atomic_fill_guard_reference',
              ),
              '$path.atomic_fill_guard_reference',
            ),
      txHashes: _strings(json['tx_hashes'], '$path.tx_hashes'),
      sourceReceipt: json['source_receipt'] == null
          ? null
          : ChainTxReceipt.fromJson(
              _object(json['source_receipt'], '$path.source_receipt'),
              '$path.source_receipt',
            ),
      updatedAt: _timestamp(json['updated_at'], '$path.updated_at'),
    );
  }

  final String executionId;
  final WireEnumValue<ExecutionPhase> phase;
  final int stateRevision;
  final String? transactionActionId;
  final int? planRevision;
  final String? actionPlanDigest;
  final List<ActionExecutionDigestRecord> actionExecutionDigests;
  final PendingUserAction? pendingUserAction;
  final bool stopAfterCurrent;
  final AtomicFillGuardReference? atomicFillGuardReference;
  final List<String> txHashes;
  final ChainTxReceipt? sourceReceipt;
  final DateTime updatedAt;

  bool get isExecutable =>
      phase.isExecutable &&
      (pendingUserAction?.isExecutable ?? true) &&
      (atomicFillGuardReference?.isExecutable ?? true) &&
      (sourceReceipt?.isExecutable ?? true);
  RouteJson toJson() => {
    'execution_id': executionId,
    'phase': phase.rawValue,
    'state_revision': stateRevision,
    'transaction_action_id': transactionActionId,
    'plan_revision': planRevision,
    'action_plan_digest': actionPlanDigest,
    'action_execution_digests': actionExecutionDigests
        .map((record) => record.toJson())
        .toList(growable: false),
    'pending_user_action': pendingUserAction?.toJson(),
    'stop_after_current': stopAfterCurrent,
    'atomic_fill_guard_reference': atomicFillGuardReference?.toJson(),
    'tx_hashes': txHashes,
    'source_receipt': sourceReceipt?.toJson(),
    'updated_at': _dateJson(updatedAt),
  };
}

final class ExternalExecutionResult extends ExternalExecutionState {
  ExternalExecutionResult._({
    required super.executionId,
    required super.phase,
    required super.stateRevision,
    required super.transactionActionId,
    required super.planRevision,
    required super.actionPlanDigest,
    required super.actionExecutionDigests,
    required super.pendingUserAction,
    required super.stopAfterCurrent,
    required super.atomicFillGuardReference,
    required super.txHashes,
    required super.sourceReceipt,
    required super.updatedAt,
    required this.serializedTransaction,
    required this.txHash,
    required this.consentDigest,
    required this.actionExecutionDigest,
    required this.approvalRecovery,
    required this.recoveryError,
    required this.warnings,
    required this.providerDeadline,
  }) : super._();

  factory ExternalExecutionResult.fromJson(
    RouteJson json, [
    String path = 'details',
  ]) {
    const resultFields = {
      'serialized_transaction',
      'tx_hash',
      'consent_digest',
      'action_execution_digest',
      'approval_recovery',
      'warnings',
      'provider_deadline',
    };
    _strictKeys(
      json,
      path,
      required: {...ExternalExecutionState.fieldNames, ...resultFields},
      optional: {'recovery_error'},
    );
    final state = ExternalExecutionState.fromJson(json, path, false);
    return ExternalExecutionResult._(
      executionId: state.executionId,
      phase: state.phase,
      stateRevision: state.stateRevision,
      transactionActionId: state.transactionActionId,
      planRevision: state.planRevision,
      actionPlanDigest: state.actionPlanDigest,
      actionExecutionDigests: state.actionExecutionDigests,
      pendingUserAction: state.pendingUserAction,
      stopAfterCurrent: state.stopAfterCurrent,
      atomicFillGuardReference: state.atomicFillGuardReference,
      txHashes: state.txHashes,
      sourceReceipt: state.sourceReceipt,
      updatedAt: state.updatedAt,
      serializedTransaction: _nullableString(
        json['serialized_transaction'],
        '$path.serialized_transaction',
      ),
      txHash: _nullableString(json['tx_hash'], '$path.tx_hash'),
      consentDigest: _string(json['consent_digest'], '$path.consent_digest'),
      actionExecutionDigest: _nullableString(
        json['action_execution_digest'],
        '$path.action_execution_digest',
      ),
      approvalRecovery: json['approval_recovery'] == null
          ? null
          : ApprovalRecovery.fromJson(
              _object(json['approval_recovery'], '$path.approval_recovery'),
              '$path.approval_recovery',
            ),
      recoveryError: json['recovery_error'] == null
          ? null
          : RouteRpcError.fromJson(
              _object(json['recovery_error'], '$path.recovery_error'),
              '$path.recovery_error',
            ),
      warnings: _list(json['warnings'], '$path.warnings', (value, itemPath) {
        return _wireEnum(value, RouteWarning.values, itemPath);
      }),
      providerDeadline: _nullableTimestamp(
        json['provider_deadline'],
        '$path.provider_deadline',
      ),
    );
  }

  final String? serializedTransaction;
  final String? txHash;
  final String consentDigest;
  final String? actionExecutionDigest;
  final ApprovalRecovery? approvalRecovery;
  final RouteRpcError? recoveryError;
  final List<WireEnumValue<RouteWarning>> warnings;
  final DateTime? providerDeadline;

  @override
  bool get isExecutable =>
      super.isExecutable &&
      (approvalRecovery?.isExecutable ?? true) &&
      recoveryError == null &&
      warnings.every((warning) => warning.isExecutable);
  @override
  RouteJson toJson() => {
    ...super.toJson(),
    'serialized_transaction': serializedTransaction,
    'tx_hash': txHash,
    'consent_digest': consentDigest,
    'action_execution_digest': actionExecutionDigest,
    'approval_recovery': approvalRecovery?.toJson(),
    if (recoveryError != null) 'recovery_error': recoveryError!.toJson(),
    'warnings': warnings.map((warning) => warning.rawValue).toList(),
    'provider_deadline': providerDeadline == null
        ? null
        : _dateJson(providerDeadline!),
  };
}

sealed class ExternalExecutionTaskStatus {
  const ExternalExecutionTaskStatus();
  factory ExternalExecutionTaskStatus.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(json, path, required: {'status', 'details'});
    final status = _string(json['status'], '$path.status');
    return switch (status) {
      'InProgress' => ExternalExecutionInProgressStatus(
        ExternalExecutionState.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'UserActionRequired' => ExternalExecutionUserActionRequiredStatus(
        ExternalExecutionState.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'Ok' => ExternalExecutionOkStatus(
        ExternalExecutionResult.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'Error' => ExternalExecutionErrorStatus(
        RouteRpcError.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      _ => UnknownExternalExecutionTaskStatus(
        rawStatus: status,
        rawDetails: _freezeJson(json['details']),
      ),
    };
  }
  String get rawStatus;
  Object? get rawDetails;
  bool get isExecutable;
  RouteJson toJson();
}

final class ExternalExecutionInProgressStatus
    extends ExternalExecutionTaskStatus {
  const ExternalExecutionInProgressStatus(this.details);
  final ExternalExecutionState details;
  @override
  String get rawStatus => 'InProgress';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => details.isExecutable;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class ExternalExecutionUserActionRequiredStatus
    extends ExternalExecutionTaskStatus {
  const ExternalExecutionUserActionRequiredStatus(this.details);
  final ExternalExecutionState details;
  @override
  String get rawStatus => 'UserActionRequired';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable =>
      details.isExecutable && details.pendingUserAction != null;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class ExternalExecutionOkStatus extends ExternalExecutionTaskStatus {
  const ExternalExecutionOkStatus(this.details);
  final ExternalExecutionResult details;
  @override
  String get rawStatus => 'Ok';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => details.isExecutable;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class ExternalExecutionErrorStatus extends ExternalExecutionTaskStatus {
  const ExternalExecutionErrorStatus(this.details);
  final RouteRpcError details;
  @override
  String get rawStatus => 'Error';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class UnknownExternalExecutionTaskStatus
    extends ExternalExecutionTaskStatus {
  const UnknownExternalExecutionTaskStatus({
    required this.rawStatus,
    required this.rawDetails,
  });
  @override
  final String rawStatus;
  @override
  final Object? rawDetails;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': rawDetails};
}

final class CancelOutcome {
  CancelOutcome._({
    required this.outcome,
    required this.phase,
    required this.stopAfterCurrent,
    required this.txHashes,
  });
  factory CancelOutcome.fromJson(RouteJson json, [String path = 'result']) {
    _strictKeys(
      json,
      path,
      required: {'outcome', 'phase', 'stop_after_current', 'tx_hashes'},
    );
    return CancelOutcome._(
      outcome: _wireEnum(
        json['outcome'],
        CancelOutcomeKind.values,
        '$path.outcome',
      ),
      phase: _string(json['phase'], '$path.phase'),
      stopAfterCurrent: _boolean(
        json['stop_after_current'],
        '$path.stop_after_current',
      ),
      txHashes: _strings(json['tx_hashes'], '$path.tx_hashes'),
    );
  }
  final WireEnumValue<CancelOutcomeKind> outcome;
  final String phase;
  final bool stopAfterCurrent;
  final List<String> txHashes;
  bool get isExecutable => outcome.isExecutable;
  RouteJson toJson() => {
    'outcome': outcome.rawValue,
    'phase': phase,
    'stop_after_current': stopAfterCurrent,
    'tx_hashes': txHashes,
  };
}

final class AssetHolding extends AssetAmount {
  AssetHolding({
    required super.asset,
    required super.amount,
    required this.address,
  });

  factory AssetHolding.fromJson(RouteJson json, [String path = 'holding']) {
    _strictKeys(json, path, required: {'asset', 'amount', 'address'});
    return AssetHolding(
      asset: RouteAsset.fromJson(
        _object(json['asset'], '$path.asset'),
        '$path.asset',
      ),
      amount: _amount(json['amount'], '$path.amount'),
      address: _string(json['address'], '$path.address'),
    );
  }

  final String address;
  @override
  RouteJson toJson() => {...super.toJson(), 'address': address};
}

final class RouteTransferAssetEvidence {
  const RouteTransferAssetEvidence({
    required this.providerChainId,
    required this.tokenIdentifier,
    required this.decimals,
    required this.symbol,
  });
  factory RouteTransferAssetEvidence.fromJson(
    RouteJson json, [
    String path = 'token',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'provider_chain_id', 'token_identifier', 'decimals', 'symbol'},
    );
    return RouteTransferAssetEvidence(
      providerChainId: _string(
        json['provider_chain_id'],
        '$path.provider_chain_id',
      ),
      tokenIdentifier: _string(
        json['token_identifier'],
        '$path.token_identifier',
      ),
      decimals: _integer(json['decimals'], '$path.decimals'),
      symbol: _string(json['symbol'], '$path.symbol'),
    );
  }
  final String providerChainId;
  final String tokenIdentifier;
  final int decimals;
  final String symbol;
  RouteJson toJson() => {
    'provider_chain_id': providerChainId,
    'token_identifier': tokenIdentifier,
    'decimals': decimals,
    'symbol': symbol,
  };
}

final class RouteTransferEvidence {
  const RouteTransferEvidence({
    required this.txHash,
    required this.chainId,
    required this.amount,
    required this.token,
  });
  factory RouteTransferEvidence.fromJson(
    RouteJson json, [
    String path = 'transfer',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'tx_hash', 'chain_id', 'amount', 'token'},
    );
    return RouteTransferEvidence(
      txHash: _string(json['tx_hash'], '$path.tx_hash'),
      chainId: _string(json['chain_id'], '$path.chain_id'),
      amount: json['amount'] == null
          ? null
          : _amount(json['amount'], '$path.amount'),
      token: json['token'] == null
          ? null
          : RouteTransferAssetEvidence.fromJson(
              _object(json['token'], '$path.token'),
              '$path.token',
            ),
    );
  }
  final String txHash;
  final String chainId;
  final String? amount;
  final RouteTransferAssetEvidence? token;
  RouteJson toJson() => {
    'tx_hash': txHash,
    'chain_id': chainId,
    'amount': amount,
    'token': token?.toJson(),
  };
}

final class RouteProviderChainObservation {
  const RouteProviderChainObservation({required this.providerChainId});
  factory RouteProviderChainObservation.fromJson(
    RouteJson json, [
    String path = 'receiving_chain',
  ]) {
    _strictKeys(json, path, required: {'provider_chain_id'});
    return RouteProviderChainObservation(
      providerChainId: _string(
        json['provider_chain_id'],
        '$path.provider_chain_id',
      ),
    );
  }
  final String providerChainId;
  RouteJson toJson() => {'provider_chain_id': providerChainId};
}

sealed class RouteEvidence {
  const RouteEvidence();
  factory RouteEvidence.fromJson(RouteJson json, [String path = 'evidence']) {
    final discriminator = _string(json['evidence_type'], '$path.evidence_type');
    return switch (discriminator) {
      'external_action' => ExternalActionRouteEvidence.fromJson(json, path),
      'source_transaction' => SourceTransactionRouteEvidence.fromJson(
        json,
        path,
      ),
      'atomic_swap' => AtomicSwapRouteEvidence.fromJson(json, path),
      'provider_status' => ProviderStatusRouteEvidence.fromJson(json, path),
      'provider_transfer' => ProviderTransferRouteEvidence.fromJson(json, path),
      _ => UnknownRouteEvidence(discriminator, json),
    };
  }
  String get evidenceType;
  bool get isExecutable;
  RouteJson toJson();
}

final class ExternalActionRouteEvidence extends RouteEvidence {
  const ExternalActionRouteEvidence({required this.actionDigest});
  factory ExternalActionRouteEvidence.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'evidence_type', 'action_digest'});
    return ExternalActionRouteEvidence(
      actionDigest: _string(json['action_digest'], '$path.action_digest'),
    );
  }
  final String actionDigest;
  @override
  String get evidenceType => 'external_action';
  @override
  bool get isExecutable => true;
  @override
  RouteJson toJson() => {
    'evidence_type': evidenceType,
    'action_digest': actionDigest,
  };
}

final class SourceTransactionRouteEvidence extends RouteEvidence {
  SourceTransactionRouteEvidence._({required this.txHash, required this.state});
  factory SourceTransactionRouteEvidence.fromJson(RouteJson json, String path) {
    _strictKeys(json, path, required: {'evidence_type', 'tx_hash', 'state'});
    return SourceTransactionRouteEvidence._(
      txHash: _string(json['tx_hash'], '$path.tx_hash'),
      state: _wireEnum(
        json['state'],
        SourceTransactionEvidenceState.values,
        '$path.state',
      ),
    );
  }
  final String txHash;
  final WireEnumValue<SourceTransactionEvidenceState> state;
  @override
  String get evidenceType => 'source_transaction';
  @override
  bool get isExecutable => state.isExecutable;
  @override
  RouteJson toJson() => {
    'evidence_type': evidenceType,
    'tx_hash': txHash,
    'state': state.rawValue,
  };
}

final class AtomicSwapRouteEvidence extends RouteEvidence {
  AtomicSwapRouteEvidence._({
    required this.swapUuid,
    required this.state,
    required this.spendTransactionHash,
  });
  factory AtomicSwapRouteEvidence.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {'evidence_type', 'swap_uuid', 'state'},
      optional: {'spend_transaction_hash'},
    );
    return AtomicSwapRouteEvidence._(
      swapUuid: _uuid(json['swap_uuid'], '$path.swap_uuid'),
      state: _wireEnum(
        json['state'],
        AtomicSwapEvidenceState.values,
        '$path.state',
      ),
      spendTransactionHash: _nullableString(
        json['spend_transaction_hash'],
        '$path.spend_transaction_hash',
      ),
    );
  }
  final String swapUuid;
  final WireEnumValue<AtomicSwapEvidenceState> state;
  final String? spendTransactionHash;
  @override
  String get evidenceType => 'atomic_swap';
  @override
  bool get isExecutable => state.isExecutable;
  @override
  RouteJson toJson() => {
    'evidence_type': evidenceType,
    'swap_uuid': swapUuid,
    'state': state.rawValue,
    if (spendTransactionHash != null)
      'spend_transaction_hash': spendTransactionHash,
  };
}

final class ProviderStatusRouteEvidence extends RouteEvidence {
  ProviderStatusRouteEvidence._({
    required this.provider,
    required this.transactionId,
    required this.tool,
    required this.fromAddress,
    required this.toAddress,
    required this.sending,
    required this.receiving,
    required this.receivingChain,
  });
  factory ProviderStatusRouteEvidence.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {
        'evidence_type',
        'provider',
        'transaction_id',
        'tool',
        'from_address',
        'to_address',
        'sending',
        'receiving',
      },
      optional: {'receiving_chain'},
    );
    final receiving = json['receiving'] == null
        ? null
        : RouteTransferEvidence.fromJson(
            _object(json['receiving'], '$path.receiving'),
            '$path.receiving',
          );
    final receivingChain = json['receiving_chain'] == null
        ? null
        : RouteProviderChainObservation.fromJson(
            _object(json['receiving_chain'], '$path.receiving_chain'),
            '$path.receiving_chain',
          );
    if (receiving != null && receivingChain != null) {
      throw FormatException(
        '$path.receiving and receiving_chain are mutually exclusive.',
      );
    }
    return ProviderStatusRouteEvidence._(
      provider: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      transactionId: _nullableString(
        json['transaction_id'],
        '$path.transaction_id',
      ),
      tool: _nullableString(json['tool'], '$path.tool'),
      fromAddress: _nullableString(json['from_address'], '$path.from_address'),
      toAddress: _nullableString(json['to_address'], '$path.to_address'),
      sending: json['sending'] == null
          ? null
          : RouteTransferEvidence.fromJson(
              _object(json['sending'], '$path.sending'),
              '$path.sending',
            ),
      receiving: receiving,
      receivingChain: receivingChain,
    );
  }
  final WireEnumValue<ExternalProvider> provider;
  final String? transactionId;
  final String? tool;
  final String? fromAddress;
  final String? toAddress;
  final RouteTransferEvidence? sending;
  final RouteTransferEvidence? receiving;
  final RouteProviderChainObservation? receivingChain;
  @override
  String get evidenceType => 'provider_status';
  @override
  bool get isExecutable => provider.isExecutable;
  @override
  RouteJson toJson() => {
    'evidence_type': evidenceType,
    'provider': provider.rawValue,
    'transaction_id': transactionId,
    'tool': tool,
    'from_address': fromAddress,
    'to_address': toAddress,
    'sending': sending?.toJson(),
    'receiving': receiving?.toJson(),
    if (receivingChain != null) 'receiving_chain': receivingChain!.toJson(),
  };
}

final class ProviderTransferRouteEvidence extends RouteEvidence {
  ProviderTransferRouteEvidence._({
    required this.provider,
    required this.transfer,
  });
  factory ProviderTransferRouteEvidence.fromJson(RouteJson json, String path) {
    _strictKeys(
      json,
      path,
      required: {'evidence_type', 'provider', 'transfer'},
    );
    return ProviderTransferRouteEvidence._(
      provider: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      transfer: RouteTransferEvidence.fromJson(
        _object(json['transfer'], '$path.transfer'),
        '$path.transfer',
      ),
    );
  }
  final WireEnumValue<ExternalProvider> provider;
  final RouteTransferEvidence transfer;
  @override
  String get evidenceType => 'provider_transfer';
  @override
  bool get isExecutable => provider.isExecutable;
  @override
  RouteJson toJson() => {
    'evidence_type': evidenceType,
    'provider': provider.rawValue,
    'transfer': transfer.toJson(),
  };
}

final class UnknownRouteEvidence extends RouteEvidence {
  UnknownRouteEvidence(this.evidenceType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String evidenceType;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class RouteStageResult {
  RouteStageResult._({
    required this.stageId,
    required this.routePhase,
    required this.txHashes,
    required this.actualHolding,
    required this.rawProviderStatus,
    required this.rawProviderSubstatus,
    required this.sourceReceipt,
    required this.receivingEvidence,
    required this.refundEvidence,
    required this.startedAt,
    required this.updatedAt,
    required this.completedAt,
  });
  factory RouteStageResult.fromJson(
    RouteJson json, [
    String path = 'stage_result',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'stage_id',
        'route_phase',
        'tx_hashes',
        'actual_holding',
        'raw_provider_status',
        'raw_provider_substatus',
        'source_receipt',
        'receiving_evidence',
        'refund_evidence',
        'started_at',
        'updated_at',
        'completed_at',
      },
    );
    RouteEvidence? evidence(String field) => json[field] == null
        ? null
        : RouteEvidence.fromJson(
            _object(json[field], '$path.$field'),
            '$path.$field',
          );
    return RouteStageResult._(
      stageId: _uuid(json['stage_id'], '$path.stage_id'),
      routePhase: _wireEnum(
        json['route_phase'],
        RoutePhase.values,
        '$path.route_phase',
      ),
      txHashes: _strings(json['tx_hashes'], '$path.tx_hashes'),
      actualHolding: json['actual_holding'] == null
          ? null
          : AssetHolding.fromJson(
              _object(json['actual_holding'], '$path.actual_holding'),
              '$path.actual_holding',
            ),
      rawProviderStatus: _nullableString(
        json['raw_provider_status'],
        '$path.raw_provider_status',
      ),
      rawProviderSubstatus: _nullableString(
        json['raw_provider_substatus'],
        '$path.raw_provider_substatus',
      ),
      sourceReceipt: json['source_receipt'] == null
          ? null
          : ChainTxReceipt.fromJson(
              _object(json['source_receipt'], '$path.source_receipt'),
              '$path.source_receipt',
            ),
      receivingEvidence: evidence('receiving_evidence'),
      refundEvidence: evidence('refund_evidence'),
      startedAt: _nullableTimestamp(json['started_at'], '$path.started_at'),
      updatedAt: _nullableTimestamp(json['updated_at'], '$path.updated_at'),
      completedAt: _nullableTimestamp(
        json['completed_at'],
        '$path.completed_at',
      ),
    );
  }
  final String stageId;
  final WireEnumValue<RoutePhase> routePhase;
  final List<String> txHashes;
  final AssetHolding? actualHolding;
  final String? rawProviderStatus;
  final String? rawProviderSubstatus;
  final ChainTxReceipt? sourceReceipt;
  final RouteEvidence? receivingEvidence;
  final RouteEvidence? refundEvidence;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  bool get isExecutable =>
      routePhase.isExecutable &&
      (actualHolding?.isExecutable ?? true) &&
      (sourceReceipt?.isExecutable ?? true) &&
      (receivingEvidence?.isExecutable ?? true) &&
      (refundEvidence?.isExecutable ?? true);
  RouteJson toJson() => {
    'stage_id': stageId,
    'route_phase': routePhase.rawValue,
    'tx_hashes': txHashes,
    'actual_holding': actualHolding?.toJson(),
    'raw_provider_status': rawProviderStatus,
    'raw_provider_substatus': rawProviderSubstatus,
    'source_receipt': sourceReceipt?.toJson(),
    'receiving_evidence': receivingEvidence?.toJson(),
    'refund_evidence': refundEvidence?.toJson(),
    'started_at': startedAt == null ? null : _dateJson(startedAt!),
    'updated_at': updatedAt == null ? null : _dateJson(updatedAt!),
    'completed_at': completedAt == null ? null : _dateJson(completedAt!),
  };
}

final class RouteControlCapabilities {
  const RouteControlCapabilities({
    required this.canCancel,
    required this.canStopAfterCurrent,
    required this.reconciliationOnly,
  });
  factory RouteControlCapabilities.fromJson(
    RouteJson json, [
    String path = 'controls',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'can_cancel', 'can_stop_after_current', 'reconciliation_only'},
    );
    return RouteControlCapabilities(
      canCancel: _boolean(json['can_cancel'], '$path.can_cancel'),
      canStopAfterCurrent: _boolean(
        json['can_stop_after_current'],
        '$path.can_stop_after_current',
      ),
      reconciliationOnly: _boolean(
        json['reconciliation_only'],
        '$path.reconciliation_only',
      ),
    );
  }
  final bool canCancel;
  final bool canStopAfterCurrent;
  final bool reconciliationOnly;
  RouteJson toJson() => {
    'can_cancel': canCancel,
    'can_stop_after_current': canStopAfterCurrent,
    'reconciliation_only': reconciliationOnly,
  };
}

final class RouteExecutionStatus {
  RouteExecutionStatus._({
    required this.routeExecutionId,
    required this.stageIndex,
    required this.phase,
    required this.routePhase,
    required this.stateRevision,
    required this.pendingUserAction,
    required this.stopAfterCurrent,
    required this.txHashes,
    required this.actualHolding,
    required this.rawProviderStatus,
    required this.rawProviderSubstatus,
    required this.receivingEvidence,
    required this.refundEvidence,
    required this.approvalRecovery,
    required this.stageResults,
    required this.controls,
    required this.createdAt,
    required this.completedAt,
    required this.updatedAt,
  });
  factory RouteExecutionStatus.fromJson(
    RouteJson json, [
    String path = 'status',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'route_execution_id',
        'stage_index',
        'phase',
        'route_phase',
        'state_revision',
        'pending_user_action',
        'stop_after_current',
        'tx_hashes',
        'actual_holding',
        'raw_provider_status',
        'raw_provider_substatus',
        'receiving_evidence',
        'refund_evidence',
        'approval_recovery',
        'stage_results',
        'controls',
        'created_at',
        'completed_at',
        'updated_at',
      },
    );
    RouteEvidence? evidence(String field) => json[field] == null
        ? null
        : RouteEvidence.fromJson(
            _object(json[field], '$path.$field'),
            '$path.$field',
          );
    return RouteExecutionStatus._(
      routeExecutionId: _uuid(
        json['route_execution_id'],
        '$path.route_execution_id',
      ),
      stageIndex: _integer(json['stage_index'], '$path.stage_index'),
      phase: _wireEnum(json['phase'], ExecutionPhase.values, '$path.phase'),
      routePhase: _wireEnum(
        json['route_phase'],
        RoutePhase.values,
        '$path.route_phase',
      ),
      stateRevision: _integer(json['state_revision'], '$path.state_revision'),
      pendingUserAction: json['pending_user_action'] == null
          ? null
          : PendingUserAction.fromJson(
              _object(json['pending_user_action'], '$path.pending_user_action'),
              '$path.pending_user_action',
            ),
      stopAfterCurrent: _boolean(
        json['stop_after_current'],
        '$path.stop_after_current',
      ),
      txHashes: _strings(json['tx_hashes'], '$path.tx_hashes'),
      actualHolding: json['actual_holding'] == null
          ? null
          : AssetHolding.fromJson(
              _object(json['actual_holding'], '$path.actual_holding'),
              '$path.actual_holding',
            ),
      rawProviderStatus: _nullableString(
        json['raw_provider_status'],
        '$path.raw_provider_status',
      ),
      rawProviderSubstatus: _nullableString(
        json['raw_provider_substatus'],
        '$path.raw_provider_substatus',
      ),
      receivingEvidence: evidence('receiving_evidence'),
      refundEvidence: evidence('refund_evidence'),
      approvalRecovery: json['approval_recovery'] == null
          ? null
          : ApprovalRecovery.fromJson(
              _object(json['approval_recovery'], '$path.approval_recovery'),
              '$path.approval_recovery',
            ),
      stageResults: _list(
        json['stage_results'],
        '$path.stage_results',
        (value, itemPath) =>
            RouteStageResult.fromJson(_object(value, itemPath), itemPath),
      ),
      controls: RouteControlCapabilities.fromJson(
        _object(json['controls'], '$path.controls'),
        '$path.controls',
      ),
      createdAt: _nullableTimestamp(json['created_at'], '$path.created_at'),
      completedAt: _nullableTimestamp(
        json['completed_at'],
        '$path.completed_at',
      ),
      updatedAt: _timestamp(json['updated_at'], '$path.updated_at'),
    );
  }
  final String routeExecutionId;
  final int stageIndex;
  final WireEnumValue<ExecutionPhase> phase;
  final WireEnumValue<RoutePhase> routePhase;
  final int stateRevision;
  final PendingUserAction? pendingUserAction;
  final bool stopAfterCurrent;
  final List<String> txHashes;
  final AssetHolding? actualHolding;
  final String? rawProviderStatus;
  final String? rawProviderSubstatus;
  final RouteEvidence? receivingEvidence;
  final RouteEvidence? refundEvidence;
  final ApprovalRecovery? approvalRecovery;
  final List<RouteStageResult> stageResults;
  final RouteControlCapabilities controls;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime updatedAt;
  bool get isExecutable =>
      phase.isExecutable &&
      routePhase.isExecutable &&
      (pendingUserAction?.isExecutable ?? true) &&
      (actualHolding?.isExecutable ?? true) &&
      (receivingEvidence?.isExecutable ?? true) &&
      (refundEvidence?.isExecutable ?? true) &&
      (approvalRecovery?.isExecutable ?? true) &&
      stageResults.every((result) => result.isExecutable);
  RouteJson toJson() => {
    'route_execution_id': routeExecutionId,
    'stage_index': stageIndex,
    'phase': phase.rawValue,
    'route_phase': routePhase.rawValue,
    'state_revision': stateRevision,
    'pending_user_action': pendingUserAction?.toJson(),
    'stop_after_current': stopAfterCurrent,
    'tx_hashes': txHashes,
    'actual_holding': actualHolding?.toJson(),
    'raw_provider_status': rawProviderStatus,
    'raw_provider_substatus': rawProviderSubstatus,
    'receiving_evidence': receivingEvidence?.toJson(),
    'refund_evidence': refundEvidence?.toJson(),
    'approval_recovery': approvalRecovery?.toJson(),
    'stage_results': stageResults
        .map((result) => result.toJson())
        .toList(growable: false),
    'controls': controls.toJson(),
    'created_at': createdAt == null ? null : _dateJson(createdAt!),
    'completed_at': completedAt == null ? null : _dateJson(completedAt!),
    'updated_at': _dateJson(updatedAt),
  };
}

sealed class TradeRouteTaskStatus {
  const TradeRouteTaskStatus();
  factory TradeRouteTaskStatus.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(json, path, required: {'status', 'details'});
    final status = _string(json['status'], '$path.status');
    return switch (status) {
      'InProgress' => TradeRouteInProgressStatus(
        RouteExecutionStatus.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'UserActionRequired' => TradeRouteUserActionRequiredStatus(
        RouteExecutionStatus.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'Ok' => TradeRouteOkStatus(
        RouteExecutionStatus.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      'Error' => TradeRouteErrorStatus(
        RouteRpcError.fromJson(
          _object(json['details'], '$path.details'),
          '$path.details',
        ),
      ),
      _ => UnknownTradeRouteTaskStatus(
        rawStatus: status,
        rawDetails: _freezeJson(json['details']),
      ),
    };
  }
  String get rawStatus;
  Object? get rawDetails;
  bool get isExecutable;
  RouteJson toJson();
}

final class TradeRouteInProgressStatus extends TradeRouteTaskStatus {
  const TradeRouteInProgressStatus(this.details);
  final RouteExecutionStatus details;
  @override
  String get rawStatus => 'InProgress';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => details.isExecutable;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class TradeRouteUserActionRequiredStatus extends TradeRouteTaskStatus {
  const TradeRouteUserActionRequiredStatus(this.details);
  final RouteExecutionStatus details;
  @override
  String get rawStatus => 'UserActionRequired';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable =>
      details.isExecutable && details.pendingUserAction != null;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class TradeRouteOkStatus extends TradeRouteTaskStatus {
  const TradeRouteOkStatus(this.details);
  final RouteExecutionStatus details;
  @override
  String get rawStatus => 'Ok';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => details.isExecutable;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class TradeRouteErrorStatus extends TradeRouteTaskStatus {
  const TradeRouteErrorStatus(this.details);
  final RouteRpcError details;
  @override
  String get rawStatus => 'Error';
  @override
  Object? get rawDetails => details;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': details.toJson()};
}

final class UnknownTradeRouteTaskStatus extends TradeRouteTaskStatus {
  const UnknownTradeRouteTaskStatus({
    required this.rawStatus,
    required this.rawDetails,
  });
  @override
  final String rawStatus;
  @override
  final Object? rawDetails;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => {'status': rawStatus, 'details': rawDetails};
}

sealed class RouteActivityExecutionSource {
  const RouteActivityExecutionSource();
  factory RouteActivityExecutionSource.fromJson(
    RouteJson json, [
    String path = 'execution_source',
  ]) {
    final discriminator = _string(json['source_type'], '$path.source_type');
    return switch (discriminator) {
      'provider_intent' => RouteActivityProviderIntentSource.fromJson(
        json,
        path,
      ),
      'client_materialized_transaction' =>
        RouteActivityClientMaterializedSource.fromJson(json, path),
      _ => UnknownRouteActivityExecutionSource(discriminator, json),
    };
  }
  String get sourceType;
  bool get isExecutable;
  RouteJson toJson();
}

final class RouteActivityProviderIntentSource
    extends RouteActivityExecutionSource {
  RouteActivityProviderIntentSource._({
    required this.provider,
    required this.materialization,
    required this.providerObservedAt,
    required this.providerStepReference,
    required this.providerStepDigest,
  });
  factory RouteActivityProviderIntentSource.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {
        'source_type',
        'provider',
        'materialization',
        'provider_observed_at',
        'provider_step_reference',
        'provider_step_digest',
      },
    );
    return RouteActivityProviderIntentSource._(
      provider: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      materialization: _wireEnum(
        json['materialization'],
        ProviderMaterialization.values,
        '$path.materialization',
      ),
      providerObservedAt: _timestamp(
        json['provider_observed_at'],
        '$path.provider_observed_at',
      ),
      providerStepReference: json['provider_step_reference'] == null
          ? null
          : ProviderStepReference.fromJson(
              _object(
                json['provider_step_reference'],
                '$path.provider_step_reference',
              ),
              '$path.provider_step_reference',
            ),
      providerStepDigest: _nullableString(
        json['provider_step_digest'],
        '$path.provider_step_digest',
      ),
    );
  }
  @override
  String get sourceType => 'provider_intent';
  final WireEnumValue<ExternalProvider> provider;
  final WireEnumValue<ProviderMaterialization> materialization;
  final DateTime providerObservedAt;
  final ProviderStepReference? providerStepReference;
  final String? providerStepDigest;
  @override
  bool get isExecutable =>
      provider.isExecutable && materialization.isExecutable;
  @override
  RouteJson toJson() => {
    'source_type': sourceType,
    'provider': provider.rawValue,
    'materialization': materialization.rawValue,
    'provider_observed_at': _dateJson(providerObservedAt),
    'provider_step_reference': providerStepReference?.toJson(),
    'provider_step_digest': providerStepDigest,
  };
}

final class RouteActivityClientMaterializedSource
    extends RouteActivityExecutionSource {
  RouteActivityClientMaterializedSource._({
    required this.provider,
    required this.providerObservedAt,
  });
  factory RouteActivityClientMaterializedSource.fromJson(
    RouteJson json,
    String path,
  ) {
    _strictKeys(
      json,
      path,
      required: {'source_type', 'provider', 'provider_observed_at'},
    );
    return RouteActivityClientMaterializedSource._(
      provider: _wireEnum(
        json['provider'],
        ExternalProvider.values,
        '$path.provider',
      ),
      providerObservedAt: _timestamp(
        json['provider_observed_at'],
        '$path.provider_observed_at',
      ),
    );
  }
  @override
  String get sourceType => 'client_materialized_transaction';
  final WireEnumValue<ExternalProvider> provider;
  final DateTime providerObservedAt;
  @override
  bool get isExecutable => provider.isExecutable;
  @override
  RouteJson toJson() => {
    'source_type': sourceType,
    'provider': provider.rawValue,
    'provider_observed_at': _dateJson(providerObservedAt),
  };
}

final class UnknownRouteActivityExecutionSource
    extends RouteActivityExecutionSource {
  UnknownRouteActivityExecutionSource(this.sourceType, RouteJson rawPayload)
    : rawPayload = Map.unmodifiable(_cloneJsonMap(rawPayload));
  @override
  final String sourceType;
  final RouteJson rawPayload;
  @override
  bool get isExecutable => false;
  @override
  RouteJson toJson() => _cloneJsonMap(rawPayload);
}

final class RouteActivityStageConsent {
  RouteActivityStageConsent._({
    required this.digestVersion,
    required this.candidateReference,
    required this.stageIntent,
    required this.executionSource,
    required this.mode,
    required this.atomicOrderGuard,
    required this.consentDigest,
  });
  factory RouteActivityStageConsent.fromJson(
    RouteJson json, [
    String path = 'stage_consent',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'digest_version',
        'candidate_reference',
        'stage_intent',
        'execution_source',
        'mode',
        'atomic_order_guard',
        'consent_digest',
      },
    );
    return RouteActivityStageConsent._(
      digestVersion: _integer(json['digest_version'], '$path.digest_version'),
      candidateReference: CandidateReference.fromJson(
        _object(json['candidate_reference'], '$path.candidate_reference'),
        '$path.candidate_reference',
      ),
      stageIntent: StageExecutionIntent.fromJson(
        _object(json['stage_intent'], '$path.stage_intent'),
        '$path.stage_intent',
      ),
      executionSource: RouteActivityExecutionSource.fromJson(
        _object(json['execution_source'], '$path.execution_source'),
        '$path.execution_source',
      ),
      mode: _wireEnum(json['mode'], ExecutionMode.values, '$path.mode'),
      atomicOrderGuard: json['atomic_order_guard'] == null
          ? null
          : AtomicOrderGuard.fromJson(
              _object(json['atomic_order_guard'], '$path.atomic_order_guard'),
              '$path.atomic_order_guard',
            ),
      consentDigest: _string(json['consent_digest'], '$path.consent_digest'),
    );
  }
  final int digestVersion;
  final CandidateReference candidateReference;
  final StageExecutionIntent stageIntent;
  final RouteActivityExecutionSource executionSource;
  final WireEnumValue<ExecutionMode> mode;
  final AtomicOrderGuard? atomicOrderGuard;
  final String consentDigest;
  bool get isExecutable =>
      stageIntent.isExecutable &&
      executionSource.isExecutable &&
      mode.isExecutable &&
      (atomicOrderGuard?.isExecutable ?? true);
  RouteJson toJson() => {
    'digest_version': digestVersion,
    'candidate_reference': candidateReference.toJson(),
    'stage_intent': stageIntent.toJson(),
    'execution_source': executionSource.toJson(),
    'mode': mode.rawValue,
    'atomic_order_guard': atomicOrderGuard?.toJson(),
    'consent_digest': consentDigest,
  };
}

final class RouteActivityConsent implements TradeRouteInitConsent {
  RouteActivityConsent._({
    required this.consentType,
    required this.digestVersion,
    required this.evaluationId,
    required this.candidateId,
    required this.candidateDigest,
    required this.routeIntent,
    required this.externalStageConsents,
    required this.atomicOrderGuards,
    required this.mode,
    required this.consentExpiresAt,
    required this.routeConsentDigest,
  });
  factory RouteActivityConsent.fromJson(
    RouteJson json, [
    String path = 'route_consent',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'consent_type',
        'digest_version',
        'evaluation_id',
        'candidate_id',
        'candidate_digest',
        'route_intent',
        'external_stage_consents',
        'atomic_order_guards',
        'mode',
        'consent_expires_at',
        'route_consent_digest',
      },
    );
    return RouteActivityConsent._(
      consentType: _wireEnum(
        json['consent_type'],
        RouteActivityConsentType.values,
        '$path.consent_type',
      ),
      digestVersion: _integer(json['digest_version'], '$path.digest_version'),
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      candidateId: _uuid(json['candidate_id'], '$path.candidate_id'),
      candidateDigest: _string(
        json['candidate_digest'],
        '$path.candidate_digest',
      ),
      routeIntent: TradeIntent.fromJson(
        _object(json['route_intent'], '$path.route_intent'),
        '$path.route_intent',
      ),
      externalStageConsents: _list(
        json['external_stage_consents'],
        '$path.external_stage_consents',
        (value, itemPath) => RouteActivityStageConsent.fromJson(
          _object(value, itemPath),
          itemPath,
        ),
      ),
      atomicOrderGuards: _list(
        json['atomic_order_guards'],
        '$path.atomic_order_guards',
        (value, itemPath) =>
            AtomicOrderGuard.fromJson(_object(value, itemPath), itemPath),
      ),
      mode: _wireEnum(json['mode'], ExecutionMode.values, '$path.mode'),
      consentExpiresAt: _timestamp(
        json['consent_expires_at'],
        '$path.consent_expires_at',
      ),
      routeConsentDigest: _string(
        json['route_consent_digest'],
        '$path.route_consent_digest',
      ),
    );
  }
  final WireEnumValue<RouteActivityConsentType> consentType;
  final int digestVersion;
  final String evaluationId;
  final String candidateId;
  final String candidateDigest;
  final TradeIntent routeIntent;
  final List<RouteActivityStageConsent> externalStageConsents;
  final List<AtomicOrderGuard> atomicOrderGuards;
  final WireEnumValue<ExecutionMode> mode;
  final DateTime consentExpiresAt;
  final String routeConsentDigest;
  @override
  bool get isExecutable =>
      consentType.isExecutable &&
      routeIntent.isExecutable &&
      externalStageConsents.every((consent) => consent.isExecutable) &&
      atomicOrderGuards.every((guard) => guard.isExecutable) &&
      mode.isExecutable;
  RouteJson toJson() => {
    'consent_type': consentType.rawValue,
    'digest_version': digestVersion,
    'evaluation_id': evaluationId,
    'candidate_id': candidateId,
    'candidate_digest': candidateDigest,
    'route_intent': routeIntent.toJson(),
    'external_stage_consents': externalStageConsents
        .map((consent) => consent.toJson())
        .toList(growable: false),
    'atomic_order_guards': atomicOrderGuards
        .map((guard) => guard.toJson())
        .toList(growable: false),
    'mode': mode.rawValue,
    'consent_expires_at': _dateJson(consentExpiresAt),
    'route_consent_digest': routeConsentDigest,
  };

  @override
  RouteJson toRequestJson() {
    if (!isExecutable) {
      throw StateError('RouteActivityConsent is not executable.');
    }
    return toJson();
  }
}

final class RouteActivityRevision {
  RouteActivityRevision._({
    required this.revision,
    required this.routeConsent,
    required this.candidate,
    required this.resolvedSourceAddress,
    required this.status,
    required this.stages,
    required this.archivedAt,
  });
  factory RouteActivityRevision.fromJson(
    RouteJson json, [
    String path = 'route_revision',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'revision',
        'route_consent',
        'candidate',
        'resolved_source_address',
        'status',
        'stages',
        'archived_at',
      },
    );
    return RouteActivityRevision._(
      revision: _integer(json['revision'], '$path.revision'),
      routeConsent: RouteActivityConsent.fromJson(
        _object(json['route_consent'], '$path.route_consent'),
        '$path.route_consent',
      ),
      candidate: TradeRouteCandidate.fromJson(
        _object(json['candidate'], '$path.candidate'),
        '$path.candidate',
      ),
      resolvedSourceAddress: _nullableString(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      status: RouteExecutionStatus.fromJson(
        _object(json['status'], '$path.status'),
        '$path.status',
      ),
      stages: _list(json['stages'], '$path.stages', (value, itemPath) {
        return RouteStageResult.fromJson(_object(value, itemPath), itemPath);
      }),
      archivedAt: _timestamp(json['archived_at'], '$path.archived_at'),
    );
  }
  final int revision;
  final RouteActivityConsent routeConsent;
  final TradeRouteCandidate candidate;
  final String? resolvedSourceAddress;
  final RouteExecutionStatus status;
  final List<RouteStageResult> stages;
  final DateTime archivedAt;
  bool get isExecutable =>
      routeConsent.isExecutable &&
      candidate.isExecutable &&
      status.isExecutable &&
      stages.every((stage) => stage.isExecutable);
  RouteJson toJson() => {
    'revision': revision,
    'route_consent': routeConsent.toJson(),
    'candidate': candidate.toJson(),
    'resolved_source_address': resolvedSourceAddress,
    'status': status.toJson(),
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
    'archived_at': _dateJson(archivedAt),
  };
}

final class RouteExecutionDetails {
  RouteExecutionDetails._({
    required this.routeExecutionId,
    required this.activityState,
    required this.routeConsent,
    required this.candidate,
    required this.resolvedSourceAddress,
    required this.recipientAddress,
    required this.status,
    required this.routeRevisions,
    required this.terminalError,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });
  factory RouteExecutionDetails.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'route_execution_id',
        'activity_state',
        'route_consent',
        'candidate',
        'resolved_source_address',
        'recipient_address',
        'status',
        'route_revisions',
        'terminal_error',
        'created_at',
        'updated_at',
        'completed_at',
      },
    );
    return RouteExecutionDetails._(
      routeExecutionId: _uuid(
        json['route_execution_id'],
        '$path.route_execution_id',
      ),
      activityState: _wireEnum(
        json['activity_state'],
        RouteActivityState.values,
        '$path.activity_state',
      ),
      routeConsent: RouteActivityConsent.fromJson(
        _object(json['route_consent'], '$path.route_consent'),
        '$path.route_consent',
      ),
      candidate: TradeRouteCandidate.fromJson(
        _object(json['candidate'], '$path.candidate'),
        '$path.candidate',
      ),
      resolvedSourceAddress: _nullableString(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      recipientAddress: _string(
        json['recipient_address'],
        '$path.recipient_address',
      ),
      status: RouteExecutionStatus.fromJson(
        _object(json['status'], '$path.status'),
        '$path.status',
      ),
      routeRevisions: _list(
        json['route_revisions'],
        '$path.route_revisions',
        (value, itemPath) =>
            RouteActivityRevision.fromJson(_object(value, itemPath), itemPath),
      ),
      terminalError: json['terminal_error'] == null
          ? null
          : RouteRpcError.fromJson(
              _object(json['terminal_error'], '$path.terminal_error'),
              '$path.terminal_error',
            ),
      createdAt: _timestamp(json['created_at'], '$path.created_at'),
      updatedAt: _timestamp(json['updated_at'], '$path.updated_at'),
      completedAt: _nullableTimestamp(
        json['completed_at'],
        '$path.completed_at',
      ),
    );
  }
  final String routeExecutionId;
  final WireEnumValue<RouteActivityState> activityState;
  final RouteActivityConsent routeConsent;
  final TradeRouteCandidate candidate;
  final String? resolvedSourceAddress;
  final String recipientAddress;
  final RouteExecutionStatus status;
  final List<RouteActivityRevision> routeRevisions;
  final RouteRpcError? terminalError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  bool get isExecutable =>
      activityState.isExecutable &&
      routeConsent.isExecutable &&
      candidate.isExecutable &&
      status.isExecutable &&
      routeRevisions.every((revision) => revision.isExecutable) &&
      terminalError == null;
  RouteJson toJson() => {
    'route_execution_id': routeExecutionId,
    'activity_state': activityState.rawValue,
    'route_consent': routeConsent.toJson(),
    'candidate': candidate.toJson(),
    'resolved_source_address': resolvedSourceAddress,
    'recipient_address': recipientAddress,
    'status': status.toJson(),
    'route_revisions': routeRevisions
        .map((revision) => revision.toJson())
        .toList(growable: false),
    'terminal_error': terminalError?.toJson(),
    'created_at': _dateJson(createdAt),
    'updated_at': _dateJson(updatedAt),
    'completed_at': completedAt == null ? null : _dateJson(completedAt!),
  };
}

final class RouteExecutionSummary {
  RouteExecutionSummary._({
    required this.routeExecutionId,
    required this.activityState,
    required this.routeSource,
    required this.fromAsset,
    required this.toAsset,
    required this.sourceAmount,
    required this.expectedReceive,
    required this.minimumReceive,
    required this.resolvedSourceAddress,
    required this.recipientAddress,
    required this.stageCount,
    required this.currentStageIndex,
    required this.phase,
    required this.routePhase,
    required this.controls,
    required this.requiresUserAttention,
    required this.requiresUserAction,
    required this.actualHolding,
    required this.terminalError,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });
  factory RouteExecutionSummary.fromJson(
    RouteJson json, [
    String path = 'execution',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'route_execution_id',
        'activity_state',
        'route_source',
        'from_asset',
        'to_asset',
        'source_amount',
        'expected_receive',
        'minimum_receive',
        'resolved_source_address',
        'recipient_address',
        'stage_count',
        'current_stage_index',
        'phase',
        'route_phase',
        'controls',
        'requires_user_attention',
        'requires_user_action',
        'actual_holding',
        'terminal_error',
        'created_at',
        'updated_at',
        'completed_at',
      },
    );
    return RouteExecutionSummary._(
      routeExecutionId: _uuid(
        json['route_execution_id'],
        '$path.route_execution_id',
      ),
      activityState: _wireEnum(
        json['activity_state'],
        RouteActivityState.values,
        '$path.activity_state',
      ),
      routeSource: _wireEnum(
        json['route_source'],
        RouteSource.values,
        '$path.route_source',
      ),
      fromAsset: RouteAsset.fromJson(
        _object(json['from_asset'], '$path.from_asset'),
        '$path.from_asset',
      ),
      toAsset: RouteAsset.fromJson(
        _object(json['to_asset'], '$path.to_asset'),
        '$path.to_asset',
      ),
      sourceAmount: _amount(json['source_amount'], '$path.source_amount'),
      expectedReceive: _amount(
        json['expected_receive'],
        '$path.expected_receive',
      ),
      minimumReceive: _amount(json['minimum_receive'], '$path.minimum_receive'),
      resolvedSourceAddress: _nullableString(
        json['resolved_source_address'],
        '$path.resolved_source_address',
      ),
      recipientAddress: _string(
        json['recipient_address'],
        '$path.recipient_address',
      ),
      stageCount: _integer(json['stage_count'], '$path.stage_count'),
      currentStageIndex: _integer(
        json['current_stage_index'],
        '$path.current_stage_index',
      ),
      phase: _wireEnum(json['phase'], ExecutionPhase.values, '$path.phase'),
      routePhase: _wireEnum(
        json['route_phase'],
        RoutePhase.values,
        '$path.route_phase',
      ),
      controls: RouteControlCapabilities.fromJson(
        _object(json['controls'], '$path.controls'),
        '$path.controls',
      ),
      requiresUserAttention: _boolean(
        json['requires_user_attention'],
        '$path.requires_user_attention',
      ),
      requiresUserAction: _boolean(
        json['requires_user_action'],
        '$path.requires_user_action',
      ),
      actualHolding: json['actual_holding'] == null
          ? null
          : AssetHolding.fromJson(
              _object(json['actual_holding'], '$path.actual_holding'),
              '$path.actual_holding',
            ),
      terminalError: json['terminal_error'] == null
          ? null
          : RouteRpcError.fromJson(
              _object(json['terminal_error'], '$path.terminal_error'),
              '$path.terminal_error',
            ),
      createdAt: _timestamp(json['created_at'], '$path.created_at'),
      updatedAt: _timestamp(json['updated_at'], '$path.updated_at'),
      completedAt: _nullableTimestamp(
        json['completed_at'],
        '$path.completed_at',
      ),
    );
  }
  final String routeExecutionId;
  final WireEnumValue<RouteActivityState> activityState;
  final WireEnumValue<RouteSource> routeSource;
  final RouteAsset fromAsset;
  final RouteAsset toAsset;
  final String sourceAmount;
  final String expectedReceive;
  final String minimumReceive;
  final String? resolvedSourceAddress;
  final String recipientAddress;
  final int stageCount;
  final int currentStageIndex;
  final WireEnumValue<ExecutionPhase> phase;
  final WireEnumValue<RoutePhase> routePhase;
  final RouteControlCapabilities controls;
  final bool requiresUserAttention;
  final bool requiresUserAction;
  final AssetHolding? actualHolding;
  final RouteRpcError? terminalError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  bool get isExecutable =>
      activityState.isExecutable &&
      routeSource.isExecutable &&
      fromAsset.isExecutable &&
      toAsset.isExecutable &&
      phase.isExecutable &&
      routePhase.isExecutable &&
      (actualHolding?.isExecutable ?? true) &&
      terminalError == null;
  RouteJson toJson() => {
    'route_execution_id': routeExecutionId,
    'activity_state': activityState.rawValue,
    'route_source': routeSource.rawValue,
    'from_asset': fromAsset.toJson(),
    'to_asset': toAsset.toJson(),
    'source_amount': sourceAmount,
    'expected_receive': expectedReceive,
    'minimum_receive': minimumReceive,
    'resolved_source_address': resolvedSourceAddress,
    'recipient_address': recipientAddress,
    'stage_count': stageCount,
    'current_stage_index': currentStageIndex,
    'phase': phase.rawValue,
    'route_phase': routePhase.rawValue,
    'controls': controls.toJson(),
    'requires_user_attention': requiresUserAttention,
    'requires_user_action': requiresUserAction,
    'actual_holding': actualHolding?.toJson(),
    'terminal_error': terminalError?.toJson(),
    'created_at': _dateJson(createdAt),
    'updated_at': _dateJson(updatedAt),
    'completed_at': completedAt == null ? null : _dateJson(completedAt!),
  };
}

final class ListRouteExecutionsResult {
  ListRouteExecutionsResult({
    required List<RouteExecutionSummary> executions,
    required this.nextCursor,
  }) : executions = List.unmodifiable(executions);
  factory ListRouteExecutionsResult.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(json, path, required: {'executions', 'next_cursor'});
    return ListRouteExecutionsResult(
      executions: _list(
        json['executions'],
        '$path.executions',
        (value, itemPath) =>
            RouteExecutionSummary.fromJson(_object(value, itemPath), itemPath),
      ),
      nextCursor: _nullableString(json['next_cursor'], '$path.next_cursor'),
    );
  }
  final List<RouteExecutionSummary> executions;
  final String? nextCursor;
  RouteJson toJson() => {
    'executions': executions
        .map((execution) => execution.toJson())
        .toList(growable: false),
    'next_cursor': nextCursor,
  };
}

String? _parseMmrpc(RouteJson json, String path) {
  _strictKeys(json, path, required: {'mmrpc', 'result'}, optional: {'id'});
  return _nullableString(json['mmrpc'], '$path.mmrpc');
}

final class TradeRouteCapabilitiesResult {
  TradeRouteCapabilitiesResult({
    required this.observedAt,
    required this.providerMetadataAt,
    required List<CapabilityRecord> capabilities,
  }) : capabilities = List.unmodifiable(capabilities);
  factory TradeRouteCapabilitiesResult.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'observed_at', 'provider_metadata_at', 'capabilities'},
    );
    return TradeRouteCapabilitiesResult(
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      providerMetadataAt: _timestamp(
        json['provider_metadata_at'],
        '$path.provider_metadata_at',
      ),
      capabilities: _list(
        json['capabilities'],
        '$path.capabilities',
        (value, itemPath) =>
            CapabilityRecord.fromJson(_object(value, itemPath), itemPath),
      ),
    );
  }
  final DateTime observedAt;
  final DateTime providerMetadataAt;
  final List<CapabilityRecord> capabilities;
  RouteJson toJson() => {
    'observed_at': _dateJson(observedAt),
    'provider_metadata_at': _dateJson(providerMetadataAt),
    'capabilities': capabilities
        .map((capability) => capability.toJson())
        .toList(growable: false),
  };
}

class TradeRouteEvaluateResult {
  TradeRouteEvaluateResult({
    required String evaluationId,
    required this.observedAt,
    required List<TradeRouteCandidate> candidates,
  }) : evaluationId = _uuid(evaluationId, 'evaluationId'),
       candidates = List.unmodifiable(candidates);
  factory TradeRouteEvaluateResult.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(
      json,
      path,
      required: {'evaluation_id', 'observed_at', 'candidates'},
    );
    return TradeRouteEvaluateResult(
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      candidates: _list(
        json['candidates'],
        '$path.candidates',
        (value, itemPath) =>
            TradeRouteCandidate.fromJson(_object(value, itemPath), itemPath),
      ),
    );
  }
  final String evaluationId;
  final DateTime observedAt;
  final List<TradeRouteCandidate> candidates;
  RouteJson toJson() => {
    'evaluation_id': evaluationId,
    'observed_at': _dateJson(observedAt),
    'candidates': candidates
        .map((candidate) => candidate.toJson())
        .toList(growable: false),
  };
}

final class TradeRouteQuoteResult extends TradeRouteEvaluateResult {
  TradeRouteQuoteResult({
    required super.evaluationId,
    required super.observedAt,
    required super.candidates,
    required this.evaluationExpiresAt,
  });
  factory TradeRouteQuoteResult.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(
      json,
      path,
      required: {
        'evaluation_id',
        'observed_at',
        'evaluation_expires_at',
        'candidates',
      },
    );
    return TradeRouteQuoteResult(
      evaluationId: _uuid(json['evaluation_id'], '$path.evaluation_id'),
      observedAt: _timestamp(json['observed_at'], '$path.observed_at'),
      evaluationExpiresAt: _timestamp(
        json['evaluation_expires_at'],
        '$path.evaluation_expires_at',
      ),
      candidates: _list(
        json['candidates'],
        '$path.candidates',
        (value, itemPath) =>
            TradeRouteCandidate.fromJson(_object(value, itemPath), itemPath),
      ),
    );
  }
  final DateTime evaluationExpiresAt;
  @override
  RouteJson toJson() => {
    ...super.toJson(),
    'evaluation_expires_at': _dateJson(evaluationExpiresAt),
  };
}

final class PrepareExecutionResult {
  const PrepareExecutionResult({
    required this.review,
    required this.routeConsent,
  });

  factory PrepareExecutionResult.fromJson(
    RouteJson json, [
    String path = 'result',
  ]) {
    _strictKeys(json, path, required: {'review', 'route_consent'});
    return PrepareExecutionResult(
      review: PreparedExecutionReview.fromJson(
        _object(json['review'], '$path.review'),
        '$path.review',
      ),
      routeConsent: RouteConsent.fromJson(
        _object(json['route_consent'], '$path.route_consent'),
        '$path.route_consent',
      ),
    );
  }

  final PreparedExecutionReview review;
  final RouteConsent routeConsent;

  bool get isExecutable {
    final consentPreparedAt = routeConsent.preparedAt;
    return review.isExecutable &&
        routeConsent.isExecutable &&
        consentPreparedAt != null &&
        consentPreparedAt.isAtSameMomentAs(review.preparedAt) &&
        routeConsent.preparedReviewDigest != null &&
        routeConsent.evaluationId == review.evaluationId &&
        routeConsent.candidateId == review.candidateId &&
        routeConsent.candidateDigest == review.candidateDigest;
  }

  RouteJson toJson() => {
    'review': review.toJson(),
    'route_consent': routeConsent.toJson(),
  };
}

final class TradeRouteCapabilitiesResponse extends BaseResponse {
  TradeRouteCapabilitiesResponse({required super.mmrpc, required this.result});
  factory TradeRouteCapabilitiesResponse.parse(RouteJson json) {
    return TradeRouteCapabilitiesResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: TradeRouteCapabilitiesResult.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final TradeRouteCapabilitiesResult result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class TradeRouteEvaluateResponse extends BaseResponse {
  TradeRouteEvaluateResponse({required super.mmrpc, required this.result});
  factory TradeRouteEvaluateResponse.parse(RouteJson json) {
    return TradeRouteEvaluateResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: TradeRouteEvaluateResult.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final TradeRouteEvaluateResult result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class TradeRouteQuoteResponse extends BaseResponse {
  TradeRouteQuoteResponse({required super.mmrpc, required this.result});
  factory TradeRouteQuoteResponse.parse(RouteJson json) {
    return TradeRouteQuoteResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: TradeRouteQuoteResult.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final TradeRouteQuoteResult result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class PrepareExecutionResponse extends BaseResponse {
  PrepareExecutionResponse({required super.mmrpc, required this.result});

  factory PrepareExecutionResponse.parse(RouteJson json) {
    return PrepareExecutionResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: PrepareExecutionResult.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }

  final PrepareExecutionResult result;

  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class RouteExecutionDetailsResponse extends BaseResponse {
  RouteExecutionDetailsResponse({required super.mmrpc, required this.result});
  factory RouteExecutionDetailsResponse.parse(RouteJson json) {
    return RouteExecutionDetailsResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: RouteExecutionDetails.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final RouteExecutionDetails result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class ListRouteExecutionsResponse extends BaseResponse {
  ListRouteExecutionsResponse({required super.mmrpc, required this.result});
  factory ListRouteExecutionsResponse.parse(RouteJson json) {
    return ListRouteExecutionsResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: ListRouteExecutionsResult.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final ListRouteExecutionsResult result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class ExternalExecutionTaskStatusResponse extends BaseResponse {
  ExternalExecutionTaskStatusResponse({
    required super.mmrpc,
    required this.result,
  });
  factory ExternalExecutionTaskStatusResponse.parse(RouteJson json) {
    return ExternalExecutionTaskStatusResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: ExternalExecutionTaskStatus.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final ExternalExecutionTaskStatus result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class TradeRouteTaskStatusResponse extends BaseResponse {
  TradeRouteTaskStatusResponse({required super.mmrpc, required this.result});
  factory TradeRouteTaskStatusResponse.parse(RouteJson json) {
    return TradeRouteTaskStatusResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: TradeRouteTaskStatus.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final TradeRouteTaskStatus result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class RouteActionResponse extends BaseResponse {
  RouteActionResponse({required super.mmrpc, required this.result});
  factory RouteActionResponse.parse(RouteJson json) {
    final mmrpc = _parseMmrpc(json, 'response');
    return RouteActionResponse(
      mmrpc: mmrpc,
      result: _string(json['result'], 'response.result'),
    );
  }
  final String result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result};
}

final class RouteCancelResponse extends BaseResponse {
  RouteCancelResponse({required super.mmrpc, required this.result});
  factory RouteCancelResponse.parse(RouteJson json) {
    return RouteCancelResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: CancelOutcome.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final CancelOutcome result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}

final class ChainTxReceiptResponse extends BaseResponse {
  ChainTxReceiptResponse({required super.mmrpc, required this.result});
  factory ChainTxReceiptResponse.parse(RouteJson json) {
    return ChainTxReceiptResponse(
      mmrpc: _parseMmrpc(json, 'response'),
      result: ChainTxReceipt.fromJson(
        _object(json['result'], 'response.result'),
      ),
    );
  }
  final ChainTxReceipt result;
  @override
  RouteJson toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}
