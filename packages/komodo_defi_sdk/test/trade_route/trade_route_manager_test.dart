// Named callback aliases keep the fake gateway's scripted surface readable.
// ignore_for_file: avoid_private_typedef_functions

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/trade_route/trade_route_manager.dart';
import 'package:test/test.dart';

const _routeId = '41f12b3c-79ac-42e7-bde9-5d43bdd1c1cb';
const _secondRouteId = 'cd735b9a-9733-41c2-90f0-c34c18e45364';
const _evaluationId = '8d0add79-50fb-4526-9e83-3a0614c0a556';
const _candidateId = '0e769fe4-3754-47ad-85b6-c5d4c775cdd9';
const _actionId = 'cc73ef2d-d2bc-4e71-bd59-acf7cb5888aa';
const _timestamp = '2026-07-15T12:00:00Z';
const _replacementExpiry = '2099-07-15T12:30:00Z';
const _replacementProposalDigest = 'replacement-proposal-digest';

void main() {
  group('TradeRouteManager lifecycle', () {
    test('uses the durable route ID for its deterministic key', () {
      expect(
        TradeRouteManager.idempotencyKeyFor(_routeId),
        'trade-route:$_routeId',
      );
    });

    test('observation cancel and dispose never cancel the backend', () async {
      final gateway = _FakeTradeRouteRpcGateway()
        ..statusHandler = ({required taskId, required forgetIfFinished}) async {
          return _taskStatusResponse();
        };
      final manager = TradeRouteManager.withGateway(
        gateway: gateway,
        defaultPollingInterval: const Duration(hours: 1),
      );
      addTearDown(manager.dispose);
      const task = TradeRouteTaskHandle(routeExecutionId: _routeId, taskId: 7);

      final firstSeen = Completer<void>();
      final subscription = manager.observeStatus(task).listen((_) {
        if (!firstSeen.isCompleted) firstSeen.complete();
      });
      await firstSeen.future.timeout(const Duration(seconds: 1));
      await subscription.cancel();

      final secondSeen = Completer<void>();
      final secondSubscription = manager.observeStatus(task).listen((_) {
        if (!secondSeen.isCompleted) secondSeen.complete();
      });
      await secondSeen.future.timeout(const Duration(seconds: 1));
      await manager.dispose();
      await secondSubscription.cancel();

      expect(gateway.cancelledRouteIds, isEmpty);
      expect(gateway.forgetIfFinishedValues, everyElement(isFalse));
    });

    test('every one-shot status lookup keeps the task attached', () async {
      final gateway = _FakeTradeRouteRpcGateway()
        ..statusHandler = ({required taskId, required forgetIfFinished}) async {
          return _taskStatusResponse();
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      await manager.pollStatus(
        const TradeRouteTaskHandle(routeExecutionId: _routeId, taskId: 11),
      );

      expect(gateway.statusTaskIds, [11]);
      expect(gateway.forgetIfFinishedValues, [false]);
    });
  });

  group('TradeRouteManager controls', () {
    test('only explicit current server controls can cancel or stop', () async {
      final executionResponses = Queue<RouteExecutionDetailsResponse>.of([
        _executionResponse(),
        _executionResponse(),
        _executionResponse(canCancel: true),
        _executionResponse(canStopAfterCurrent: true),
        _executionResponse(canCancel: true, reconciliationOnly: true),
      ]);
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return executionResponses.removeFirst();
        }
        ..cancelHandler = ({required routeExecutionId}) async {
          return _cancelResponse();
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      await expectLater(
        manager.cancelTradeRoute(routeExecutionId: _routeId),
        throwsA(isA<TradeRouteControlNotAuthorizedException>()),
      );
      await expectLater(
        manager.stopAfterCurrent(routeExecutionId: _routeId),
        throwsA(isA<TradeRouteControlNotAuthorizedException>()),
      );
      await manager.cancelTradeRoute(routeExecutionId: _routeId);
      await manager.stopAfterCurrent(routeExecutionId: _routeId);
      await expectLater(
        manager.cancelTradeRoute(routeExecutionId: _routeId),
        throwsA(isA<TradeRouteControlNotAuthorizedException>()),
      );

      expect(gateway.cancelledRouteIds, [_routeId, _routeId]);
    });

    test('unknown allowed actions fail closed before delivery', () async {
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            canStopAfterCurrent: true,
            pendingAllowedActions: const ['future_action'],
          );
        }
        ..userActionHandler = ({required taskId, required userAction}) async =>
            _actionResponse();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      await expectLater(
        manager.deliverUserAction(
          task: const TradeRouteTaskHandle(
            routeExecutionId: _routeId,
            taskId: 12,
          ),
          userAction: RouteExecutionUserAction.stopAfterCurrent(
            actionId: _actionId,
            expectedStateRevision: 8,
          ),
        ),
        throwsA(isA<TradeRouteActionNotAuthorizedException>()),
      );

      expect(gateway.deliveredTaskIds, isEmpty);
    });

    test(
      'unknown server state fails closed despite advertised controls',
      () async {
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              canCancel: true,
              routePhase: 'future_route_phase',
            );
          }
          ..cancelHandler = ({required routeExecutionId}) async {
            return _cancelResponse();
          };
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.cancelTradeRoute(routeExecutionId: _routeId),
          throwsA(isA<TradeRouteControlNotAuthorizedException>()),
        );

        expect(gateway.cancelledRouteIds, isEmpty);
      },
    );

    test('delivery success is exposed only as an acknowledgement', () async {
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            canStopAfterCurrent: true,
            pendingAllowedActions: const ['stop_after_current'],
          );
        }
        ..userActionHandler = ({required taskId, required userAction}) async =>
            _actionResponse();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      final acknowledgement = await manager.deliverUserAction(
        task: const TradeRouteTaskHandle(
          routeExecutionId: _routeId,
          taskId: 13,
        ),
        userAction: RouteExecutionUserAction.stopAfterCurrent(
          actionId: _actionId,
          expectedStateRevision: 8,
        ),
      );

      expect(acknowledgement.result, 'success');
      expect(acknowledgement.wasDelivered, isTrue);
      expect(acknowledgement.routeExecutionId, _routeId);
      expect(gateway.deliveredTaskIds, [13]);
    });

    test('exact authoritative replacement authority is delivered', () async {
      final replacement = _replacementStageConsent();
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            pendingAllowedActions: const ['accept_replacement'],
            pendingReason: 'quote_changed',
            replacementSummary: _replacementSummaryJson(replacement),
          );
        }
        ..userActionHandler = ({required taskId, required userAction}) async =>
            _actionResponse();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      final acknowledgement = await manager.deliverUserAction(
        task: const TradeRouteTaskHandle(
          routeExecutionId: _routeId,
          taskId: 14,
        ),
        userAction: RouteExecutionUserAction.acceptReplacement(
          actionId: _actionId,
          expectedStateRevision: 8,
          proposalDigest: _replacementProposalDigest,
          replacementStageConsent: replacement,
        ),
      );

      expect(acknowledgement.wasDelivered, isTrue);
      expect(gateway.deliveredTaskIds, [14]);
    });

    for (final missingValue in const [
      'replacement summary',
      'replacement stage consent',
    ]) {
      test('missing $missingValue fails closed before delivery', () async {
        final replacement = _replacementStageConsent();
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              pendingAllowedActions: const ['accept_replacement'],
              pendingReason: 'quote_changed',
              replacementSummary: missingValue == 'replacement summary'
                  ? null
                  : _replacementSummaryJson(null),
            );
          }
          ..userActionHandler =
              ({required taskId, required userAction}) async =>
                  _actionResponse();
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.deliverUserAction(
            task: const TradeRouteTaskHandle(
              routeExecutionId: _routeId,
              taskId: 15,
            ),
            userAction: RouteExecutionUserAction.acceptReplacement(
              actionId: _actionId,
              expectedStateRevision: 8,
              proposalDigest: _replacementProposalDigest,
              replacementStageConsent: replacement,
            ),
          ),
          throwsA(isA<TradeRouteActionNotAuthorizedException>()),
        );

        expect(gateway.deliveredTaskIds, isEmpty);
      });
    }

    test(
      'expired replacement authority fails closed before delivery',
      () async {
        final replacement = _replacementStageConsent();
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              pendingAllowedActions: const ['accept_replacement'],
              pendingReason: 'quote_changed',
              replacementSummary: _replacementSummaryJson(
                replacement,
                expiresAt: '2000-07-15T12:30:00Z',
              ),
            );
          }
          ..userActionHandler =
              ({required taskId, required userAction}) async =>
                  _actionResponse();
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.deliverUserAction(
            task: const TradeRouteTaskHandle(
              routeExecutionId: _routeId,
              taskId: 16,
            ),
            userAction: RouteExecutionUserAction.acceptReplacement(
              actionId: _actionId,
              expectedStateRevision: 8,
              proposalDigest: _replacementProposalDigest,
              replacementStageConsent: replacement,
            ),
          ),
          throwsA(isA<TradeRouteActionNotAuthorizedException>()),
        );

        expect(gateway.deliveredTaskIds, isEmpty);
      },
    );

    test(
      'expired replacement stage consent fails closed before delivery',
      () async {
        final replacement = _replacementStageConsent(
          consentExpiry: '2000-07-15T12:30:00Z',
        );
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              pendingAllowedActions: const ['accept_replacement'],
              pendingReason: 'quote_changed',
              replacementSummary: _replacementSummaryJson(replacement),
            );
          }
          ..userActionHandler =
              ({required taskId, required userAction}) async =>
                  _actionResponse();
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.deliverUserAction(
            task: const TradeRouteTaskHandle(
              routeExecutionId: _routeId,
              taskId: 17,
            ),
            userAction: RouteExecutionUserAction.acceptReplacement(
              actionId: _actionId,
              expectedStateRevision: 8,
              proposalDigest: _replacementProposalDigest,
              replacementStageConsent: replacement,
            ),
          ),
          throwsA(isA<TradeRouteActionNotAuthorizedException>()),
        );

        expect(gateway.deliveredTaskIds, isEmpty);
      },
    );

    test(
      'non-executable replacement authority fails closed before delivery',
      () async {
        final replacement = _replacementStageConsent(mode: 'future_mode');
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              pendingAllowedActions: const ['accept_replacement'],
              pendingReason: 'quote_changed',
              replacementSummary: _replacementSummaryJson(replacement),
            );
          }
          ..userActionHandler =
              ({required taskId, required userAction}) async =>
                  _actionResponse();
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.deliverUserAction(
            task: const TradeRouteTaskHandle(
              routeExecutionId: _routeId,
              taskId: 17,
            ),
            userAction: RouteExecutionUserAction.acceptReplacement(
              actionId: _actionId,
              expectedStateRevision: 8,
              proposalDigest: _replacementProposalDigest,
              replacementStageConsent: replacement,
            ),
          ),
          throwsA(isA<TradeRouteActionNotAuthorizedException>()),
        );

        expect(gateway.deliveredTaskIds, isEmpty);
      },
    );

    test('mismatched proposal digest fails closed before delivery', () async {
      final replacement = _replacementStageConsent();
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            pendingAllowedActions: const ['accept_replacement'],
            pendingReason: 'quote_changed',
            replacementSummary: _replacementSummaryJson(replacement),
          );
        }
        ..userActionHandler = ({required taskId, required userAction}) async =>
            _actionResponse();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      await expectLater(
        manager.deliverUserAction(
          task: const TradeRouteTaskHandle(
            routeExecutionId: _routeId,
            taskId: 18,
          ),
          userAction: RouteExecutionUserAction.acceptReplacement(
            actionId: _actionId,
            expectedStateRevision: 8,
            proposalDigest: 'different-proposal-digest',
            replacementStageConsent: replacement,
          ),
        ),
        throwsA(isA<TradeRouteActionNotAuthorizedException>()),
      );

      expect(gateway.deliveredTaskIds, isEmpty);
    });

    test(
      'mismatched full stage consent fails closed before delivery',
      () async {
        final replacement = _replacementStageConsent();
        final submitted = _replacementStageConsent(
          resolvedSourceAddress: '0x4444444444444444444444444444444444444444',
        );
        final gateway = _FakeTradeRouteRpcGateway()
          ..getExecutionHandler = ({required routeExecutionId}) async {
            return _executionResponse(
              pendingAllowedActions: const ['accept_replacement'],
              pendingReason: 'quote_changed',
              replacementSummary: _replacementSummaryJson(replacement),
            );
          }
          ..userActionHandler =
              ({required taskId, required userAction}) async =>
                  _actionResponse();
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.deliverUserAction(
            task: const TradeRouteTaskHandle(
              routeExecutionId: _routeId,
              taskId: 19,
            ),
            userAction: RouteExecutionUserAction.acceptReplacement(
              actionId: _actionId,
              expectedStateRevision: 8,
              proposalDigest: _replacementProposalDigest,
              replacementStageConsent: submitted,
            ),
          ),
          throwsA(isA<TradeRouteActionNotAuthorizedException>()),
        );

        expect(gateway.deliveredTaskIds, isEmpty);
      },
    );

    test('invalid stage-consent digest fails closed before delivery', () async {
      final replacement = _replacementStageConsent(validDigest: false);
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            pendingAllowedActions: const ['accept_replacement'],
            pendingReason: 'quote_changed',
            replacementSummary: _replacementSummaryJson(replacement),
          );
        }
        ..userActionHandler = ({required taskId, required userAction}) async =>
            _actionResponse();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      await expectLater(
        manager.deliverUserAction(
          task: const TradeRouteTaskHandle(
            routeExecutionId: _routeId,
            taskId: 20,
          ),
          userAction: RouteExecutionUserAction.acceptReplacement(
            actionId: _actionId,
            expectedStateRevision: 8,
            proposalDigest: _replacementProposalDigest,
            replacementStageConsent: replacement,
          ),
        ),
        throwsA(isA<TradeRouteActionNotAuthorizedException>()),
      );

      expect(gateway.deliveredTaskIds, isEmpty);
    });
  });

  test(
    'reattachment reads the durable journal before requesting a task',
    () async {
      final gateway = _FakeTradeRouteRpcGateway()
        ..getExecutionHandler = ({required routeExecutionId}) async {
          return _executionResponse();
        }
        ..initHandler =
            ({
              required routeExecutionId,
              required idempotencyKey,
              required routeConsent,
            }) async => NewTaskResponse(mmrpc: '2.0', taskId: 77);
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      final attached = await manager.reattachTradeRoute(
        routeExecutionId: _routeId,
      );

      expect(gateway.calls, ['get:$_routeId', 'init:$_routeId']);
      expect(gateway.initIdempotencyKeys, ['trade-route:$_routeId']);
      expect(
        gateway.initConsents.single,
        same(attached.execution.routeConsent),
      );
      expect(gateway.initConsents.single, isA<RouteActivityConsent>());
      expect(attached.execution.routeExecutionId, _routeId);
      expect(attached.task.routeExecutionId, _routeId);
      expect(attached.task.taskId, 77);
    },
  );

  test(
    'sparse Activity pages continue and preserve authoritative order',
    () async {
      final responses = Queue<ListRouteExecutionsResponse>.of([
        _listResponse(executions: const [], nextCursor: 'cursor-1'),
        _listResponse(
          executions: [_summaryJson(_secondRouteId), _summaryJson(_routeId)],
          nextCursor: null,
        ),
      ]);
      final gateway = _FakeTradeRouteRpcGateway()
        ..listHandler = ({required limit, state, cursor}) async {
          return responses.removeFirst();
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);

      final executions = await manager.listAllExecutions(
        state: RouteActivityState.active,
        limit: 25,
      );

      expect(executions.map((item) => item.routeExecutionId), [
        _secondRouteId,
        _routeId,
      ]);
      expect(gateway.listCursors, [null, 'cursor-1']);
      expect(gateway.listLimits, [25, 25]);
    },
  );

  test('one-shot Activity page forwards cursor and validates limit', () async {
    final gateway = _FakeTradeRouteRpcGateway()
      ..listHandler = ({required limit, state, cursor}) async {
        return _listResponse(
          executions: [_summaryJson(_routeId)],
          nextCursor: 'cursor-8',
        );
      };
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);

    final page = await manager.listExecutions(
      state: RouteActivityState.completed,
      cursor: 'cursor-7',
      limit: 17,
    );

    expect(page.executions.single.routeExecutionId, _routeId);
    expect(page.nextCursor, 'cursor-8');
    expect(gateway.listCursors, ['cursor-7']);
    expect(gateway.listLimits, [17]);
    await expectLater(
      manager.listExecutions(limit: 0),
      throwsA(isA<RangeError>()),
    );
    await expectLater(
      manager.listExecutions(limit: 101),
      throwsA(isA<RangeError>()),
    );
    expect(gateway.listCursors, ['cursor-7']);
  });

  group('TradeRouteManager preparation', () {
    test(
      'forwards the exact preparation authority and returns consent',
      () async {
        final response = _preparedExecutionResponse();
        final gateway = _FakeTradeRouteRpcGateway()
          ..prepareHandler =
              ({
                required evaluationId,
                required candidateId,
                required candidateDigest,
                required finalMinimumReceive,
                required consentExpiresAt,
                required stages,
              }) async => response;
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);
        final limits = _prepareStageLimits();

        final result = await manager.prepareExecution(
          evaluationId: _evaluationId,
          candidateId: _candidateId,
          candidateDigest: 'candidate-digest',
          finalMinimumReceive: '90',
          consentExpiresAt: DateTime.parse('2026-07-15T12:30:00Z'),
          stages: [limits],
        );

        expect(result.routeConsent, same(response.result.routeConsent));
        expect(gateway.preparedEvaluationIds, [_evaluationId]);
        expect(gateway.preparedCandidateIds, [_candidateId]);
        expect(gateway.preparedCandidateDigests, ['candidate-digest']);
        expect(gateway.preparedFinalMinimumReceives, ['90']);
        expect(gateway.preparedConsentExpiries, [
          DateTime.parse('2026-07-15T12:30:00Z'),
        ]);
        expect(gateway.preparedStageLimits.single.single, same(limits));
      },
    );

    for (final tamper in const [
      'prepared review digest',
      'stage consent digest',
      'route consent digest',
    ]) {
      test('rejects a mismatched $tamper', () async {
        final gateway = _FakeTradeRouteRpcGateway()
          ..prepareHandler =
              ({
                required evaluationId,
                required candidateId,
                required candidateDigest,
                required finalMinimumReceive,
                required consentExpiresAt,
                required stages,
              }) async => _tamperedPreparedExecutionResponse(tamper);
        final manager = TradeRouteManager.withGateway(gateway: gateway);
        addTearDown(manager.dispose);

        await expectLater(
          manager.prepareExecution(
            evaluationId: _evaluationId,
            candidateId: _candidateId,
            candidateDigest: 'candidate-digest',
            finalMinimumReceive: '90',
            consentExpiresAt: DateTime.parse('2026-07-15T12:30:00Z'),
            stages: [_prepareStageLimits()],
          ),
          throwsStateError,
        );
      });
    }
  });
}

