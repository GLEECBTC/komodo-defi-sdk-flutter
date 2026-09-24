import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';

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

  // -------------------------------------------------------------- responses

  Map<String, dynamic> _supportedCoinsResponse(Map<String, dynamic> request) {
    final invalid =
        _shape(
          request,
          allowed: const {'provider'},
          strings: const {'provider'},
        ) ??
        _options(request, providerOnly: true);
    if (invalid != null) return invalid;
    final coins = _supportedCoins.keys.toList()..sort();
    return _ok(request, {
      'provider': _provider,
      'coins': [
        for (final coin in coins)
          {'coin': coin, 'chain_id': _supportedCoins[coin]},
      ],
    });
  }

  Map<String, dynamic> _quoteResponse(Map<String, dynamic> request) {
    final invalid =
        _shape(
          request,
          allowed: _quoteKeys,
          required: const {'from', 'to', 'amount'},
          strings: const {'from', 'to', 'order', 'provider'},
          numbers: const {'amount', 'slippage'},
        ) ??
        _options(request);
    if (invalid != null) return invalid;
    final params = _params(request);
    final from = params['from'] as String;
    final to = params['to'] as String;
    final amount = _numberText(params['amount']);

    final errors = _quoteErrors[_pairKey(from, to)];
    if (errors != null && errors.isNotEmpty) {
      final scripted = errors.first;
      if (scripted.remaining != null) {
        scripted.remaining = scripted.remaining! - 1;
        if (scripted.remaining == 0) errors.removeAt(0);
      }
      return _scriptedError(request, scripted.error);
    }

    final quote = _quoteFor(from, to, amount);
    if (quote == null) {
      final scripted = _quotes[_pairKey(from, to)];
      throw StateError(
        scripted == null
            ? 'No routed_swap::quote scripted for "$from" -> "$to". Add '
                  'one with quote(...), or script the failure with '
                  'quoteFails(...): an unscripted pair is a scripting bug, '
                  'not a NoRouteFound.'
            : 'routed_swap::quote for "$from" -> "$to" asked for $amount, but '
                  'the scripted routes quote '
                  '${scripted.map((q) => q.amount).join(', ')}. The engine '
                  'never returns a route for a different source amount.',
      );
    }
    return _ok(request, {
      'routes': [quote.toJson(amount: amount)],
    });
  }

  Map<String, dynamic> _initResponse(Map<String, dynamic> request) {
    final invalid =
        _shape(
          request,
          allowed: {..._quoteKeys, 'min_to_amount', 'client_id'},
          required: const {'from', 'to', 'amount', 'min_to_amount'},
          strings: const {'from', 'to', 'order', 'provider'},
          numbers: const {'amount', 'min_to_amount', 'slippage'},
          counts: const {'client_id'},
        ) ??
        _options(request);
    if (invalid != null) return invalid;
    if (_pendingInits.isEmpty) {
      throw StateError(
        'task::routed_swap::init called with nothing scripted. Enqueue a '
        'run(RoutedSwapRun(...)) or an initFails(...).',
      );
    }
    final next = _pendingInits.removeAt(0);
    if (next is RoutedSwapQuoteError) return _scriptedError(request, next);

    final params = _params(request);
    final seq = _swaps.length + 1;
    final uuid = _uuidFor(seq);
    final plan = _Plan.resolve(
      next as RoutedSwapRun,
      seq: seq,
      uuid: uuid,
      from: params['from'] as String,
      to: params['to'] as String,
      amount: _numberText(params['amount']),
      minToAmount: _numberText(params['min_to_amount']),
      displayedRoute: _quoteFor(
        params['from'] as String,
        params['to'] as String,
        _numberText(params['amount']),
      ),
    );
    final createdAt = _now();
    final swap = _Swap(plan: plan, createdAt: createdAt)
      ..events.add(_Event.progress(createdAt, plan.initialDetails))
      ..transitions = plan.liveTransitions();
    _swaps.add(swap);
    _register(swap);
    for (var i = 0; i < next.advanceOnInit && !swap.isTerminal; i++) {
      _step(swap);
    }
    return _ok(request, {'task_id': swap.taskId});
  }

  Map<String, dynamic> _statusResponse(Map<String, dynamic> request) {
    final invalid = _shape(
      request,
      required: const {'task_id'},
      counts: const {'task_id'},
      booleans: const {'forget_if_finished'},
    );
    if (invalid != null) return invalid;
    if (_statusFailures.isNotEmpty) {
      final message = _statusFailures.removeAt(0);
      return _error(
        request,
        type: 'Internal',
        message: 'Internal error: $message',
        data: message,
        path: 'rpc_common',
      );
    }
    final params = _params(request);
    final taskId = params['task_id'] as int;
    final swap = _tasks[taskId];
    if (swap == null) {
      // RpcTaskStatusError::NoSuchTask(TaskId) is a newtype variant, so the
      // id is the bare error_data.
      return _error(
        request,
        type: 'NoSuchTask',
        message: "No such task '$taskId'",
        data: taskId,
        path: 'rpc_common',
      );
    }
    if (!swap.isTerminal &&
        swap.plan.run.autoAdvance &&
        swap.observed >= swap.plan.run.pollsPerState) {
      _step(swap);
    }
    swap.observed++;
    final result = _status(swap);
    final forget = params['forget_if_finished'] as bool? ?? true;
    if (swap.isTerminal && forget) _unregister(swap);
    return _ok(request, result);
  }

  Map<String, dynamic> _cancelResponse(Map<String, dynamic> request) {
    final invalid = _shape(
      request,
      required: const {'task_id'},
      counts: const {'task_id'},
    );
    if (invalid != null) return invalid;
    final taskId = _params(request)['task_id'] as int;
    if (_cancelFailures.isNotEmpty) {
      final message = _cancelFailures.removeAt(0);
      // InternalError(String) is a newtype variant: the message is the bare
      // error_data.
      return _error(
        request,
        type: 'InternalError',
        message: message,
        data: message,
        path: 'swap_task',
      );
    }
    final swap = _tasks[taskId];
    // Cancel refusals are struct variants, so error_data is {task_id}.
    if (swap == null) {
      return _error(
        request,
        type: 'NoSuchTask',
        message: 'No such routed swap task: $taskId',
        data: {'task_id': taskId},
        path: 'swap_task',
      );
    }
    if (swap.isTerminal) {
      return _error(
        request,
        type: 'TaskFinished',
        message: 'Routed swap task is already finished: $taskId',
        data: {'task_id': taskId},
        path: 'swap_task',
      );
    }
    if (swap.engineState.isPostBroadcast) {
      return _error(
        request,
        type: 'TaskAlreadyBroadcast',
        message: 'Routed swap task has already broadcast: $taskId',
        data: {'task_id': taskId},
        path: 'swap_task',
      );
    }
    _unregister(swap);
    swap.events.add(_Event.cancelled(_now()));
    return _ok(request, 'success');
  }

  Map<String, dynamic> _historyResponse(Map<String, dynamic> request) {
    final invalid = _historyShape(request);
    if (invalid != null) return invalid;
    final params = _params(request);
    final limit = params['limit'] as int? ?? 10;
    final pageNumber = params['page_number'] as int? ?? 1;
    final uuid = params['uuid'] as String?;
    final statusFilter = params['status_filter'] as String? ?? 'all';
    final myCoin = params['my_coin'] as String?;
    final otherCoin = params['other_coin'] as String?;
    final fromTimestamp = params['from_timestamp'] as int?;
    final toTimestamp = params['to_timestamp'] as int?;

    if (limit == 0) {
      return _scriptedError(
        request,
        RoutedSwapQuoteError.invalidParam(
          'limit',
          'Pagination must have a positive limit',
        ),
      );
    }
    if (fromTimestamp != null &&
        toTimestamp != null &&
        fromTimestamp > toTimestamp) {
      return _scriptedError(
        request,
        RoutedSwapQuoteError.invalidParam(
          'to_timestamp',
          'Must not precede from_timestamp',
        ),
      );
    }

    final wanted = uuid == null ? null : _normalizeUuid(uuid);
    final matches = _sorted(_swaps).where((swap) {
      if (wanted != null && swap.uuid != wanted) return false;
      final inFlight = _status(swap)['status'] == 'InProgress';
      if (statusFilter == 'in_flight' && !inFlight) return false;
      if (statusFilter == 'terminal' && inFlight) return false;
      if (myCoin != null && swap.plan.from != myCoin) return false;
      if (otherCoin != null && swap.plan.to != otherCoin) return false;
      if (fromTimestamp != null && swap.createdAt < fromTimestamp) {
        return false;
      }
      // started_at < :to_timestamp — the upper bound is exclusive.
      if (toTimestamp != null && swap.createdAt >= toTimestamp) return false;
      return true;
    }).toList();

    final total = matches.length;
    return _ok(request, {
      'entries': [
        for (final swap in matches.skip((pageNumber - 1) * limit).take(limit))
          _entry(swap),
      ],
      'total': total,
      'limit': limit,
      'page_number': pageNumber,
      'total_pages': (total + limit - 1) ~/ limit,
    });
  }

  // --------------------------------------------------------------- internals

  int _now() => _clock?.call() ?? _counter++;

  void _register(_Swap swap) {
    final taskId = _nextTaskId++;
    swap
      ..taskId = taskId
      ..taskIds.add(taskId)
      ..observed = 0;
    _tasks[taskId] = swap;
  }

  void _unregister(_Swap swap) {
    _tasks.remove(swap.taskId);
    swap.taskId = null;
  }

  void _step(_Swap swap) {
    if (swap.cursor >= swap.transitions.length) return;
    final transition = swap.transitions[swap.cursor++];
    swap.observed = 0;
    for (final gas in transition.gas) {
      final recorded = swap.events.any(
        (e) => e.kind == _EventKind.gasSpent && e.txHash == gas.txHash,
      );
      if (!recorded) swap.events.add(_Event.gas(_now(), gas));
    }
    final details = transition.details;
    if (details == null) {
      swap.events.add(transition.terminal!.event(_now()));
      return;
    }
    // Tracking persists only a changed update (`update_tracking`).
    if (transition.tracking &&
        jsonEncode(swap.lastProgress) == jsonEncode(details)) {
      return;
    }
    swap.events.add(_Event.progress(_now(), details));
  }

  void _resume(_Swap swap) {
    final ladder = swap.plan.ladder;
    final confirmation = ladder.indexWhere(
      (tick) => tick.state == RoutedSwapRunState.waitingSourceConfirmation,
    );
    swap
      ..transitions = swap.plan.transitions([
        RoutedSwapTick.waitingSourceConfirmation,
        if (confirmation >= 0) ...ladder.sublist(confirmation + 1),
      ], previous: null)
      ..cursor = 0
      ..observed = 0;
  }

  _Swap _swapByUuid(String uuid) {
    final wanted = _normalizeUuid(uuid);
    return _swaps.firstWhere(
      (swap) => swap.uuid == wanted,
      orElse: () =>
          throw ArgumentError.value(uuid, 'uuid', 'no routed swap recorded'),
    );
  }

  RoutedSwapQuote? _quoteFor(String from, String to, String amount) {
    final scripted = _quotes[_pairKey(from, to)];
    if (scripted == null) return null;
    for (final quote in scripted.reversed) {
      if (quote.amount != null && _sameNumber(quote.amount!, amount)) {
        return quote;
      }
    }
    for (final quote in scripted.reversed) {
      if (quote.amount == null) return quote;
    }
    return null;
  }

  static Map<String, dynamic> _status(_Swap swap) {
    final semantic = swap.semantic;
    return switch (semantic.kind) {
      _EventKind.progress => {
        'status': 'InProgress',
        'details': semantic.details,
      },
      _EventKind.completed => {'status': 'Ok', 'details': semantic.details},
      _EventKind.failed => {'status': 'Error', 'details': semantic.details},
      _EventKind.cancelled => {
        'status': 'Error',
        'details': _synthetic(
          swap,
          'TaskCancelled',
          'Routed swap cancelled before broadcast',
        ),
      },
      _EventKind.aborted => {
        'status': 'Error',
        'details': _synthetic(
          swap,
          'AbortedOnRestart',
          'Swap aborted by node restart before broadcast',
        ),
      },
      _EventKind.gasSpent || _EventKind.approvalHash => throw StateError(
        'informational event used as task state',
      ),
    };
  }

  /// `SyntheticTerminalError`: the history-only outcomes, with no
  /// `error_data`.
  static Map<String, dynamic> _synthetic(
    _Swap swap,
    String errorType,
    String error,
  ) {
    Map<String, dynamic>? route;
    for (final event in swap.events.reversed) {
      if (event.kind != _EventKind.progress) continue;
      route = event.details!['executed_route'] as Map<String, dynamic>?;
      if (route != null) break;
    }
    return {
      'uuid': swap.uuid,
      'provider': _provider,
      if (route != null) 'executed_route': route,
      'error_type': errorType,
      'error': error,
    };
  }

  /// `RoutedSwapDbRepr::history_entry`.
  static Map<String, dynamic> _entry(_Swap swap) {
    final index = swap.events.lastIndexWhere((e) => !e.isMetadata);
    final semantic = swap.events[index];
    int? finishedAt;
    if (semantic.kind == _EventKind.cancelled) {
      finishedAt = semantic.at;
      for (final event in swap.events.skip(index + 1)) {
        if (event.kind == _EventKind.approvalHash && event.txHash!.isNotEmpty) {
          finishedAt = event.at;
        }
      }
    } else if (semantic.isTerminal) {
      finishedAt = semantic.at;
    }

    final approvals = <String>[];
    final gasSpent = <Map<String, dynamic>>[];
    final totals = <String, Decimal>{};
    for (final event in swap.events) {
      final hash = switch (event.kind) {
        _EventKind.progress => event.details!['approve_tx_hash'] as String?,
        _EventKind.approvalHash => event.txHash,
        _ => null,
      };
      if (hash != null && !approvals.contains(hash)) approvals.add(hash);
      if (event.kind == _EventKind.gasSpent) {
        gasSpent.add({
          'tx_hash': event.txHash,
          'coin': event.coin,
          'amount': event.amount,
        });
        totals[event.coin!] =
            (totals[event.coin!] ?? Decimal.zero) +
            Decimal.parse(event.amount!);
      }
    }
    return {
      'created_at': swap.createdAt,
      'updated_at': swap.events.last.at,
      if (finishedAt != null) 'finished_at': finishedAt,
      'requested': {
        'from': swap.plan.from,
        'to': swap.plan.to,
        'amount': _decimalText(swap.plan.amount),
      },
      'min_to_amount_accepted': _decimalText(swap.plan.minToAmount),
      'approval_tx_hashes': approvals,
      'gas_spent': gasSpent,
      'total_gas_spent': [
        for (final entry in totals.entries)
          {'coin': entry.key, 'amount': entry.value.toString()},
      ],
      'swap': _status(swap),
    };
  }

  /// `ORDER BY started_at DESC, uuid ASC`.
  static List<_Swap> _sorted(List<_Swap> swaps) => [...swaps]
    ..sort((a, b) {
      final byCreated = b.createdAt.compareTo(a.createdAt);
      return byCreated != 0 ? byCreated : a.uuid.compareTo(b.uuid);
    });

  Map<String, dynamic>? _historyShape(Map<String, dynamic> request) {
    final invalid = _shape(
      request,
      strings: const {'status_filter'},
      optionalStrings: const {'uuid', 'my_coin', 'other_coin'},
      counts: const {'limit', 'page_number'},
      optionalCounts: const {'from_timestamp', 'to_timestamp'},
    );
    if (invalid != null) return invalid;
    final params = _params(request);
    final uuid = params['uuid'];
    if (uuid is String && !_uuidPattern.hasMatch(uuid)) {
      return _invalidRequest(request, 'invalid UUID `$uuid`');
    }
    final filter = params['status_filter'];
    const filters = {'in_flight', 'terminal', 'all'};
    if (filter != null && !filters.contains(filter)) {
      return _invalidRequest(
        request,
        'unknown variant `$filter`, expected one of `in_flight`, `terminal`, '
        '`all`',
      );
    }
    if (params['page_number'] == 0) {
      return _invalidRequest(
        request,
        'invalid value: integer `0`, expected a nonzero usize',
      );
    }
    return null;
  }

  /// Serde rejecting a request before the handler runs: the dispatcher's
  /// `InvalidRequest`. [strings], [numbers], [counts] and [booleans] must not
  /// be null when present; the `optional` sets are `Option<T>` fields, which
  /// accept null.
  static Map<String, dynamic>? _shape(
    Map<String, dynamic> request, {
    Set<String>? allowed,
    Set<String> required = const {},
    Set<String> strings = const {},
    Set<String> optionalStrings = const {},
    Set<String> numbers = const {},
    Set<String> counts = const {},
    Set<String> optionalCounts = const {},
    Set<String> booleans = const {},
  }) {
    final raw = request['params'];
    if (raw != null && raw is! Map) {
      return _invalidRequest(request, 'invalid type: expected a map');
    }
    final params = _params(request);
    for (final key in params.keys) {
      if (allowed != null && !allowed.contains(key)) {
        return _invalidRequest(request, 'unknown field `$key`');
      }
    }
    for (final key in required) {
      if (!params.containsKey(key)) {
        return _invalidRequest(request, 'missing field `$key`');
      }
    }
    for (final entry in params.entries) {
      final key = entry.key;
      final value = entry.value;
      final nullable =
          optionalStrings.contains(key) || optionalCounts.contains(key);
      if (value == null) {
        if (nullable) continue;
        if (strings.contains(key) ||
            numbers.contains(key) ||
            counts.contains(key) ||
            booleans.contains(key)) {
          return _invalidRequest(
            request,
            'invalid type: null, expected a value for `$key`',
          );
        }
        continue;
      }
      final valid = switch (key) {
        _ when strings.contains(key) || optionalStrings.contains(key) =>
          value is String,
        _ when numbers.contains(key) =>
          value is num || value is String && Decimal.tryParse(value) != null,
        _ when counts.contains(key) || optionalCounts.contains(key) =>
          value is int && value >= 0,
        _ when booleans.contains(key) => value is bool,
        _ => true,
      };
      if (!valid) {
        return _invalidRequest(request, 'invalid type for `$key`: $value');
      }
    }
    return null;
  }

  /// `validate_request_options` then `validate_slippage`.
  static Map<String, dynamic>? _options(
    Map<String, dynamic> request, {
    bool providerOnly = false,
  }) {
    final params = _params(request);
    final provider = params['provider'];
    if (provider != null && provider != _provider) {
      return _scriptedError(
        request,
        RoutedSwapQuoteError.invalidParam(
          'provider',
          'Unsupported routed swap provider',
        ),
      );
    }
    if (providerOnly) return null;
    final order = params['order'];
    if (order != null && order != 'cheapest' && order != 'fastest') {
      return _scriptedError(
        request,
        RoutedSwapQuoteError.invalidParam(
          'order',
          'Unsupported routed swap order',
        ),
      );
    }
    final slippage = params['slippage'];
    if (slippage is num && !(slippage >= 0 && slippage <= 0.5)) {
      return _scriptedError(
        request,
        RoutedSwapQuoteError.amountOutOfBounds(
          param: 'slippage',
          value: _f64Text(slippage),
          min: '0',
          max: '0.5',
        ),
      );
    }
    return null;
  }

  static Map<String, dynamic> _invalidRequest(
    Map<String, dynamic> request,
    String detail,
  ) => _error(
    request,
    type: 'InvalidRequest',
    message: 'Error parsing request: $detail',
    data: detail,
    path: 'dispatcher',
  );

  static Map<String, dynamic> _scriptedError(
    Map<String, dynamic> request,
    RoutedSwapQuoteError error,
  ) => _error(
    request,
    type: error.errorType,
    message: error.message,
    data: error.errorData,
  );

  static Map<String, dynamic> _ok(
    Map<String, dynamic> request,
    Object result,
  ) => _wireMap({
    'mmrpc': '2.0',
    'result': result,
    // `MmRpcResponse.id` is an `Option` without `skip_serializing_if`: the
    // one null KDF does send.
    'id': request['id'],
  });

  /// A top-level MMRPC error: the serialized `MmError` flattened beside
  /// `mmrpc`. Distinct from a terminal task `Error` result.
  static Map<String, dynamic> _error(
    Map<String, dynamic> request, {
    required String type,
    required String message,
    required Object data,
    String path = 'routed_swap',
  }) => _wireMap({
    'mmrpc': '2.0',
    'error': message,
    'error_path': path,
    'error_trace': '$path:1]',
    'error_type': type,
    'error_data': data,
    'id': request['id'],
  });
}

