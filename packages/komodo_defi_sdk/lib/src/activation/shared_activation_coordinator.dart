import 'dart:async';
import 'dart:developer' show log;

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Shared coordinator for asset activations across all managers.
/// Prevents race conditions by ensuring only one activation per asset at a time
/// and sharing the result with all requesting managers.
///
/// **CRITICAL TIMING ISSUE HANDLING:**
/// This coordinator addresses a race condition where activation RPC can complete
/// successfully, but the coin may not immediately appear in the enabled coins list.
/// This can cause subsequent operations (balance fetching, address generation) to
/// fail with "No such coin" errors. The coordinator waits for coin availability
/// verification before declaring activation successful.
class SharedActivationCoordinator {
  SharedActivationCoordinator(this._activationManager, this._auth) {
    _authSubscription = _auth.watchSessionContext().listen(
      _handleSessionChanged,
    );
  }

  final ActivationManager _activationManager;
  final KomodoDefiLocalAuth _auth;
  StreamSubscription<AuthSessionContext?>? _authSubscription;

  /// Track pending activations to prevent duplicates.
  ///
  /// Holds an *outcome*, never a failed future. See [_ActivationOutcome].
  final Map<AssetId, Completer<_ActivationOutcome>> _pendingActivations = {};

  AuthSessionContext? _session;
  bool _isDisposed = false;

  void _handleSessionChanged(AuthSessionContext? session) {
    if (_isDisposed) return;
    if (session == null ||
        (_session != null && !_auth.isSessionContextCurrent(_session!))) {
      _resetState();
    }
    _session = session;
  }

  /// Reset all internal state when wallet changes
  void _resetState() {
    log(
      'Resetting SharedActivationCoordinator state due to wallet change',
      name: 'SharedActivationCoordinator',
    );

    // Cancel all pending activations
    for (final completer in _pendingActivations.values) {
      if (!completer.isCompleted) {
        completer.complete(
          _ActivationOutcome.error(
            StateError('Wallet changed, activation cancelled'),
            StackTrace.current,
          ),
        );
      }
    }
    _pendingActivations.clear();
  }

  /// Upper bound on one activation attempt, for assets whose activation is
  /// expected to complete promptly.
  ///
  /// The protocol strategies poll KDF in `while (!isComplete)` loops with no
  /// exit other than a terminal status, and they emit a progress event on every
  /// iteration - so a stalled activation looks like a *healthy* one to any
  /// inter-event timeout. Without a total deadline the completer below stays
  /// pending forever, and because [activateAsset] hands that same completer to
  /// every later caller, a retry re-joins the wedged attempt instead of
  /// starting a new one. A caller-side `.timeout()` cannot fix that: Dart
  /// timeouts do not cancel, so the entry in [_pendingActivations] survives.
  ///
  /// Deliberately shorter than the app's own per-attempt bound
  /// (`CoinsRepo.activateAssetsSync`), so this fires first, clears the pending
  /// entry, and lets the app's retry perform a genuinely fresh attempt. That
  /// ordering is an invariant: raising either bound requires raising the app's
  /// to stay above [evmActivationTimeout].
  ///
  /// This is a backstop against a *wedged* activation, not a UX deadline, so it
  /// has to sit above the slowest activation that legitimately completes.
  ///
  /// The 8.2s BTC-segwit / 6.1s KMD figures this used to cite were measured
  /// against the concurrent HD gap scan, which is **not** in the pinned KDF -
  /// it is `407cf6c0a` / `ba4b3996e`, kdf-internal PR #18, still unmerged. The
  /// pin (`feat/lifi-integration`, `4872ef2`) walks the gap one address at a
  /// time, where the
  /// same runs measured BTC-segwit 121.2s and KMD 46.9s
  /// The wallet repository documents repeatable measurement in
  /// `docs/WALLET_LOAD_MEASUREMENT.md`; remeasure before lowering these bounds.
  ///
  /// Three minutes still holds for **software** wallets, because those numbers
  /// were taken at `gap_limit: 20` and `HdGapLimit.resolve` sends
  /// `software` = 3 (`newlyGeneratedFirstSignIn` = 1) for them, so the walk is
  /// ~4 probes rather than 21 at a measured ~2.1s per gap unit.
  ///
  /// **Trezor is the exception and has the least headroom.** `HdGapLimit.resolve`
  /// returns `hardware` = 20 for `PrivateKeyPolicy.trezor()`, so a hardware
  /// wallet still walks the full gap - 121.2s of this 180s bound on BTC-segwit,
  /// ~1.5x, not 6x. It is a backstop rather than a budget, so that is survivable,
  /// but it is the number to re-measure before anyone shrinks this bound, and it
  /// is why the bound must not shrink at all while the pin lacks PR #18.
  static const Duration defaultActivationTimeout = Duration(minutes: 3);

