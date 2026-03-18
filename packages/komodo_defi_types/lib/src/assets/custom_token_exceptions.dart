import 'package:komodo_defi_types/src/coin_classes/coin_subclasses.dart';

class CustomTokenConflictException implements Exception {
  const CustomTokenConflictException({
    required this.assetId,
    required this.network,
    required this.existingContractAddress,
    required this.requestedContractAddress,
  });

  final String assetId;
  final CoinSubClass network;
  final String existingContractAddress;
  final String requestedContractAddress;

  String get message =>
      'A different ${network.formatted} token with id "$assetId" is already '
      'stored. Existing contract: $existingContractAddress. Requested '
      'contract: $requestedContractAddress.';

  @override
  String toString() => message;
}

class UnsupportedCustomTokenNetworkException implements Exception {
  const UnsupportedCustomTokenNetworkException(this.network);

  final CoinSubClass network;

  String get message =>
      'Custom token import is not supported for ${network.formatted}.';

  @override
  String toString() => message;
}
