import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';

/// Manager responsible for handling asset activation lifecycle
class ActivationManager {
  /// Per-asset activation timing, at INFO.
  ///
  /// This class had no logging of any kind, which meant the single most
  /// expensive step of a login - how long each asset took to activate, and
  /// which one never finished - was invisible in a release build. Everything
  /// downstream (balances, tx history, the wallet total) waits on it.
  static final Logger _logger = Logger('ActivationManager');

  /// Manager responsible for handling asset activation lifecycle
  ActivationManager(
    this._client,
    this._auth,
    this._assetHistory,
    this._assetLookup,
    this._balanceManager,
    this._configService,
    this._assetsUpdateManager,
    this._activatedAssetsCache, {
    TronGaslessProviderConfig? tronGaslessProvider,
    GaslessCapabilityRegistry? gaslessCapabilities,
  }) : _tronGaslessProvider = tronGaslessProvider,
       _gaslessCapabilities =
           gaslessCapabilities ?? GaslessCapabilityRegistry();

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final AssetHistoryStorage _assetHistory;
  final IAssetLookup _assetLookup;
  final IBalanceManager _balanceManager;
  final ActivationConfigService _configService;
  final KomodoAssetsUpdateManager _assetsUpdateManager;
  final ActivatedAssetsCache _activatedAssetsCache;

  /// Optional Tron GasFree provider config, attached to TRX platform
  /// activations to enable gas-free TRC20 transfers. Held in memory only.
  final TronGaslessProviderConfig? _tronGaslessProvider;
  final GaslessCapabilityRegistry _gaslessCapabilities;
  final _activationMutex = Mutex();
  static const _operationTimeout = Duration(seconds: 30);
  static const SdkErrorMapper _errorMapper = SdkErrorMapper();

  final Map<AssetId, Completer<void>> _activationCompleters = {};

  /// Assets this session actually activated, as opposed to found already
  /// enabled.
  ///
  /// Needed because the two things a caller wants to know are answered in
  /// different places: `SharedActivationCoordinator.activateAsset` reports
  /// "already active" for every call after the first, so the *second* caller in
  /// a login - `PubkeyManager._fetchFreshPubkeys`, which runs after
  /// `BalanceManager._ensureAssetActivated` - can no longer tell whether an
  /// activation happened at all this session. It needs to, because a fresh
  /// activation already made KDF walk the HD address gap.
  final Set<AssetId> _freshlyActivated = <AssetId>{};

  /// Whether [assetId] was activated during this session rather than found
  /// already enabled.
  bool wasFreshlyActivated(AssetId assetId) =>
      _freshlyActivated.contains(assetId);
  final Map<AssetId, _ActivationCancellation> _cancelledActivations = {};
  int _activationSessionGeneration = 0;
  bool _isDisposed = false;

  /// Authoritative per-asset activation state. Absent means "not activated".
  ///
  /// This manager is the only place where every activation path converges:
  /// [SharedActivationCoordinator.activateAsset] and
  /// `AssetManager.activateAsset`/`activateAssets` (used by the app's
  /// ZHTLC/ARRR flow) both end up in [activateAssets]. Holding the state
  /// anywhere else leaves a blind spot.
  final Map<AssetId, AssetActivationState> _activationStates = {};

  final StreamController<Map<AssetId, AssetActivationState>>
  _activationStatesController =
      StreamController<Map<AssetId, AssetActivationState>>.broadcast();

  /// Current activation state for every asset the SDK has observed.
  ///
  /// Assets absent from this map are neither activating, active nor failed.
  Map<AssetId, AssetActivationState> get activationStates => _snapshot();

  /// Last observed activation state for [assetId], or null if none.
  AssetActivationState? activationStateOf(AssetId assetId) =>
      _activationStates[assetId];

  /// Current activation states, then every subsequent change.
  ///
  /// The first event is always a snapshot of the current state, so a
  /// subscriber that attaches mid-activation - or long after one finished -
  /// still learns the truth. Closes only when this manager is disposed.
  ///
  /// A whole-map snapshot rather than per-asset deltas, deliberately: a
  /// dropped snapshot self-heals on the next emission, whereas a dropped
  /// delta is lost for good, which is the defect this stream exists to fix.
  /// It also lets a wallet change be stated as `{}` and lets a group
  /// activation report its platform and tokens atomically.
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    late final StreamController<Map<AssetId, AssetActivationState>> out;
    StreamSubscription<Map<AssetId, AssetActivationState>>? subscription;

    out = StreamController<Map<AssetId, AssetActivationState>>(
      onListen: () {
        // Subscribe first, replay second. A change emitted while this is
        // handing over then queues behind the replay instead of falling into
        // the gap - which is exactly what a `yield current; yield* stream`
        // prologue over an unbuffered broadcast controller would do.
        subscription = _activationStatesController.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        out.add(_snapshot());
      },
      onCancel: () => subscription?.cancel(),
    );