/// The in-progress states of `task::routed_swap::status`, in engine order.
enum RoutedSwapRunState {
  /// The internal fresh quote.
  fetchingQuote('FetchingQuote'),

  /// Static preflight, balances and the confirmed allowance.
  checkingAllowance('CheckingAllowance'),

  /// ERC-20 approval transactions.
  approving('Approving'),

  /// Signing. The last cancellable state.
  signing('Signing'),

  /// The irreversible handoff; cancellation is refused from here on.
  broadcasting('Broadcasting'),

  /// Source-chain confirmation.
  waitingSourceConfirmation('WaitingSourceConfirmation'),

  /// Cross-chain only: following the bridge.
  trackingBridge('TrackingBridge');

  const RoutedSwapRunState(this.wire);

  /// The `state` string on the wire.
  final String wire;

  /// Whether the engine's cancellation gate is irreversible in this state.
  bool get isPostBroadcast => index >= RoutedSwapRunState.broadcasting.index;
}

/// One persisted in-progress transition of a [RoutedSwapRun].
class RoutedSwapTick {
  const RoutedSwapTick._(
    this.state, {
    this.approveTxHash,
    this.withSourceTxHash = true,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
  });

  /// `Approving`: without [txHash] until the approval is broadcast, then with
  /// the hash just broadcast — a zero-reset shows two different hashes.
  const RoutedSwapTick.approving([String? txHash])
    : this._(RoutedSwapRunState.approving, approveTxHash: txHash);

