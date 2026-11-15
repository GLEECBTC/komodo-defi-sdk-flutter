import 'dart:async';

import 'package:komodo_defi_types/src/api/rpc_dispatch_guard.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a suspended transport checks authorization immediately before sending',
    () async {
      var allowed = true;
      var dispatched = false;
      final transportReady = Completer<void>();
      final release = Completer<void>();
      final operation = RpcDispatchGuard.run(
        () {
          if (!allowed) throw StateError('locked');
        },
        () async {
          transportReady.complete();
          await release.future;
          RpcDispatchGuard.ensureCurrent('send_raw_transaction');
          dispatched = true;
        },
        methods: const {'send_raw_transaction'},
      );
      final assertion = expectLater(
        operation,
        throwsA(isA<RpcDispatchRejected>()),
      );
      await transportReady.future;
      allowed = false;
      release.complete();
      await assertion;
      expect(dispatched, isFalse);
    },
  );

  test('read-only continuation is not denied by a mutation scope', () async {
    await RpcDispatchGuard.run(() => throw StateError('locked'), () async {
      await Future<void>.value();
      RpcDispatchGuard.ensureCurrent('task::routed_swap::status');
    }, methods: const {'task::routed_swap::init'});
  });

  test('nested scopes cannot replace an earlier authorization', () {
    expect(
      () => RpcDispatchGuard.run(
        () => throw StateError('stale wallet'),
        () => RpcDispatchGuard.run(
          () {},
          () => RpcDispatchGuard.ensureCurrent('sell'),
          methods: const {'sell'},
        ),
        methods: const {'sell'},
      ),
      throwsA(isA<RpcDispatchRejected>()),
    );
  });

  test('completed request scopes do not leak into later engine work', () async {
    await RpcDispatchGuard.run(
      () {},
      () async => RpcDispatchGuard.ensureCurrent('sell'),
      methods: const {'sell'},
    );
    RpcDispatchGuard.ensureCurrent('sell');
    expect(
      const RpcDispatchRejected('secret canary').toString(),
      isNot(contains('secret canary')),
    );
  });
}
