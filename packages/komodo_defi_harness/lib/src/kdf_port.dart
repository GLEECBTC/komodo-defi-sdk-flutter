import 'dart:io';

/// The port every KDF in this repo listens on.
///
/// It is effectively fixed, not merely defaulted: `generateWithDefaults` sets
/// it and the auth path never overrides it. So the process tier has to run
/// single-threaded, and there is no ephemeral-port allocator worth building.
const int kdfRpcPort = 7783;

/// Whether anything at all is listening on [port] on loopback.
///
/// Implemented by trying to *bind*: a connect probe cannot distinguish
/// "nothing there" from "there, but not answering yet".
Future<bool> isPortOccupied({int port = kdfRpcPort}) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return false;
  } on SocketException {
    return true;
  }
}

/// Waits for [port] to become free, up to [timeout].
///
/// Returns whether it is free. A KDF that has been asked to stop does not
/// release its listener instantly, so back-to-back process-tier tests would
/// otherwise see the previous test's port and skip - which reads as "not
/// configured" rather than "not ready yet", and silently reduces the tier to
/// one test per run.
Future<bool> waitForFreeKdfPort({
  int port = kdfRpcPort,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (!await isPortOccupied(port: port)) return true;
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future<void>.delayed(pollInterval);
  }
}

/// Throws unless [port] is free. For the **process tier**, which binds it.
///
/// A leaked 120 MB KDF holding this port breaks every subsequent run, and the
/// failure it produces without this check lands somewhere unhelpful.
Future<void> requireFreeKdfPort({int port = kdfRpcPort}) async {
  if (!await isPortOccupied(port: port)) return;
  throw StateError(
    'Something is already listening on 127.0.0.1:$port, and KDF\'s port is '
    'fixed so the harness cannot move out of the way.\n'
    '  - leftover harness KDF: lsof -ti tcp:$port | xargs kill\n'
    '  - your own wallet build: stop it for the duration of the run\n'
    'Find out which: lsof -nP -iTCP:$port',
  );
}

/// Asserts that no `HttpClient` in this isolate can reach the network.
///
/// For the **replay tier**, whose hermeticity does not come from the replay
/// seam alone. `mm2Rpc` is faked, but two things go around it:
///
/// - `KomodoDefiSdk.initialize` fetches seed nodes over HTTP
///   (`SeedNodeUpdater.fetchSeedNodes`).
/// - SSE event streaming dials a hardcoded `127.0.0.1:7783`
///   (komodo_defi_framework `lib/src/streaming/event_streaming_platform_io.dart`,
///   `_buildEventsUrl`).
///
/// What actually stops both is `TestWidgetsFlutterBinding`, which installs
/// `_MockHttpOverrides` (flutter_test `src/_binding_io.dart`,
/// `setupHttpOverrides`): every `HttpClient` returns an empty 400 and issues no
/// request. That is why a replay run prints `Failed to fetch seed nodes.
/// Status code: 400` and `Preflight: KDF returned status 400` - the stub, not a
/// server.
///
/// [KdfHarness.process] clears that override, because a real KDF needs real
/// sockets. If it fails to restore it, a subsequent replay test in the same run
/// would silently regain egress: the seed-node fetch becomes a real request
/// charged to `sdk_init_ms`, and the SSE preflight can reach a live KDF whose
/// balance events then land in the cache being measured. Green run, wrong
/// numbers.
///
/// A port probe cannot catch that - under the stub it only ever sees the 400.
/// Checking the override itself is the test that actually holds.
void requireHermeticHttp() {
  if (HttpOverrides.current != null) return;
  throw StateError(
    'HttpOverrides.global is not set, so this isolate has real network '
    'access and the replay tier is no longer hermetic.\n'
    'TestWidgetsFlutterBinding installs a stub that makes every HttpClient '
    'return 400 without issuing a request; something has cleared it - most '
    'likely a process-tier harness that did not restore it in dispose.\n'
    'Without it the seed-node fetch is charged to sdk_init_ms and SSE event '
    'streaming can attach to a real KDF on 127.0.0.1:$kdfRpcPort, whose '
    'balance events would be measured as this run\'s.',
  );
}