  /// `Broadcasting`. With an external wallet that broadcasts itself the hash
  /// is unknown until the wallet answers, so [withSourceTxHash] is false.
  const RoutedSwapTick.broadcasting({bool withSourceTxHash = true})
    : this._(
        RoutedSwapRunState.broadcasting,
        withSourceTxHash: withSourceTxHash,
      );

  /// `TrackingBridge` after one provider status poll. The KDF-owned `stage`
  /// is derived from [substatus] the way the engine derives it:
  /// `WAIT_SOURCE_CONFIRMATIONS` → `bridging`, `WAIT_DESTINATION_TRANSACTION`
  /// → `destination_pending`, `REFUND_IN_PROGRESS` → `refund_pending`
  /// (which latches), anything else leaves it where it was. The first
  /// `TrackingBridge` of a run is persisted before the provider reports
  /// anything, so it carries none of these.
  const RoutedSwapTick.trackingBridge({
    String? substatus,
    String? substatusMessage,
    String? providerExplorerUrl,
  }) : this._(
         RoutedSwapRunState.trackingBridge,
         substatus: substatus,
         substatusMessage: substatusMessage,
         providerExplorerUrl: providerExplorerUrl,
       );

  /// `FetchingQuote`, persisted at `init`.
  static const RoutedSwapTick fetchingQuote = RoutedSwapTick._(
    RoutedSwapRunState.fetchingQuote,
  );

  /// `CheckingAllowance`.
  static const RoutedSwapTick checkingAllowance = RoutedSwapTick._(
    RoutedSwapRunState.checkingAllowance,
  );

  /// `Signing`.
  static const RoutedSwapTick signing = RoutedSwapTick._(
    RoutedSwapRunState.signing,
  );

  /// `WaitingSourceConfirmation`.
  static const RoutedSwapTick waitingSourceConfirmation = RoutedSwapTick._(
    RoutedSwapRunState.waitingSourceConfirmation,
  );

  /// The state.
  final RoutedSwapRunState state;

  /// The approval hash on an `Approving` tick.
  final String? approveTxHash;

  /// Whether a `Broadcasting` tick already knows the source hash.
  final bool withSourceTxHash;

  /// The provider's opaque substatus.
  final String? substatus;

  /// The provider's opaque substatus message.
  final String? substatusMessage;

  /// The provider's explorer link.
  final String? providerExplorerUrl;
}

/// The terminal `Ok` outcomes.
enum RoutedSwapRunOutcome {
  /// The requested coin at or above the accepted minimum.
  completed('completed'),

  /// Delivered on the destination chain, below the minimum or as another
  /// token.
  partial('partial'),

  /// Funds returned on the source chain.
  refunded('refunded');

  const RoutedSwapRunOutcome(this.wire);

  /// The `outcome` string on the wire.
  final String wire;
}

/// A scripted `routed_swap::quote` route, and the shape of `executed_route`
/// and `fresh_route`.
class RoutedSwapQuote {
  /// Creates a route. [amount] is the sold amount; leave it null to echo the
  /// requested amount, as the engine does.
  RoutedSwapQuote({
    required this.from,
    required this.to,
    required this.toAmount,
    required this.toAmountMin,
    this.amount,
    this.crossChain = true,
    this.toolKey = 'stargateV2',
    this.toolName = 'Stargate V2',
    this.toolLogoUrl,
    this.fromAddress = RoutedSwapQuote.defaultAddress,
    this.approval,
    this.steps = const [],
    this.feeCosts = const [],
    this.gasCosts = const [],
    this.executionDurationS = 95,
  }) {
    if (_decimal(toAmountMin, 'toAmountMin') > _decimal(toAmount, 'toAmount')) {
      throw ArgumentError(
        'toAmountMin ($toAmountMin) exceeds toAmount ($toAmount): the engine '
        'rejects that route in preflight (amount_bounds).',
      );
    }
    if (amount != null) _decimal(amount!, 'amount');
    if (executionDurationS < 0) {
      throw ArgumentError.value(executionDurationS, 'executionDurationS');
    }
  }

  /// The wallet address routes send from and to by default.
  static const String defaultAddress =
      '0x5520086ad0cd4e4a4fa0d4c3e0a7c4c1b0b1c0de';

  /// Source ticker.
  final String from;

  /// Destination ticker.
  final String to;

  /// Sold amount, or null to echo the request.
  final String? amount;

  /// Expected receive.
  final String toAmount;

  /// Guaranteed receive after slippage.
  final String toAmountMin;

  /// `cross_chain` when true, `same_chain` otherwise.
  final bool crossChain;

  /// Stable provider tool key.
  final String toolKey;

  /// Tool name.
  final String toolName;

  /// Tool logo; omitted when null.
  final String? toolLogoUrl;

  /// The source coin's enabled address. `to_address` always equals it in v1.
  final String fromAddress;

  /// Approval transactions the sell needs, or null when none.
  final RoutedSwapQuoteApproval? approval;

  /// Route legs.
  final List<RoutedSwapQuoteStep> steps;

  /// Provider and protocol fees.
  final List<RoutedSwapQuoteFee> feeCosts;

  /// Execution gas.
  final List<RoutedSwapQuoteGas> gasCosts;

  /// Estimated duration, seconds.
  final int executionDurationS;

  /// Per-coin sums of [gasCosts] plus the approval gas, in first-seen order
  /// (`add_gas_total`). A total carries `amount_usd` only when every row it
  /// sums does; approval gas never does.
  List<Map<String, dynamic>> get totalGasCosts {
    final amounts = <String, Decimal>{};
    final usd = <String, Decimal?>{};
    void add(String coin, String amount, String? amountUsd) {
      final value = Decimal.parse(amount);
      final valueUsd = amountUsd == null ? null : Decimal.parse(amountUsd);
      if (!amounts.containsKey(coin)) {
        amounts[coin] = value;
        usd[coin] = valueUsd;
        return;
      }
      amounts[coin] = amounts[coin]! + value;
      final sum = usd[coin];
      usd[coin] = sum == null || valueUsd == null ? null : sum + valueUsd;
    }

    for (final gas in gasCosts) {
      add(gas.coin, gas.amount, gas.amountUsd);
    }
    final approval = this.approval;
    if (approval != null) add(approval.gasCoin, approval.gasAmount, null);
    return [
      for (final coin in amounts.keys)
        {
          'coin': coin,
          'amount': amounts[coin].toString(),
          if (usd[coin] != null) 'amount_usd': usd[coin].toString(),
        },
    ];
  }

