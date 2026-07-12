import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tron_grid_address_codec.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Provider-independent custody balance lookup used for recovery-only access.
abstract interface class GaslessCustodyBalanceReader {
  /// Reads the exact enrolled token balance at [custodyAddress].
  Future<Decimal> readBalance(Asset asset, String custodyAddress);

  /// Releases resources owned by the reader.
  void dispose();
}

/// Strict TRONGrid implementation for mainnet and Nile TRC-20 balances.
final class TronGridGaslessCustodyBalanceReader
    implements GaslessCustodyBalanceReader {
  /// Creates a reader, optionally using a caller-owned HTTP [client].
  TronGridGaslessCustodyBalanceReader({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  /// Reads a confirmed, exact-contract token balance in human units.
  Future<Decimal> readBalance(Asset asset, String custodyAddress) async {
    final protocol = asset.protocol;
    if (protocol is! Trc20Protocol || !isValidTronAddress(custodyAddress)) {
      throw StateError('Invalid GasFree custody balance request');
    }
    final contract =
        protocol.config['contract_address']?.toString() ??
        ((protocol.config['protocol'] as Map?)?['protocol_data']
                as Map?)?['contract_address']
            ?.toString();
    final decimals = asset.id.chainId.decimals;
    if (contract == null ||
        !isValidTronAddress(contract) ||
        decimals == null ||
        decimals < 0 ||
        decimals > 255) {
      throw StateError('Invalid GasFree token balance configuration');
    }
    final host = protocol.isTestnet ? 'nile.trongrid.io' : 'api.trongrid.io';
    final uri = Uri.https(host, '/v1/accounts/$custodyAddress', {
      'only_confirmed': 'true',
      'visible': 'true',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('GasFree custody balance service is unavailable');
    }
    // Account payloads are small; cap at 256 KiB before decoding untrusted JSON.
    if (response.bodyBytes.length > 256 * 1024) {
      throw const FormatException('Custody balance response is too large');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: false),
    );
    if (decoded is! Map || decoded['data'] is! List) {
      throw const FormatException('Invalid custody balance response');
    }
    if (decoded.containsKey('success') && decoded['success'] != true) {
      throw const FormatException('Custody balance response was unsuccessful');
    }
    final data = decoded['data'] as List;
    if (data.isEmpty) return Decimal.zero;
    if (data.length != 1 || data.single is! Map) {
      throw const FormatException('Custody account provenance is unavailable');
    }
    final trc20 = (data.single as Map)['trc20'];
    if (trc20 == null) return Decimal.zero;
    if (trc20 is! List) {
      throw const FormatException('Custody token provenance is unavailable');
    }
    final values = <String>[];
    for (final item in trc20) {
      if (item is! Map) {
        throw const FormatException('Invalid custody token balance');
      }
      final value = item[contract];
      if (value != null) values.add(value.toString());
    }
    if (values.isEmpty) return Decimal.zero;
    if (values.length != 1 ||
        !RegExp(r'^(0|[1-9]\d*)$').hasMatch(values.single)) {
      throw const FormatException('Ambiguous custody token balance');
    }
    final digits = values.single.padLeft(decimals + 1, '0');
    final split = digits.length - decimals;
    return Decimal.parse(
      decimals == 0
          ? digits
          : '${digits.substring(0, split)}.${digits.substring(split)}',
    );
  }

  @override
  /// Closes the internally owned HTTP client, if any.
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

/// Interface defining the contract for balance management operations
abstract class IBalanceManager {
  /// Gets the current balance for an asset.
  /// Will ensure the asset is activated before querying.
  ///
  /// Note: If the asset was recently activated through [ActivationManager],
  /// the balance will typically be pre-cached and return immediately. However,
  /// this should not be relied upon as a way to check activation status.
  ///
  /// Throws [AuthException] if user is not signed in.
  /// Throws [ArgumentError] if asset is not found.
  /// May throw [TimeoutException] if balance fetch times out.
  Future<BalanceInfo> getBalance(AssetId assetId);

  /// Returns custody and every Standard address balance without substituting
  /// one rail for another when provider status is unavailable.
  Future<GaslessBalanceSnapshot> getGaslessBalanceSnapshot(AssetId assetId);

  /// Returns the retained rail-aware snapshot without triggering I/O.
  GaslessBalanceSnapshot? lastKnownGaslessBalanceSnapshot(AssetId assetId);

  /// Gets a stream of balance updates for an asset.
  /// The stream will emit the current balance immediately if available,
  /// and then emit updates whenever the balance changes.
  ///
  /// If [activateIfNeeded] is false, will not trigger activation but will
  /// wait for the asset to be activated externally.
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  });

  /// Returns whether [assetId] currently has an active watcher subscription.
  bool hasActiveWatcher(AssetId assetId);

  /// Counts how many [assetIds] do not currently have active watcher coverage.
  int countMissingWatchersForAssets(Iterable<AssetId> assetIds);

  /// Returns true when any asset in [assetIds] lacks active watcher coverage.
  bool hasMissingWatchersForAssets(Iterable<AssetId> assetIds);

  /// Gets the last known balance for an asset without triggering a refresh.
  /// Returns null if no balance has been fetched yet.
  BalanceInfo? lastKnown(AssetId assetId);

  /// Disposes of all resources and stops all balance watching
  Future<void> dispose();

  /// Pre-caches the balance for an asset.
  /// This is an internal method used during activation to optimize initial balance fetches.
  Future<void> precacheBalance(Asset asset);
}

/// Implementation of the [IBalanceManager] interface for managing asset balances.
///
/// This class provides balance management operations with efficient caching
/// and update mechanisms using appropriate balance strategies based on asset type.
class BalanceManager implements IBalanceManager {
  /// Creates a new instance of [BalanceManager].
  ///
  /// Requires an [IAssetLookup] to find asset information and [KomodoDefiLocalAuth] for auth.
  /// The [activationCoordinator] and [pubkeyManager] can be initialized as null and set later
  /// to break circular dependencies.
  BalanceManager({
    required IAssetLookup assetLookup,
    required KomodoDefiLocalAuth auth,
    required PubkeyManager? pubkeyManager,
    required SharedActivationCoordinator? activationCoordinator,
    required EventStreamingManager eventStreamingManager,
    AssetHistoryStorage? assetHistoryStorage,
    ApiClient? client,
    GaslessCapabilityRegistry? gaslessCapabilities,
    GaslessCustodyBalanceReader? gaslessCustodyBalanceReader,
  }) : _activationCoordinator = activationCoordinator,
       _pubkeyManager = pubkeyManager,
       _assetLookup = assetLookup,
       _auth = auth,
       _eventStreamingManager = eventStreamingManager,
       _client = client,
       _gaslessCapabilities = gaslessCapabilities,
       _gaslessCustodyBalanceReader =
           gaslessCustodyBalanceReader ?? TronGridGaslessCustodyBalanceReader(),
       _assetHistoryStorage = assetHistoryStorage ?? AssetHistoryStorage() {
    // Listen for auth state changes
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
    _logger.fine('Initialized');
  }
  static final Logger _logger = Logger('BalanceManager');

  SharedActivationCoordinator? _activationCoordinator;
  PubkeyManager? _pubkeyManager;
  final IAssetLookup _assetLookup;
  final KomodoDefiLocalAuth _auth;
  final EventStreamingManager _eventStreamingManager;
  final AssetHistoryStorage _assetHistoryStorage;

  /// RPC client, used to fetch the GasFree custody balance for gasless TRC-20
  /// assets. Null in contexts (e.g. some tests) where gasless substitution is
  /// not needed; when null, all assets use their standard (EOA) balance.
  final ApiClient? _client;
  final GaslessCapabilityRegistry? _gaslessCapabilities;
  final GaslessCustodyBalanceReader _gaslessCustodyBalanceReader;
  StreamSubscription<KdfUser?>? _authSubscription;
  final Duration _defaultPollingInterval = const Duration(seconds: 30);

  /// Enable debug logging for balance polling fallback
  static bool enableDebugLogging = true;

  /// Cache of the latest known balances for each asset
  final Map<AssetId, BalanceInfo> _balanceCache = {};

  /// Assets whose public balance was built from a rail-aware GasFree snapshot.
  /// A transient refresh must never replace this total-owned value with EOA-only
  /// funds, which would understate portfolio ownership.
  final Set<AssetId> _gaslessSnapshotSourcedBalances = {};
  final Map<AssetId, GaslessBalanceSnapshot> _gaslessSnapshotCache = {};

  /// Track active balance watch streams by asset ID
  final Map<AssetId, StreamSubscription<dynamic>> _activeWatchers = {};
  final Map<AssetId, StreamSubscription<AssetPubkeys>> _pubkeyHintWatchers = {};
  final Set<AssetId> _pendingFastRefresh = <AssetId>{};

  /// Stream controllers for each asset being watched
  final Map<AssetId, StreamController<BalanceInfo>> _balanceControllers = {};

  /// Stale-guard timers to periodically refresh balances even while streaming
  final Map<AssetId, Timer> _staleBalanceTimers = {};

  /// Current wallet ID being tracked
  WalletId? _currentWalletId;

  /// Invalidates every in-flight fetch as soon as authentication changes.
  int _walletGeneration = 0;

  /// Flag indicating if the manager has been disposed
  bool _isDisposed = false;

  /// Getter for activationCoordinator to make it accessible
  SharedActivationCoordinator? get activationCoordinator =>
      _activationCoordinator;

  /// Getter for pubkeyManager to make it accessible
  PubkeyManager? get pubkeyManager => _pubkeyManager;

  @override
  bool hasActiveWatcher(AssetId assetId) {
    if (_isDisposed) return false;
    return _activeWatchers.containsKey(assetId);
  }

  @override
  int countMissingWatchersForAssets(Iterable<AssetId> assetIds) {
    if (_isDisposed) return assetIds.toSet().length;
    final uniqueIds = assetIds.toSet();
    return uniqueIds
        .where((assetId) => !_activeWatchers.containsKey(assetId))
        .length;
  }

  @override
  bool hasMissingWatchersForAssets(Iterable<AssetId> assetIds) {
    return countMissingWatchersForAssets(assetIds) > 0;
  }

  /// Setter for activationCoordinator to resolve circular dependencies
  void setActivationCoordinator(SharedActivationCoordinator coordinator) {
    _activationCoordinator = coordinator;
  }

  /// Setter for pubkeyManager to resolve circular dependencies
  void setPubkeyManager(PubkeyManager manager) {
    _pubkeyManager = manager;
  }

  bool _supportsBalanceStreaming(Asset asset) => asset.supportsBalanceStreaming;

  /// Handle authentication state changes
  Future<void> _handleAuthStateChanged(KdfUser? user) async {
    if (_isDisposed) return;
    final newWalletId = user?.walletId;
    // If the wallet ID has changed, reset all state
    _logger.fine(
      'Auth state changed. wallet: $_currentWalletId -> $newWalletId',
    );
    if (!_sameOptionalWallet(_currentWalletId, newWalletId)) {
      // Change identity before awaiting cleanup so an already-completing RPC
      // cannot commit into the next wallet's cache in the reset window.
      _walletGeneration++;
      _currentWalletId = newWalletId;
      await _resetState();
    }
  }

  bool _sameOptionalWallet(WalletId? left, WalletId? right) {
    if (left == null || right == null) return left == right;
    return isSameStableWallet(left, right);
  }

  Future<WalletOperationContext> _captureWalletContext() async {
    final user = await _auth.currentUser;
    if (user == null) throw AuthException.notSignedIn();

    if (_currentWalletId == null) {
      _currentWalletId = user.walletId;
    } else if (!isSameStableWallet(_currentWalletId!, user.walletId)) {
      // Auth streams are asynchronous. Proactively invalidate here too so a
      // caller cannot observe the prior wallet's cache before the event lands.
      _walletGeneration++;
      _currentWalletId = user.walletId;
      await _resetState();
    }

    return WalletOperationContext(
      walletId: user.walletId,
      generation: _walletGeneration,
    );
  }

  bool _isWalletContextCurrentSync(WalletOperationContext context) {
    final current = _currentWalletId;
    return !_isDisposed &&
        context.generation == _walletGeneration &&
        current != null &&
        isSameStableWallet(context.walletId, current);
  }

  Future<bool> _isWalletContextCurrent(WalletOperationContext context) async {
    if (!_isWalletContextCurrentSync(context)) return false;
    final currentUser = await _auth.currentUser;
    return currentUser != null &&
        _isWalletContextCurrentSync(context) &&
        isSameStableWallet(context.walletId, currentUser.walletId);
  }

  Future<void> _requireWalletContextCurrent(
    WalletOperationContext context,
  ) async {
    if (await _isWalletContextCurrent(context)) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed while fetching balance',
    );
  }

  /// Reset all internal state when wallet changes
  Future<void> _resetState() async {
    _logger.fine('Resetting state');
    final stopwatch = Stopwatch()..start();

    // Clear wallet-owned values before awaiting cancellation. This prevents a
    // newly signed-in caller from observing the previous wallet during cleanup.
    _balanceCache.clear();
    _gaslessSnapshotSourcedBalances.clear();
    _gaslessSnapshotCache.clear();
    _pendingFastRefresh.clear();

    final List<Future<void>> cleanupFutures = <Future<void>>[];
    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();

    for (final subscription in watcherSubs) {
      cleanupFutures.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling balance watcher', e, s);
        }),
      );
    }

    // Cancel all stale balance timers to prevent timer leak on wallet change
    for (final timer in _staleBalanceTimers.values) {
      timer.cancel();
    }
    _staleBalanceTimers.clear();

    final List<StreamController<BalanceInfo>> controllers = _balanceControllers
        .values
        .toList();
    _balanceControllers.clear();

    for (final controller in controllers) {
      if (!controller.isClosed) {
        // Add error to signal disconnection before closing
        controller.addError(
          const WalletChangedDisconnectException(
            'Wallet changed, reconnecting balance watchers',
          ),
        );

        cleanupFutures.add(
          controller.close().catchError((Object e, StackTrace s) {
            _logger.warning('Error closing balance controller', e, s);
          }),
        );
      }
    }

    if (cleanupFutures.isNotEmpty) {
      await Future.wait(cleanupFutures);
    }

    stopwatch.stop();
    _logger.fine(
      'State reset completed in ${stopwatch.elapsedMilliseconds}ms '
      '(${watcherSubs.length} subscriptions, ${controllers.length} controllers)',
    );
  }

  @override
  Future<BalanceInfo> getBalance(AssetId assetId) async {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }

    // Check if dependencies are properly initialized
    if (_pubkeyManager == null) {
      throw StateError('PubkeyManager is not initialized');
    }

    final walletContext = await _captureWalletContext();

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      throw ArgumentError('Asset not found for balance check: $assetId');
    }

    try {
      // GasFree portfolio balance is total wallet ownership across custody and
      // every retained Standard address. Rail-specific send limits must use the
      // snapshot/source selection instead of this aggregate.
      if (_client != null && _isTrc20(asset)) {
        try {
          final owned = await _maybeGaslessTotalOwnedBalance(asset);
          if (owned != null) {
            await _requireWalletContextCurrent(walletContext);
            _balanceCache[assetId] = owned;
            _gaslessSnapshotSourcedBalances.add(assetId);
            return owned;
          }
        } catch (_) {
          await _requireWalletContextCurrent(walletContext);
          // Never silently substitute an EOA balance for a confirmed GasFree
          // wallet snapshot. A cached owned-funds snapshot is preferable;
          // surface the availability error so callers can render it explicitly.
          final cached = _balanceCache[assetId];
          if (cached != null &&
              _gaslessSnapshotSourcedBalances.contains(assetId)) {
            return cached;
          }
          rethrow;
        }
      }

      final balance = await _pubkeyManager!
          .getPubkeys(asset)
          .then((pubkeys) => pubkeys.balance);
      await _requireWalletContextCurrent(walletContext);
      // A concurrent GasFree snapshot may have landed while awaiting the EOA
      // balance; don't clobber the total-owned cache with the EOA number.
      if (_isTrc20(asset) &&
          _gaslessSnapshotSourcedBalances.contains(assetId)) {
        final custodyCached = _balanceCache[assetId];
        if (custodyCached != null) return custodyCached;
      }
      // Update cache with the latest balance
      _balanceCache[assetId] = balance;
      return balance;
    } catch (e) {
      // Rethrow with more context
      throw StateError('Failed to get balance for ${assetId.name}: $e');
    }
  }

  @override
  Future<GaslessBalanceSnapshot> getGaslessBalanceSnapshot(
    AssetId assetId,
  ) async {
    final walletContext = await _captureWalletContext();
    final asset = _assetLookup.fromId(assetId);
    final client = _client;
    final pubkeyManager = _pubkeyManager;
    if (asset == null) {
      throw ArgumentError('Asset not found for balance check: $assetId');
    }
    final recoveryOnly = !_isGaslessReady(asset);
    if (!recoveryOnly && client == null) {
      throw StateError('GasFree client is not available for ${asset.id.id}');
    }
    final retained = _gaslessSnapshotCache[assetId];
    if (pubkeyManager == null) {
      throw StateError('PubkeyManager is not initialized');
    }

    try {
      final pubkeys = await pubkeyManager.getPubkeys(asset);
      await _requireWalletContextCurrent(walletContext);
      final retainedCustody = _canonicalGasfreePrimary(
        pubkeys.keys,
      )?.gasfreeAddress?.trim();
      if (recoveryOnly &&
          (retainedCustody == null || retainedCustody.isEmpty)) {
        if (retained != null) return retained.asStale();
        throw StateError(
          'No retained GasFree custody identity for ${asset.id.id}',
        );
      }
      final GaslessAccountStatusResponse? status;
      final String custodyAddress;
      final Decimal custodyTotal;
      if (recoveryOnly) {
        custodyAddress = retainedCustody!;
        custodyTotal = await _gaslessCustodyBalanceReader.readBalance(
          asset,
          custodyAddress,
        );
        status = null;
      } else {
        status = await client!.rpc.withdraw.gaslessAccountStatus(
          coin: asset.id.id,
        );
        custodyAddress = status.gasfreeAddress;
        custodyTotal = status.onChainBalance;
        final expectedCustody = retainedCustody ?? retained?.custodyAddress;
        if (expectedCustody != null &&
            expectedCustody.isNotEmpty &&
            custodyAddress != expectedCustody) {
          _gaslessCapabilities?.markSecurityMismatch(
            assetId,
            reasonCode: 'custody_address_mismatch',
          );
          if (retained != null) return retained.asStale();
          throw StateError('GasFree custody address does not match retention');
        }
      }
      await _requireWalletContextCurrent(walletContext);
      if (status != null && !status.providerAvailable) {
        switch (status.reasonCode) {
          case 'custody_address_mismatch' ||
              'provider_identity_mismatch' ||
              'provider_invalid_response':
            _gaslessCapabilities?.markSecurityMismatch(
              assetId,
              reasonCode: status.reasonCode ?? 'provider_security_mismatch',
            );
          case 'provider_authentication_failed':
            _gaslessCapabilities?.markDisabled(
              assetId,
              reasonCode: 'provider_authentication_failed',
            );
          case 'token_unsupported' || 'token_decimals_mismatch':
            _gaslessCapabilities?.markUnsupported(
              assetId,
              reasonCode: status.reasonCode ?? 'token_unsupported',
            );
          default:
            _gaslessCapabilities?.markStale(
              assetId,
              reasonCode:
                  status.reasonCode ?? 'provider_temporarily_unavailable',
            );
        }
      }
      final standardBalances = [
        for (final key in pubkeys.keys)
          GaslessStandardBalance(
            address: key.address,
            derivationPath: key.derivationPath,
            balance: key.balance,
          ),
      ];
      final standardTotal = standardBalances.fold(
        Decimal.zero,
        (total, item) => total + item.balance.total,
      );
      final snapshot = GaslessBalanceSnapshot(
        custodyAddress: custodyAddress,
        custodyTotal: custodyTotal,
        custodySpendable: status?.providerAvailable == true
            ? status?.spendableBalance
            : null,
        frozenAmount: status?.providerAvailable == true
            ? status?.frozenBalance
            : null,
        standardBalances: standardBalances,
        totalWalletOwned: custodyTotal + standardTotal,
        capturedAt: DateTime.now().toUtc(),
        provenance: status?.providerAvailable == true
            ? GaslessBalanceProvenance.authoritativeProvider
            : GaslessBalanceProvenance.onChainOnly,
        isFresh: status?.providerAvailable == true,
      );
      _gaslessSnapshotCache[assetId] = snapshot;
      return snapshot;
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (_) {
      if (retained != null) return retained.asStale();
      rethrow;
    }
  }

  @override
  GaslessBalanceSnapshot? lastKnownGaslessBalanceSnapshot(AssetId assetId) =>
      _gaslessSnapshotCache[assetId];

  /// Whether [asset] is a TRON TRC-20 token, whose gaslessly-spendable balance
  /// lives at the GasFree custody address rather than the EOA.
  bool _isTrc20(Asset asset) => asset.protocol is Trc20Protocol;

  bool _isGaslessReady(Asset asset) =>
      _gaslessCapabilities?.isReady(asset.id) ?? false;

  PubkeyInfo? _canonicalGasfreePrimary(List<PubkeyInfo> keys) {
    final hdPrimary = keys
        .where(
          (key) =>
              key.derivationPath ==
              GaslessCapabilityRegistry.canonicalPrimaryDerivationPath,
        )
        .toList(growable: false);
    if (hdPrimary.length == 1) return hdPrimary.single;
    if (keys.length == 1 &&
        (keys.single.derivationPath == null ||
            keys.single.derivationPath!.isEmpty)) {
      return keys.single;
    }
    return null;
  }

  /// Returns total wallet-owned GasFree and Standard funds for [asset].
  /// Null means the asset has never had a ready GasFree capability and should
  /// stay on the normal Standard rail.
  Future<BalanceInfo?> _maybeGaslessTotalOwnedBalance(Asset asset) async {
    if (_client == null && _isGaslessReady(asset)) {
      return null;
    }
    if (!_isGaslessReady(asset) &&
        !_gaslessSnapshotCache.containsKey(asset.id)) {
      final pubkeys =
          _pubkeyManager?.lastKnown(asset.id) ??
          await _pubkeyManager?.getPubkeys(asset);
      if (pubkeys == null ||
          (_canonicalGasfreePrimary(pubkeys.keys)?.gasfreeAddress ?? '')
              .isEmpty) {
        return null;
      }
    }
    try {
      final snapshot = await getGaslessBalanceSnapshot(asset.id);
      return snapshot.walletBalance;
    } catch (e) {
      _logger.fine(
        'GasFree wallet snapshot unavailable for ${asset.id.name}; '
        'preserving balance provenance: $e',
      );
      rethrow;
    }
  }

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) async* {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }

    final lastKnownBalance = lastKnown(assetId);
    if (lastKnownBalance != null) {
      yield lastKnownBalance;
    }

    final controller = _balanceControllers.putIfAbsent(
      assetId,
      () => StreamController<BalanceInfo>.broadcast(
        onListen: () {
          _logger.fine(
            'onListen: ${assetId.name}, activateIfNeeded: $activateIfNeeded',
          );
          _startWatchingBalance(assetId, activateIfNeeded);
        },
        onCancel: () {
          _logger.fine('onCancel: ${assetId.name}');
          _stopWatchingBalance(assetId);
        },
      ),
    );

    yield* controller.stream;
  }

  /// Ensures an asset is activated using the shared activation coordinator
  Future<bool> _ensureAssetActivated(Asset asset, bool activateIfNeeded) async {
    // Check if activationCoordinator is initialized
    if (_activationCoordinator == null) {
      _logger.fine(
        'SharedActivationCoordinator not initialized, cannot activate asset',
      );
      return false;
    }

    if (!activateIfNeeded) {
      return _activationCoordinator!.isAssetActive(asset.id);
    }

    final isActive = await _activationCoordinator!.isAssetActive(asset.id);
    if (isActive) {
      return true;
    }

    try {
      // Use the shared coordinator to activate the asset
      final result = await _activationCoordinator!.activateAsset(asset);
      return result.isSuccess;
    } catch (e) {
      _logger.fine('Failed to activate asset ${asset.id.name}: $e');
      return false;
    }
  }

  /// Start watching the balance for a specific asset
  Future<void> _startWatchingBalance(
    AssetId assetId,
    bool activateIfNeeded,
  ) async {
    final controller = _balanceControllers[assetId];
    if (controller == null || _isDisposed) return;

    // Check if dependencies are initialized
    if (_activationCoordinator == null || _pubkeyManager == null) {
      if (!controller.isClosed) {
        controller.addError(
          StateError('Dependencies not fully initialized yet'),
        );
      }
      return;
    }

    // Cancel any existing watcher for this asset
    await _activeWatchers[assetId]?.cancel();
    _activeWatchers.remove(assetId);

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      controller.addError(
        ArgumentError('Asset not found for balance watch: $assetId'),
      );
      return;
    }

    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } on AuthException {
      // Don't throw an error, just wait for authentication
      _logger.fine(
        'Delaying balance watcher start for ${assetId.name}: unauthenticated',
      );
      return;
    }
    final user = await _auth.currentUser;
    if (user == null ||
        !isSameStableWallet(user.walletId, walletContext.walletId)) {
      return;
    }
    _logger.fine('Starting balance watcher for ${assetId.name}');

    // Optimization: Check if this is a newly created wallet (not imported)
    final previouslyEnabledAssets = await _assetHistoryStorage.getWalletAssets(
      walletContext.walletId,
    );
    if (!await _isWalletContextCurrent(walletContext)) return;
    final isFirstTimeEnabling = !previouslyEnabledAssets.contains(assetId.id);

    // Check metadata to determine if this was an imported wallet
    // Only optimize for genuinely new wallets, not imported ones
    final isImported = user.metadata['isImported'] == true;
    final isNewWallet = previouslyEnabledAssets.isEmpty && !isImported;

    // Emit the last known balance immediately if available
    final maybeKnownBalance = lastKnown(assetId);
    if (maybeKnownBalance != null) {
      controller.add(maybeKnownBalance);
      _logger.fine('Emitted initial balance for ${assetId.name}');
    } else if (isFirstTimeEnabling && isNewWallet) {
      // For newly created wallets (not imported) on first-time asset enablement,
      // assume zero balance to reduce RPC spam
      final zeroBalance = BalanceInfo(
        total: Decimal.zero,
        spendable: Decimal.zero,
        unspendable: Decimal.zero,
      );
      _balanceCache[assetId] = zeroBalance;
      controller.add(zeroBalance);
      _logger.fine(
        'Emitted zero balance for first-time asset ${assetId.name} in new wallet',
      );
    }

    try {
      // Ensure asset is activated if needed
      final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
      if (!await _isWalletContextCurrent(walletContext)) return;

      // If activation was requested but failed, emit error
      if (activateIfNeeded && !isActive) {
        final activationError = ActivationFailedException(
          assetId: assetId,
          message: 'Asset activation failed',
          errorCode: 'BALANCE_ACTIVATION_ERROR',
        );

        if (!controller.isClosed) {
          controller.addError(activationError);
        }

        // Recovery mode: keep this watcher alive and retry in the background
        // so callers do not need to re-subscribe after startup races.
        _logger.warning(
          'Activation unavailable for ${assetId.name}; '
          'starting recovery watchers',
          activationError,
        );
        _startStaleBalanceGuard(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        await _startBalancePolling(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        return;
      }

      // Mark asset as seen after successful activation
      if (isActive && isFirstTimeEnabling) {
        await _assetHistoryStorage.addAssetToWallet(user.walletId, assetId.id);
        if (!await _isWalletContextCurrent(walletContext)) return;

        // Fetch real balance (will update from zero for new wallets)
        final balance = await getBalance(assetId);
        if (_isWalletContextCurrentSync(walletContext) &&
            !controller.isClosed) {
          controller.add(balance);
        }
      } else if (isActive) {
        // If active but not first time, still get balance
        final balance = await getBalance(assetId);
        if (_isWalletContextCurrentSync(walletContext) &&
            !controller.isClosed) {
          controller.add(balance);
        }
      }

      // Subscribe to balance event stream for real-time updates.
      //
      // TRC-20 assets are polled instead: their displayed balance is the GasFree
      // custody balance (fetched via `getBalance`), which the EOA balance event
      // stream and the pubkey-derived hint would not reflect. The pubkey hint is
      // skipped for them to avoid briefly flashing the EOA balance.
      final isGaslessAsset =
          _client != null &&
          (_isGaslessReady(asset) ||
              _gaslessSnapshotCache.containsKey(assetId));
      if (!_supportsBalanceStreaming(asset) || isGaslessAsset) {
        if (!isGaslessAsset) {
          _attachPubkeyHintListener(
            asset: asset,
            assetId: assetId,
            controller: controller,
            activateIfNeeded: activateIfNeeded,
            walletContext: walletContext,
          );
        }
        await _startBalancePolling(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        return;
      }

      _logger.fine('Subscribing to balance stream for ${assetId.id}');
      final balanceStreamSubscription = await _eventStreamingManager
          .subscribeToBalance(coin: assetId.id);
      if (!await _isWalletContextCurrent(walletContext)) {
        await balanceStreamSubscription.cancel();
        return;
      }

      var hasFallenBack = false;
      Future<void> fallbackToPolling({
        String reason = 'stream stopped',
        Object? error,
        StackTrace? stackTrace,
      }) async {
        if (hasFallenBack || _isDisposed) return;
        hasFallenBack = true;

        _logger.info(
          'Falling back to balance polling for ${assetId.name}: $reason',
        );

        try {
          await balanceStreamSubscription.cancel();
        } catch (cancelError, cancelStack) {
          _logger.fine(
            'Error cancelling balance stream for ${assetId.name}',
            cancelError,
            cancelStack,
          );
        }

        if (_activeWatchers[assetId] == balanceStreamSubscription) {
          await _startBalancePolling(
            asset: asset,
            assetId: assetId,
            controller: controller,
            activateIfNeeded: activateIfNeeded,
            walletContext: walletContext,
          );
        }

        if (error != null) {
          _logger.warning(
            'Balance stream fallback reason for ${assetId.name}: $error',
            error,
            stackTrace,
          );
        }
      }

      _activeWatchers[assetId] = balanceStreamSubscription
        ..onData((balanceEvent) {
          if (!_isWalletContextCurrentSync(walletContext)) return;

          // Verify the event is for the correct coin
          if (balanceEvent.coin != assetId.id) return;

          // Update cache with the new balance
          _balanceCache[assetId] = balanceEvent.balance;

          // Emit the balance update to listeners
          if (!controller.isClosed) {
            controller.add(balanceEvent.balance);
            _logger.fine(
              'Balance update received for ${assetId.name}: ${balanceEvent.balance.total}',
            );
          }

          // Trigger background refresh to sync per-address balances
          // This ensures address balances match the updated total
          // and notifies any watchPubkeys stream listeners
          if (_pubkeyManager != null) {
            _pubkeyManager!
                .precachePubkeys(asset)
                .then((_) {
                  _logger.fine(
                    'Pubkeys refreshed after balance update for '
                    '${assetId.name}',
                  );
                })
                .catchError((Object e, StackTrace s) {
                  _logger.fine(
                    'Failed to refresh pubkeys for ${assetId.name}',
                    e,
                    s,
                  );
                })
                .ignore();
          }
        })
        ..onError((Object error, StackTrace stackTrace) {
          unawaited(
            fallbackToPolling(
              reason: 'stream error',
              error: error,
              stackTrace: stackTrace,
            ),
          );
        })
        ..onDone(() {
          unawaited(fallbackToPolling(reason: 'stream closed'));
        });

      // Start stale-guard to periodically confirm balance in case of missed events
      _startStaleBalanceGuard(
        asset: asset,
        assetId: assetId,
        controller: controller,
        activateIfNeeded: activateIfNeeded,
        walletContext: walletContext,
      );
    } catch (e, s) {
      _logger.warning(
        'Failed to start balance watcher for ${assetId.name}',
        e,
        s,
      );
      await _startBalancePolling(
        asset: asset,
        assetId: assetId,
        controller: controller,
        activateIfNeeded: activateIfNeeded,
        walletContext: walletContext,
      );
    }
  }

  Future<void> _startBalancePolling({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
    required WalletOperationContext walletContext,
  }) async {
    if (controller.isClosed || !_isWalletContextCurrentSync(walletContext)) {
      return;
    }

    _logger.fine('Starting balance polling fallback for ${assetId.name}');

    Future<BalanceInfo?> fetchLatestBalance() async {
      if (!_isWalletContextCurrentSync(walletContext)) return null;

      if (_activationCoordinator == null || _pubkeyManager == null) {
        return null;
      }

      if (!await _isWalletContextCurrent(walletContext)) {
        return null;
      }

      if (enableDebugLogging) {
        _logger.info(
          '[POLLING] Fetching balance for ${assetId.name} '
          '(every ${_defaultPollingInterval.inSeconds}s)',
        );
      }

      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);

        if (isActive) {
          final balance = await getBalance(assetId);
          if (!await _isWalletContextCurrent(walletContext)) return null;
          if (enableDebugLogging) {
            _logger.info(
              '[POLLING] Balance fetched for ${assetId.name}: '
              '${balance.total}',
            );
          }
          return balance;
        }
      } on Object catch (error, stackTrace) {
        if (enableDebugLogging) {
          _logger.warning(
            '[POLLING] Balance fetch failed for ${assetId.name}',
            error,
            stackTrace,
          );
        }
      }

      return lastKnown(assetId);
    }

    // Kick off an immediate refresh so polling fallback can recover quickly
    // after startup races without waiting for the first periodic tick.
    unawaited(() async {
      final balance = await fetchLatestBalance();
      if (balance != null &&
          !controller.isClosed &&
          _isWalletContextCurrentSync(walletContext)) {
        controller.add(balance);
      }
    }());

    final periodicStream = Stream<void>.periodic(_defaultPollingInterval);
    final subscription = periodicStream
        .asyncMap<BalanceInfo?>((_) => fetchLatestBalance())
        .listen(
          (balance) {
            if (balance != null &&
                !controller.isClosed &&
                _isWalletContextCurrentSync(walletContext)) {
              controller.add(balance);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
            _logger.warning(
              'Balance polling error for ${assetId.name}',
              error,
              stackTrace,
            );
          },
          onDone: () {
            _stopWatchingBalance(assetId);
            _logger.fine('Balance polling closed for ${assetId.name}');
          },
          cancelOnError: false,
        );

    _activeWatchers[assetId] = subscription;
  }

  /// Stop watching the balance for a specific asset
  void _stopWatchingBalance(AssetId assetId) {
    final watcher = _activeWatchers[assetId];
    if (watcher != null) {
      watcher.cancel();
      _activeWatchers.remove(assetId);
      _logger.fine('Stopped watcher for ${assetId.name}');
    }
    _stopPubkeyHintListener(assetId);
    _stopStaleBalanceGuard(assetId);
    // Don't close the controller here, just remove the watcher
    // The controller will be closed when all listeners are gone
  }

  void _startStaleBalanceGuard({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
    required WalletOperationContext walletContext,
  }) {
    // Cancel any existing timer first
    _staleBalanceTimers[assetId]?.cancel();

    _staleBalanceTimers[assetId] = Timer.periodic(_defaultPollingInterval, (
      _,
    ) async {
      if (controller.isClosed || !_isWalletContextCurrentSync(walletContext)) {
        return;
      }
      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
        if (!isActive) return;

        final latest = await getBalance(assetId);
        if (!await _isWalletContextCurrent(walletContext)) return;
        final previous = _balanceCache[assetId];
        final changed =
            previous == null ||
            previous.total != latest.total ||
            previous.spendable != latest.spendable ||
            previous.unspendable != latest.unspendable;
        if (changed) {
          _balanceCache[assetId] = latest;
          if (!controller.isClosed) {
            controller.add(latest);
          }
        }
      } catch (_) {
        // best-effort; swallow transient errors
      }
    });

    // Kick off an immediate one-shot refresh
    unawaited(() async {
      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
        if (!isActive) return;
        final latest = await getBalance(assetId);
        if (!await _isWalletContextCurrent(walletContext)) return;
        final previous = _balanceCache[assetId];
        final changed =
            previous == null ||
            previous.total != latest.total ||
            previous.spendable != latest.spendable ||
            previous.unspendable != latest.unspendable;
        if (changed && !controller.isClosed) {
          _balanceCache[assetId] = latest;
          controller.add(latest);
        }
      } catch (_) {}
    }());
  }

  void _stopStaleBalanceGuard(AssetId assetId) {
    _staleBalanceTimers[assetId]?.cancel();
    _staleBalanceTimers.remove(assetId);
  }

  void _attachPubkeyHintListener({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
    required WalletOperationContext walletContext,
  }) {
    final pubkeyManager = _pubkeyManager;
    if (pubkeyManager == null || _isDisposed) return;

    _pubkeyHintWatchers[assetId]?.cancel();
    _pubkeyHintWatchers[assetId] = pubkeyManager
        .watchPubkeys(asset, activateIfNeeded: activateIfNeeded)
        .listen(
          (AssetPubkeys pubkeys) {
            unawaited(
              _handlePubkeyBalanceHint(
                asset: asset,
                assetId: assetId,
                controller: controller,
                pubkeys: pubkeys,
                walletContext: walletContext,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.fine(
              'Pubkey hint watcher error for ${assetId.name}',
              error,
              stackTrace,
            );
          },
        );
  }

  void _stopPubkeyHintListener(AssetId assetId) {
    _pubkeyHintWatchers.remove(assetId)?.cancel();
  }

  Future<void> _handlePubkeyBalanceHint({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required AssetPubkeys pubkeys,
    required WalletOperationContext walletContext,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext) ||
        _supportsBalanceStreaming(asset)) {
      return;
    }

    final latest = pubkeys.balance;
    final previous = _balanceCache[assetId];
    final changed =
        previous == null ||
        previous.total != latest.total ||
        previous.spendable != latest.spendable ||
        previous.unspendable != latest.unspendable;
    if (!changed) return;

    _balanceCache[assetId] = latest;
    if (!controller.isClosed) {
      controller.add(latest);
    }

    _pendingFastRefresh.add(assetId);
    unawaited(
      _performImmediateBalanceRefresh(
        asset: asset,
        assetId: assetId,
        controller: controller,
        walletContext: walletContext,
      ),
    );
  }

  Future<void> _performImmediateBalanceRefresh({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required WalletOperationContext walletContext,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;
    if (!_pendingFastRefresh.contains(assetId)) return;

    try {
      final refreshed = await getBalance(assetId);
      if (!await _isWalletContextCurrent(walletContext)) return;
      _balanceCache[assetId] = refreshed;
      if (!controller.isClosed) {
        controller.add(refreshed);
      }
    } catch (error, stackTrace) {
      _logger.fine(
        'Immediate balance refresh failed for ${assetId.name}',
        error,
        stackTrace,
      );
    } finally {
      _pendingFastRefresh.remove(assetId);
    }
  }

  @override
  BalanceInfo? lastKnown(AssetId assetId) {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }
    return _balanceCache[assetId];
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _walletGeneration++;

    // Take snapshots to avoid concurrent modification while cancelling/closing
    final StreamSubscription<KdfUser?>? authSub = _authSubscription;
    _authSubscription = null;

    final List<StreamSubscription<dynamic>> watcherSubs =
        List<StreamSubscription<dynamic>>.from(_activeWatchers.values);
    _activeWatchers.clear();

    // Cancel auth subscription and all watchers concurrently; swallow errors
    final List<Future<void>> cancelFutures = <Future<void>>[];
    if (authSub != null) {
      cancelFutures.add(
        authSub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling auth subscription', e, s);
        }),
      );
    }
    for (final StreamSubscription<dynamic> sub in watcherSubs) {
      cancelFutures.add(
        sub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling balance watcher', e, s);
        }),
      );
    }
    if (cancelFutures.isNotEmpty) {
      await Future.wait(cancelFutures);
    }

    // Snapshot controllers and close all concurrently; swallow errors
    final List<StreamSubscription<AssetPubkeys>> pubkeyHintSubs =
        List<StreamSubscription<AssetPubkeys>>.from(_pubkeyHintWatchers.values);
    _pubkeyHintWatchers.clear();
    for (final StreamSubscription<AssetPubkeys> sub in pubkeyHintSubs) {
      cancelFutures.add(
        sub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey hint watcher', e, s);
        }),
      );
    }

    final List<StreamController<BalanceInfo>> controllers =
        List<StreamController<BalanceInfo>>.from(_balanceControllers.values);
    _balanceControllers.clear();

    final List<Future<void>> closeFutures = <Future<void>>[];
    for (final StreamController<BalanceInfo> controller in controllers) {
      if (!controller.isClosed) {
        closeFutures.add(
          controller.close().catchError((Object e, StackTrace s) {
            _logger.warning('Error closing balance controller', e, s);
          }),
        );
      }
    }
    if (closeFutures.isNotEmpty) {
      await Future.wait(closeFutures);
    }

    // Clear all other resources
    _balanceCache.clear();
    _gaslessSnapshotSourcedBalances.clear();
    _gaslessSnapshotCache.clear();
    _currentWalletId = null;
    _gaslessCustodyBalanceReader.dispose();
    _logger.fine('Disposed');

    // Cancel any remaining stale-guard timers
    for (final timer in _staleBalanceTimers.values) {
      timer.cancel();
    }
    _staleBalanceTimers.clear();
  }

  @override
  Future<void> precacheBalance(Asset asset) async {
    if (_isDisposed) return;

    // Check if pubkeyManager is initialized
    if (_pubkeyManager == null) {
      _logger.fine('Cannot pre-cache balance: PubkeyManager not initialized');
      return;
    }

    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } on AuthException {
      return;
    }

    // Retry logic to handle timing issues after activation
    const maxRetries = 3;
    const baseDelay = Duration(milliseconds: 200);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        BalanceInfo? owned;
        if (_client != null && _isTrc20(asset)) {
          owned = await _maybeGaslessTotalOwnedBalance(asset);
          if (!await _isWalletContextCurrent(walletContext)) return;
          if (owned != null) {
            _gaslessSnapshotSourcedBalances.add(asset.id);
          } else {
            // Keep a snapshot-sourced total instead of overwriting it with the
            // EOA-only balance; re-emit it so watchers settle (see getBalance).
            //
            // With no snapshot yet (first activation), fall through to the EOA
            // precache: custody errors are swallowed above, so the
            // coin-not-found retry below never fires for them and the first
            // number may briefly be the EOA balance — the watcher's own
            // getBalance / first poll corrects it within one interval.
            final cached = _balanceCache[asset.id];
            if (cached != null &&
                _gaslessSnapshotSourcedBalances.contains(asset.id)) {
              final controller = _balanceControllers[asset.id];
              if (controller != null && !controller.isClosed) {
                controller.add(cached);
              }
              return;
            }
          }
        }
        final balance =
            owned ??
            await _pubkeyManager!
                .getPubkeys(asset)
                .then<BalanceInfo>((pubkeys) => pubkeys.balance);
        if (!await _isWalletContextCurrent(walletContext)) return;
        _balanceCache[asset.id] = balance;

        // If there's an active stream controller for this asset, emit the balance
        final controller = _balanceControllers[asset.id];
        if (controller != null && !controller.isClosed) {
          controller.add(balance);
        }
        return; // Success, exit retry loop
      } catch (e) {
        final isLastAttempt = attempt == maxRetries - 1;
        final errorStr = e.toString().toLowerCase();
        final isCoinNotFound =
            errorStr.contains('no such coin') ||
            errorStr.contains('coin not found') ||
            errorStr.contains('not activated') ||
            errorStr.contains('invalid coin');

        if (isCoinNotFound && !isLastAttempt) {
          _logger.fine(
            'Balance pre-cache retry ${attempt + 1}: ${asset.id.name} not yet available',
          );
          await Future<void>.delayed(baseDelay * (attempt + 1));
          if (!await _isWalletContextCurrent(walletContext)) return;
          continue;
        }

        // Either not a timing issue or final attempt - fail silently
        _logger.fine('Failed to pre-cache balance for ${asset.id.name}: $e');
        return;
      }
    }
  }
}
