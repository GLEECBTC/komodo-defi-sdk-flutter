import 'dart:convert';
import 'dart:io';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> vectors;
  late StageConsent stageConsent;
  late RouteConsent routeConsent;
  late TradeRouteCandidate candidate;

  setUpAll(() {
    vectors =
        jsonDecode(
              File(
                'test/fixtures/trade_route/external_liquidity_digest_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    stageConsent = StageConsent.fromJson(
      _map(_map(vectors['stage_consent'])['value']),
    );
    routeConsent = RouteConsent.fromJson(
      _map(_map(vectors['route_consent'])['value']),
    );
    candidate = TradeRouteCandidate.fromJson(
      _map(_map(vectors['candidate'])['value']),
    );
  });

  group('cross-language digest fixture', () {
    test('parses KDF candidate and complete consent values', () {
      expect(candidate.candidateId, '00000000-0000-0000-0000-000000000001');
      expect(stageConsent.consentDigest, 'excluded');
      expect(routeConsent.routeConsentDigest, 'excluded');
      expect(
        tradeRouteCandidateDigest(candidate),
        'aa0935e4ed46f00fef305abd10457254f0d20b034cd50d98669ce5f280774e18',
      );
      expect(
        tradeRouteStageConsentDigest(stageConsent),
        'a58070a1d52c06f41bd7b579496ad425c24662be50f3f8ec622edeb5c66eabe1',
      );
      expect(
        tradeRouteConsentDigest(routeConsent),
        'af843a41b576477c2a31ca270e3f130d7612fd80a8a6e3ac258ff4a74b0188dd',
      );
      expect(
        () => tradeRouteCanonicalDigest({'too_large': 9007199254740992}),
        throwsA(isA<TradeRouteDigestException>()),
      );
    });

    test('round-tripped models remain strictly parseable', () {
      expect(
        () => TradeRouteCandidate.fromJson(candidate.toJson()),
        returnsNormally,
      );
      expect(
        () => StageConsent.fromJson(stageConsent.toJson()),
        returnsNormally,
      );
      expect(
        () => RouteConsent.fromJson(routeConsent.toJson()),
        returnsNormally,
      );
    });

    test('replacement summaries retain exact KDF-prepared consent', () {
      final json = <String, dynamic>{
        'proposal_digest': 'proposal-digest',
        'stage_id': stageConsent.stageIntent.stageId,
        'provider_step_digest': null,
        'changed_fields': <String>['expected_receive'],
        'expected_receive': stageConsent.stageIntent.acceptedExpectedReceive,
        'minimum_receive': stageConsent.stageIntent.minimumReceive,
        'fees': <Object?>[],
        'required_total_network_fee': null,
        'selected_tools': stageConsent.stageIntent.selectedTools.toJson(),
        'expires_at': '2030-01-01T00:00:00Z',
        'replacement_stage_consent': stageConsent.toJson(),
      };

      final summary = ReplacementSummary.fromJson(json);
      expect(
        summary.replacementStageConsent?.consentDigest,
        stageConsent.consentDigest,
      );
      expect(summary.isExecutable, isTrue);
      expect(
        ReplacementSummary.fromJson(
          Map<String, dynamic>.from(json)..remove('replacement_stage_consent'),
        ).isExecutable,
        isFalse,
      );
      expect(
        () => ReplacementSummary.fromJson({
          ...json,
          'provider_payload': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });

    test('prepared bindings participate in every consent digest', () {
      final response = PrepareExecutionResponse.parse(
        _preparedExecutionEnvelope(vectors),
      );
      final result = response.result;
      final preparedStage = result.routeConsent.externalStageConsents.single;

      expect(
        tradeRouteStageConsentDigest(preparedStage),
        preparedStage.consentDigest,
      );
      expect(
        tradeRouteConsentDigest(result.routeConsent),
        result.routeConsent.routeConsentDigest,
      );
      expect(
        tradeRoutePreparedExecutionReviewDigest(result.review),
        result.routeConsent.preparedReviewDigest,
      );
      expect(result.routeConsent.preparedAt, result.review.preparedAt);
      expect(result.isExecutable, isTrue);

      final tamperedStageJson = preparedStage.toJson();
      final preparedExecution = _map(tamperedStageJson['prepared_execution']);
      preparedExecution['resolved_source_address'] = '0xtampered';
      tamperedStageJson['prepared_execution'] = preparedExecution;
      final tamperedStage = StageConsent.fromJson(tamperedStageJson);
      expect(
        tradeRouteStageConsentDigest(tamperedStage),
        isNot(tamperedStage.consentDigest),
      );
    });

    test('canonical prepare fixture matches the candidate and all digests', () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/trade_route/prepare_execution_response.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final response = PrepareExecutionResponse.parse(fixture);
      final result = response.result;

      expect(result.review.candidateId, candidate.candidateId);
      expect(
        result.review.candidateDigest,
        tradeRouteCandidateDigest(candidate),
      );
      expect(
        tradeRoutePreparedExecutionReviewDigest(result.review),
        result.routeConsent.preparedReviewDigest,
      );
      expect(
        result.routeConsent.externalStageConsents.every(
          (consent) =>
              tradeRouteStageConsentDigest(consent) == consent.consentDigest,
        ),
        isTrue,
      );
      expect(
        tradeRouteConsentDigest(result.routeConsent),
        result.routeConsent.routeConsentDigest,
      );
      expect(result.isExecutable, isTrue);
    });
  });

  group('all fifteen method envelopes', () {
    test('capabilities omits provider_snapshot for KDF-owned discovery', () {
      final request = TradeRouteCapabilitiesRequest().toJson();
      final params = request['params']! as Map<String, dynamic>;

      expect(params, isNot(contains('provider_snapshot')));
    });

    test('use exact method names and nested v2 params', () {
      final intent = routeConsent.routeIntent;
      final snapshot = ProviderMetadataSnapshot(
        provider: ExternalProvider.lifi,
        observedAt: DateTime.utc(2026, 7, 16, 12),
        pairs: const [],
      );
      const executionId = '00000000-0000-4000-8000-000000000050';
      const routeExecutionId = '00000000-0000-4000-8000-000000000051';
      const actionId = '00000000-0000-4000-8000-000000000052';

      final envelopes = <String, Map<String, dynamic>>{
        'experimental::trade_route::capabilities':
            TradeRouteCapabilitiesRequest(providerSnapshot: snapshot).toJson(),
        'experimental::trade_route::evaluate': TradeRouteEvaluateRequest(
          intent: intent,
          candidateSources: const [CandidateSource.kdfAtomic],
        ).toJson(),
        'experimental::trade_route::get_execution':
            GetTradeRouteExecutionRequest(
              routeExecutionId: routeExecutionId,
            ).toJson(),
        'experimental::trade_route::list_executions':
            ListTradeRouteExecutionsRequest().toJson(),
        'experimental::trade_route::quote': TradeRouteQuoteRequest(
          intent: intent,
          routeSources: const [RouteSource.kdf],
        ).toJson(),
        'experimental::trade_route::prepare_execution': PrepareExecutionRequest(
          evaluationId: routeConsent.evaluationId,
          candidateId: routeConsent.candidateId,
          candidateDigest: routeConsent.candidateDigest,
          finalMinimumReceive: '90',
          consentExpiresAt: routeConsent.consentExpiresAt,
          stages: [
            PrepareExecutionStageLimits(
              stageId: stageConsent.stageIntent.stageId,
              maxExpectedReceiveDegradationBps: 100,
              nonNetworkFeeLimits: stageConsent.stageIntent.nonNetworkFeeLimits,
              maxTotalNetworkFee: stageConsent.stageIntent.maxTotalNetworkFee,
            ),
          ],
        ).toJson(),
        'task::external_execution::init': ExternalExecutionInitRequest(
          executionId: executionId,
          idempotencyKey: 'route-stage-0',
          stageConsent: stageConsent,
        ).toJson(),
        'task::external_execution::status': ExternalExecutionStatusRequest(
          taskId: 41,
          forgetIfFinished: false,
        ).toJson(),
        'task::external_execution::user_action':
            ExternalExecutionUserActionRequest(
              taskId: 41,
              userAction: ExternalExecutionUserAction.rejectChange(
                actionId: actionId,
                expectedStateRevision: 3,
              ),
            ).toJson(),
        'task::external_execution::cancel': CancelExternalExecutionRequest(
          executionId: executionId,
        ).toJson(),
        'experimental::chain_tx::receipt': ChainTxReceiptRequest(
          coin: 'ETH',
          txHash: '0xabc',
          requiredConfirmations: 2,
        ).toJson(),
        'task::trade_route::init': TradeRouteInitRequest(
          routeExecutionId: routeExecutionId,
          idempotencyKey: 'route-0',
          routeConsent: routeConsent,
        ).toJson(),
        'task::trade_route::status': TradeRouteStatusRequest(
          taskId: 42,
          forgetIfFinished: false,
        ).toJson(),
        'task::trade_route::user_action': TradeRouteUserActionRequest(
          taskId: 42,
          userAction: RouteExecutionUserAction.stopAfterCurrent(
            actionId: actionId,
            expectedStateRevision: 8,
          ),
        ).toJson(),
        'task::trade_route::cancel': CancelTradeRouteRequest(
          routeExecutionId: routeExecutionId,
        ).toJson(),
      };

      expect(envelopes, hasLength(15));
      for (final entry in envelopes.entries) {
        expect(entry.value['method'], entry.key);
        expect(entry.value['mmrpc'], '2.0');
        expect(entry.value['params'], isA<Map<String, dynamic>>());
        expect(entry.value, isNot(contains('userpass')));
      }
      expect(
        _map(
          envelopes['task::trade_route::user_action']!['params'],
        )['user_action'],
        {
          'action_id': actionId,
          'expected_state_revision': 8,
          'action_type': 'stop_after_current',
        },
      );
    });
  });

  group('typed response parsers', () {
    test('parses the smallest complete Activity detail fixture', () {
      final response = RouteExecutionDetailsResponse.parse({
        'mmrpc': '2.0',
        'result': _activityDetails(vectors, candidate),
      });

      expect(response.result.routeExecutionId, _routeId);
      expect(response.result.status.controls.canCancel, isTrue);
      expect(response.result.candidate.stages, hasLength(2));
    });

    test('serializes exact Activity consent for task reattachment', () {
      final details = RouteExecutionDetailsResponse.parse({
        'mmrpc': '2.0',
        'result': _activityDetails(vectors, candidate),
      }).result;
      final request = TradeRouteInitRequest(
        routeExecutionId: details.routeExecutionId,
        idempotencyKey: 'reattach-activity-route',
        routeConsent: details.routeConsent,
      ).toJson();

      expect(
        _map(request['params'])['route_consent'],
        details.routeConsent.toJson(),
      );
    });

    test('parses status, init, cancel, receipt and action envelopes', () {
      final status = TradeRouteTaskStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {'status': 'InProgress', 'details': _routeStatus()},
      });
      final init = NewTaskResponse.parse({
        'mmrpc': '2.0',
        'result': {'task_id': 77},
      });
      final cancel = RouteCancelResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'outcome': 'stop_after_current',
          'phase': 'source_pending',
          'stop_after_current': true,
          'tx_hashes': ['0xabc'],
        },
      });
      final action = RouteActionResponse.parse({
        'mmrpc': '2.0',
        'result': 'success',
      });
      final receipt = ChainTxReceiptResponse.parse({
        'mmrpc': '2.0',
        'result': _receipt(),
      });

      expect(status.result, isA<TradeRouteInProgressStatus>());
      expect(init.taskId, 77);
      expect(
        cancel.result.outcome.knownValue,
        CancelOutcomeKind.stopAfterCurrent,
      );
      expect(action.result, 'success');
      expect(receipt.result.statusValue.knownValue, ChainTxStatus.confirmed);
    });

    test('parses the complete prepare-execution Review and consent', () {
      final response = PrepareExecutionResponse.parse(
        _preparedExecutionEnvelope(vectors),
      );
      final stage =
          response.result.review.stages.single
              as KnownPreparedExecutionStageReview;
      final approval = stage.approval;

      expect(stage.kind, PreparedExecutionStageKind.externalLiquidity);
      expect(approval, isA<ExactApprovalRequiredPreparedApproval>());
      expect(stage.requiredMaxNetworkFee?.amount, '10');
      expect(
        response
            .result
            .routeConsent
            .externalStageConsents
            .single
            .preparedExecution
            ?.approval,
        isA<ExactApprovalRequiredPreparedApproval>(),
      );
      expect(response.result.isExecutable, isTrue);
      expect(
        () => PrepareExecutionResponse.parse(response.toJson()),
        returnsNormally,
      );
    });

    test('status requests parse domain Error as a typed response', () {
      final routeResponse = TradeRouteStatusRequest(taskId: 7).parseResponse(
        jsonEncode({
          'mmrpc': '2.0',
          'result': {
            'status': 'Error',
            'details': {
              'error_type': 'RouteNotFound',
              'error_data': {'route_execution_id': _routeId},
            },
          },
        }),
      );
      final externalResponse = ExternalExecutionStatusRequest(taskId: 8)
          .parseResponse(
            jsonEncode({
              'mmrpc': '2.0',
              'result': {
                'status': 'Error',
                'details': {
                  'error_type': 'ExecutionNotFound',
                  'error_data': {
                    'execution_id': '00000000-0000-4000-8000-000000000099',
                  },
                },
              },
            }),
          );

      expect(routeResponse.result, isA<TradeRouteErrorStatus>());
      expect(externalResponse.result, isA<ExternalExecutionErrorStatus>());
    });
  });

  group('unknown and malformed discriminators', () {
    test('unknown task status preserves discriminator and payload inertly', () {
      final response = TradeRouteTaskStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'status': 'PausedByFutureKdf',
          'details': {'safe': true},
        },
      });

      final status = response.result as UnknownTradeRouteTaskStatus;
      expect(status.rawStatus, 'PausedByFutureKdf');
      expect(status.rawDetails, {'safe': true});
      expect(status.isExecutable, isFalse);
    });

    test('unknown stage and evidence preserve raw payload inertly', () {
      final stage = RouteStage.fromJson({
        'stage_type': 'future_stage',
        'opaque': {'safe': true},
      });
      final evidence = RouteEvidence.fromJson({
        'evidence_type': 'future_evidence',
        'opaque': 4,
      });

      expect(stage, isA<UnknownRouteStage>());
      expect(stage.isExecutable, isFalse);
      expect(stage.toJson()['opaque'], {'safe': true});
      expect(stage.toRequestJson, throwsStateError);
      expect(evidence, isA<UnknownRouteEvidence>());
      expect(evidence.isExecutable, isFalse);
    });

    test('unknown errors and allowed actions fail closed', () {
      final error = RouteRpcError.fromJson({
        'error_type': 'FutureRouteError',
        'error_data': {'safe': true},
      });
      final pending = PendingUserAction.fromJson({
        'action_id': '00000000-0000-4000-8000-000000000052',
        'reason': 'quote_changed',
        'allowed_actions': ['future_action'],
        'replacement_summary': null,
      });

      expect(error, isA<UnknownRouteRpcError>());
      expect(error.rawDiscriminator, 'FutureRouteError');
      expect(error.isExecutable, isFalse);
      expect(pending.allowedActions.single.rawValue, 'future_action');
      expect(pending.allowedActions.single.isExecutable, isFalse);
      expect(pending.isExecutable, isFalse);
    });

    test(
      'EvaluationNotFound is known and requires an exact evaluation UUID',
      () {
        final error = RouteRpcError.fromJson({
          'error_type': 'EvaluationNotFound',
          'error_data': {
            'evaluation_id': '00000000-0000-4000-8000-000000000099',
          },
        });

        expect(error, isA<KnownRouteRpcError>());
        expect(error.rawDiscriminator, 'EvaluationNotFound');
        expect(error.rawData, {
          'evaluation_id': '00000000-0000-4000-8000-000000000099',
        });
        expect(error.isExecutable, isFalse);
        expect(
          () => RouteRpcError.fromJson({
            'error_type': 'EvaluationNotFound',
            'error_data': {'evaluation_id': 'not-a-uuid'},
          }),
          throwsFormatException,
        );
        expect(
          () => RouteRpcError.fromJson({
            'error_type': 'EvaluationNotFound',
            'error_data': {
              'evaluation_id': '00000000-0000-4000-8000-000000000099',
              'provider_payload': 'must-not-be-accepted',
            },
          }),
          throwsFormatException,
        );
      },
    );

    test('unknown Activity consent cannot be reused for reattachment', () {
      final consentJson = _map(
        _activityDetails(vectors, candidate)['route_consent'],
      );
      final stages = consentJson['external_stage_consents']! as List<dynamic>;
      final firstStage = _map(stages.first);
      firstStage['execution_source'] = {
        'source_type': 'future_execution_source',
        'opaque': true,
      };
      stages[0] = firstStage;
      final consent = RouteActivityConsent.fromJson(consentJson);

      expect(consent.isExecutable, isFalse);
      expect(
        () => TradeRouteInitRequest(
          routeExecutionId: _routeId,
          idempotencyKey: 'unsafe-reattach',
          routeConsent: consent,
        ).toJson(),
        throwsStateError,
      );
    });

    test('known malformed variants throw instead of becoming unknown', () {
      expect(
        () => RouteStage.fromJson({'stage_type': 'kdf_atomic'}),
        throwsFormatException,
      );
      expect(
        () => TradeRouteTaskStatusResponse.parse({
          'mmrpc': '2.0',
          'result': {'status': 'InProgress', 'details': <String, dynamic>{}},
        }),
        throwsFormatException,
      );
      expect(
        () => RouteRpcError.fromJson({
          'error_type': 'RouteNotFound',
          'error_data': {'wrong': _routeId},
        }),
        throwsFormatException,
      );
    });

    test('unknown prepared stage and approval variants remain inert', () {
      final unknownStage = PreparedExecutionStageReview.fromJson({
        'stage_kind': 'future_stage',
        'opaque': {'safe': true},
      });
      final unknownApproval = PreparedApproval.fromJson({
        'approval_type': 'future_approval',
        'opaque': {'safe': true},
      });

      expect(unknownStage, isA<UnknownPreparedExecutionStageReview>());
      expect(unknownStage.stageKind, 'future_stage');
      expect(unknownStage.isExecutable, isFalse);
      expect(unknownStage.toJson()['opaque'], {'safe': true});
      expect(unknownApproval, isA<UnknownPreparedApproval>());
      expect(unknownApproval.approvalType, 'future_approval');
      expect(unknownApproval.isExecutable, isFalse);
      expect(unknownApproval.toJson()['opaque'], {'safe': true});
    });

    test('all known prepared approval variants remain executable', () {
      final notApplicable = PreparedApproval.fromJson({
        'approval_type': 'not_applicable',
      });
      final sufficient = PreparedApproval.fromJson({
        'approval_type': 'sufficient_allowance',
        'token': _assetJson(),
        'spender': '0x3333333333333333333333333333333333333333',
        'current_allowance': '200',
        'required_amount': '100',
      });
      final exact = PreparedApproval.fromJson(_preparedApprovalJson());

      expect(notApplicable, isA<NotApplicablePreparedApproval>());
      expect(sufficient, isA<SufficientAllowancePreparedApproval>());
      expect(exact, isA<ExactApprovalRequiredPreparedApproval>());
      expect(
        [notApplicable, sufficient, exact].every((item) => item.isExecutable),
        isTrue,
      );
    });

    test('unknown prepared approval cannot reach route init', () {
      final envelope = _preparedExecutionEnvelope(vectors);
      final result = _map(envelope['result']);
      final consent = _map(result['route_consent']);
      final stageConsents = consent['external_stage_consents']! as List;
      final stageConsentJson = _map(stageConsents.single);
      final preparedExecution = _map(stageConsentJson['prepared_execution']);
      preparedExecution['approval'] = {
        'approval_type': 'future_approval',
        'opaque': true,
      };
      stageConsentJson['prepared_execution'] = preparedExecution;
      stageConsents[0] = stageConsentJson;
      consent['external_stage_consents'] = stageConsents;
      final parsed = RouteConsent.fromJson(consent);

      expect(parsed.isExecutable, isFalse);
      expect(
        () => TradeRouteInitRequest(
          routeExecutionId: _routeId,
          idempotencyKey: 'unsafe-prepared-route',
          routeConsent: parsed,
        ).toJson(),
        throwsStateError,
      );
    });

    test('known prepared variants reject unknown or missing fields', () {
      expect(
        () => PreparedExecutionStageReview.fromJson({
          ..._preparedStageReviewJson(),
          'future_field': true,
        }),
        throwsFormatException,
      );
      expect(
        () => PreparedApproval.fromJson({
          'approval_type': 'exact_approval_required',
          'token': _assetJson(),
          'spender': '0x3333333333333333333333333333333333333333',
          'current_allowance': '0',
          'required_amount': '100',
        }),
        throwsFormatException,
      );
    });
  });

  group('Activity keyset pagination', () {
    test('keeps sparse-page cursors and stops only on null', () {
      final sparse = ListRouteExecutionsResponse.parse({
        'mmrpc': '2.0',
        'result': {'executions': <Object>[], 'next_cursor': 'v1-opaque-cursor'},
      });
      final terminal = ListRouteExecutionsResponse.parse({
        'mmrpc': '2.0',
        'result': {'executions': <Object>[], 'next_cursor': null},
      });

      expect(sparse.result.executions, isEmpty);
      expect(sparse.result.nextCursor, 'v1-opaque-cursor');
      expect(terminal.result.nextCursor, isNull);
    });

    test('serializes filter-bound cursor and enforces limit bounds', () {
      final request = ListTradeRouteExecutionsRequest(
        state: RouteActivityState.attentionRequired,
        cursor: 'v1-filter-bound',
        limit: 100,
      ).toJson();
      expect(request['params'], {
        'state': 'attention_required',
        'cursor': 'v1-filter-bound',
        'limit': 100,
      });
      expect(() => ListTradeRouteExecutionsRequest(limit: 0), throwsRangeError);
      expect(
        () => ListTradeRouteExecutionsRequest(limit: 101),
        throwsRangeError,
      );
    });
  });
}

