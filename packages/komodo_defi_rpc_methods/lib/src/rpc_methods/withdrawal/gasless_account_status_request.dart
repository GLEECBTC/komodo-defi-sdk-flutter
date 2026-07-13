import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Fetches a read-only snapshot of the user's GasFree custody account for a
/// gasless-enabled TRC-20 token via `gasless::account_status`.
class GaslessAccountStatusRequest
    extends BaseRequest<GaslessAccountStatusResponse, GeneralErrorResponse> {
  GaslessAccountStatusRequest({required super.rpcPass, required this.coin})
    : super(method: 'gasless::account_status', mmrpc: RpcVersion.v2_0);

  final String coin;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {'coin': coin},
  };

  @override
  GaslessAccountStatusResponse parse(Map<String, dynamic> json) =>
      GaslessAccountStatusResponse.parse(json);
}

/// Authoritative availability of a GasFree custody account.
enum GaslessAccountAvailability {
  /// Provider status is authoritative and the account may be used now.
  available('available'),

  /// An existing transfer currently freezes the custody account.
  pendingTransfer('pending_transfer'),

  /// The provider does not support this token enrollment.
  tokenUnsupported('token_unsupported'),

  /// Provider status could not be obtained.
  providerUnreachable('provider_unreachable');

  const GaslessAccountAvailability(this.wireValue);

  /// Stable snake-case value used by KDF.
  final String wireValue;

  /// Parses KDF's stable snake-case representation.
  static GaslessAccountAvailability parse(String value) => switch (value) {
    'available' => available,
    'pending_transfer' => pendingTransfer,
    'token_unsupported' => tokenUnsupported,
    'provider_unreachable' => providerUnreachable,
    _ => throw const FormatException('Unknown GasFree account availability'),
  };
}

/// The GasFree custody account status for one TRC-20 token.
///
/// [onChainBalance] and [gasfreeAddress] are always present. Fee and maximum
/// fields are meaningful only when [availability] is
/// [GaslessAccountAvailability.available].
class GaslessAccountStatusResponse extends BaseResponse {
  GaslessAccountStatusResponse({
    required super.mmrpc,
    required this.gasfreeAddress,
    required this.onChainBalance,
    required this.availability,
    required this.hasExplicitAvailability,
    this.serviceProvider,
    this.active,
    this.frozenBalance,
    this.spendableBalance,
    this.transferFee,
    this.activationFee,
    this.maxWithdrawable,
    this.reasonCode,
  });

  factory GaslessAccountStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.valueOrNull<JsonMap>('result') ?? json;
    Decimal? dec(String key) {
      final raw = result.valueOrNull<dynamic>(key);
      return raw == null ? null : Decimal.parse(raw.toString());
    }

    final rawAvailability = result.valueOrNull<String>('availability');
    final legacyProviderAvailable = result.valueOrNull<bool>(
      'provider_available',
    );
    final reasonCode = result.valueOrNull<String>('reason_code');
    if (rawAvailability == null && legacyProviderAvailable == null) {
      throw ArgumentError('GasFree account availability is required');
    }
    final availability = rawAvailability != null
        ? GaslessAccountAvailability.parse(rawAvailability)
        : switch ((legacyProviderAvailable!, reasonCode)) {
            (true, _) => GaslessAccountAvailability.available,
            (false, 'token_unsupported') =>
              GaslessAccountAvailability.tokenUnsupported,
            (false, 'pending_transfer') =>
              GaslessAccountAvailability.pendingTransfer,
            _ => GaslessAccountAvailability.providerUnreachable,
          };

    return GaslessAccountStatusResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      gasfreeAddress: result.value<String>('gasfree_address'),
      onChainBalance: Decimal.parse(
        result.value<dynamic>('on_chain_balance').toString(),
      ),
      availability: availability,
      hasExplicitAvailability: rawAvailability != null,
      serviceProvider: result.valueOrNull<String>('service_provider'),
      active: result.valueOrNull<bool>('active'),
      frozenBalance: dec('frozen_balance'),
      spendableBalance: dec('spendable_balance'),
      transferFee: dec('transfer_fee'),
      activationFee: dec('activation_fee'),
      maxWithdrawable: dec('max_withdrawable'),
      reasonCode: reasonCode,
    );
  }

  /// Locally-derived CREATE2 custody address the tokens settle from.
  final String gasfreeAddress;

  /// Whether the GasFree account has been on-chain activated. `null` if the
  /// provider is unavailable.
  final bool? active;

  /// Raw TRC-20 balance held at the custody address, in token units.
  final Decimal onChainBalance;

  /// Amount currently locked by an in-flight transfer. `null` if the provider is
  /// unavailable.
  final Decimal? frozenBalance;

  /// `onChainBalance - frozenBalance` — the balance not locked by a pending
  /// transfer. `null` if the provider is unavailable.
  final Decimal? spendableBalance;

  /// Per-transfer provider fee, charged in the token. `null` if the provider is
  /// unavailable.
  final Decimal? transferFee;

  /// One-time activation fee charged in the token on the first transfer; `null`
  /// when the account is already active or the provider is unavailable.
  final Decimal? activationFee;

  /// Largest amount the user can gaslessly send now. `null` if the provider is
  /// unavailable. Matches the withdraw `max` amount.
  final Decimal? maxWithdrawable;

  /// KDF's authoritative status for the custody account.
  final GaslessAccountAvailability availability;

  /// Whether [availability] came from the enum contract rather than the
  /// deprecated boolean compatibility field.
  final bool hasExplicitAvailability;

  /// Compatibility alias for callers that have not migrated to [availability].
  @Deprecated('Use availability == GaslessAccountAvailability.available')
  bool get providerAvailable =>
      availability == GaslessAccountAvailability.available;

  /// Exact service-provider address that produced the authoritative status.
  ///
  /// `null` for degraded responses and KDF versions that predate provider
  /// identity attestation. A missing value must never enable new receives.
  final String? serviceProvider;

  /// Stable reason for a provider-unavailable, unsupported, or security state.
  /// Raw upstream provider content is never exposed here.
  final String? reasonCode;

  /// The custody balance as a [BalanceInfo] (`total` = on-chain,
  /// `spendable` = on-chain minus frozen, `unspendable` = frozen), so it can
  /// drop straight into balance widgets in place of the EOA balance.
  BalanceInfo get custodyBalance {
    final hasAuthoritativeSpendability =
        availability == GaslessAccountAvailability.available &&
        spendableBalance != null &&
        frozenBalance != null;
    final spendable = hasAuthoritativeSpendability
        ? spendableBalance!
        : Decimal.zero;
    final unspendable = hasAuthoritativeSpendability
        ? frozenBalance!
        : onChainBalance;
    return BalanceInfo(
      total: onChainBalance,
      spendable: spendable,
      unspendable: unspendable,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'gasfree_address': gasfreeAddress,
      'on_chain_balance': onChainBalance.toString(),
      if (hasExplicitAvailability)
        'availability': availability.wireValue
      else
        'provider_available': providerAvailable,
      if (serviceProvider != null) 'service_provider': serviceProvider,
      if (active != null) 'active': active,
      if (frozenBalance != null) 'frozen_balance': frozenBalance.toString(),
      if (spendableBalance != null)
        'spendable_balance': spendableBalance.toString(),
      if (transferFee != null) 'transfer_fee': transferFee.toString(),
      if (activationFee != null) 'activation_fee': activationFee.toString(),
      if (maxWithdrawable != null)
        'max_withdrawable': maxWithdrawable.toString(),
      if (reasonCode != null) 'reason_code': reasonCode,
    },
  };
}