  /// The `RoutedSwapRoute` wire object, selling [amount] (or this route's
  /// own amount).
  Map<String, dynamic> toJson({String? amount}) {
    final sold = this.amount ?? amount;
    if (sold == null) {
      throw ArgumentError('A route with no amount needs the requested one.');
    }
    return {
      'provider': _provider,
      'from': {'coin': from, 'amount': sold},
      'to': {'coin': to, 'amount': toAmount, 'amount_min': toAmountMin},
      'tool': {
        'key': toolKey,
        'name': toolName,
        if (toolLogoUrl != null) 'logo_url': toolLogoUrl,
      },
      'kind': crossChain ? 'cross_chain' : 'same_chain',
      'from_address': fromAddress,
      'to_address': fromAddress,
      if (approval != null) 'approval': approval!.toJson(),
      'total_gas_costs': totalGasCosts,
      'steps': [for (final step in steps) step.toJson()],
      'fee_costs': [for (final fee in feeCosts) fee.toJson()],
      'gas_costs': [for (final gas in gasCosts) gas.toJson()],
      'execution_duration_s': executionDurationS,
    };
  }
}

/// The approval transactions a sell needs before the swap.
class RoutedSwapQuoteApproval {
  /// One exact-amount approval (`no_allowance`).
  const RoutedSwapQuoteApproval.noAllowance({
    required this.gasCoin,
    required this.gasAmount,
    this.spender = RoutedSwapQuoteApproval.lifiDiamond,
  }) : resetsFirst = false;

  /// A reset to zero, then the exact-amount approval (`zero_reset`).
  const RoutedSwapQuoteApproval.zeroReset({
    required this.gasCoin,
    required this.gasAmount,
    this.spender = RoutedSwapQuoteApproval.lifiDiamond,
  }) : resetsFirst = true;

  /// LI.FI's diamond, the spender KDF allowlists.
  static const String lifiDiamond =
      '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE';

  /// The coin paying approval gas: the source chain's native coin.
  final String gasCoin;

  /// Estimated approval gas for all of the approval transactions.
  final String gasAmount;

  /// The contract the approval grants to.
  final String spender;

  /// Whether the allowance is reset to zero first.
  final bool resetsFirst;

  /// The `approval` wire object. Its single gas row never has USD.
  Map<String, dynamic> toJson() => {
    'required': true,
    'tx_count': resetsFirst ? 2 : 1,
    'reason': resetsFirst ? 'zero_reset' : 'no_allowance',
    'spender': spender,
    'gas_costs': [
      {'coin': gasCoin, 'amount': gasAmount},
    ],
  };
}

/// One route leg.
class RoutedSwapQuoteStep {
  /// A conversion on one chain.
  const RoutedSwapQuoteStep.swap({required this.tool, required int chainId})
    : _chainId = chainId,
      _fromChainId = null,
      _toChainId = null;

  /// A bridge between two chains.
  const RoutedSwapQuoteStep.cross({
    required this.tool,
    required int fromChainId,
    required int toChainId,
  }) : _chainId = null,
       _fromChainId = fromChainId,
       _toChainId = toChainId;

  /// Provider tool key.
  final String tool;
  final int? _chainId;
  final int? _fromChainId;
  final int? _toChainId;

  /// The tagged `steps[]` wire object.
  Map<String, dynamic> toJson() => _chainId != null
      ? {'type': 'swap', 'tool': tool, 'chain_id': _chainId}
      : {
          'type': 'cross',
          'tool': tool,
          'from_chain_id': _fromChainId,
          'to_chain_id': _toChainId,
        };
}

/// One provider or protocol fee.
class RoutedSwapQuoteFee {
  /// Creates a fee in a KDF [coin] or, when the token maps to none, a
  /// provider [symbol] — exactly one of the two.
  RoutedSwapQuoteFee({
    required this.name,
    required this.amount,
    required this.included,
    this.coin,
    this.symbol,
    this.amountUsd,
  }) {
    if ((coin == null) == (symbol == null)) {
      throw ArgumentError('A fee names exactly one of coin or symbol.');
    }
  }

  /// Provider label.
  final String name;

  /// Fee amount.
  final String amount;

  /// Whether it is already deducted from `to.amount`.
  final bool included;

  /// KDF ticker.
  final String? coin;

  /// Provider symbol.
  final String? symbol;

  /// Provider USD value.
  final String? amountUsd;

  /// The `fee_costs[]` wire object.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (coin != null) 'coin': coin,
    if (symbol != null) 'symbol': symbol,
    'amount': amount,
    if (amountUsd != null) 'amount_usd': amountUsd,
    'included': included,
  };
}

/// Execution gas for one coin.
class RoutedSwapQuoteGas {
  /// Creates a gas row.
  const RoutedSwapQuoteGas({
    required this.coin,
    required this.amount,
    this.amountUsd,
  });

  /// Gas coin ticker.
  final String coin;

  /// Gas amount.
  final String amount;

  /// Provider USD value.
  final String? amountUsd;

  /// The `gas_costs[]` wire object.
  Map<String, dynamic> toJson() => {
    'coin': coin,
    'amount': amount,
    if (amountUsd != null) 'amount_usd': amountUsd,
  };
}

/// A top-level MMRPC error from `routed_swap::quote`, `task::routed_swap::init`
/// or `routed_swap::history` — `RoutedSwapRpcError`.
class RoutedSwapQuoteError {
  RoutedSwapQuoteError._(this.errorType, this.errorData, this.message);

  /// `CoinNotActive`.
  factory RoutedSwapQuoteError.coinNotActive(String coin) =>
      RoutedSwapQuoteError._('CoinNotActive', {
        'coin': coin,
      }, 'Coin $coin is not active');

  /// `PairNotSupported`.
  factory RoutedSwapQuoteError.pairNotSupported(
    String from,
    String to,
    String reason,
  ) => RoutedSwapQuoteError._('PairNotSupported', {
    'from': from,
    'to': to,
    'reason': reason,
  }, 'Pair $from/$to is not supported: $reason');

  /// `InvalidParam`.
  factory RoutedSwapQuoteError.invalidParam(String param, String reason) =>
      RoutedSwapQuoteError._('InvalidParam', {
        'param': param,
        'reason': reason,
      }, 'Invalid parameter $param: $reason');

  /// `AmountOutOfBounds`; the engine always reports both bounds.
  factory RoutedSwapQuoteError.amountOutOfBounds({
    required String param,
    required String value,
    required String min,
    required String max,
  }) => RoutedSwapQuoteError._(
    'AmountOutOfBounds',
    {'param': param, 'value': value, 'min': min, 'max': max},
    'Parameter $param out of bounds, value: $value, min: $min max: $max',
  );

  /// `MyAddressError`.
  factory RoutedSwapQuoteError.myAddressError(String coin, String message) =>
      RoutedSwapQuoteError._('MyAddressError', {
        'coin': coin,
        'message': message,
      }, 'Cannot use $coin source address: $message');

  /// `InvalidConfig`.
  factory RoutedSwapQuoteError.invalidConfig(String message) =>
      RoutedSwapQuoteError._('InvalidConfig', {'message': message}, message);

  /// `NoRouteFound`. The engine always sends at least one reason, falling
  /// back to "No route found".
  factory RoutedSwapQuoteError.noRouteFound({
    List<String> reasons = const ['No route found'],
    String? providerRequestId,
  }) {
    if (reasons.isEmpty) {
      throw ArgumentError('The engine never sends an empty reasons list.');
    }
    return RoutedSwapQuoteError._('NoRouteFound', {
      'reasons': reasons,
      'provider_request_id': ?providerRequestId,
    }, 'No route found');
  }

  /// `RateLimited`.
  factory RoutedSwapQuoteError.rateLimited({String? providerRequestId}) =>
      RoutedSwapQuoteError._('RateLimited', {
        'provider_request_id': ?providerRequestId,
      }, 'Routed swap provider rate limit exceeded');

  /// `ProviderApiError`.
  factory RoutedSwapQuoteError.providerApiError(
    String message, {
    String? providerRequestId,
  }) => RoutedSwapQuoteError._('ProviderApiError', {
    'message': message,
    'provider_request_id': ?providerRequestId,
  }, message);

  /// `TransportError`.
  factory RoutedSwapQuoteError.transportError(String message) =>
      RoutedSwapQuoteError._('TransportError', {'message': message}, message);

  /// `InternalError`.
  factory RoutedSwapQuoteError.internalError(String message) =>
      RoutedSwapQuoteError._('InternalError', {'message': message}, message);

  /// The `error_type`.
  final String errorType;

  /// The `error_data`.
  final Map<String, dynamic> errorData;

  /// The `error` display text.
  final String message;
}

/// A terminal task `Error` — `RoutedSwapTaskError`.
///
/// Where it can be raised is checked against the run's ladder: an error the
/// engine cannot produce at that point throws [ArgumentError].
class RoutedSwapRunError {
  RoutedSwapRunError._(
    this.errorType, {
    Map<String, dynamic> data = const {},
    String? message,
    this.freshRoute,
    this.reason,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
  }) : _data = data,
       _message = message;

  /// `QuoteWorsened`: the fresh route's minimum fell below the accepted one.
  /// Nothing was executed, so there is no `executed_route`.
  factory RoutedSwapRunError.quoteWorsened({
    required RoutedSwapQuote freshRoute,
  }) => RoutedSwapRunError._(
    'QuoteWorsened',
    message: 'Fresh route is below the accepted minimum',
    freshRoute: freshRoute,
  );