  /// The EVM family is far slower than everything else: `enable_eth_with_tokens`
  /// is a single *synchronous* RPC that does HD address discovery inline, and it
  /// was measured at 196.9-346.4s for ETH + 2 ERC-20 tokens on a fresh HD
  /// wallet. A 60s bound - which this used to apply to every protocol - fired
  /// mid-activation on every such login, published `failed`, and let the retry
  /// issue a duplicate concurrent enable.
  static const Duration evmActivationTimeout = Duration(minutes: 8);

  /// ZHTLC activation legitimately runs for minutes (parameter download and
  /// block scanning), so it is exempt - a deadline there would turn correct
  /// slow progress into a failure.
  Duration? _timeoutFor(Asset asset) {
    if (asset.id.subClass == CoinSubClass.zhtlc) return null;
    // Matches on the protocol class rather than the sub-class so that every
    // member of the EVM family is covered, including ones added later: the
    // whole avx20/bep20/polygon/arbitrum/base/... arm maps to `Erc20Protocol`.
    // TRX and TRC-20 route through `enable_eth_with_tokens` too.
    final protocol = asset.protocol;
    if (protocol is Erc20Protocol ||
        protocol is TrxProtocol ||
        protocol is Trc20Protocol) {
      return evmActivationTimeout;
    }
    return defaultActivationTimeout;
  }