typedef _GetExecutionHandler =
    Future<RouteExecutionDetailsResponse> Function({
      required String routeExecutionId,
    });
typedef _InitHandler =
    Future<NewTaskResponse> Function({
      required String routeExecutionId,
      required String idempotencyKey,
      required TradeRouteInitConsent routeConsent,
    });
typedef _StatusHandler =
    Future<TradeRouteTaskStatusResponse> Function({
      required int taskId,
      required bool forgetIfFinished,
    });
typedef _CancelHandler =
    Future<RouteCancelResponse> Function({required String routeExecutionId});
typedef _UserActionHandler =
    Future<RouteActionResponse> Function({
      required int taskId,
      required RouteExecutionUserAction userAction,
    });
typedef _ListHandler =
    Future<ListRouteExecutionsResponse> Function({
      required int limit,
      RouteActivityState? state,
      String? cursor,
    });

typedef _PrepareHandler =
    Future<PrepareExecutionResponse> Function({
      required String evaluationId,
      required String candidateId,
      required String candidateDigest,
      required String finalMinimumReceive,
      required DateTime consentExpiresAt,
      required List<PrepareExecutionStageLimits> stages,
    });

final class _FakeTradeRouteRpcGateway
    implements TradeRouteRpcGateway, TradeRouteDiscoveryRpcGateway {
  _GetExecutionHandler? getExecutionHandler;
  _InitHandler? initHandler;
  _StatusHandler? statusHandler;
  _CancelHandler? cancelHandler;
  _UserActionHandler? userActionHandler;
  _ListHandler? listHandler;
  _PrepareHandler? prepareHandler;

  final calls = <String>[];
  final statusTaskIds = <int>[];
  final forgetIfFinishedValues = <bool>[];
  final cancelledRouteIds = <String>[];
  final deliveredTaskIds = <int>[];
  final initIdempotencyKeys = <String>[];
  final initConsents = <TradeRouteInitConsent>[];
  final listCursors = <String?>[];
  final listLimits = <int>[];
  final preparedEvaluationIds = <String>[];
  final preparedCandidateIds = <String>[];
  final preparedCandidateDigests = <String>[];
  final preparedFinalMinimumReceives = <String>[];
  final preparedConsentExpiries = <DateTime>[];
  final preparedStageLimits = <List<PrepareExecutionStageLimits>>[];

  @override
  Future<TradeRouteCapabilitiesResponse> capabilities({
    required List<ExternalProvider> providers,
    required List<String> tickers,
    ProviderMetadataSnapshot? providerSnapshot,
  }) => throw StateError('Unexpected capabilities call');

  @override
  Future<RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) {
    calls.add('cancel:$routeExecutionId');
    cancelledRouteIds.add(routeExecutionId);
    final handler = cancelHandler;
    if (handler == null) throw StateError('Unexpected cancelTradeRoute call');
    return handler(routeExecutionId: routeExecutionId);
  }

  @override
  Future<RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  }) {
    calls.add('get:$routeExecutionId');
    final handler = getExecutionHandler;
    if (handler == null) throw StateError('Unexpected getExecution call');
    return handler(routeExecutionId: routeExecutionId);
  }

  @override
  Future<NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required TradeRouteInitConsent routeConsent,
  }) {
    calls.add('init:$routeExecutionId');
    initIdempotencyKeys.add(idempotencyKey);
    initConsents.add(routeConsent);
    final handler = initHandler;
    if (handler == null) throw StateError('Unexpected initTradeRoute call');
    return handler(
      routeExecutionId: routeExecutionId,
      idempotencyKey: idempotencyKey,
      routeConsent: routeConsent,
    );
  }

  @override
  Future<ListRouteExecutionsResponse> listExecutions({
    required int limit,
    RouteActivityState? state,
    String? cursor,
  }) {
    calls.add('list:${cursor ?? 'first'}');
    listCursors.add(cursor);
    listLimits.add(limit);
    final handler = listHandler;
    if (handler == null) throw StateError('Unexpected listExecutions call');
    return handler(state: state, cursor: cursor, limit: limit);
  }

  @override
  Future<PrepareExecutionResponse> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
  }) {
    calls.add('prepare:$candidateId');
    preparedEvaluationIds.add(evaluationId);
    preparedCandidateIds.add(candidateId);
    preparedCandidateDigests.add(candidateDigest);
    preparedFinalMinimumReceives.add(finalMinimumReceive);
    preparedConsentExpiries.add(consentExpiresAt);
    preparedStageLimits.add(List.unmodifiable(stages));
    final handler = prepareHandler;
    if (handler == null) throw StateError('Unexpected prepareExecution call');
    return handler(
      evaluationId: evaluationId,
      candidateId: candidateId,
      candidateDigest: candidateDigest,
      finalMinimumReceive: finalMinimumReceive,
      consentExpiresAt: consentExpiresAt,
      stages: stages,
    );
  }

  @override
  Future<TradeRouteQuoteResponse> quote({
    required TradeIntent intent,
    required List<RouteSource> routeSources,
    required RankingPolicy rankingPolicy,
    ValuationSnapshot? valuationSnapshot,
  }) => throw StateError('Unexpected quote call');

  @override
  Future<TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  }) {
    calls.add('status:$taskId');
    statusTaskIds.add(taskId);
    forgetIfFinishedValues.add(forgetIfFinished);
    final handler = statusHandler;
    if (handler == null) throw StateError('Unexpected tradeRouteStatus call');
    return handler(taskId: taskId, forgetIfFinished: forgetIfFinished);
  }

  @override
  Future<RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required RouteExecutionUserAction userAction,
  }) {
    calls.add('action:$taskId');
    deliveredTaskIds.add(taskId);
    final handler = userActionHandler;
    if (handler == null) {
      throw StateError('Unexpected tradeRouteUserAction call');
    }
    return handler(taskId: taskId, userAction: userAction);
  }
}