  /// `InsufficientBalance`.
  factory RoutedSwapRunError.insufficientBalance({
    required String coin,
    required String available,
    required String requiredAmount,
  }) => RoutedSwapRunError._(
    'InsufficientBalance',
    data: {'coin': coin, 'available': available, 'required': requiredAmount},
    message:
        'Insufficient $coin balance: available $available, required '
        '$requiredAmount',
  );

  /// `ApprovalFailed`: [reason] is `approval_broadcast_failed`,
  /// `approval_transaction_failed`, `allowance_reset_not_confirmed` or
  /// `confirmed_allowance_insufficient`.
  factory RoutedSwapRunError.approvalFailed(String reason) {
    _checkOneOf(reason, 'reason', _approvalFailures);
    return RoutedSwapRunError._(
      'ApprovalFailed',
      data: {'reason': reason},
      message: 'Token approval failed: $reason',
      reason: reason,
    );
  }

  /// `SwapTxFailed`: [reason] is `source_transaction_reverted` or
  /// `source_transaction_not_confirmed`. The source hash is the run's.
  factory RoutedSwapRunError.swapTxFailed(String reason) {
    _checkOneOf(reason, 'reason', _txFailures);
    return RoutedSwapRunError._('SwapTxFailed', reason: reason);
  }

  /// `SigningRejected`: [reason] is `user_rejected`, `timeout` or
  /// `unsupported_method`.
  factory RoutedSwapRunError.signingRejected(String reason) {
    _checkOneOf(reason, 'reason', _signingRejections);
    return RoutedSwapRunError._(
      'SigningRejected',
      data: {'reason': reason},
      message: 'Wallet rejected the routed swap transaction: $reason',
      reason: reason,
    );
  }

  /// `BridgeFailed`, from the provider's final `FAILED` status. The engine
  /// never sets `provider_request_id` on it (`bridge_failed()` passes
  /// `None`). A `REFUND_IN_PROGRESS` substatus keeps tracking instead.
  factory RoutedSwapRunError.bridgeFailed({
    String? substatus = 'UNKNOWN_ERROR',
    String? substatusMessage,
    String? providerExplorerUrl,
  }) {
    if (substatus == 'REFUND_IN_PROGRESS') {
      throw ArgumentError(
        'A FAILED status whose refund is in flight keeps tracking; the '
        'engine does not fail the task on it.',
      );
    }
    return RoutedSwapRunError._(
      'BridgeFailed',
      substatus: substatus,
      substatusMessage: substatusMessage,
      providerExplorerUrl: providerExplorerUrl,
    );
  }

  /// `PreflightRejected`: [check] is `simulation`, `target_allowlist`,
  /// `spender_allowlist`, `value_cap`, `amount_bounds` or `gas_bounds`.
  factory RoutedSwapRunError.preflightRejected(String check) {
    _checkOneOf(check, 'check', _preflightChecks);
    return RoutedSwapRunError._(
      'PreflightRejected',
      data: {'check': check},
      message: 'Routed swap preflight rejected by the $check check',
    );
  }

  /// `NoRouteFound` from the internal fresh quote.
  factory RoutedSwapRunError.noRouteFound({
    List<String> reasons = const ['No route found'],
    String? providerRequestId,
  }) {
    if (reasons.isEmpty) {
      throw ArgumentError('The engine never sends an empty reasons list.');
    }
    return RoutedSwapRunError._(
      'NoRouteFound',
      data: {'reasons': reasons, 'provider_request_id': ?providerRequestId},
      message: 'No route found',
    );
  }

  /// `RateLimited` from the internal fresh quote.
  factory RoutedSwapRunError.rateLimited({String? providerRequestId}) =>
      RoutedSwapRunError._(
        'RateLimited',
        data: {'provider_request_id': ?providerRequestId},
        message: 'Routed swap provider rate limit exceeded',
      );

  /// `ProviderApiError` from the internal fresh quote.
  factory RoutedSwapRunError.providerApiError(
    String message, {
    String? providerRequestId,
  }) => RoutedSwapRunError._(
    'ProviderApiError',
    data: {'message': message, 'provider_request_id': ?providerRequestId},
    message: message,
  );

  /// `AmountOutOfBounds` from the internal fresh quote.
  factory RoutedSwapRunError.amountOutOfBounds({
    required String param,
    required String value,
    required String min,
    required String max,
  }) => RoutedSwapRunError._(
    'AmountOutOfBounds',
    data: {'param': param, 'value': value, 'min': min, 'max': max},
    message:
        'Parameter $param out of bounds, value: $value, min: $min max: $max',
  );

  /// `InternalError`. Legal after `Broadcasting` too: an external wallet's
  /// handoff can fail without returning a hash.
  factory RoutedSwapRunError.internalError(String message) =>
      RoutedSwapRunError._(
        'InternalError',
        data: {'message': message},
        message: message,
      );

  /// `TransportError`; terminal only before `Broadcasting`.
  factory RoutedSwapRunError.transportError(String message) =>
      RoutedSwapRunError._(
        'TransportError',
        data: {'message': message},
        message: message,
      );

  /// The `error_type`.
  final String errorType;

  /// For `QuoteWorsened`.
  final RoutedSwapQuote? freshRoute;

  /// The typed reason, when the variant has one.
  final String? reason;

  /// For `BridgeFailed`.
  final String? substatus;

  /// For `BridgeFailed`.
  final String? substatusMessage;

  /// For `BridgeFailed`.
  final String? providerExplorerUrl;

  final Map<String, dynamic> _data;
  final String? _message;

  /// Whether the engine raises this while `FetchingQuote` in the default
  /// ladder: the internal fresh quote failed.
  bool get _raisedByFreshQuote => const {
    'QuoteWorsened',
    'NoRouteFound',
    'RateLimited',
    'ProviderApiError',
    'AmountOutOfBounds',
    'TransportError',
  }.contains(errorType);

  String _messageFor(String sourceTxHash) => switch (errorType) {
    'SwapTxFailed' => 'Routed swap transaction $sourceTxHash failed: $reason',
    'BridgeFailed' => 'Routed swap bridge failed for transaction $sourceTxHash',
    _ => _message!,
  };

  Map<String, dynamic> _dataFor(String sourceTxHash, String amount) =>
      switch (errorType) {
        'QuoteWorsened' => {'fresh_route': freshRoute!.toJson(amount: amount)},
        'SwapTxFailed' => {'source_tx_hash': sourceTxHash, 'reason': reason},
        'BridgeFailed' => {
          'source_tx_hash': sourceTxHash,
          'substatus': ?substatus,
          'substatus_message': ?substatusMessage,
          'provider_explorer_url': ?providerExplorerUrl,
        },
        _ => _data,
      };

  static void _checkOneOf(String value, String name, Set<String> allowed) {
    if (!allowed.contains(value)) {
      throw ArgumentError.value(value, name, 'must be one of $allowed');
    }
  }
}

/// One scripted execution: what `task::routed_swap::init` starts.
///
/// The [ladder] is the list of transitions the engine persists; it defaults to
/// the path the engine takes for the route, [error] and [outcome]. Status
/// reads observe it (see [pollsPerState]); history sees every transition.
class RoutedSwapRun {
  /// Scripts one execution. Throws [ArgumentError] for a combination the
  /// engine cannot produce; checks that need the `init` request run there.
  RoutedSwapRun({
    this.route,
    this.ladder,
    this.tracking,
    this.outcome,
    this.partialReason,
    this.receivedCoin,
    this.receivedSymbol,
    this.receivedAmount,
    this.error,
    this.sourceTxHash,
    this.approvalTxHashes,
    this.destTxHash,
    this.providerExplorerUrl,
    this.gasCoin,
    this.approvalGas = '0.0021',
    this.sourceGas = '0.0134',
    this.autoAdvance = true,
    this.pollsPerState = 1,
    this.advanceOnInit = 0,
  }) {
    if (error != null && outcome != null) {
      throw ArgumentError('A run ends in error or in an outcome, not both.');
    }
    if (receivedCoin != null && receivedSymbol != null) {
      throw ArgumentError('`received` names a coin or a symbol, not both.');
    }
    if ((outcome == RoutedSwapRunOutcome.partial) != (partialReason != null)) {
      throw ArgumentError(
        'partial_reason is present exactly on a partial outcome.',
      );
    }
    if (partialReason != null) {
      RoutedSwapRunError._checkOneOf(partialReason!, 'partialReason', const {
        'below_minimum',
        'intermediate_token',
      });
      if (receivedAmount == null) {
        throw ArgumentError('A partial outcome needs its receivedAmount.');
      }
    }
    if (pollsPerState < 1) {
      throw ArgumentError.value(pollsPerState, 'pollsPerState');
    }
    if (advanceOnInit < 0) {
      throw ArgumentError.value(advanceOnInit, 'advanceOnInit');
    }
    final tracking = this.tracking;
    if (tracking != null) {
      if (this.ladder != null) {
        throw ArgumentError('tracking shapes the default ladder only.');
      }
      if (tracking.any((t) => t.state != RoutedSwapRunState.trackingBridge)) {
        throw ArgumentError('tracking lists TrackingBridge ticks only.');
      }
      final route = this.route;
      if (route != null && !route.crossChain) {
        throw ArgumentError('Same-chain swaps never enter TrackingBridge.');
      }
    }
    final ladder = this.ladder;
    if (ladder != null) {
      _checkLadder(
        ladder,
        crossChain: route?.crossChain,
        error: error,
        outcome: outcome,
      );
    }
  }

  /// The executed route. Defaults to the scripted quote for the pair, else a
  /// route whose minimum is exactly the accepted `min_to_amount`. A route
  /// whose minimum is below the accepted one fails `QuoteWorsened`, as the
  /// engine's guard does.
  final RoutedSwapQuote? route;