  /// Activate an asset with coordination across all managers.
  /// Returns a Future that completes when activation is finished.
  /// Multiple concurrent calls for the same asset will share the same result.
  ///
  /// [timeout] overrides [defaultActivationTimeout] for this call.
  Future<ActivationResult> activateAsset(
    Asset asset, {
    Duration? timeout,
  }) async {
    if (_isDisposed) {
      throw StateError('SharedActivationCoordinator has been disposed');
    }

    final session = await _auth.captureSessionContext();
    _auth.ensureSessionContextCurrent(session);
    _handleSessionChanged(session);

    // Check if activation is already in progress
    final existingActivation = _pendingActivations[asset.id];
    if (existingActivation != null) {
      log('Joining existing activation', name: 'SharedActivationCoordinator');
      return _allowedResult((await existingActivation.future).unwrap());
    }

    final shouldRefreshTronGaslessActivation = _activationManager
        .shouldRefreshTronGaslessActivation(asset);

    // Check if asset is already active
    final isActive = await _activationManager.isAssetActive(asset.id);
    if (_isDisposed || !_auth.isSessionContextCurrent(session)) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during asset activation',
      );
    }
    if (isActive && !shouldRefreshTronGaslessActivation) {
      _activationManager.ensureActiveAssetAllowed(asset.id);
      return ActivationResult.alreadyActive(asset.id);
    }

    _activationManager.ensureActivationAllowed(asset.id);
    // Never completed with an error - see [_ActivationOutcome]. That also
    // removes the need for a side listener on an attempt nobody is waiting on:
    // the caller only gets this future if it reaches the `return` below, and
    // [_resetState] and [dispose] both terminate pending attempts on a wallet
    // switch or sign-out during login activations, i.e. exactly when several
    // are in flight. A future that carries a value has no unhandled error to
    // report.
    final completer = Completer<_ActivationOutcome>();
    _pendingActivations[asset.id] = completer;

    // Clear any previous failed status for this asset

    // Broadcast that this asset is now pending
    final deadline = timeout ?? _timeoutFor(asset);
    // Drive the activation in its own future so `completer.future` is returned
    // to the caller synchronously. Awaiting the progress stream inline meant a
    // stream that never emits and never closes suspended this method *before*
    // the return - so the deadline timer below could complete the completer and
    // the initiating caller would still wait forever. Joiners were unaffected,
    // which is what made it easy to miss.
    unawaited(_driveActivation(asset, completer, deadline, session));
    return _allowedResult((await completer.future).unwrap());
  }

  /// Rechecks a shared success against the policy as each caller receives it.
  ///
  /// A finished attempt stays registered until the manager has cleaned up, so
  /// a caller can join it after a restriction was published.
  ActivationResult _allowedResult(ActivationResult result) {
    if (result.isFailure) return result;
    try {
      _activationManager.ensureActiveAssetAllowed(result.assetId);
      return result;
    } on ActivationPolicyException catch (error) {
      return ActivationResult.failure(
        result.assetId,
        error.toString(),
        cause: error,
      );
    }
  }

  /// Runs one activation attempt to a terminal state and completes [completer].
  ///
  /// Split out of [activateAsset] purely so that method can return the future
  /// without awaiting this one - see the comment at its call site.
  Future<void> _driveActivation(
    Asset asset,
    Completer<_ActivationOutcome> completer,
    Duration? deadline,
    AuthSessionContext session,
  ) async {
    Timer? deadlineTimer;
    try {
      if (deadline != null) {
        deadlineTimer = Timer(deadline, () {
          if (completer.isCompleted) return;
          log(
            'Activation exceeded ${deadline.inSeconds}s '
            'without a terminal status; abandoning this attempt',
            name: 'SharedActivationCoordinator',
          );
          final reason = 'Activation timed out after ${deadline.inSeconds}s';
          // Release BOTH in-flight registrations. Clearing only the one below
          // is not enough: the wedged generator is still suspended inside the
          // hung status poll, so its own cleanup never runs and
          // `ActivationManager._activationCompleters` keeps the dead completer.
          // The next attempt would then be told "already in progress" and park
          // on it - a fresh coordinator attempt that issues no new RPC, which
          // is indistinguishable from the stall this deadline exists to break.
          unawaited(_activationManager.abandonActivation(asset.id, reason));
          completer.complete(
            _ActivationOutcome.result(
              ActivationResult.failure(asset.id, reason),
            ),
          );
          // Release the slot here rather than waiting for `finally`: if the
          // progress stream is wedged mid-RPC the `await for` below never
          // resumes, so `finally` never runs and the failed completer would
          // stay registered - making every later attempt return this stale
          // failure instead of retrying.
          _removePendingActivation(asset.id, completer);
        });
      }

      _auth.ensureSessionContextCurrent(session);
      // Subscribe to activation stream and wait for completion.
      //
      // The `completer.isCompleted` check also breaks the loop when the
      // deadline above fired: cancelling the `await for` tears down the
      // strategy's poll loop instead of leaving it running unobserved.
      await for (final progress in _activationManager.activateAsset(asset)) {
        if (completer.isCompleted) break;
        _auth.ensureSessionContextCurrent(session);
        if (progress.isComplete) {
          if (progress.isSuccess) {
            // Wait for coin to actually become available before declaring success
            try {
              await _waitForCoinAvailability(asset.id);
              _auth.ensureSessionContextCurrent(session);
              final result = ActivationResult.success(asset.id);
              if (!completer.isCompleted) {
                completer.complete(_ActivationOutcome.result(result));
              }
            } catch (e) {
              if (completer.isCompleted) break;
              _activationManager.recordActivationFailure(
                asset.id,
                'Activation completed but the coin did not become available',
              );
              final result = ActivationResult.failure(
                asset.id,
                'Activation completed but coin did not become available: $e',
              );
              if (!completer.isCompleted) {
                completer.complete(_ActivationOutcome.result(result));
              }
            }
          } else {
            final result = ActivationResult.failure(
              asset.id,
              progress.errorMessage ?? 'Unknown activation error',
            );
            if (!completer.isCompleted) {
              completer.complete(_ActivationOutcome.result(result));
            }
          }
          break;
        }
      }
    } catch (e) {
      if (!completer.isCompleted) {
        log('Activation failed', name: 'SharedActivationCoordinator');
        completer.complete(
          _ActivationOutcome.result(
            ActivationResult.failure(asset.id, e.toString(), cause: e),
          ),
        );
      }
    } finally {
      // The `await for` above only completes the completer when it sees a
      // terminal `progress.isComplete`. A progress stream that ends without one
      // - an activation strategy returning early, a controller closed by a
      // session reset, an empty stream - falls straight through to here with
      // the completer still pending, and `completer.future` below then never
      // resolves.
      //
      // That future is awaited by every caller of this coordinator:
      // `BalanceManager._ensureAssetActivated` (so the balance watcher never
      // starts) and the wallet's login fan-out via `ensureAssetActivated` (so
      // `Future.wait` over the whole batch never returns, the coin holds
      // `activating` forever, and the app's post-login bookkeeping never runs).
      // Anyone who joined through `_pendingActivations` hangs with it.
      //
      // Fail closed instead: a failure is recoverable - the caller retries, and
      // the app's reconcile pass corrects the row if KDF did activate it after
      // all - whereas a pending future is not.
      if (!completer.isCompleted) {
        log(
          'Activation stream ended without a terminal '
          'progress event; failing the activation rather than hanging',
          name: 'SharedActivationCoordinator',
        );
        _activationManager.recordActivationFailure(
          asset.id,
          'Activation stream ended without a terminal progress event',
        );
        completer.complete(
          _ActivationOutcome.result(
            ActivationResult.failure(
              asset.id,
              'Activation stream ended without a terminal progress event',
            ),
          ),
        );
      }
      deadlineTimer?.cancel();
      _removePendingActivation(asset.id, completer);
    }
  }

  /// Deregisters [completer] only if it is still the registered attempt.
  ///
  /// The deadline timer and the `finally` block can both reach here, and by
  /// then a *new* attempt may already have registered its own completer. An
  /// unconditional remove would deregister that live attempt, so every joiner
  /// after it would start a duplicate activation.
  void _removePendingActivation(
    AssetId assetId,
    Completer<_ActivationOutcome> completer,
  ) {
    if (identical(_pendingActivations[assetId], completer)) {
      _pendingActivations.remove(assetId);
    }
  }

  /// Check if an asset is active (delegated to ActivationManager)
  Future<bool> isAssetActive(AssetId assetId) {
    return _activationManager.isAssetActive(assetId);
  }

  /// See [ActivationManager.ensureActiveAssetAllowed].
  void ensureActiveAssetAllowed(AssetId assetId) =>
      _activationManager.ensureActiveAssetAllowed(assetId);

  /// Whether [assetId] was activated during this session rather than found
  /// already enabled. See [ActivationManager.wasFreshlyActivated].
  bool wasFreshlyActivated(AssetId assetId) =>
      _activationManager.wasFreshlyActivated(assetId);

  /// Current activation state of every asset the SDK has observed.
  Map<AssetId, AssetActivationState> get activationStates =>
      _activationManager.activationStates;

  /// Current activation states, then every subsequent change.
  ///
  /// See [ActivationManager.watchActivationStates].
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      _activationManager.watchActivationStates();

  /// Current state for [assetId], then every subsequent change to it.
  Stream<AssetActivationState?> watchActivationStateOf(AssetId assetId) =>
      _activationManager.watchActivationStateOf(assetId);

  /// Wait for a coin to become available after activation completes.
  /// This addresses the timing issue where activation RPC completes successfully
  /// but the coin needs a few milliseconds to appear in the enabled coins list.
  Future<void> _waitForCoinAvailability(AssetId assetId) async {
    const maxRetries = 15; // Up to ~3 seconds with exponential backoff
    const baseDelay = Duration(milliseconds: 50);
    const maxDelay = Duration(milliseconds: 500);

    log(
      'Waiting for coin availability after activation',
      name: 'SharedActivationCoordinator',
    );

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Force refresh to bypass cache and get fresh data from backend
        final isAvailable = await _activationManager.isAssetActive(
          assetId,
          forceRefresh: true,
        );
        if (isAvailable) {
          log(
            'Coin available after ${attempt + 1} attempts',
            name: 'SharedActivationCoordinator',
          );
          return;
        }
      } catch (e) {
        log(
          'Coin availability check failed (attempt ${attempt + 1})',
          name: 'SharedActivationCoordinator',
        );
      }

      if (attempt < maxRetries - 1) {
        // Exponential backoff with max cap
        final delayMs = (baseDelay.inMilliseconds * (1 << attempt)).clamp(
          baseDelay.inMilliseconds,
          maxDelay.inMilliseconds,
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw StateError(
      'Coin ${assetId.id} did not become available after activation '
      '(waited $maxRetries attempts)',
    );
  }

  /// Dispose of the coordinator and clean up resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    log(
      'Disposing SharedActivationCoordinator',
      name: 'SharedActivationCoordinator',
    );

    // Cancel auth subscription
    await _authSubscription?.cancel();
    _authSubscription = null;

    // Cancel all pending activations
    for (final completer in _pendingActivations.values) {
      if (!completer.isCompleted) {
        completer.complete(
          _ActivationOutcome.error(
            StateError('SharedActivationCoordinator disposed'),
            StackTrace.current,
          ),
        );
      }
    }
    _pendingActivations.clear();

    // Close all active streams
    // Close state tracking streams

    // Clear state tracking sets
  }
}