RouteExecutionDetailsResponse _executionResponse({
  bool canCancel = false,
  bool canStopAfterCurrent = false,
  bool reconciliationOnly = false,
  List<String>? pendingAllowedActions,
  String pendingReason = 'recovery_required',
  Map<String, dynamic>? replacementSummary,
  String routePhase = 'validating',
}) => RouteExecutionDetailsResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'route_execution_id': _routeId,
    'activity_state': 'active',
    'route_consent': _routeConsentJson(),
    'candidate': _candidateJson(),
    'resolved_source_address': '0x1111111111111111111111111111111111111111',
    'recipient_address': '0x2222222222222222222222222222222222222222',
    'status': _statusJson(
      canCancel: canCancel,
      canStopAfterCurrent: canStopAfterCurrent,
      reconciliationOnly: reconciliationOnly,
      pendingAllowedActions: pendingAllowedActions,
      pendingReason: pendingReason,
      replacementSummary: replacementSummary,
      routePhase: routePhase,
    ),
    'route_revisions': <Object>[],
    'terminal_error': null,
    'created_at': _timestamp,
    'updated_at': _timestamp,
    'completed_at': null,
  },
});

TradeRouteTaskStatusResponse _taskStatusResponse() =>
    TradeRouteTaskStatusResponse.parse({
      'mmrpc': '2.0',
      'result': {'status': 'InProgress', 'details': _statusJson()},
    });

