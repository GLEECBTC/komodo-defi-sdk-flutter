import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';

part 'routed_swap_fixture_errors.dart';
part 'routed_swap_fixture_internals.dart';
part 'routed_swap_fixture_plan.dart';
part 'routed_swap_fixture_responses.dart';
part 'routed_swap_fixture_run.dart';
part 'routed_swap_fixture_support.dart';
part 'routed_swap_fixture_types.dart';

/// Scripts KDF's `routed_swap` RPC surface onto a [KdfScript].
///
/// Built against the engine rather than the contract prose: every payload is
/// the serde shape of `komodo-defi-framework` `feat/lifi-integration`
/// (`mm2src/mm2_main/src/routed_swap/`), optional fields are omitted and never
/// `null`, and where the contract document and the engine disagree the engine
/// wins.
///
/// A routed swap runs against a live bridge with real money and can take 30+
/// minutes, so it is not a dev loop. This fixture makes every in-progress
/// state, terminal outcome and error, cancellation, forgetting, restart and
/// the durable history reachable in milliseconds.
///
/// **Event-sourced like the engine.** Each swap keeps the engine's durable
/// event log: progress, gas spent, approval hashes and a terminal event. A
/// `task::routed_swap::status` read and a `routed_swap::history` entry are two
/// projections of that one log, so they cannot disagree.
///
/// **Polls drive time.** The engine advances on its own; here each status
/// poll advances a swap by one persisted transition (see
/// [RoutedSwapRun.pollsPerState] and [RoutedSwapRun.autoAdvance]), and
/// [advance] moves it without a poll — which is how a real poll lands after
/// several transitions.
///
/// Composes with `KdfWalletFixture`: call [applyTo] on the script that fixture
/// builds.
class RoutedSwapFixture {
  /// Creates a fixture.
  ///
  /// [clock] supplies unix seconds for every persisted event. The default is
  /// a counter that ticks once per event, so ordering is deterministic; pass
  /// [RoutedSwapFixture.wallClock] when the code under test compares history
  /// timestamps with the real time. Task ids start at [firstTaskId].
  RoutedSwapFixture({int Function()? clock, this.firstTaskId = 1})
    : _clock = clock,
      _nextTaskId = firstTaskId;

  /// Real UTC unix seconds.
  static int wallClock() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  /// The first task id handed out, and the one a restart starts over from.
  final int firstTaskId;

  final int Function()? _clock;
  int _counter = 1754784000;

  final Map<String, int> _supportedCoins = <String, int>{};
  final Map<String, List<RoutedSwapQuote>> _quotes = {};
  final Map<String, List<_ScriptedQuoteError>> _quoteErrors = {};
  final List<Object> _pendingInits = <Object>[];
  final List<_Swap> _swaps = <_Swap>[];
  final Map<int, _Swap> _tasks = <int, _Swap>{};
  final List<String> _statusFailures = <String>[];
  final List<String> _cancelFailures = <String>[];
  int _nextTaskId;

  // ------------------------------------------------------------- scripting

  /// Lists [coin] in `routed_swap::supported_coins`: eligible to attempt a
  /// quote, not a promise that a route exists.
  void supportedCoin(String coin, {required int chainId}) {
    _supportedCoins[coin] = chainId;
  }

  /// Scripts a `routed_swap::quote` route for its `from`/`to` pair.
  ///
  /// A route with a null [RoutedSwapQuote.amount] answers any requested
  /// amount; one with an amount answers only that amount. The route also
  /// becomes the executed route of a [RoutedSwapRun] for the same pair that
  /// scripts none.
  void quote(RoutedSwapQuote quote) {
    (_quotes[_pairKey(quote.from, quote.to)] ??= []).add(quote);
  }

  /// Scripts `routed_swap::quote` failing for a pair: on every call, or on
  /// the next [times] calls only.
  void quoteFails(
    String from,
    String to,
    RoutedSwapQuoteError error, {
    int? times,
  }) {
    if (times != null && times < 1) {
      throw ArgumentError.value(times, 'times', 'must be positive');
    }
    (_quoteErrors[_pairKey(from, to)] ??= []).add(
      _ScriptedQuoteError(error, times),
    );
  }

  /// Enqueues one execution for the next `task::routed_swap::init`.
  ///
  /// Runs and [initFails] rejections share one queue, consumed in order.
  void run(RoutedSwapRun run) => _pendingInits.add(run);

  /// Makes the next `task::routed_swap::init` fail before any task exists.
  ///
  /// Only errors the engine raises before registering a task are accepted:
  /// the provider is not called until the task runs, so `NoRouteFound`,
  /// `RateLimited`, `ProviderApiError`, `TransportError` and `InvalidConfig`
  /// arrive as terminal task errors instead.
  void initFails(RoutedSwapQuoteError error) {
    if (!_initErrorTypes.contains(error.errorType)) {
      throw ArgumentError.value(
        error.errorType,
        'error',
        'init only fails before a task exists with one of $_initErrorTypes; '
            'provider errors surface as terminal task errors',
      );
    }
    _pendingInits.add(error);
  }

  /// Makes the next [times] `task::routed_swap::status` reads fail with the
  /// generic task-manager `Internal` error.
  void statusFailsInternally({
    int times = 1,
    String message = 'routed swap task manager is unavailable',
  }) {
    for (var i = 0; i < times; i++) {
      _statusFailures.add(message);
    }
  }