const _routeId = '00000000-0000-4000-8000-000000000051';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

Map<String, dynamic> _routeStatus() => {
  'route_execution_id': _routeId,
  'stage_index': 0,
  'phase': 'planned',
  'route_phase': 'validating',
  'state_revision': 0,
  'pending_user_action': null,
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
    'can_cancel': true,
    'can_stop_after_current': false,
    'reconciliation_only': false,
  },
  'created_at': '2026-07-16T12:00:00Z',
  'completed_at': null,
  'updated_at': '2026-07-16T12:00:00Z',
};

Map<String, dynamic> _activityDetails(
  Map<String, dynamic> fixture,
  TradeRouteCandidate parsedCandidate,
) {
  final activityConsent =
      jsonDecode(jsonEncode(_map(_map(fixture['route_consent'])['value'])))
          as Map<String, dynamic>;
  activityConsent['consent_type'] = 'activity_reattachment';
  final stages = activityConsent['external_stage_consents']! as List<dynamic>;
  for (var index = 0; index < stages.length; index++) {
    final stage = _map(stages[index])..remove('route_intent');
    final source = _map(stage['execution_source'])..remove('provider_step');
    stage['execution_source'] = source;
    stages[index] = stage;
  }
  return {
    'route_execution_id': _routeId,
    'activity_state': 'active',
    'route_consent': activityConsent,
    'candidate': parsedCandidate.toJson(),
    'resolved_source_address': '0x1111111111111111111111111111111111111111',
    'recipient_address': parsedCandidate.stages.last is KdfAtomicRouteStage
        ? (parsedCandidate.stages.last as KdfAtomicRouteStage).common.recipient
        : '0x2222222222222222222222222222222222222222',
    'status': _routeStatus(),
    'route_revisions': <Object>[],
    'terminal_error': null,
    'created_at': '2026-07-16T12:00:00Z',
    'updated_at': '2026-07-16T12:00:00Z',
    'completed_at': null,
  };
}

