import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/base_strategies/activation_strategy_base.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Enables the current wallet's single Solana address and its trusted tokens.
/// HD derivation is selected by KDF's wallet, never by discovery parameters.
class SolanaActivationStrategy extends ProtocolActivationStrategy {
  /// Creates an activator for a host-verified engine capability set.
  SolanaActivationStrategy(super.client, this._keyPolicy, this._capabilities);

  final PrivateKeyPolicy _keyPolicy;
  final SolanaCapabilities _capabilities;

  /// Rejects experimental operations before any engine request is dispatched.
  static void ensureSupported(Asset asset, SolanaCapabilities capabilities) {
    final protocol = asset.protocol;
    if (protocol is! SolanaProtocol && protocol is! SolanaTokenProtocol) return;
    if (!capabilities.enabled) {
      throw UnsupportedError('Solana is unavailable in this engine build');
    }
    if (protocol is SolanaTokenProtocol &&
        protocol.programId != SolanaTokenProtocol.classicTokenProgramId &&
        protocol.programId != SolanaTokenProtocol.token2022ProgramId) {
      throw UnsupportedError('Unsupported Solana token program');
    }
    if (protocol is SolanaTokenProtocol &&
        protocol.isToken2022 &&
        !capabilities.token2022Enabled) {
      throw UnsupportedError(
        'Token-2022 transfers are not verified for this engine',
      );
    }
  }

  @override
  Set<CoinSubClass> get supportedProtocols => const {
    CoinSubClass.solana,
    CoinSubClass.solanaToken,
  };

  @override
  bool get supportsBatchActivation => true;

  // Complete, trusted protocol overrides are supported for both configured
  // tickers and SDK custom tokens. Arbitrary mint discovery is not supported.
  @override
  bool canHandle(Asset asset) => supportedProtocols.contains(asset.id.subClass);

  JsonMap _tokenProtocol(Asset token) =>
      token.protocol.config.value<JsonMap>('protocol');

  @override
  Stream<ActivationProgress> activate(
    Asset asset, [
    List<Asset>? children,
  ]) async* {
    ensureSupported(asset, _capabilities);
    if (_keyPolicy != const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an internal wallet');
    }
    for (final token in children ?? <Asset>[]) {
      ensureSupported(token, _capabilities);
      if (token.protocol is! SolanaTokenProtocol ||
          (token.protocol as SolanaTokenProtocol).platform != asset.id.id) {
        throw ArgumentError('Solana token platform does not match activation');
      }
    }
    yield const ActivationProgress(status: 'Activating Solana wallet');
    try {
      if (asset.protocol case final SolanaProtocol protocol) {
        final result = await client.post(
          EnableSolanaWithAssetsRequest(
            ticker: asset.id.id,
            nodes: protocol.nodes,
            tokensParams: [
              for (final token in children ?? <Asset>[])
                SolanaTokenRequest(
                  ticker: token.id.id,
                  protocol: _tokenProtocol(token),
                ),
            ],
          ),
        );
        if (result.ticker != asset.id.id || result.address.isEmpty) {
          throw const FormatException('Invalid Solana activation identity');
        }
      } else {
        final result = await client.post(
          EnableSolanaTokenRequest(
            ticker: asset.id.id,
            protocol: _tokenProtocol(asset),
          ),
        );
        if (result.ticker != asset.id.id || result.address.isEmpty) {
          throw const FormatException(
            'Invalid Solana token activation identity',
          );
        }
      }
      yield ActivationProgress.success();
    } on Exception catch (error, stack) {
      yield buildErrorProgress(
        asset: asset,
        error: error,
        stackTrace: stack,
        errorCode: 'SOLANA_ACTIVATION_ERROR',
      );
    }
  }
}