  /// Makes the next `task::routed_swap::cancel` answer `InternalError`. The
  /// task is left running.
  void cancelFailsInternally({
    String message = 'Unable to persist routed swap state',
  }) {
    _cancelFailures.add(message);
  }

  // --------------------------------------------------------------- driving

  /// Advances the live task [taskId] by [steps] persisted transitions without
  /// a status read, the way a real poll can land after several transitions.
  /// The next read reports the new state. Stops at the terminal result.
  void advance(int taskId, {int steps = 1}) {
    final swap = _tasks[taskId];
    if (swap == null) {
      throw ArgumentError.value(taskId, 'taskId', 'no live routed task');
    }
    for (var i = 0; i < steps && !swap.isTerminal; i++) {
      _step(swap);
    }
  }

  /// Restarts KDF.
  ///
  /// Like `routed_swap_kick_starts`: a swap that never reached
  /// `Broadcasting` becomes `AbortedOnRestart`; one in `Broadcasting` with no
  /// saved source hash becomes `InternalError`, because an external wallet may
  /// have broadcast; one with a saved hash stays in flight and resumes by
  /// re-entering `WaitingSourceConfirmation` and tracking the bridge from
  /// `unknown` again — drive it with [advancePersisted].
  ///
  /// Every task id dies. With [reuseTaskIds] the ids start over from
  /// [firstTaskId], as the engine's process-global counter does, so a stale
  /// id can name a different swap after a restart.
  void restartKdf({bool reuseTaskIds = true}) {
    for (final swap in _swaps) {
      swap.taskId = null;
      if (swap.isTerminal) continue;
      final state = swap.engineState;
      if (!state.isPostBroadcast) {
        swap.events.add(_Event.aborted(_now()));
        continue;
      }
      final hashSaved =
          state != RoutedSwapRunState.broadcasting ||
          swap.lastProgress.containsKey('source_tx_hash');
      if (!hashSaved) {
        swap.events.add(
          _Event.failed(
            _now(),
            swap.plan.errorDetails(
              RoutedSwapRunError.internalError(
                'Broadcast handoff did not persist a transaction hash',
              ),
              withRoute: true,
            ),
          ),
        );
        continue;
      }
      _resume(swap);
    }
    _tasks.clear();
    if (reuseTaskIds) _nextTaskId = firstTaskId;
  }

  /// Advances a task-less in-flight swap — one resumed by [restartKdf] — by
  /// [steps] persisted transitions. Stops at the terminal result.
  void advancePersisted(String uuid, {int steps = 1}) {
    final swap = _swapByUuid(uuid);
    if (swap.taskId != null) {
      throw StateError(
        'Routed swap $uuid still has live task ${swap.taskId}; drive it with '
        'status reads or advance(taskId).',
      );
    }
    for (var i = 0; i < steps && !swap.isTerminal; i++) {
      _step(swap);
    }
  }

  /// Runs a task-less in-flight swap to its terminal result.
  void finishPersisted(String uuid) {
    final swap = _swapByUuid(uuid);
    advancePersisted(uuid, steps: swap.transitions.length + 1);
  }

  /// Records an approval hash that returned after the cancellation of [uuid]
  /// was accepted: metadata only, the outcome stays `TaskCancelled`, and the
  /// entry's `finished_at` moves to it.
  void recordLateApprovalHash(String uuid, String txHash) {
    final swap = _swapByUuid(uuid);
    if (swap.semantic.kind != _EventKind.cancelled) {
      throw StateError('Routed swap $uuid was not cancelled.');
    }
    swap.events.add(_Event.approvalHash(_now(), txHash));
  }

  // ------------------------------------------------------------ inspection

  /// The persistent uuid of the swap [taskId] was created for, including
  /// tasks that have since been forgotten, cancelled or restarted.
  String uuidOf(int taskId) {
    for (final swap in _swaps.reversed) {
      if (swap.taskIds.contains(taskId)) return swap.uuid;
    }
    throw ArgumentError.value(taskId, 'taskId', 'no routed task was created');
  }

  /// Whether [taskId] is a live task KDF would answer for.
  bool hasTask(int taskId) => _tasks.containsKey(taskId);

  /// Every history entry, newest first, as `routed_swap::history` returns it.
  List<Map<String, dynamic>> get historyEntries => [
    for (final swap in _sorted(_swaps)) _wireMap(_entry(swap)),
  ];

  /// The history entry for [uuid].
  Map<String, dynamic> historyEntry(String uuid) =>
      _wireMap(_entry(_swapByUuid(uuid)));

  // ----------------------------------------------------------------- wiring

  /// Wires every routed-swap method onto [script].
  void applyTo(KdfScript script) {
    script
      ..on('routed_swap::supported_coins', _supportedCoinsResponse)
      ..on('routed_swap::quote', _quoteResponse)
      ..on('routed_swap::history', _historyResponse)
      ..on('task::routed_swap::init', _initResponse)
      ..on('task::routed_swap::status', _statusResponse)
      ..on('task::routed_swap::cancel', _cancelResponse);
  }

  /// A script answering only the routed-swap methods.
  KdfScript build() {
    final script = KdfScript();
    applyTo(script);
    return script;
  }
}