    return out.stream;
  }

  /// Current state for [assetId], then every subsequent change to it.
  ///
  /// Derived from [watchActivationStates] rather than a second source, so the
  /// two can never disagree. Emits null while the asset is not tracked.
  Stream<AssetActivationState?> watchActivationStateOf(AssetId assetId) =>
      watchActivationStates().map((states) => states[assetId]).distinct();

  /// Copy, never a view: consumers must not observe the live map mutating
  /// under them, or `distinct()` and any downstream diffing silently break.
  Map<AssetId, AssetActivationState> _snapshot() =>
      Map<AssetId, AssetActivationState>.unmodifiable(_activationStates);

  void _emitActivationStates() {
    if (_isDisposed || _activationStatesController.isClosed) return;
    _activationStatesController.add(_snapshot());
  }

  /// Writes [states], emitting at most once and only if something changed.
  ///
  /// No-op suppression is load-bearing:
  /// [SharedActivationCoordinator._waitForCoinAvailability] polls the
  /// activated set up to 15 times per asset, and each read folds back into
  /// here. Without this every consumer would receive 15 identical snapshots
  /// per asset per activation.
  void _setActivationStates(Iterable<AssetActivationState> states) {
    var changed = false;
    for (final state in states) {
      if (_activationStates[state.assetId] == state) continue;
      _activationStates[state.assetId] = state;
      changed = true;
    }
    if (changed) _emitActivationStates();
  }

  /// Records a terminal failure observed outside the activation stream.
  ///
  /// The coordinator's post-activation availability check is stricter than
  /// `progress.isSuccess`, so it can contradict a success this manager has
  /// already recorded.
  void recordActivationFailure(AssetId assetId, String errorMessage) {
    _setActivationStates([
      AssetActivationState.failed(assetId, errorMessage: errorMessage),
    ]);
  }

  /// Releases the in-flight registration for [assetId] so the next attempt is
  /// genuinely new.
  ///
  /// There are **two** in-flight registries on the activation path, and a
  /// deadline that clears only one of them does not deliver a fresh retry:
  /// `SharedActivationCoordinator._pendingActivations` dedupes coordinator
  /// callers, and [_activationCompleters] dedupes activation attempts here.
  /// When the coordinator abandons a wedged attempt it releases its own slot,
  /// but the wedged generator is still suspended inside the hung status poll,
  /// so its `_cleanupActivation` never runs and this map keeps the dead
  /// completer. The retry then reaches [_registerActivation], is told
  /// `shouldStartActivation: false`, and parks on a future that will never
  /// complete - no new `task::enable_*::init`, no progress, exactly the stall
  /// the deadline was added to break.
  ///
  /// Failing the completer rather than dropping it silently is deliberate:
  /// anyone who already joined the dead attempt is waiting on this future, and
  /// a failure is recoverable where a pending future is not.
  ///
  /// The wedged generator can still complete its own completer later; every
  /// site guards on `isCompleted`, and [_cleanupActivation] only removes an
  /// entry it still owns, so the fresh attempt registered after this cannot be
  /// deregistered by the abandoned one.
  Future<void> abandonActivation(AssetId assetId, String reason) async {
    if (_isDisposed) return;
    await _protectedOperation(() async {
      final completer = _activationCompleters.remove(assetId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          ActivationFailedException(
            assetId: assetId,
            message: reason,
            errorCode: 'ACTIVATION_ABANDONED',
          ),
        );
      }
      _cancelledActivations.remove(assetId);
    });
    recordActivationFailure(assetId, reason);
  }

  /// Folds KDF's authoritative enabled set into the state map.
  ///
  /// This is what makes activations performed by other SDK subsystems - and
  /// divergence on the KDF side - visible without any consumer polling.
  void _foldAuthoritativeActiveSet(Set<AssetId> enabled) {
    // An empty [enabled] is folded like any other: the caller guarantees it
    // is KDF's authoritative "nothing enabled" - a successful read for a
    // signed-in user - and not the signed-out cache short-circuit (see
    // [_readActivatedAssetIds]). A failed or wedged read throws before here.
    var changed = false;

    for (final assetId in enabled) {
      final current = _activationStates[assetId];
      // Never clobber an in-flight activation: an asset that is still
      // activating legitimately does not appear in `get_enabled_coins` yet,
      // and this branch only ever sees ids that do.
      if (current != null && current.isActive) continue;
      _activationStates[assetId] = AssetActivationState.active(assetId);
      changed = true;
    }

    // Anything we believed active but KDF no longer reports is gone.
    // `activating` and `failed` are left alone - the first is not expected in
    // the enabled set yet, and the second must stay visible until retried.
    final staleActive = _activationStates.entries
        .where((e) => e.value.isActive && !enabled.contains(e.key))
        .map((e) => e.key)
        .toList();
    for (final assetId in staleActive) {
      _activationStates.remove(assetId);
      changed = true;
    }

    if (changed) _emitActivationStates();
  }

  /// Reads the activated set and folds it into [activationStates].
  ///
  /// All authoritative reads in this class go through here so the fold cannot
  /// be forgotten at a call site.
  Future<Set<AssetId>> _readActivatedAssetIds({
    bool forceRefresh = false,
  }) async {
    final generation = _activationSessionGeneration;
    final ids = await _activatedAssetsCache.getActivatedAssetIds(
      forceRefresh: forceRefresh,
    );
    // Drop a result that started before a wallet change, so it cannot
    // re-seed the previous wallet's assets after the reset cleared them.
    if (generation != _activationSessionGeneration) return ids;
    if (ids.isEmpty) {
      // An empty set from the cache is ambiguous: it is also what a
      // signed-out session reads (`ActivatedAssetsCache` answers `const []`
      // without an RPC). Only a signed-in user's empty set is KDF's
      // authoritative "nothing enabled" - the last coin disabled elsewhere,
      // or an authenticated KDF restart that re-enabled nothing - and that
      // one must sweep whatever this map still believes is active. Sign-out
      // itself is handled by [resetActivationSessionState].
      final user = await _auth.currentUser;
      if (user == null || generation != _activationSessionGeneration) {
        return ids;
      }
    }
    _foldAuthoritativeActiveSet(ids);
    return ids;
  }

  /// Helper for mutex-protected operations with timeout
  Future<T> _protectedOperation<T>(Future<T> Function() operation) {
    return _activationMutex
        .protect(operation)
        .timeout(
          _operationTimeout,
          onTimeout: () =>
              throw TimeoutException('Operation timed out', _operationTimeout),
        );
  }

  /// Activate a single asset
  Stream<ActivationProgress> activateAsset(Asset asset) {
    final parentId = asset.id.parentId;
    if (asset.protocol is Trc20Protocol &&
        _tronGaslessProvider != null &&
        _gaslessCapabilities.isConfigured(asset) &&
        parentId != null) {
      final parentAsset = _assetLookup.fromId(parentId);
      if (parentAsset != null) {
        return activateAssets([parentAsset, asset]);
      }
    }

    return activateAssets([asset]);
  }

  /// Whether an active TRC20 token may refresh its provider-backed status.
  ///
  /// Disabled activations and hard security mismatches require a controlled
  /// reactivation/session reset instead of another in-place status attempt.
  bool shouldRefreshTronGaslessActivation(Asset asset) =>
      _tronGaslessProvider != null &&
      _gaslessCapabilities.isConfigured(asset) &&
      !_gaslessCapabilities.isReady(asset.id) &&
      _gaslessCapabilities.canRefreshAccountStatus(asset);

  /// Clear per-session activation hints when the active wallet changes.
  void resetActivationSessionState() {
    _activationSessionGeneration++;
    _freshlyActivated.clear();
    final staleCompleters = _activationCompleters.values.toList();
    _activationCompleters.clear();
    _cancelledActivations.clear();
    _gaslessCapabilities.resetSession();

    // Nothing is activated for the incoming wallet. Emitting the empty map
    // rather than closing the stream keeps long-lived subscribers - which
    // outlive a wallet switch - and states the reset in a form a late
    // subscriber also replays.
    if (_activationStates.isNotEmpty) {
      _activationStates.clear();
      _emitActivationStates();
    }

    for (final completer in staleCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(
          const WalletChangedDisconnectException(
            'Wallet changed during asset activation',
          ),
        );
      }
    }
  }

  Future<_GaslessActivationContext> _captureGaslessContext() async {
    final generation = _gaslessCapabilities.sessionGeneration;
    final user = await _auth.currentUser;
    if (user == null ||
        !_gaslessCapabilities.ensureWalletSession(user.walletId.pubkeyHash) ||
        generation != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
    return _GaslessActivationContext(
      walletId: user.walletId,
      sessionGeneration: generation,
    );
  }

  Future<void> _requireGaslessContextCurrent(
    _GaslessActivationContext context,
  ) async {
    if (context.sessionGeneration != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
    final user = await _auth.currentUser;
    if (user == null ||
        !_gaslessCapabilities.ensureWalletSession(user.walletId.pubkeyHash) ||
        context.sessionGeneration != _gaslessCapabilities.sessionGeneration ||
        !isSameStableWallet(context.walletId, user.walletId)) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
  }

  /// Request cancellation of an in-flight activation for [assetId].
  ///
  /// Cancellation is best-effort. The current activation stream is terminated
  /// at the next progress boundary and emits an error completion state.
  void cancelActivation(
    AssetId assetId, {
    String reason = 'Activation cancelled by caller',
  }) {
    if (_isDisposed) return;
    // Only record cancellation for activations that are currently in-flight.
    // This avoids stale cancellation markers cancelling future fresh attempts.
    final completer = _activationCompleters[assetId];
    if (completer == null) {
      _cancelledActivations.remove(assetId);
      return;
    }
    _cancelledActivations[assetId] = _ActivationCancellation(
      completer: completer,
      sessionGeneration: _activationSessionGeneration,
      reason: reason,
    );
  }

  /// Request cancellation for all in-flight activations.
  void cancelAllActivations({
    String reason = 'Activation cancelled by caller',
  }) {
    if (_isDisposed) return;
    final pendingActivations = _activationCompleters.entries.toList();
    for (final entry in pendingActivations) {
      _cancelledActivations[entry.key] = _ActivationCancellation(
        completer: entry.value,
        sessionGeneration: _activationSessionGeneration,
        reason: reason,
      );
    }
  }

  /// Activate multiple assets
  Stream<ActivationProgress> activateAssets(List<Asset> assets) async* {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    final groups = _AssetGroup._groupByPrimary(assets, _assetLookup);

    for (final group in groups) {
      final activationSessionGeneration = _activationSessionGeneration;
      final pendingCancellation = _currentCancellation(group.primary.id);
      if (pendingCancellation != null) {
        yield ActivationProgress.error(
          message: pendingCancellation.reason,
          errorCode: 'ACTIVATION_CANCELLED',
        );
        continue;
      }

      final gaslessRefreshCandidate = _shouldRefreshTronGaslessActivation(
        group,
      );
      final candidateGaslessContext = gaslessRefreshCandidate
          ? await _captureGaslessContext()
          : null;
      final shouldRefreshTronGaslessActivation =
          candidateGaslessContext != null;
      final gaslessContext = candidateGaslessContext;

      // Check activation status atomically
      final activationStatus = await _checkActivationStatus(group);
      if (activationStatus.isComplete) {
        if (!shouldRefreshTronGaslessActivation) {
          // Already active. Publish it: this branch is otherwise invisible to
          // observers, and it is the common case on a warm re-login.
          _setActivationStates(_groupStates(group, _activeState));
          yield activationStatus;
          continue;
        }
        // An already-active token cannot be reconfigured in place. Probe its
        // activation-scoped GasFree status; `GaslessNotConfigured` is retained
        // as `reactivation_required` while Standard TRON remains available.
      }

      // Register activation attempt.
      final registration = await _registerActivation(
        group.primary.id,
        activationSessionGeneration,
      );
      final primaryCompleter = registration.completer;
      if (registration.shouldStartActivation) {
        // Before any RPC, so an observer sees the row turn over immediately.
        _setActivationStates(_groupStates(group, _activatingState));
      }
      if (!registration.shouldStartActivation) {
        debugPrint(
          'Activation already in progress for ${group.primary.id.name}',
        );
        try {
          await primaryCompleter.future;
        } catch (e, st) {
          final mappedError = _mapError(e, group.primary.id);
          yield ActivationProgress.error(
            message: mappedError.fallbackMessage,
            sdkError: mappedError,
            stackTrace: st,
          );
          continue;
        }

        // In-flight activations are keyed on the primary asset id alone, so the
        // activation we just joined may have enabled the platform WITHOUT our
        // child tokens — e.g. a concurrent standalone TRX activation racing a
        // `[TRX, USDT-TRC20]` group. Verify the children are actually enabled
        // before reporting success: reporting a child as active without ever
        // registering it in KDF is invisible here and only surfaces later as a
        // `NoSuchCoin` error at withdraw/preview time.
        final joinedStatus = await _checkActivationStatus(
          group,
          forceRefresh: true,
        );
        if (joinedStatus.isComplete) {
          final verified = shouldRefreshTronGaslessActivation
              ? await _verifyGaslessCapability(
                  group,
                  joinedStatus,
                  gaslessContext!,
                )
              : joinedStatus;
          yield verified;
          continue;
        }

        // Platform active but our children are missing: fall through to the
        // activation block below. With the platform already active, the
        // strategy activates only the still-missing children individually
        // (enable_erc20, retaining the gasless config) instead of re-running
        // the platform batch (which KDF would reject as already activated).
      }

      yield ActivationProgress(
        status: 'Starting activation for ${group.primary.id.name}...',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.groupStart,
          stepCount: 1,
          additionalInfo: {
            'primaryAsset': group.primary.id.name,
            'childCount': group.children.length,
          },
        ),
      );

      // Both ends are logged, not just the end. A wedged activation never
      // reaches the `finally` below - the strategy stays suspended inside its
      // status poll - so the start line is the only evidence that the asset was
      // ever attempted. An asset with a start and no finish is the signature of
      // the stall that cost users minutes.
      final activationStopwatch = Stopwatch()..start();
      _logger.info(
        'Activating ${group.primary.id.id}'
        '${group.children.isEmpty ? '' : ' with ${group.children.length} '
                  'token(s)'}',
      );

      try {
        // Get the current user's auth options to retrieve privKeyPolicy
        final currentUser = await _auth.currentUser;
        final privKeyPolicy =
            currentUser?.walletId.authOptions.privKeyPolicy ??
            const PrivateKeyPolicy.contextPrivKey();

        final gaslessProvider = _gaslessProviderFor(group);

        // Hardware keeps the full BIP-44 gap; a wallet this session generated
        // has no on-chain history to find, so its first sign-in walks the
        // minimum. Resolved here because this is the one place that already
        // holds the current user.
        final hdGapLimit = currentUser == null
            ? null
            : HdGapLimit.resolve(
                privKeyPolicy: privKeyPolicy,
                isNewlyGeneratedFirstSignIn: currentUser.isGeneratedThisSession,
              );

        // Create activator with the user's privKeyPolicy
        final activator = ActivationStrategyFactory.createStrategy(
          _client,
          privKeyPolicy,
          _configService,
          _activatedAssetsCache,
          tronGaslessProvider: gaslessProvider,
          hdGapLimit: hdGapLimit,
        );

        var completionHandled = false;
        final activationStream =
            activationStatus.isComplete &&
                shouldRefreshTronGaslessActivation &&
                gaslessProvider != null
            // The standard asset is already active. Feed that successful
            // status through the capability verifier, whose GasFree-only
            // failures are deliberately non-terminal for Standard TRON.
            ? Stream<ActivationProgress>.value(activationStatus)
            : activator.activate(group.primary, group.children.toList());
        await for (final rawProgress in activationStream) {
          final cancellation = _cancellationFor(group.primary.id, registration);
          if (cancellation != null) {
            final cancellationError = ActivationCancelledException(
              assetId: group.primary.id,
              message: cancellation.reason,
            );
            if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(cancellationError);
            }
            yield ActivationProgress.error(
              message: cancellation.reason,
              errorCode: 'ACTIVATION_CANCELLED',
            );
            break;
          }

          var progress = _attachSdkError(rawProgress, group.primary.id);
          if (progress.isComplete &&
              progress.isSuccess &&
              shouldRefreshTronGaslessActivation) {
            progress = await _verifyGaslessCapability(
              group,
              progress,
              gaslessContext!,
            );
          }

          if (progress.isComplete) {
            if (completionHandled) {
              debugPrint(
                'Ignoring duplicate completion event for '
                '${group.primary.id.name}',
              );
            } else {
              completionHandled = true;
              // Finalize before exposing the terminal event. The shared
              // coordinator stops listening at that event, which cancels this
              // async* generator at the yield suspension point. Completing the
              // join future and all successful activation side effects here
              // keeps joined callers live and makes terminal success truthful.
              await _handleActivationComplete(
                group,
                progress,
                primaryCompleter,
                gaslessContext: gaslessContext,
              );
            }
          }

          yield progress;
        }

        // The strategy can finish WITHOUT emitting a terminal completion event
        // when the platform and all requested children are already active (the
        // individual-children path skips already-active children and yields
        // nothing). Without a terminal event the coordinator's Future
        // (shared_activation_coordinator) would await forever. Emit a
        // synthetic completion (or failure) so it always resolves.
        if (!completionHandled &&
            _cancellationFor(group.primary.id, registration) == null) {
          final status = await _checkActivationStatus(
            group,
            forceRefresh: true,
          );
          completionHandled = true;
          if (status.isComplete) {
            final verified = shouldRefreshTronGaslessActivation
                ? await _verifyGaslessCapability(group, status, gaslessContext!)
                : status;
            await _handleActivationComplete(
              group,
              verified,
              primaryCompleter,
              gaslessContext: gaslessContext,
            );
            yield verified;
          } else {
            final mappedError = _mapError(
              StateError(
                'Activation produced no result for ${group.primary.id.name}',
              ),
              group.primary.id,
            );
            if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(mappedError);
            }
            yield ActivationProgress.error(
              message: mappedError.fallbackMessage,
              sdkError: mappedError,
            );
          }
        }
      } catch (e, st) {
        final recoveredProgress = shouldRefreshTronGaslessActivation
            ? null
            : await _tryRecoverAlreadyActivated(group, e);
        if (recoveredProgress != null) {
          if (!primaryCompleter.isCompleted) {
            primaryCompleter.complete();
          }
          _setActivationStates(_groupStates(group, _activeState));
          yield recoveredProgress;
          continue;
        }

        debugPrint('Activation failed: $e');
        final mappedError = _mapError(e, group.primary.id);
        if (!primaryCompleter.isCompleted) {
          primaryCompleter.completeError(mappedError);
        }
        _setActivationStates(
          _groupStates(
            group,
            (id) => AssetActivationState.failed(
              id,
              errorMessage: mappedError.fallbackMessage,
              sdkError: mappedError,
            ),
          ),
        );
        yield ActivationProgress.error(
          message: mappedError.fallbackMessage,
          sdkError: mappedError,
          stackTrace: st,
        );
      } finally {
        activationStopwatch.stop();
        // The outcome is read back from the state map rather than tracked in a
        // local, so this reports what consumers will actually observe -
        // including the `_failGroupIfStillActivating` correction below and any
        // GasFree downgrade applied on the way through.
        _logger.info(
          'Activated ${group.primary.id.id} in '
          '${activationStopwatch.elapsedMilliseconds}ms '
          '(${_activationStates[group.primary.id]?.status.name ?? 'unknown'})',
        );

        // Fail closed. Also runs when a subscriber cancels this `async*`
        // generator mid-activation - the `AssetManager.activateAsset` path
        // can do that - which is the only other way an asset could sit on
        // `activating` for the rest of the session.
        _failGroupIfStillActivating(
          group,
          'Activation ended without a terminal result',
        );
        try {
          await _cleanupActivation(group.primary.id, registration);
        } catch (e) {
          debugPrint('Failed to cleanup activation: $e');
        }
      }
    }
  }

  /// Builds one state per asset in [group] (platform plus its tokens).
  ///
  /// A group activation enables the platform coin and its children together,
  /// so their states must move together too.
  Iterable<AssetActivationState> _groupStates(
    _AssetGroup group,
    AssetActivationState Function(AssetId) build,
  ) => [group.primary, ...group.children].map((asset) => build(asset.id));

  static AssetActivationState _activatingState(AssetId id) =>
      AssetActivationState.activating(id);

  static AssetActivationState _activeState(AssetId id) =>
      AssetActivationState.active(id);

  void _failGroupIfStillActivating(_AssetGroup group, String errorMessage) {
    final stuck = [group.primary, ...group.children]
        .map((asset) => asset.id)
        .where((id) => _activationStates[id]?.isActivating ?? false)
        .map(
          (id) => AssetActivationState.failed(id, errorMessage: errorMessage),
        );
    if (stuck.isNotEmpty) _setActivationStates(stuck);
  }

  ActivationProgress _attachSdkError(
    ActivationProgress progress,
    AssetId assetId,
  ) {
    if (!progress.isError || progress.sdkError != null) {
      return progress;
    }

    final errorMessage = progress.errorMessage ?? 'Activation failed';
    final sdkError = _mapError(errorMessage, assetId);

    return progress.copyWith(
      errorMessage: sdkError.fallbackMessage,
      sdkError: sdkError,
    );
  }

  SdkError _mapError(Object error, AssetId assetId) {
    return _errorMapper.map(
      error,
      context: SdkErrorContext(operation: 'activation', assetId: assetId.id),
    );
  }

  /// Check if asset and its children are already activated.
  Future<ActivationProgress> _checkActivationStatus(
    _AssetGroup group, {
    bool forceRefresh = false,
  }) async {
    try {
      // Use cache instead of direct RPC call to avoid excessive requests
      final enabledAssetIds = await _readActivatedAssetIds(
        forceRefresh: forceRefresh,
      );

      final isActive = enabledAssetIds.contains(group.primary.id);
      final childrenActive = group.children.every(
        (child) => enabledAssetIds.contains(child.id),
      );

      if (isActive && childrenActive) {
        return ActivationProgress.alreadyActiveSuccess(
          assetName: group.primary.id.name,
          childCount: group.children.length,
        );
      }
    } catch (e) {
      debugPrint('Failed to check activation status: $e');
    }

    return const ActivationProgress(
      status: 'Needs activation',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.init,
        stepCount: 1,
      ),
    );
  }

  _ActivationCancellation? _currentCancellation(AssetId assetId) {
    final cancellation = _cancelledActivations[assetId];
    if (cancellation == null ||
        cancellation.sessionGeneration != _activationSessionGeneration ||
        !identical(_activationCompleters[assetId], cancellation.completer)) {
      return null;
    }
    return cancellation;
  }

  _ActivationCancellation? _cancellationFor(
    AssetId assetId,
    _ActivationRegistration registration,
  ) {
    final cancellation = _cancelledActivations[assetId];
    if (cancellation == null ||
        cancellation.sessionGeneration != registration.sessionGeneration ||
        !identical(cancellation.completer, registration.completer)) {
      return null;
    }
    return cancellation;
  }

  /// Register a new activation attempt or join an existing one.
  Future<_ActivationRegistration> _registerActivation(
    AssetId assetId,
    int expectedSessionGeneration,
  ) async {
    return _protectedOperation(() async {
      if (expectedSessionGeneration != _activationSessionGeneration) {
        throw const WalletChangedDisconnectException(
          'Wallet changed during asset activation',
        );
      }

      final existingCompleter = _activationCompleters[assetId];
      if (existingCompleter != null) {
        return _ActivationRegistration(
          completer: existingCompleter,
          sessionGeneration: expectedSessionGeneration,
          shouldStartActivation: false,
        );
      }

      final completer = Completer<void>();
      // A sole activation attempt has no joiner awaiting this future. Attach a
      // side listener so completing it with an error does not become an
      // unhandled zone error; concurrent joiners still receive the same error.
      unawaited(completer.future.catchError((Object _) {}));
      _activationCompleters[assetId] = completer;
      return _ActivationRegistration(
        completer: completer,
        sessionGeneration: expectedSessionGeneration,
        shouldStartActivation: true,
      );
    });
  }

  Future<ActivationProgress?> _tryRecoverAlreadyActivated(
    _AssetGroup group,
    Object error,
  ) async {
    if (!_isAlreadyActivatedError(error)) {
      return null;
    }

    _activatedAssetsCache.invalidate();
    final refreshedStatus = await _checkActivationStatus(
      group,
      forceRefresh: true,
    );
    return refreshedStatus.isComplete ? refreshedStatus : null;
  }

  bool _isAlreadyActivatedError(Object error) {
    final message = error.toString();
    return message.contains('PlatformIsAlreadyActivated') ||
        message.contains('CoinIsAlreadyActivated') ||
        message.contains('activated already');
  }

  /// Handle completion of activation
  Future<void> _handleActivationComplete(
    _AssetGroup group,
    ActivationProgress progress,
    Completer<void> completer, {
    _GaslessActivationContext? gaslessContext,
  }) async {
    if (progress.isSuccess) {
      // Published first, before any await. The work below is guarded by
      // `user != null` and can throw part-way through
      // `_requireGaslessContextCurrent`; a state write buried in there would
      // be skipped for an activation that genuinely succeeded. A throw there
      // means the wallet changed, and the reset clears the map anyway.
      _setActivationStates(_groupStates(group, _activeState));

      // Recorded here rather than inferred from an `ActivationResult`, because
      // by the time the pubkey layer asks, the coordinator reports "already
      // active" - see [_freshlyActivated].
      _freshlyActivated
        ..add(group.primary.id)
        ..addAll(group.children.map((child) => child.id));

      if (gaslessContext != null) {
        await _requireGaslessContextCurrent(gaslessContext);
      }
      final user = await _auth.currentUser;
      if (gaslessContext != null) {
        await _requireGaslessContextCurrent(gaslessContext);
      }
      if (user != null) {
        // Store custom tokens using CoinConfigManager
        if (group.primary.protocol.isCustomToken) {
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
          await _assetsUpdateManager.assets.storeCustomToken(group.primary);
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
        } else {
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
          await _assetHistory.addAssetToWallet(
            user.walletId,
            group.primary.id.id,
          );
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
        }

        final allAssets = [group.primary, ...group.children];

        for (final asset in allAssets) {
          if (asset.protocol.isCustomToken) {
            if (gaslessContext != null) {
              await _requireGaslessContextCurrent(gaslessContext);
            }
            await _assetsUpdateManager.assets.storeCustomToken(asset);
            if (gaslessContext != null) {
              await _requireGaslessContextCurrent(gaslessContext);
            }
          }

          // Pre-cache the balance, but do NOT await it here.
          //
          // Two reasons, and the first is a hard deadlock:
          //
          // 1. `precacheBalance` awaits `PubkeyManager.getPubkeys(asset)`. On
          //    the fresh-fetch path - no in-memory cache, no in-flight request,
          //    no persisted pubkeys, i.e. the first ever activation of this
          //    asset for this wallet on this device - that re-enters
          //    `SharedActivationCoordinator.activateAsset(asset)`. The
          //    coordinator finds its own still-pending completer in
          //    `_pendingActivations` and joins it. But that completer is only
          //    completed after this method returns, so the activation waits on
          //    itself. Nothing on the chain has a timeout, so the asset stays
          //    `activating` forever and every caller blocked on it - the login
          //    fan-out's `Future.wait`, the balance watcher's
          //    `_ensureAssetActivated` - hangs with it.
          //
          // 2. Even without the cycle it is a `get_new_address`/pubkey round
          //    trip per asset sitting between KDF reporting success and the
          //    terminal `ActivationProgress` the UI is waiting on. It is a
          //    cache warm-up; nothing about the activation's correctness
          //    depends on it, and the balance watcher fetches the balance on
          //    its own anyway.
          //
          // The genuinely load-bearing side effects above (asset history,
          // custom-token storage, cache invalidation, completing the join
          // future) stay inline and still gate the terminal event.
          unawaited(
            _balanceManager.precacheBalance(asset).catchError((Object e) {
              debugPrint(
                'Background balance pre-cache failed for ${asset.id.id}: $e',
              );
            }),
          );
        }

        if (gaslessContext != null) {
          await _requireGaslessContextCurrent(gaslessContext);
        }
        _activatedAssetsCache.invalidate();
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    } else {
      // Record the strategy's terminal failure - message and structured
      // error - in the state map. Left on `activating`, the `finally`'s
      // `_failGroupIfStillActivating` would replace it with the generic
      // "ended without a terminal result", discarding the actionable error
      // from the public [activationStates] API.
      _setActivationStates(
        _groupStates(
          group,
          (id) => AssetActivationState.failed(
            id,
            errorMessage: progress.errorMessage ?? 'Unknown error',
            sdkError: progress.sdkError,
          ),
        ),
      );
      if (!completer.isCompleted) {
        completer.completeError(progress.errorMessage ?? 'Unknown error');
      }
    }
  }

  bool _shouldRefreshTronGaslessActivation(_AssetGroup group) {
    if (_tronGaslessProvider == null) {
      return false;
    }

    if (group.primary.protocol is Trc20Protocol) {
      return shouldRefreshTronGaslessActivation(group.primary);
    }

    if (group.primary.protocol is TrxProtocol) {
      return group.children.any(shouldRefreshTronGaslessActivation);
    }

    return false;
  }

  TronGaslessProviderConfig? _gaslessProviderFor(_AssetGroup group) {
    final provider = _tronGaslessProvider;
    if (provider == null) return null;
    // Provider configuration is activation-scoped on the TRX platform. Attach
    // it even when TRX is activated before any enrolled token; KDF has no
    // supported runtime mutation RPC for an already-active platform.
    if (group.primary.protocol is TrxProtocol) return provider;
    return _gaslessAssets(group).isEmpty ? null : provider;
  }

  Iterable<Asset> _gaslessAssets(_AssetGroup group) sync* {
    if (_gaslessCapabilities.isConfigured(group.primary)) {
      yield group.primary;
    }
    for (final child in group.children) {
      if (_gaslessCapabilities.isConfigured(child)) yield child;
    }
  }

  Future<ActivationProgress> _verifyGaslessCapability(
    _AssetGroup group,
    ActivationProgress success,
    _GaslessActivationContext context,
  ) async {
    final pendingProbes = <({Asset asset, int epoch})>[];
    try {
      await _requireGaslessContextCurrent(context);
      final assets = _gaslessAssets(group).toList();
      if (assets.isEmpty) return success;
      if (_tronGaslessProvider == null) {
        throw StateError('GasFree provider configuration is unavailable');
      }
      for (final asset in assets) {
        final requestedPath = asset.id.derivationPath?.trim();
        final walletType = switch ((
          context.walletId.authOptions.derivationMethod,
          context.walletId.authOptions.privKeyPolicy,
        )) {
          (DerivationMethod.hdWallet, const PrivateKeyPolicy.trezor()) =>
            GaslessWalletType.hardwareHd,
          (DerivationMethod.hdWallet, _) => GaslessWalletType.softwareHd,
          (DerivationMethod.iguana, _) => GaslessWalletType.softwareIguana,
        };
        final capabilityPath = switch (walletType) {
          GaslessWalletType.softwareHd ||
          GaslessWalletType.hardwareHd => requestedPath ?? '',
          GaslessWalletType.softwareIguana => '',
        };
        final protocol = asset.protocol as Trc20Protocol;
        final topLevelContract = protocol.config['contract_address'];
        final protocolJson = protocol.config['protocol'];
        final protocolData = protocolJson is Map
            ? protocolJson['protocol_data']
            : null;
        final nestedContract = protocolData is Map
            ? protocolData['contract_address']
            : null;
        final contractAddress = topLevelContract is String
            ? topLevelContract
            : nestedContract is String
            ? nestedContract
            : null;
        final walletPubkeyHash = context.walletId.pubkeyHash;
        if (contractAddress == null || walletPubkeyHash == null) {
          _gaslessCapabilities.markSecurityMismatch(asset.id);
          continue;
        }
        final activatedIdentity = GaslessCapabilityIdentity(
          assetId: asset.id,
          platform: protocol.platform,
          contractAddress: contractAddress,
          providerAddress: _tronGaslessProvider.serviceProvider?.trim() ?? '',
          walletPubkeyHash: walletPubkeyHash,
          walletType: walletType,
          derivationPath: capabilityPath,
        );
        if (!_gaslessCapabilities.bindActivatedIdentity(
          asset,
          activatedIdentity,
        )) {
          continue;
        }
        final statusEpoch = _gaslessCapabilities.beginAccountStatusProbe(
          asset.id,
        );
        _gaslessCapabilities.markChecking(asset.id);
        pendingProbes.add((asset: asset, epoch: statusEpoch));
      }

      // The identity binding above is local and stays on the activation path,
      // so the terminal progress still reports GasFree as "checking" rather
      // than absent. The account-status RPC itself is deliberately not awaited
      // here - see [_refreshGaslessAccountStatuses].
      if (pendingProbes.isNotEmpty) {
        unawaited(_refreshGaslessAccountStatuses(pendingProbes, context));
      }
      return success;
    } catch (error, stackTrace) {
      Object effectiveError = error;
      try {
        await _requireGaslessContextCurrent(context);
      } on WalletChangedDisconnectException catch (walletError) {
        effectiveError = walletError;
      }
      if (effectiveError is WalletChangedDisconnectException) {
        final mappedError = _mapError(effectiveError, group.primary.id);
        return ActivationProgress.error(
          message: mappedError.fallbackMessage,
          sdkError: mappedError,
          stackTrace: stackTrace,
        );
      }
      for (final asset in _gaslessAssets(group)) {
        if (_gaslessCapabilities.markAccountStatusError(asset.id, error)) {
          continue;
        } else {
          _gaslessCapabilities.markUnconfirmed(asset.id);
        }
      }
      // GasFree readiness is an optional rail layered on a successful KDF
      // activation. The typed account status and capability state gate the
      // optional rail while Standard TRON remains usable.
      return success;
    }
  }

  /// Refreshes GasFree account status out of band.
  ///
  /// Deliberately not awaited by the activation stream.
  /// `gasless::account_status` is a proxy round trip with a 10s timeout, and
  /// awaiting it before yielding the terminal [ActivationProgress] held the
  /// asset in `activating` - with no balance watcher and no Send - for its
  /// entire duration. Since USDT-TRC20 is a default coin, that landed on the
  /// post-login critical path for every wallet that has it.
  ///
  /// Safe to land late: the result is already non-fatal (a failure only marks
  /// the capability unconfirmed), and the registry guards stale results with
  /// per-asset probe epochs plus the wallet-context check below.
  Future<void> _refreshGaslessAccountStatuses(
    List<({Asset asset, int epoch})> probes,
    _GaslessActivationContext context,
  ) async {
    for (final probe in probes) {
      final asset = probe.asset;
      try {
        final status = await _client.rpc.withdraw.gaslessAccountStatus(
          coin: asset.id.id,
        );
        await _requireGaslessContextCurrent(context);
        if (!_gaslessCapabilities.isCurrentAccountStatusProbe(
          asset.id,
          probe.epoch,
        )) {
          continue;
        }
        _gaslessCapabilities.refreshAccountStatus(asset, status);
      } on WalletChangedDisconnectException {
        // The wallet changed underneath us; every remaining result is stale
        // and the registry is reset by the auth listener.
        return;
      } catch (error) {
        try {
          await _requireGaslessContextCurrent(context);
        } on WalletChangedDisconnectException {
          return;
        }
        if (!_gaslessCapabilities.isCurrentAccountStatusProbe(
          asset.id,
          probe.epoch,
        )) {
          continue;
        }
        if (!_gaslessCapabilities.markAccountStatusError(asset.id, error)) {
          _gaslessCapabilities.markUnconfirmed(asset.id);
        }
      }
    }
  }

  /// Cleanup after activation attempt
  Future<void> _cleanupActivation(
    AssetId assetId,
    _ActivationRegistration registration,
  ) async {
    await _protectedOperation(() async {
      if (registration.sessionGeneration != _activationSessionGeneration ||
          !identical(_activationCompleters[assetId], registration.completer)) {
        return;
      }
      _activationCompleters.remove(assetId);
      final cancellation = _cancelledActivations[assetId];
      if (cancellation == null ||
          identical(cancellation.completer, registration.completer)) {
        _cancelledActivations.remove(assetId);
      }
    });
  }

  /// Get currently activated assets
  Future<Set<AssetId>> getActiveAssets() async {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    try {
      return await _readActivatedAssetIds();
    } catch (e) {
      debugPrint('Failed to get active assets: $e');
      return {};
    }
  }

  /// Check if specific asset is active
  Future<bool> isAssetActive(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    try {
      final activeAssets = forceRefresh
          ? await _readActivatedAssetIds(forceRefresh: true)
          : await getActiveAssets();
      return activeAssets.contains(assetId);
    } catch (e) {
      debugPrint('Failed to check if asset is active: $e');
      return false;
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    await _protectedOperation(() async {
      _isDisposed = true;

      // Complete any pending completers with errors
      final completers = List<Completer<void>>.from(
        _activationCompleters.values,
      );
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError('ActivationManager disposed');
        }
      }

      _activationCompleters.clear();
      _cancelledActivations.clear();
      _activationStates.clear();
      await _activationStatesController.close();
    });
  }
}