Map<String, dynamic> _receipt() => {
  'chain_family': 'evm',
  'chain_id': '1',
  'tx_hash': '0xabc',
  'status': 'confirmed',
  'confirmations': 3,
  'block_hash': '0xdef',
  'block_height': '22810000',
  'gas_used': '21000',
  'effective_gas_price': '2',
  'network_fee': null,
  'revert_reason': null,
  'observed_at': '2026-07-16T12:00:00Z',
};

const _fixtureCandidateDigest =
    'aa0935e4ed46f00fef305abd10457254f0d20b034cd50d98669ce5f280774e18';

Map<String, dynamic> _preparedExecutionEnvelope(Map<String, dynamic> fixture) {
  final routeConsentJson =
      jsonDecode(jsonEncode(_map(_map(fixture['route_consent'])['value'])))
          as Map<String, dynamic>;
  routeConsentJson['candidate_digest'] = _fixtureCandidateDigest;

  final stageConsents =
      routeConsentJson['external_stage_consents']! as List<dynamic>;
  final stageConsentJson = _map(stageConsents.single);
  final candidateReference = _map(stageConsentJson['candidate_reference']);
  candidateReference['candidate_digest'] = _fixtureCandidateDigest;
  stageConsentJson['candidate_reference'] = candidateReference;
  stageConsentJson['prepared_execution'] = {
    'resolved_source_address': '0x1111111111111111111111111111111111111111',
    'approval': _preparedApprovalJson(),
    'required_max_network_fee': {'asset': _assetJson(), 'amount': '10'},
  };
  stageConsentJson['consent_digest'] = 'pending';
  final parsedStageConsent = StageConsent.fromJson(stageConsentJson);
  stageConsentJson['consent_digest'] = tradeRouteStageConsentDigest(
    parsedStageConsent,
  );
  stageConsents[0] = stageConsentJson;
  routeConsentJson['external_stage_consents'] = stageConsents;

  final reviewJson = {
    'review_version': 1,
    'prepared_at': '2026-07-16T12:00:30Z',
    'evaluation_id': routeConsentJson['evaluation_id'],
    'candidate_id': routeConsentJson['candidate_id'],
    'candidate_digest': _fixtureCandidateDigest,
    'route_source': 'lifi',
    'source_asset': _assetJson(),
    'destination_asset': _assetJson(),
    'source_amount': '100',
    'source_address_selector': {'selector_type': 'active'},
    'resolved_source_address': '0x1111111111111111111111111111111111111111',
    'recipient': '0x2222222222222222222222222222222222222222',
    'expected_receive': '95',
    'minimum_receive': '90',
    'fees': <Object>[],
    'estimated_duration_seconds': 60,
    'warnings': <String>[],
    'expires_at': '2026-07-16T12:00:50Z',
    'stages': [_preparedStageReviewJson()],
  };
  final review = PreparedExecutionReview.fromJson(reviewJson);
  routeConsentJson['prepared_at'] = reviewJson['prepared_at'];
  routeConsentJson['prepared_review_digest'] =
      tradeRoutePreparedExecutionReviewDigest(review);
  routeConsentJson['route_consent_digest'] = 'pending';
  final parsedRouteConsent = RouteConsent.fromJson(routeConsentJson);
  routeConsentJson['route_consent_digest'] = tradeRouteConsentDigest(
    parsedRouteConsent,
  );

  return {
    'mmrpc': '2.0',
    'result': {'review': reviewJson, 'route_consent': routeConsentJson},
  };
}

Map<String, dynamic> _preparedStageReviewJson() => {
  'stage_index': 0,
  'stage_id': '00000000-0000-0000-0000-000000000003',
  'stage_kind': 'external_liquidity',
  'from_asset': _assetJson(),
  'to_asset': _assetJson(),
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
  'max_total_network_fee': {'asset': _assetJson(), 'amount': '10'},
  'required_max_network_fee': {'asset': _assetJson(), 'amount': '10'},
  'resolved_source_address': '0x1111111111111111111111111111111111111111',
  'approval': _preparedApprovalJson(),
};

Map<String, dynamic> _preparedApprovalJson() => {
  'approval_type': 'exact_approval_required',
  'token': _assetJson(),
  'spender': '0x3333333333333333333333333333333333333333',
  'current_allowance': '0',
  'required_amount': '100',
  'reset_required': false,
};

Map<String, dynamic> _assetJson() => {
  'ticker': 'ETH',
  'chain_family': 'evm',
  'chain_id': '1',
  'asset_kind': 'native',
  'contract_address': null,
  'decimals': 18,
};