  /// The persisted transitions, starting at `FetchingQuote`.
  final List<RoutedSwapTick>? ladder;

  /// `TrackingBridge` ticks after the initial one, for the default ladder.
  final List<RoutedSwapTick>? tracking;

  /// The terminal `Ok` outcome; `completed` when neither this nor [error] is
  /// set.
  final RoutedSwapRunOutcome? outcome;

  /// `below_minimum` or `intermediate_token`, on a partial outcome.
  final String? partialReason;

  /// The received coin: the requested one by default, the source coin for a
  /// refund.
  final String? receivedCoin;

  /// A received provider symbol with no KDF ticker.
  final String? receivedSymbol;

  /// The received amount: the route's `to.amount` by default, the sold amount
  /// for a refund.
  final String? receivedAmount;

  /// The terminal task error.
  final RoutedSwapRunError? error;

  /// The source transaction hash.
  final String? sourceTxHash;

  /// Hashes the default ladder broadcasts approvals with, in order.
  final List<String>? approvalTxHashes;

  /// The destination transaction hash of a cross-chain delivery.
  final String? destTxHash;

  /// The provider's explorer link.
  final String? providerExplorerUrl;

  /// The coin paying gas: the route's approval gas coin, else its first gas
  /// coin, else `ETH`.
  final String? gasCoin;

  /// Actual gas of each approval transaction.
  final String approvalGas;

  /// Actual gas of the source transaction.
  final String sourceGas;

  /// Whether a status read advances the swap. When false only
  /// [RoutedSwapFixture.advance] does.
  final bool autoAdvance;

  /// Status reads that report each state before the next read advances.
  final int pollsPerState;

  /// Transitions applied during `init`, before the first status read — a
  /// task that raced ahead of it.
  final int advanceOnInit;

  static void _checkLadder(
    List<RoutedSwapTick> ladder, {
    required bool? crossChain,
    required RoutedSwapRunError? error,
    required RoutedSwapRunOutcome? outcome,
  }) {
    if (ladder.isEmpty ||
        ladder.first.state != RoutedSwapRunState.fetchingQuote) {
      throw ArgumentError(
        'A ladder starts at FetchingQuote: init persists it before the task '
        'runs.',
      );
    }
    const successors = <RoutedSwapRunState, Set<RoutedSwapRunState>>{
      RoutedSwapRunState.fetchingQuote: {RoutedSwapRunState.checkingAllowance},
      RoutedSwapRunState.checkingAllowance: {
        RoutedSwapRunState.approving,
        RoutedSwapRunState.signing,
      },
      RoutedSwapRunState.approving: {
        RoutedSwapRunState.approving,
        RoutedSwapRunState.signing,
      },
      RoutedSwapRunState.signing: {RoutedSwapRunState.broadcasting},
      RoutedSwapRunState.broadcasting: {
        RoutedSwapRunState.waitingSourceConfirmation,
      },
      RoutedSwapRunState.waitingSourceConfirmation: {
        RoutedSwapRunState.trackingBridge,
      },
      RoutedSwapRunState.trackingBridge: {RoutedSwapRunState.trackingBridge},
    };
    final approvals = <String>{};
    var tracked = false;
    for (var i = 1; i < ladder.length; i++) {
      final previous = ladder[i - 1].state;
      final tick = ladder[i];
      if (!successors[previous]!.contains(tick.state)) {
        throw ArgumentError(
          '${tick.state.wire} cannot follow ${previous.wire}. The engine '
          'persists FetchingQuote, CheckingAllowance, [Approving...], '
          'Signing, Broadcasting, WaitingSourceConfirmation, '
          '[TrackingBridge...] in that order.',
        );
      }
      if (tick.state == RoutedSwapRunState.approving) {
        final hash = tick.approveTxHash;
        if (previous != RoutedSwapRunState.approving) {
          if (hash != null) {
            throw ArgumentError(
              'The first Approving is persisted before any approval is '
              'broadcast, so it has no approve_tx_hash.',
            );
          }
        } else if (hash == null || !approvals.add(hash)) {
          throw ArgumentError(
            'A later Approving carries the new hash just broadcast.',
          );
        } else if (approvals.length > 2) {
          throw ArgumentError(
            'At most two approvals: a zero-reset, then the exact amount.',
          );
        }
      }
      if (tick.state == RoutedSwapRunState.trackingBridge) {
        if (crossChain == false) {
          throw ArgumentError('Same-chain swaps never enter TrackingBridge.');
        }
        if (!tracked &&
            (tick.substatus != null ||
                tick.substatusMessage != null ||
                tick.providerExplorerUrl != null)) {
          throw ArgumentError(
            'The first TrackingBridge is persisted before the provider '
            'reports anything.',
          );
        }
        tracked = true;
      }
    }
    _checkRaisePoint(
      ladder.last,
      crossChain: crossChain,
      error: error,
      outcome: outcome,
    );
  }

  static void _checkRaisePoint(
    RoutedSwapTick last, {
    required bool? crossChain,
    required RoutedSwapRunError? error,
    required RoutedSwapRunOutcome? outcome,
  }) {
    final state = last.state;
    final String where;
    final bool possible;
    if (error == null) {
      where =
          'an Ok outcome after WaitingSourceConfirmation (same-chain) or '
          'TrackingBridge (cross-chain)';
      possible = switch (crossChain) {
        true => state == RoutedSwapRunState.trackingBridge,
        false => state == RoutedSwapRunState.waitingSourceConfirmation,
        null =>
          state == RoutedSwapRunState.trackingBridge ||
              state == RoutedSwapRunState.waitingSourceConfirmation,
      };
    } else {
      switch (error.errorType) {
        case 'QuoteWorsened' ||
            'NoRouteFound' ||
            'RateLimited' ||
            'ProviderApiError' ||
            'AmountOutOfBounds':
          where = '${error.errorType} while FetchingQuote';
          possible = state == RoutedSwapRunState.fetchingQuote;
        case 'InsufficientBalance':
          where =
              'InsufficientBalance at CheckingAllowance, before any '
              'approval';
          possible = state == RoutedSwapRunState.checkingAllowance;
        case 'PreflightRejected':
          where = 'PreflightRejected at CheckingAllowance or Approving';
          possible =
              state == RoutedSwapRunState.checkingAllowance ||
              state == RoutedSwapRunState.approving;
        case 'ApprovalFailed':
          where =
              'ApprovalFailed at Approving, with the hash of the approval '
              'that failed unless it was never broadcast';
          possible =
              state == RoutedSwapRunState.approving &&
              (error.reason == 'approval_broadcast_failed' ||
                  last.approveTxHash != null);
        case 'SigningRejected':
          where =
              'SigningRejected at Approving, Signing, or a Broadcasting '
              'handoff that has no hash yet';
          possible =
              state == RoutedSwapRunState.approving ||
              state == RoutedSwapRunState.signing ||
              (state == RoutedSwapRunState.broadcasting &&
                  !last.withSourceTxHash);
        case 'SwapTxFailed':
          where = 'SwapTxFailed at WaitingSourceConfirmation';
          possible = state == RoutedSwapRunState.waitingSourceConfirmation;
        case 'BridgeFailed':
          where = 'BridgeFailed at TrackingBridge, cross-chain only';
          possible =
              state == RoutedSwapRunState.trackingBridge &&
              (crossChain ?? true);
        case 'TransportError':
          where = 'TransportError before Broadcasting';
          possible = !state.isPostBroadcast;
        default:
          where = '${error.errorType} anywhere';
          possible = true;
      }
    }
    if (!possible) {
      throw ArgumentError(
        'The engine raises $where; this ladder ends at ${state.wire}.',
      );
    }
  }
}

// ------------------------------------------------------------------ private

const String _provider = 'lifi';

const Set<String> _quoteKeys = {
  'from',
  'to',
  'amount',
  'slippage',
  'order',
  'provider',
};

const Set<String> _initErrorTypes = {
  'CoinNotActive',
  'PairNotSupported',
  'InvalidParam',
  'AmountOutOfBounds',
  'MyAddressError',
  'InternalError',
};

const Set<String> _approvalFailures = {
  'approval_broadcast_failed',
  'approval_transaction_failed',
  'allowance_reset_not_confirmed',
  'confirmed_allowance_insufficient',
};

const Set<String> _txFailures = {
  'source_transaction_reverted',
  'source_transaction_not_confirmed',
};

const Set<String> _signingRejections = {
  'user_rejected',
  'timeout',
  'unsupported_method',
};

const Set<String> _preflightChecks = {
  'simulation',
  'target_allowlist',
  'spender_allowlist',
  'value_cap',
  'amount_bounds',
  'gas_bounds',
};

const List<String> _stageOrder = [
  'unknown',
  'bridging',
  'destination_pending',
  'refund_pending',
];

final RegExp _uuidPattern = RegExp(
  '^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}|[0-9a-fA-F]{32})$',
);

String _pairKey(String from, String to) => '$from->$to';

String _uuidFor(int seq) =>
    '${seq.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

String _txHash(String tag, int seq) =>
    '0x$tag${seq.toRadixString(16).padLeft(62, '0')}';

String _normalizeUuid(String uuid) {
  final lower = uuid.toLowerCase();
  if (lower.length != 32) return lower;
  return '${lower.substring(0, 8)}-${lower.substring(8, 12)}-'
      '${lower.substring(12, 16)}-${lower.substring(16, 20)}-'
      '${lower.substring(20)}';
}

Map<String, dynamic> _params(Map<String, dynamic> request) {
  final params = request['params'];
  return params is Map ? Map<String, dynamic>.from(params) : const {};
}

String _numberText(Object? value) =>
    value is String ? value : _f64Text(value! as num);