RouteCancelResponse _cancelResponse() => RouteCancelResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'outcome': 'cancelled',
    'phase': 'validating',
    'stop_after_current': false,
    'tx_hashes': <String>[],
  },
});

RouteActionResponse _actionResponse() =>
    RouteActionResponse.parse({'mmrpc': '2.0', 'result': 'success'});

ListRouteExecutionsResponse _listResponse({
  required List<Map<String, dynamic>> executions,
  required String? nextCursor,
}) => ListRouteExecutionsResponse.parse({
  'mmrpc': '2.0',
  'result': {'executions': executions, 'next_cursor': nextCursor},
});

Map<String, dynamic> _statusJson({
  bool canCancel = false,
  bool canStopAfterCurrent = false,
  bool reconciliationOnly = false,
  List<String>? pendingAllowedActions,
  String pendingReason = 'recovery_required',
  Map<String, dynamic>? replacementSummary,
  String routePhase = 'validating',
}) => {
  'route_execution_id': _routeId,
  'stage_index': 0,
  'phase': 'planned',
  'route_phase': routePhase,
  'state_revision': 8,
  'pending_user_action': pendingAllowedActions == null
      ? null
      : {
          'action_id': _actionId,
          'reason': pendingReason,
          'allowed_actions': pendingAllowedActions,
          'replacement_summary': replacementSummary,
        },
  'stop_after_current': false,
  'tx_hashes': <String>[],
  'actual_holding': null,
  'raw_provider_status': null,
  'raw_provider_substatus': null,
  'receiving_evidence': null,
  'refund_evidence': null,
  'approval_recovery': null,
  'stage_results': <Object>[],
  'controls': {
    'can_cancel': canCancel,
    'can_stop_after_current': canStopAfterCurrent,
    'reconciliation_only': reconciliationOnly,
  },
  'created_at': _timestamp,
  'completed_at': null,
  'updated_at': _timestamp,
};

