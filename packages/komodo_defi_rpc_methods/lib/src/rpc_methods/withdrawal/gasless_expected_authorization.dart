import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Exact non-secret context that binds submit and trace responses to the
/// authorization signed during preview.
class GaslessExpectedAuthorization extends Equatable {
  const GaslessExpectedAuthorization({
    required this.requestId,
    required this.account,
    required this.custodyAddress,
    required this.provider,
    required this.receiver,
    required this.token,
    required this.amount,
    required this.maxFee,
    required this.deadline,
    required this.version,
    required this.nonce,
    required this.signatureFingerprint,
  });

  factory GaslessExpectedAuthorization.fromJson(JsonMap json) =>
      GaslessExpectedAuthorization(
        requestId: json.value<String>('request_id'),
        account: json.value<String>('account'),
        custodyAddress: json.value<String>('custody_address'),
        provider: json.value<String>('provider'),
        receiver: json.value<String>('receiver'),
        token: json.value<String>('token'),
        amount: json.value<String>('amount'),
        maxFee: json.value<String>('max_fee'),
        deadline: json.value<String>('deadline'),
        version: json.value<String>('version'),
        nonce: json.value<String>('nonce'),
        signatureFingerprint: json.value<String>('signature_fingerprint'),
      );

  final String requestId;
  final String account;
  final String custodyAddress;
  final String provider;
  final String receiver;
  final String token;
  final String amount;
  final String maxFee;
  final String deadline;
  final String version;
  final String nonce;
  final String signatureFingerprint;

  JsonMap toJson() => {
    'request_id': requestId,
    'account': account,
    'custody_address': custodyAddress,
    'provider': provider,
    'receiver': receiver,
    'token': token,
    'amount': amount,
    'max_fee': maxFee,
    'deadline': deadline,
    'version': version,
    'nonce': nonce,
    'signature_fingerprint': signatureFingerprint,
  };

  @override
  List<Object?> get props => [
    requestId,
    account,
    custodyAddress,
    provider,
    receiver,
    token,
    amount,
    maxFee,
    deadline,
    version,
    nonce,
    signatureFingerprint,
  ];
}