/// Rust's `f64` display: no trailing `.0` on whole numbers.
String _f64Text(num value) =>
    value is double && value.isFinite && value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();

/// `MmNumber::to_decimal`: rational, so trailing zeros are gone.
String _decimalText(String value) =>
    Decimal.tryParse(value)?.toString() ?? value;

bool _sameNumber(String a, String b) {
  final left = Decimal.tryParse(a);
  final right = Decimal.tryParse(b);
  return left != null && left == right;
}

Decimal _decimal(String value, String name) {
  final parsed = Decimal.tryParse(value);
  if (parsed == null || parsed < Decimal.zero) {
    throw ArgumentError.value(value, name, 'must be a non-negative decimal');
  }
  return parsed;
}

String _observedStage(String? substatus) => switch (substatus) {
  'WAIT_SOURCE_CONFIRMATIONS' => 'bridging',
  'WAIT_DESTINATION_TRANSACTION' => 'destination_pending',
  'REFUND_IN_PROGRESS' => 'refund_pending',
  _ => 'unknown',
};

/// `RoutedSwapTrackingStage::advance`: a refund latches, other stages only
/// move forward.
String _advanceStage(String current, String observed) {
  if (observed == 'refund_pending' || current == 'refund_pending') {
    return 'refund_pending';
  }
  return _stageOrder.indexOf(observed) > _stageOrder.indexOf(current)
      ? observed
      : current;
}