Map<String, dynamic> _routeConsentJson() => {
  'consent_type': 'activity_reattachment',
  'digest_version': 1,
  'evaluation_id': _evaluationId,
  'candidate_id': _candidateId,
  'candidate_digest': 'candidate-digest',
  'route_intent': _intentJson(),
  'external_stage_consents': <Object>[],
  'atomic_order_guards': <Object>[],
  'mode': 'sign_and_broadcast',
  'consent_expires_at': '2026-07-15T12:30:00Z',
  'route_consent_digest': 'route-consent-digest',
};

Map<String, dynamic> _intentJson() => {
  'from_asset': _assetJson('ETH'),
  'to_asset': _assetJson('MATIC'),
  'source_amount': '100',
  'minimum_receive': '90',
  'slippage_bps': 50,
  'source_address': {'selector_type': 'active'},
  'recipient': '0x2222222222222222222222222222222222222222',
  'tool_policy': {
    'bridges': {'allow': <String>[], 'deny': <String>[], 'prefer': <String>[]},
    'exchanges': {
      'allow': <String>[],
      'deny': <String>[],
      'prefer': <String>[],
    },
  },
  'consent_expires_at': '2026-07-15T12:30:00Z',
};

Map<String, dynamic> _candidateJson() => {
  'candidate_id': _candidateId,
  'candidate_digest': 'candidate-digest',
  'route_source': 'lifi',
  'stages': <Object>[],
  'expected_receive': '95',
  'minimum_receive': '90',
  'fees': <Object>[],
  'net_receive_value': null,
  'valuation_observed_at': null,
  'rank_status': 'ranked',
  'rank': 0,
  'estimated_duration_seconds': 60,
  'quote_observed_at': _timestamp,
  'expires_at': '2026-07-15T12:05:00Z',
  'warnings': <String>[],
};

