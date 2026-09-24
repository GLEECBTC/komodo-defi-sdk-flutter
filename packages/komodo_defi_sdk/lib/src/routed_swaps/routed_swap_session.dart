part of 'routed_swap_manager.dart';

class _RoutedSwapHandle implements RoutedSwapHandle {
  _RoutedSwapHandle(this._session);

  final _RoutedSwapSession _session;

  @override
  String get uuid => _session.uuid;

  @override
  RoutedSwapProgress get latest => _session.latest;

  @override
  Stream<RoutedSwapProgress> get progress => _session.stream;

  @override
  Future<RoutedSwapProgress> get result => _session.result;

  @override
  Future<void> cancel() => _session.cancel();
}

/// Follows one swap: its task while it exists, polled as the truth with the
/// event stream as a nudge, and the durable record once the task is gone.
///
/// Runs independently of listeners — a screen closing must not stop a swap
/// from being followed — until the swap is terminal.
class _RoutedSwapSession {
  _RoutedSwapSession({
    required RoutedSwapManager manager,
    required this.uuid,
    required RoutedSwapProgress seed,
    int? taskId,
    this.offer,
  }) : _manager = manager,
       _taskId = taskId,
       _latest = seed;

  final RoutedSwapManager _manager;
  final String uuid;

  /// The offer the user accepted, for swaps started in this process.
  final RoutedSwapOffer? offer;

  int? _taskId;
  RoutedSwapProgress _latest;

  /// The last phase read from the live task — the only kind of observation
  /// that can prove a later failure happened before broadcast.
  RoutedSwapPhase? _lastLivePhase;
  final StreamController<RoutedSwapProgress> _updates =
      StreamController<RoutedSwapProgress>.broadcast();
  final Completer<RoutedSwapProgress> _result = Completer<RoutedSwapProgress>();

  Timer? _timer;
  StreamSubscription<void>? _nudges;
  var _refreshing = false;
  var _failures = 0;
  var _disposed = false;

  RoutedSwapProgress get latest => _latest;

  RoutedSwapPhase? get lastLivePhase => _lastLivePhase;

  bool get isDisposed => _disposed;

  Future<RoutedSwapProgress> get result => _result.future;

  Stream<RoutedSwapProgress> get stream => Stream.multi((out) {
    out.add(_latest);
    if (_updates.isClosed) {
      unawaited(out.close());
      return;
    }
    final subscription = _updates.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = subscription.cancel;
  });

  void start() {
    if (_latest.isTerminal) {
      final taskId = _taskId;
      if (taskId == null) {
        _finish();
      } else {
        unawaited(_settleTerminalSeed(taskId));
      }
      return;
    }
    final taskId = _taskId;
    if (taskId != null) {
      try {
        _nudges = _manager._taskNudges
            ?.call(taskId)
            .listen((_) => _refreshSoon(), onError: (_) {});
      } on Object {
        // A stream that will not start is not worth surfacing; polling covers
        // it.
      }
    }
    _schedule(_taskId != null ? _manager._pollInterval : Duration.zero);
  }

  void _refreshSoon() {
    if (_refreshing || _disposed || _latest.isTerminal) return;
    _timer?.cancel();
    unawaited(_refresh());
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed || _latest.isTerminal) return;
    _timer = Timer(delay, () => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    if (_refreshing || _disposed || _latest.isTerminal) return;
    _refreshing = true;
    var next = _taskId != null
        ? _manager._pollInterval
        : _manager._historyPollInterval;
    try {
      if (_taskId != null) {
        await _refreshFromTask(_taskId!);
      } else {
        await _refreshFromHistory();
      }
      _failures = 0;
      if (_latest.delayedSince != null && !_latest.isTerminal) {
        _emit(_latest.copyWith(clearDelayedSince: true));
      }
    } on rpc.RoutedSwapNoSuchTaskException {
      // The task is gone — cancelled, forgotten, or lost to a restart. The
      // swap itself may be entirely fine; the durable record decides.
      _taskId = null;
      next = Duration.zero;
    } on Object {
      _failures++;
      next = _backoff(next);
      if (_failures >= _manager._delayedAfterFailures &&
          _latest.delayedSince == null) {
        _emit(_latest.copyWith(delayedSince: DateTime.now()));
      }
    } finally {
      _refreshing = false;
    }
    if (_latest.isTerminal) {
      _finish();
    } else {
      _schedule(next);
    }
  }

  Duration _backoff(Duration base) {
    final factor = math.pow(2, math.min(_failures, 5)).toInt();
    final delay = base * factor;
    return delay > _manager._maxBackoff ? _manager._maxBackoff : delay;
  }