/// What goes over the wire: plain decoded JSON, so a caller can neither
/// mutate fixture state nor receive a value KDF could not send.
Map<String, dynamic> _wireMap(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class _ScriptedQuoteError {
  _ScriptedQuoteError(this.error, this.remaining);

  final RoutedSwapQuoteError error;
  int? remaining;
}

enum _EventKind {
  progress,
  completed,
  failed,
  gasSpent,
  approvalHash,
  cancelled,
  aborted,
}

/// `RoutedSwapEvent`.
class _Event {
  _Event._(
    this.at,
    this.kind, {
    this.details,
    this.txHash,
    this.coin,
    this.amount,
  });

  _Event.progress(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.progress, details: details);

  _Event.completed(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.completed, details: details);

  _Event.failed(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.failed, details: details);

  _Event.gas(int at, _Gas gas)
    : this._(
        at,
        _EventKind.gasSpent,
        txHash: gas.txHash,
        coin: gas.coin,
        amount: gas.amount,
      );

  _Event.approvalHash(int at, String txHash)
    : this._(at, _EventKind.approvalHash, txHash: txHash);

  _Event.cancelled(int at) : this._(at, _EventKind.cancelled);

  _Event.aborted(int at) : this._(at, _EventKind.aborted);

  final int at;
  final _EventKind kind;
  final Map<String, dynamic>? details;
  final String? txHash;
  final String? coin;
  final String? amount;

  /// Gas and approval metadata never replace the task state.
  bool get isMetadata =>
      kind == _EventKind.gasSpent || kind == _EventKind.approvalHash;

  bool get isTerminal =>
      kind == _EventKind.completed ||
      kind == _EventKind.failed ||
      kind == _EventKind.cancelled ||
      kind == _EventKind.aborted;
}

class _Gas {
  const _Gas(this.txHash, this.coin, this.amount);

  final String txHash;
  final String coin;
  final String amount;
}

class _Terminal {
  const _Terminal({required this.ok, required this.details});

  final bool ok;
  final Map<String, dynamic> details;

  _Event event(int at) =>
      ok ? _Event.completed(at, details) : _Event.failed(at, details);
}

class _Transition {
  _Transition.progress(Map<String, dynamic> this.details, this.gas)
    : terminal = null,
      tracking = details['state'] == RoutedSwapRunState.trackingBridge.wire;

  _Transition.terminal(_Terminal this.terminal, this.gas)
    : details = null,
      tracking = false;

  final Map<String, dynamic>? details;
  final _Terminal? terminal;
  final List<_Gas> gas;
  final bool tracking;
}

/// A run resolved against its `init` request.
class _Plan {
  _Plan._({
    required this.run,
    required this.uuid,
    required this.from,
    required this.to,
    required this.amount,
    required this.minToAmount,
    required this.route,
    required this.routeJson,
    required this.ladder,
    required this.error,
    required this.sourceTxHash,
    required this.gasCoin,
    required this.okDetails,
  });

  factory _Plan.resolve(
    RoutedSwapRun run, {
    required int seq,
    required String uuid,
    required String from,
    required String to,
    required String amount,
    required String minToAmount,
    required RoutedSwapQuote? displayedRoute,
  }) {
    final route =
        run.route ??
        displayedRoute ??
        RoutedSwapQuote(
          from: from,
          to: to,
          toAmount: minToAmount,
          toAmountMin: minToAmount,
        );
    if (route.from != from || route.to != to) {
      throw ArgumentError(
        'The run executes ${route.from} -> ${route.to} but init asked for '
        '$from -> $to.',
      );
    }
    if (route.amount != null && !_sameNumber(route.amount!, amount)) {
      throw ArgumentError(
        'The run executes ${route.amount} but init sells $amount; the engine '
        'rejects a provider route for a different source amount.',
      );
    }
    final guard = Decimal.parse(minToAmount);
    if (guard <= Decimal.zero || Decimal.parse(amount) <= Decimal.zero) {
      throw ArgumentError(
        'The engine rejects a non-positive amount or min_to_amount with '
        'AmountOutOfBounds before any task exists; script that with '
        'initFails(...).',
      );
    }

    var error = run.error;
    if (error == null && Decimal.parse(route.toAmountMin) < guard) {
      if (run.ladder != null || run.outcome != null) {
        throw ArgumentError(
          'The executed route guarantees ${route.toAmountMin}, below the '
          'accepted min_to_amount $minToAmount, so the engine fails the run '
          'QuoteWorsened while FetchingQuote.',
        );
      }
      error = RoutedSwapRunError.quoteWorsened(freshRoute: route);
    }
    final fresh = error?.freshRoute;
    if (fresh != null && Decimal.parse(fresh.toAmountMin) >= guard) {
      throw ArgumentError(
        'QuoteWorsened needs a fresh amount_min below the accepted '
        'min_to_amount $minToAmount; ${fresh.toAmountMin} passes the guard.',
      );
    }

    final source = run.sourceTxHash ?? _txHash('b0', seq);
    final url = run.providerExplorerUrl ?? 'https://scan.li.fi/tx/$source';
    final ladder =
        run.ladder ??
        _defaultLadder(
          run,
          route,
          error,
          run.approvalTxHashes ?? [_txHash('a1', seq), _txHash('a2', seq)],
          url,
        );
    RoutedSwapRun._checkLadder(
      ladder,
      crossChain: route.crossChain,
      error: error,
      outcome: run.outcome,
    );
    if (ladder.length > 1 && Decimal.parse(route.toAmountMin) < guard) {
      throw ArgumentError(
        'The executed route guarantees ${route.toAmountMin}, below the '
        'accepted min_to_amount $minToAmount: the engine fails QuoteWorsened '
        'while FetchingQuote and never reaches ${ladder.last.state.wire}.',
      );
    }

    final routeJson = route.toJson(amount: amount);
    return _Plan._(
      run: run,
      uuid: uuid,
      from: from,
      to: to,
      amount: amount,
      minToAmount: minToAmount,
      route: route,
      routeJson: routeJson,
      ladder: ladder,
      error: error,
      sourceTxHash: source,
      gasCoin:
          run.gasCoin ??
          route.approval?.gasCoin ??
          (route.gasCosts.isEmpty ? 'ETH' : route.gasCosts.first.coin),
      okDetails: error != null
          ? null
          : _okDetails(
              run,
              uuid: uuid,
              route: route,
              routeJson: routeJson,
              to: to,
              amount: amount,
              guard: guard,
              source: source,
              dest: run.destTxHash ?? _txHash('d0', seq),
              url: url,
            ),
    );
  }

  final RoutedSwapRun run;
  final String uuid;
  final String from;
  final String to;
  final String amount;
  final String minToAmount;
  final RoutedSwapQuote route;
  final Map<String, dynamic> routeJson;
  final List<RoutedSwapTick> ladder;
  final RoutedSwapRunError? error;
  final String sourceTxHash;
  final String gasCoin;
  final Map<String, dynamic>? okDetails;

  Map<String, dynamic> get initialDetails => _inProgress(ladder.first, null);

  /// Everything after the `FetchingQuote` persisted at init.
  List<_Transition> liveTransitions() =>
      transitions(ladder.sublist(1), previous: ladder.first);

  /// [ticks] then the terminal result. Stages restart from `unknown`, as
  /// each `track_bridge` call does.
  List<_Transition> transitions(
    List<RoutedSwapTick> ticks, {
    required RoutedSwapTick? previous,
  }) {
    final out = <_Transition>[];
    var stage = 'unknown';
    var before = previous;
    for (final tick in ticks) {
      String? tickStage;
      if (tick.state == RoutedSwapRunState.trackingBridge) {
        stage = _advanceStage(stage, _observedStage(tick.substatus));
        tickStage = stage;
      }
      out.add(
        _Transition.progress(_inProgress(tick, tickStage), _gasAfter(before)),
      );
      before = tick;
    }
    final error = this.error;
    final terminal = error == null
        ? _Terminal(ok: true, details: okDetails!)
        : _Terminal(
            ok: false,
            details: errorDetails(
              error,
              withRoute: ladder.last.state != RoutedSwapRunState.fetchingQuote,
            ),
          );
    final unconfirmed =
        error?.errorType == 'SwapTxFailed' &&
        error?.reason == 'source_transaction_not_confirmed';
    out.add(
      _Transition.terminal(
        terminal,
        unconfirmed ? const <_Gas>[] : _gasAfter(before),
      ),
    );
    return out;
  }

  /// `record_gas` runs once a transaction's confirmation wait ends, before
  /// the next transition is persisted.
  List<_Gas> _gasAfter(RoutedSwapTick? tick) {
    final approval = tick?.approveTxHash;
    if (approval != null) return [_Gas(approval, gasCoin, run.approvalGas)];
    if (tick?.state == RoutedSwapRunState.waitingSourceConfirmation) {
      return [_Gas(sourceTxHash, gasCoin, run.sourceGas)];
    }
    return const [];
  }

  /// `RoutedSwapInProgressStatus`: the tag first, then the fields, with
  /// `executed_route` on every state after `FetchingQuote`.
  Map<String, dynamic> _inProgress(RoutedSwapTick tick, String? stage) {
    final state = tick.state;
    return {
      'state': state.wire,
      'uuid': uuid,
      'provider': _provider,
      if (state != RoutedSwapRunState.fetchingQuote)
        'executed_route': routeJson,
      if (state == RoutedSwapRunState.approving)
        'approve_tx_hash': ?tick.approveTxHash,
      if (state == RoutedSwapRunState.broadcasting && tick.withSourceTxHash)
        'source_tx_hash': sourceTxHash,
      if (state == RoutedSwapRunState.waitingSourceConfirmation)
        'source_tx_hash': sourceTxHash,
      if (state == RoutedSwapRunState.trackingBridge) ...{
        'source_tx_hash': sourceTxHash,
        'stage': stage,
        'substatus': ?tick.substatus,
        'substatus_message': ?tick.substatusMessage,
        'provider_explorer_url': ?tick.providerExplorerUrl,
        'execution_duration_s': route.executionDurationS,
      },
    };
  }

  /// The serialized `MmError<RoutedSwapTaskError>`: `error`, `error_path`
  /// and `error_trace`, then `uuid`, `provider` and `executed_route` hoisted
  /// beside `error_type` — never inside `error_data`.
  Map<String, dynamic> errorDetails(
    RoutedSwapRunError error, {
    required bool withRoute,
  }) => {
    'error': error._messageFor(sourceTxHash),
    'error_path': 'swap_task',
    'error_trace': 'swap_task:1]',
    'uuid': uuid,
    'provider': _provider,
    if (withRoute) 'executed_route': routeJson,
    'error_type': error.errorType,
    'error_data': error._dataFor(sourceTxHash, amount),
  };

  static List<RoutedSwapTick> _defaultLadder(
    RoutedSwapRun run,
    RoutedSwapQuote route,
    RoutedSwapRunError? error,
    List<String> approvalHashes,
    String url,
  ) {
    final type = error?.errorType;
    final ladder = <RoutedSwapTick>[RoutedSwapTick.fetchingQuote];
    if (error != null && error._raisedByFreshQuote) return ladder;
    ladder.add(RoutedSwapTick.checkingAllowance);
    if (type == 'InsufficientBalance' ||
        type == 'PreflightRejected' ||
        type == 'InternalError') {
      return ladder;
    }
    final approval = route.approval;
    if (approval != null || type == 'ApprovalFailed') {
      final resets = approval?.resetsFirst ?? false;
      if (approvalHashes.length < (resets ? 2 : 1)) {
        throw ArgumentError('approvalTxHashes is short for this approval.');
      }
      final hashes = approvalHashes.take(resets ? 2 : 1).toList();
      ladder.add(const RoutedSwapTick.approving());
      if (type == 'ApprovalFailed') {
        switch (error!.reason) {
          case 'approval_broadcast_failed':
            break;
          case 'approval_transaction_failed' || 'allowance_reset_not_confirmed':
            ladder.add(RoutedSwapTick.approving(hashes.first));
          default:
            ladder.addAll(hashes.map(RoutedSwapTick.approving));
        }
        return ladder;
      }
      ladder.addAll(hashes.map(RoutedSwapTick.approving));
    }
    ladder.add(RoutedSwapTick.signing);
    if (type == 'SigningRejected') return ladder;
    ladder
      ..add(const RoutedSwapTick.broadcasting())
      ..add(RoutedSwapTick.waitingSourceConfirmation);
    if (type == 'SwapTxFailed' || !route.crossChain) return ladder;
    ladder
      ..add(const RoutedSwapTick.trackingBridge())
      ..addAll(run.tracking ?? const []);
    if (type == 'BridgeFailed') {
      return ladder..add(
        RoutedSwapTick.trackingBridge(
          substatus: error!.substatus,
          substatusMessage: error.substatusMessage,
          providerExplorerUrl: error.providerExplorerUrl,
        ),
      );
    }
    if (run.tracking != null) return ladder;
    return ladder..addAll(switch (run.outcome) {
      RoutedSwapRunOutcome.refunded => [
        RoutedSwapTick.trackingBridge(
          substatus: 'REFUND_IN_PROGRESS',
          substatusMessage: 'The refund is in progress.',
          providerExplorerUrl: url,
        ),
        RoutedSwapTick.trackingBridge(
          substatus: 'REFUNDED',
          substatusMessage: 'The transfer was refunded.',
          providerExplorerUrl: url,
        ),
      ],
      _ => [
        RoutedSwapTick.trackingBridge(
          substatus: 'WAIT_DESTINATION_TRANSACTION',
          substatusMessage: 'Waiting for the destination transaction.',
          providerExplorerUrl: url,
        ),
        if (run.outcome == RoutedSwapRunOutcome.partial)
          RoutedSwapTick.trackingBridge(
            substatus: 'PARTIAL',
            substatusMessage: 'The transfer was partially completed.',
            providerExplorerUrl: url,
          )
        else
          RoutedSwapTick.trackingBridge(
            substatus: 'COMPLETED',
            substatusMessage: 'The transfer is complete.',
            providerExplorerUrl: url,
          ),
      ],
    });
  }

  /// `RoutedSwapOutcome`, classified the way `terminal_status` classifies:
  /// `completed` only for the requested coin at or above the accepted
  /// minimum.
  static Map<String, dynamic> _okDetails(
    RoutedSwapRun run, {
    required String uuid,
    required RoutedSwapQuote route,
    required Map<String, dynamic> routeJson,
    required String to,
    required String amount,
    required Decimal guard,
    required String source,
    required String dest,
    required String url,
  }) {
    final outcome = run.outcome ?? RoutedSwapRunOutcome.completed;
    final head = {
      'outcome': outcome.wire,
      'uuid': uuid,
      'provider': _provider,
      'executed_route': routeJson,
    };
    if (!route.crossChain) {
      if (outcome != RoutedSwapRunOutcome.completed ||
          run.receivedCoin != null ||
          run.receivedSymbol != null ||
          run.receivedAmount != null ||
          run.destTxHash != null) {
        throw ArgumentError(
          'A same-chain swap only completes: it receives the executed '
          "route's quoted to.amount and has no destination transaction.",
        );
      }
      return {
        ...head,
        'received': {'coin': route.to, 'amount': route.toAmount},
        'source_tx_hash': source,
      };
    }

    final symbol = run.receivedSymbol;
    final coin = symbol != null
        ? null
        : run.receivedCoin ??
              (outcome == RoutedSwapRunOutcome.refunded ? route.from : to);
    final received =
        run.receivedAmount ??
        (outcome == RoutedSwapRunOutcome.refunded ? amount : route.toAmount);
    final requested = coin == to;
    final enough = _decimal(received, 'receivedAmount') >= guard;
    switch (outcome) {
      case RoutedSwapRunOutcome.completed:
        if (!requested || !enough) {
          throw ArgumentError(
            'The engine completes only the requested coin at or above the '
            'accepted minimum; this delivery is partial.',
          );
        }
      case RoutedSwapRunOutcome.partial:
        final classified = requested ? 'below_minimum' : 'intermediate_token';
        if (requested && enough || classified != run.partialReason) {
          throw ArgumentError(
            'The engine classifies this delivery as '
            '${requested && enough ? 'completed' : classified}, not '
            '${run.partialReason}.',
          );
        }
      case RoutedSwapRunOutcome.refunded:
        if (run.destTxHash != null) {
          throw ArgumentError('A refund has no destination transaction.');
        }
    }
    return {
      ...head,
      'partial_reason': ?run.partialReason,
      'received': {'coin': ?coin, 'symbol': ?symbol, 'amount': received},
      'source_tx_hash': source,
      if (outcome != RoutedSwapRunOutcome.refunded) 'dest_tx_hash': dest,
      'provider_explorer_url': url,
    };
  }
}

/// One swap: its durable record, its run and its live task.
class _Swap {
  _Swap({required this.plan, required this.createdAt});

  final _Plan plan;
  final int createdAt;
  final List<_Event> events = <_Event>[];

  /// Every task id this swap was ever registered under.
  final Set<int> taskIds = <int>{};
  List<_Transition> transitions = const [];
  int cursor = 0;
  int? taskId;

  /// Status reads of the current state.
  int observed = 0;

  String get uuid => plan.uuid;

  _Event get semantic => events.lastWhere((e) => !e.isMetadata);

  bool get isTerminal => semantic.isTerminal;

  Map<String, dynamic> get lastProgress =>
      events.lastWhere((e) => e.kind == _EventKind.progress).details!;

  /// The engine's current state, from the latest progress event.
  RoutedSwapRunState get engineState {
    final wire = lastProgress['state'];
    return RoutedSwapRunState.values.firstWhere((s) => s.wire == wire);
  }
}