/// Result of an asset activation operation
class ActivationResult {
  const ActivationResult._(
    this.assetId,
    this.isSuccess,
    this.errorMessage, {
    this.wasAlreadyActive = false,
    this.cause,
  });

  /// Activation ran and succeeded.
  factory ActivationResult.success(AssetId assetId) {
    return ActivationResult._(assetId, true, null);
  }

  /// The asset was already enabled in KDF, so nothing was activated.
  ///
  /// Distinguished from [ActivationResult.success] because callers need to
  /// know whether KDF just did the work an activation implies. In particular a
  /// UTXO activation carries `scan_policy: scan_if_new_wallet` with
  /// `gap_limit: 20`, so a *fresh* activation has already walked the address
  /// gap - and a caller that then asks for `task::scan_for_new_addresses`
  /// makes KDF walk it a second time for nothing.
  factory ActivationResult.alreadyActive(AssetId assetId) {
    return ActivationResult._(assetId, true, null, wasAlreadyActive: true);
  }

  /// Activation failed, retaining its typed cause when available.
  factory ActivationResult.failure(
    AssetId assetId,
    String errorMessage, {
    Object? cause,
  }) {
    return ActivationResult._(assetId, false, errorMessage, cause: cause);
  }

  /// The requested asset.
  final AssetId assetId;