  Future<void> _refreshFromTask(int taskId) async {
    final response = await _manager._client.rpc.routedSwap.status(taskId);
    // KDF numbers tasks from zero again after a restart, so this id can now
    // belong to a different swap. Treat it as gone; history decides.
    if (response.details.uuid != uuid) {
      throw rpc.RoutedSwapNoSuchTaskException(
        message: 'Task $taskId now belongs to another swap',
        taskId: taskId,
      );
    }
    final progress = _manager._progressFromStatus(
      response.details,
      accepted: offer,
      previousExecuted: _latest.executedOffer,
      approvalTxHashes: _latest.approvalTxHashes,
      lastLivePhase: _lastLivePhase,
    );
    if (!progress.isTerminal) {
      _lastLivePhase = progress.phase;
      _emit(progress);
      return;
    }
    _emit(await _enriched(progress));
    unawaited(_forget(taskId));
  }

  /// [terminal], completed from the durable record — timestamps, every
  /// approval, the gas actually spent — when the record has caught up.
  Future<RoutedSwapProgress> _enriched(RoutedSwapProgress terminal) async {
    try {
      final entry = await _manager._entryFor(uuid);
      if (entry != null && entry.swap.isTerminal) {
        return _manager._progressFromEntry(
          entry,
          accepted: offer,
          previous: terminal,
          lastLivePhase: _lastLivePhase,
        );
      }
    } on Object {
      // The live terminal result stands on its own.
    }
    return terminal;
  }

  /// A swap whose very first read was already terminal still gets the
  /// durable record's details, and its task is still released.
  Future<void> _settleTerminalSeed(int taskId) async {
    _emit(await _enriched(_latest));
    await _forget(taskId);
    _finish();
  }

  Future<void> _refreshFromHistory() async {
    final entry = await _manager._entryFor(uuid);
    if (entry == null) throw RoutedSwapNotFoundException(uuid);
    _emit(
      _manager._progressFromEntry(
        entry,
        accepted: offer,
        previous: _latest,
        lastLivePhase: _lastLivePhase,
      ),
    );
  }

  /// Releases the finished task. The result has been read and emitted, and
  /// the durable record keeps it.
  Future<void> _forget(int taskId) async {
    _taskId = null;
    try {
      await _manager._client.rpc.routedSwap.status(
        taskId,
        forgetIfFinished: true,
      );
    } on Object {
      // Already gone is the same outcome.
    }
  }

  void _emit(RoutedSwapProgress progress) {
    if (_disposed || _updates.isClosed) return;
    if (progress == _latest) return;
    _latest = progress;
    _updates.add(progress);
    if (progress.isTerminal) _finish();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    unawaited(_nudges?.cancel());
    _nudges = null;
    if (!_result.isCompleted) _result.complete(_latest);
    if (!_updates.isClosed) unawaited(_updates.close());
  }

  Future<void> cancel() async {
    final taskId = _taskId;
    if (_latest.isTerminal) {
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.alreadyFinished,
      );
    }
    if (taskId == null) {
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.notAddressable,
      );
    }
    if (!_latest.canCancel) {
      throw RoutedSwapNotCancellableException(uuid, _latest.phase);
    }

    try {
      await _manager._client.rpc.routedSwap.cancel(taskId);
    } on rpc.RoutedSwapTaskAlreadyBroadcastException {
      _refreshSoon();
      throw RoutedSwapNotCancellableException(uuid, RoutedSwapPhase.sending);
    } on rpc.RoutedSwapTaskFinishedException {
      _refreshSoon();
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.alreadyFinished,
      );
    } on rpc.RoutedSwapNoSuchTaskException {
      // Gone already — an earlier cancel may have landed. The durable record
      // says whether this one is moot or impossible.
      _taskId = null;
      await _refreshNow();
      if (_latest.failure?.kind == RoutedSwapFailureKind.cancelled) return;
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: _latest.isTerminal
            ? RoutedSwapCancelRefusal.alreadyFinished
            : RoutedSwapCancelRefusal.notAddressable,
      );
    } on Object catch (error) {
      _refreshSoon();
      throw RoutedSwapCancelUnconfirmedException(uuid, error);
    }

    // Accepted: the task is removed and history records the cancellation.
    _taskId = null;
    await _refreshNow();
  }

  Future<void> _refreshNow() async {
    _timer?.cancel();
    while (_refreshing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _refresh();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _nudges?.cancel();
    _nudges = null;
    if (!_updates.isClosed) await _updates.close();
  }
}
