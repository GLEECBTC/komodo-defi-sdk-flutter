part of 'routed_swap_fixture.dart';

/// The scripted engine's answer to each routed-swap RPC.
extension _FixtureResponses on RoutedSwapFixture {
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
}