Map<String, dynamic> _summaryJson(String routeExecutionId) => {
  'route_execution_id': routeExecutionId,
  'activity_state': 'active',
  'route_source': 'lifi',
  'from_asset': _assetJson('ETH'),
  'to_asset': _assetJson('MATIC'),
  'source_amount': '100',
  'expected_receive': '95',
  'minimum_receive': '90',
  'resolved_source_address': '0x1111111111111111111111111111111111111111',
  'recipient_address': '0x2222222222222222222222222222222222222222',
  'stage_count': 0,
  'current_stage_index': 0,
  'phase': 'planned',
  'route_phase': 'validating',
  'controls': {
    'can_cancel': true,
    'can_stop_after_current': false,
    'reconciliation_only': false,
  },
  'requires_user_attention': false,
  'requires_user_action': false,
  'actual_holding': null,
  'terminal_error': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
  'completed_at': null,
};

Map<String, dynamic> _assetJson(String ticker) => {
  'ticker': ticker,
  'chain_family': 'evm',
  'chain_id': ticker == 'ETH' ? '1' : '137',
  'asset_kind': 'native',
  'contract_address': null,
  'decimals': 18,
};

StageConsent _replacementStageConsent({
  String mode = 'sign_and_broadcast',
  String consentExpiry = _replacementExpiry,
  String resolvedSourceAddress = '0x1111111111111111111111111111111111111111',
  bool validDigest = true,
}) {
  final json =
      jsonDecode(jsonEncode(_preparedStageConsentJson()))
          as Map<String, dynamic>;
  final routeIntent = Map<String, dynamic>.from(json['route_intent']! as Map)
    ..['consent_expires_at'] = consentExpiry;
  final stageIntent = Map<String, dynamic>.from(json['stage_intent']! as Map)
    ..['accepted_expected_receive'] = '94'
    ..['minimum_receive'] = '89'
    ..['consent_expires_at'] = consentExpiry;
  final preparedExecution = Map<String, dynamic>.from(
    json['prepared_execution']! as Map,
  )..['resolved_source_address'] = resolvedSourceAddress;
  json
    ..['route_intent'] = routeIntent
    ..['stage_intent'] = stageIntent
    ..['prepared_execution'] = preparedExecution
    ..['mode'] = mode
    ..['consent_digest'] = 'pending';

  final unsigned = StageConsent.fromJson(json);
  json['consent_digest'] = validDigest
      ? tradeRouteStageConsentDigest(unsigned)
      : 'invalid-stage-consent-digest';
  return StageConsent.fromJson(json);
}

