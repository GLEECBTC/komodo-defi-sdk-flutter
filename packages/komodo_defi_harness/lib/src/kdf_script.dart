import 'dart:async';

/// A scripted KDF response.
typedef KdfResponder =
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Deterministic responses for a fake KDF, keyed by RPC method.
///
/// Keyed by `(method, invocationIndex)` rather than method alone, because
/// KDF's activation protocol is task-based: `task::enable_utxo::init` returns a
/// task id and the SDK then polls `task::enable_utxo::status` until it reports
/// a terminal status. A flat method -> response map cannot express "in
/// progress twice, then Ok", so the poller either finishes on the first tick
/// (hiding all activation latency) or never finishes at all.
class KdfScript {
  KdfScript();

  final Map<String, List<KdfResponder>> _sequences = {};
  final Map<String, KdfResponder> _defaults = {};
  final Map<String, int> _counts = {};

  /// Called when KDF is (re)started, with the start parameters.
  ///
  /// KDF is stateful and several RPCs answer differently before and after a
  /// wallet has been activated - `get_wallet_names` most importantly, since
  /// registration requires the wallet to be *absent* and the post-sign-in
  /// identity check requires it to be *present*. This is the hook a script
  /// uses to move between those answers.
  void Function(Map<String, dynamic> startParams)? onKdfStart;

  /// Records how many times each method was called. The point of the harness
  /// is to make RPC amplification measurable, so this is part of the result,
  /// not debug output.
  Map<String, int> get invocationCounts => Map.unmodifiable(_counts);

  int callsTo(String method) => _counts[method] ?? 0;

  /// Every method seen, in call order, with duplicates. Useful for asserting
  /// on ordering (e.g. that a cached read happened before activation).
  final List<String> callLog = [];

  /// Always answer [method] with [responder].
  void on(String method, KdfResponder responder) {
    _defaults[method] = responder;
  }

  /// Answer [method] with a fixed [result] payload.
  void reply(String method, Map<String, dynamic> result) {
    on(method, (_) => result);
  }

  /// Answer successive calls to [method] with [responders] in order; once
  /// exhausted, fall back to the last one (so a poller that keeps polling
  /// keeps seeing the terminal state rather than falling off the end).
  void sequence(String method, List<KdfResponder> responders) {
    _sequences[method] = responders;
  }

  /// Never answer [method]. Models a KDF that accepted the request and then
  /// stopped making progress - the exact shape the activation deadline exists
  /// for, and one a real KDF cannot be asked for on demand.
  void hang(String method) {
    on(method, (_) => Completer<Map<String, dynamic>>().future);
  }

  /// Resolves the response for [request], or null when nothing is scripted.
  FutureOr<Map<String, dynamic>>? respondTo(Map<String, dynamic> request) {
    final method = request['method'] as String? ?? '<unknown>';
    final index = _counts[method] ?? 0;
    _counts[method] = index + 1;
    callLog.add(method);

    final sequence = _sequences[method];
    if (sequence != null && sequence.isNotEmpty) {
      final responder = index < sequence.length
          ? sequence[index]
          : sequence.last;
      return responder(request);
    }

    return _defaults[method]?.call(request);
  }
}