class _GaslessActivationContext {
  const _GaslessActivationContext({
    required this.walletId,
    required this.sessionGeneration,
  });

  final WalletId walletId;
  final int sessionGeneration;
}

/// Internal class for grouping related assets
class _AssetGroup {
  _AssetGroup({required this.primary, Set<Asset>? children})
    : children = children ?? <Asset>{},
      assert(
        (children ?? const <Asset>{}).every(
          (asset) => asset.id.parentId == primary.id,
        ),
        'All child assets must have the parent asset as their parent',
      );

  final Asset primary;
  final Set<Asset> children;

  static List<_AssetGroup> _groupByPrimary(
    List<Asset> assets,
    IAssetLookup assetLookup,
  ) {
    final groups = <AssetId, _AssetGroup>{};

    for (final asset in assets) {
      final parentId = asset.id.parentId;
      if (parentId == null || asset.protocol.isCustomToken) {
        groups.putIfAbsent(asset.id, () => _AssetGroup(primary: asset));
        continue;
      }

      final parentAsset = assetLookup.fromId(parentId);
      if (parentAsset == null) {
        groups.putIfAbsent(asset.id, () => _AssetGroup(primary: asset));
        continue;
      }

      final group = groups.putIfAbsent(
        parentId,
        () => _AssetGroup(primary: parentAsset),
      );
      group.children.add(asset);
    }

    return groups.values.toList();
  }
}

class _ActivationRegistration {
  const _ActivationRegistration({
    required this.completer,
    required this.sessionGeneration,
    required this.shouldStartActivation,
  });

  final Completer<void> completer;
  final int sessionGeneration;
  final bool shouldStartActivation;
}

class _ActivationCancellation {
  const _ActivationCancellation({
    required this.completer,
    required this.sessionGeneration,
    required this.reason,
  });

  final Completer<void> completer;
  final int sessionGeneration;
  final String reason;
}