  /// Whether the asset is available after this operation.
  final bool isSuccess;

  /// A readable failure explanation, or null for a successful operation.
  final String? errorMessage;

  /// The original failure, preserved for callers that handle typed outcomes.
  final Object? cause;

  /// Throws the typed cause when available, preserving policy/session failures.
  void throwIfFailed() {
    if (isSuccess) return;
    final error = cause;
    if (error is Exception) throw error;
    if (error is Error) throw error;
    throw AssetActivationException(assetId, errorMessage);
  }

  /// Whether the asset was already enabled, i.e. this call activated nothing.
  final bool wasAlreadyActive;

  /// Whether this operation failed to make the asset available.
  bool get isFailure => !isSuccess;

  @override
  String toString() {
    return isSuccess
        ? 'ActivationResult.success(${assetId.id})'
        : 'ActivationResult.failure(${assetId.id}, $errorMessage)';
  }
}

/// A terminal activation failure without a more specific typed cause.
final class AssetActivationException implements Exception {
  /// Describes a failure that did not provide a more specific exception.
  const AssetActivationException(this.assetId, this.message);

  /// The asset whose activation failed.
  final AssetId assetId;

  /// A readable explanation when one was supplied by the activation service.
  final String? message;
  @override
  String toString() => message ?? 'Asset activation failed';
}

/// The settled result of one shared activation attempt, carried as a *value*
/// so it can cross an error zone. See
/// [SharedActivationCoordinator._pendingActivations].
///
/// A single completer is shared by every caller waiting on the same asset, and
/// those callers do not all sit in the same error zone:
/// `PubkeyManager._activateForContext` reaches
/// [SharedActivationCoordinator.activateAsset] from inside `retry()`, which
/// runs each attempt in its own `runZonedGuarded`, and work dispatched
/// un-awaited from an attempt keeps running in that zone afterwards.
///
/// Dart refuses to deliver a future's *error* across an error-zone boundary:
/// rather than completing the cross-zone listener, `_propagateToListeners`
/// reports the error as uncaught in the zone that created the future and
/// abandons that listener's future forever - so a joiner from another zone used
/// to hang until the coordinator's own deadline fired, and the pubkey path has
/// no deadline at all. Carrying the outcome as a value and rethrowing it in
/// each caller's own zone is the same remedy `PubkeyManager` applies to its
/// shared pubkey fetch.
class _ActivationOutcome {
  const _ActivationOutcome._(this._result, this._error, this._stackTrace);

  /// The attempt reached a terminal state, successful or not.
  factory _ActivationOutcome.result(ActivationResult result) =>
      _ActivationOutcome._(result, null, null);

  /// The attempt was terminated without a result, e.g. by a wallet change.
  factory _ActivationOutcome.error(Object error, StackTrace stackTrace) =>
      _ActivationOutcome._(null, error, stackTrace);

  final ActivationResult? _result;
  final Object? _error;
  final StackTrace? _stackTrace;

  /// Returns the result, or rethrows the original error in the caller's zone.
  ActivationResult unwrap() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stackTrace!);
    return _result!;
  }
}
