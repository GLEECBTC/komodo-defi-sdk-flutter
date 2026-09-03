import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Fetches a read-only snapshot of the user's GasFree custody account for a
/// gasless-enabled TRC-20 token via `gasless::account_status`.
class GaslessAccountStatusRequest
    extends
        BaseRequest<
          GaslessAccountStatusResponse,
          GaslessAccountStatusException
        > {
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

  @override
  GaslessAccountStatusException? parseCustomErrorResponse(JsonMap json) =>
      GaslessAccountStatusException.tryParse(json);
}

/// Authoritative availability of a GasFree custody account.
enum GaslessAccountAvailability {
  /// The provider preflight responded with a full account snapshot.
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
/// [onChainBalance] and [gasfreeAddress] are always present. Fee fields and the
/// provider-derived balance split are retained for both `available` and
/// `pending_transfer`; [maxWithdrawable] is populated only for `available`.
class GaslessAccountStatusResponse extends BaseResponse {
  GaslessAccountStatusResponse({
    required super.mmrpc,
    required this.gasfreeAddress,
    required this.onChainBalance,
    required this.availability,
    this.serviceProvider,
    this.active,
    this.frozenBalance,
    this.spendableBalance,
    this.transferFee,
    this.activationFee,
    this.maxWithdrawable,
  }) {
    _validateShape();
  }

  factory GaslessAccountStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.valueOrNull<JsonMap>('result');
    if (result == null) {
      throw const FormatException(
        'GasFree account status requires an MMRPC result envelope',
      );
    }
    const allowedKeys = {
      'gasfree_address',
      'service_provider',
      'availability',
      'active',
      'on_chain_balance',
      'frozen_balance',
      'spendable_balance',
      'transfer_fee',
      'activation_fee',
      'max_withdrawable',
    };
    final missingKeys = allowedKeys.where((key) => !result.containsKey(key));
    if (missingKeys.isNotEmpty) {
      throw FormatException(
        'GasFree account status is missing fields serialized by KDF: '
        '${missingKeys.join(', ')}',
      );
    }
    final unknownKeys = result.keys.where((key) => !allowedKeys.contains(key));
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'GasFree account status contains unknown fields: '
        '${unknownKeys.join(', ')}',
      );
    }

    Decimal? decimalString(String key) {
      final raw = result[key];
      if (raw == null) return null;
      if (raw is! String) {
        throw FormatException(
          'GasFree account status $key must be a numeric string or null',
        );
      }
      final amount = Decimal.parse(raw);
      if (amount < Decimal.zero) {
        throw FormatException(
          'GasFree account status $key must be non-negative',
        );
      }
      return amount;
    }

    final onChainBalance = decimalString('on_chain_balance');
    if (onChainBalance == null) {
      throw const FormatException(
        'GasFree account status on_chain_balance must be a numeric string',
      );
    }
    return GaslessAccountStatusResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      gasfreeAddress: result.value<String>('gasfree_address'),
      onChainBalance: onChainBalance,
      availability: GaslessAccountAvailability.parse(
        result.value<String>('availability'),
      ),
      serviceProvider: result.valueOrNull<String>('service_provider'),
      active: result.valueOrNull<bool>('active'),
      frozenBalance: decimalString('frozen_balance'),
      spendableBalance: decimalString('spendable_balance'),
      transferFee: decimalString('transfer_fee'),
      activationFee: decimalString('activation_fee'),
      maxWithdrawable: decimalString('max_withdrawable'),
    );
  }

  /// Opaque GasFree custody address returned and verified by KDF.
  final String gasfreeAddress;

  /// Whether the GasFree account has been on-chain activated. `null` when the
  /// token is unsupported or the provider is unavailable.
  final bool? active;

  /// Raw TRC-20 balance held at the custody address, in token units.
  final Decimal onChainBalance;

  /// Amount currently locked by an in-flight transfer. `null` when the token is
  /// unsupported or the provider is unavailable.
  final Decimal? frozenBalance;

  /// `onChainBalance - frozenBalance` — the balance not locked by a pending
  /// transfer. `null` when the token is unsupported or the provider is
  /// unavailable.
  final Decimal? spendableBalance;

  /// Per-transfer provider fee, charged in the token. `null` when the token is
  /// unsupported or the provider is unavailable.
  final Decimal? transferFee;

  /// One-time activation fee charged in the token on the first transfer; `null`
  /// when the account is already active, the token is unsupported, or the
  /// provider is unavailable.
  final Decimal? activationFee;

  /// Optional advisory amount the user can gaslessly send now.
  ///
  /// KDF remains authoritative for a withdrawal requested with `max: true`,
  /// which does not require this field or an explicit amount.
  final Decimal? maxWithdrawable;

  /// KDF's normalized status for the custody account.
  final GaslessAccountAvailability availability;

  /// Exact service-provider address that produced the authoritative status.
  ///
  /// Present for every provider-reachable state and `null` only when the
  /// provider is unreachable.
  final String? serviceProvider;

  void _validateShape() {
    final providerPresent = serviceProvider?.trim().isNotEmpty ?? false;
    final providerFieldsPresent =
        active != null &&
        frozenBalance != null &&
        spendableBalance != null &&
        transferFee != null;
    if ((active ?? false) && activationFee != null) {
      throw const FormatException(
        'An active GasFree account cannot include an activation fee',
      );
    }

    switch (availability) {
      case GaslessAccountAvailability.available:
        if (!providerPresent ||
            !providerFieldsPresent ||
            maxWithdrawable == null) {
          throw const FormatException(
            'Invalid available GasFree account status shape',
          );
        }
      case GaslessAccountAvailability.pendingTransfer:
        if (!providerPresent ||
            !providerFieldsPresent ||
            maxWithdrawable != null) {
          throw const FormatException(
            'Invalid pending_transfer GasFree account status shape',
          );
        }
      case GaslessAccountAvailability.tokenUnsupported:
        if (!providerPresent ||
            active != null ||
            frozenBalance != null ||
            spendableBalance != null ||
            transferFee != null ||
            activationFee != null ||
            maxWithdrawable != null) {
          throw const FormatException(
            'Invalid token_unsupported GasFree account status shape',
          );
        }
      case GaslessAccountAvailability.providerUnreachable:
        if (serviceProvider != null ||
            active != null ||
            frozenBalance != null ||
            spendableBalance != null ||
            transferFee != null ||
            activationFee != null ||
            maxWithdrawable != null) {
          throw const FormatException(
            'Invalid provider_unreachable GasFree account status shape',
          );
        }
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'gasfree_address': gasfreeAddress,
      'service_provider': serviceProvider,
      'availability': availability.wireValue,
      'active': active,
      'on_chain_balance': onChainBalance.toString(),
      'frozen_balance': frozenBalance?.toString(),
      'spendable_balance': spendableBalance?.toString(),
      'transfer_fee': transferFee?.toString(),
      'activation_fee': activationFee?.toString(),
      'max_withdrawable': maxWithdrawable?.toString(),
    },
  };
}
