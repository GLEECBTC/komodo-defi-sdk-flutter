import 'dart:async';

/// Carries a caller's authorization to the actual transport dispatch.
///
/// A scope applies only to the specified RPC methods. Read-only polling and
/// engine work after a submitted mutation must not be given a new guard.
/// Guards are in-memory callbacks, never request fields or persisted state.
abstract final class RpcDispatchGuard {
  static final Object _zoneKey = Object();

  /// Runs [operation] with a final authorization check for [methods].
  /// Nested operations retain all applicable outer authorization checks.
  static T run<T>(
    void Function() ensureAuthorized,
    T Function() operation, {
    required Set<String> methods,
  }) => runZoned(
    operation,
    zoneValues: {
      _zoneKey: _DispatchScope(
        ensureAuthorized,
        Set.unmodifiable(methods),
        Zone.current[_zoneKey] as _DispatchScope?,
      ),
    },
  );

  /// Must run after asynchronous preparation and before the first transport
  /// invocation. A rejection establishes that this request was not sent.
  static void ensureCurrent(String method) {
    var scope = Zone.current[_zoneKey] as _DispatchScope?;
    while (scope != null) {
      if (scope.methods.contains(method)) {
        try {
          scope.ensureAuthorized();
        } on RpcDispatchRejected {
          rethrow;
        } on Object catch (cause) {
          throw RpcDispatchRejected(cause);
        }
      }
      scope = scope.parent;
    }
  }
}

final class _DispatchScope {
  const _DispatchScope(this.ensureAuthorized, this.methods, this.parent);

  final void Function() ensureAuthorized;
  final Set<String> methods;
  final _DispatchScope? parent;
}

/// The transport refused a request before dispatch, so no ambiguous remote
/// outcome should be inferred. The cause is intentionally absent from text.
final class RpcDispatchRejected implements Exception {
  /// Records a local refusal without including its details in diagnostics.
  const RpcDispatchRejected(this.cause);

  /// Local authorization failure; consumers may classify it without logging it.
  final Object cause;

  @override
  String toString() => 'RPC dispatch authorization expired';
}