Map<String, dynamic> _replacementSummaryJson(
  StageConsent? consent, {
  String expiresAt = _replacementExpiry,
}) => {
  'proposal_digest': _replacementProposalDigest,
  'stage_id': '00000000-0000-4000-8000-000000000003',
  'provider_step_digest': null,
  'changed_fields': ['expected_receive', 'minimum_receive'],
  'expected_receive': '94',
  'minimum_receive': '89',
  'fees': <Object>[],
  'required_total_network_fee': null,
  'selected_tools': {
    'bridges': ['across'],
    'exchanges': <String>[],
  },
  'expires_at': expiresAt,
  'replacement_stage_consent': consent?.toJson(),
};

PrepareExecutionStageLimits _prepareStageLimits() =>
    PrepareExecutionStageLimits(
      stageId: '00000000-0000-4000-8000-000000000003',
      maxExpectedReceiveDegradationBps: 100,
      nonNetworkFeeLimits: const [],
      maxTotalNetworkFee: FeeCap(
        asset: RouteAsset.fromJson(_assetJson('ETH')),
        amount: '10',
      ),
    );

PrepareExecutionResponse _preparedExecutionResponse() {
  final stageConsentJson = _preparedStageConsentJson();
  final stageConsent = StageConsent.fromJson(stageConsentJson);
  stageConsentJson['consent_digest'] = tradeRouteStageConsentDigest(
    stageConsent,
  );

  final reviewJson = _preparedReviewJson();
  final review = PreparedExecutionReview.fromJson(reviewJson);
  final routeConsentJson = <String, dynamic>{
    'digest_version': 1,
    'evaluation_id': _evaluationId,
    'candidate_id': _candidateId,
    'candidate_digest': 'candidate-digest',
    'route_intent': _intentJson(),
    'external_stage_consents': [stageConsentJson],
    'atomic_order_guards': <Object>[],
    'mode': 'sign_and_broadcast',
    'consent_expires_at': '2026-07-15T12:30:00Z',
    'prepared_at': _timestamp,
    'prepared_review_digest': tradeRoutePreparedExecutionReviewDigest(review),
    'route_consent_digest': 'pending',
  };
  final routeConsent = RouteConsent.fromJson(routeConsentJson);
  routeConsentJson['route_consent_digest'] = tradeRouteConsentDigest(
    routeConsent,
  );

  return PrepareExecutionResponse.parse({
    'mmrpc': '2.0',
    'result': {'review': reviewJson, 'route_consent': routeConsentJson},
  });
}

PrepareExecutionResponse _tamperedPreparedExecutionResponse(String tamper) {
  final json =
      jsonDecode(jsonEncode(_preparedExecutionResponse().toJson()))
          as Map<String, dynamic>;
  final result = Map<String, dynamic>.from(json['result']! as Map);
  final routeConsent = Map<String, dynamic>.from(
    result['route_consent']! as Map,
  );
  switch (tamper) {
    case 'prepared review digest':
      final review = Map<String, dynamic>.from(result['review']! as Map);
      review['expected_receive'] = '94';
      result['review'] = review;
    case 'stage consent digest':
      final stages = routeConsent['external_stage_consents']! as List<dynamic>;
      final stage = Map<String, dynamic>.from(stages.single as Map);
      final prepared = Map<String, dynamic>.from(
        stage['prepared_execution']! as Map,
      );
      prepared['resolved_source_address'] =
          '0x4444444444444444444444444444444444444444';
      stage['prepared_execution'] = prepared;
      stages[0] = stage;
      routeConsent['external_stage_consents'] = stages;
    case 'route consent digest':
      routeConsent['route_consent_digest'] = 'tampered';
    default:
      throw ArgumentError.value(tamper, 'tamper');
  }
  result['route_consent'] = routeConsent;
  json['result'] = result;
  return PrepareExecutionResponse.parse(json);
}

Map<String, dynamic> _preparedStageConsentJson() => {
  'digest_version': 1,
  'candidate_reference': {
    'evaluation_id': _evaluationId,
    'candidate_id': _candidateId,
    'candidate_digest': 'candidate-digest',
    'stage_id': '00000000-0000-4000-8000-000000000003',
  },
  'route_intent': _intentJson(),
  'stage_intent': {
    'route_intent_digest': 'route-intent-digest',
    'stage_id': '00000000-0000-4000-8000-000000000003',
    'from_asset': _assetJson('ETH'),
    'to_asset': _assetJson('MATIC'),
    'source_amount': '100',
    'accepted_expected_receive': '95',
    'minimum_receive': '90',
    'max_expected_receive_degradation_bps': 100,
    'slippage_bps': 50,
    'source_address': {'selector_type': 'active'},
    'recipient': '0x2222222222222222222222222222222222222222',
    'tool_policy': {
      'bridges': {
        'allow': <String>[],
        'deny': <String>[],
        'prefer': <String>[],
      },
      'exchanges': {
        'allow': <String>[],
        'deny': <String>[],
        'prefer': <String>[],
      },
    },
    'selected_tools': {
      'bridges': ['across'],
      'exchanges': <String>[],
    },
    'provider_tokens': {
      'from_token': '0x0000000000000000000000000000000000000000',
      'to_token': '0x0000000000000000000000000000000000000000',
    },
    'provider_chain_ids': {'from_chain': '1', 'to_chain': '137'},
    'non_network_fee_limits': <Object>[],
    'max_total_network_fee': {'asset': _assetJson('ETH'), 'amount': '10'},
    'consent_expires_at': '2026-07-15T12:30:00Z',
  },
  'execution_source': {
    'source_type': 'provider_intent',
    'provider': 'lifi',
    'materialization': 'simple_quote',
    'provider_observed_at': _timestamp,
    'provider_step': null,
    'provider_step_reference': null,
    'provider_step_digest': null,
  },
  'mode': 'sign_and_broadcast',
  'atomic_order_guard': null,
  'prepared_execution': {
    'resolved_source_address': '0x1111111111111111111111111111111111111111',
    'approval': {'approval_type': 'not_applicable'},
    'required_max_network_fee': {'asset': _assetJson('ETH'), 'amount': '10'},
  },
  'consent_digest': 'pending',
};

Map<String, dynamic> _preparedReviewJson() => {
  'review_version': 1,
  'prepared_at': _timestamp,
  'evaluation_id': _evaluationId,
  'candidate_id': _candidateId,
  'candidate_digest': 'candidate-digest',
  'route_source': 'lifi',
  'source_asset': _assetJson('ETH'),
  'destination_asset': _assetJson('MATIC'),
  'source_amount': '100',
  'source_address_selector': {'selector_type': 'active'},
  'resolved_source_address': '0x1111111111111111111111111111111111111111',
  'recipient': '0x2222222222222222222222222222222222222222',
  'expected_receive': '95',
  'minimum_receive': '90',
  'fees': <Object>[],
  'estimated_duration_seconds': 60,
  'warnings': <String>[],
  'expires_at': '2026-07-15T12:05:00Z',
  'stages': [
    {
      'stage_index': 0,
      'stage_id': '00000000-0000-4000-8000-000000000003',
      'stage_kind': 'external_liquidity',
      'from_asset': _assetJson('ETH'),
      'to_asset': _assetJson('MATIC'),
      'source_amount': '100',
      'expected_receive': '95',
      'minimum_receive': '90',
      'recipient': '0x2222222222222222222222222222222222222222',
      'fees': <Object>[],
      'warnings': <String>[],
      'selected_tools': {
        'bridges': ['across'],
        'exchanges': <String>[],
      },
      'non_network_fee_limits': <Object>[],
      'max_total_network_fee': {'asset': _assetJson('ETH'), 'amount': '10'},
      'required_max_network_fee': {'asset': _assetJson('ETH'), 'amount': '10'},
      'resolved_source_address': '0x1111111111111111111111111111111111111111',
      'approval': {'approval_type': 'not_applicable'},
    },
  ],
};
