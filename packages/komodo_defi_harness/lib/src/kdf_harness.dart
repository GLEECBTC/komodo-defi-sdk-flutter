import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_harness/src/kdf_port.dart';
import 'package:komodo_defi_harness/src/kdf_process_requirements.dart';
import 'package:komodo_defi_harness/src/process_kdf_operations.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';
import 'package:komodo_defi_harness/src/replay_kdf_operations.dart';
import 'package:komodo_defi_harness/src/secret.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Which derivation mode the wallet signs in with.
///
/// This single switch is the entire HD/iguana difference as far as the app is
/// concerned - it becomes `AuthOptions.derivationMethod` and reaches KDF as
/// `enable_hd`. Nothing in this repo's test suites exercised the HD branch
/// before this harness; the integration suite signs in as iguana only.
enum KdfWalletType { hd, iguana }

/// The rpc password both tiers use.
///
/// Must not contain the word "password": a real KDF refuses to start with
/// `Password can't contain the word password` (mm2:359), and the replay tier
/// would never catch that because nothing validates it there.
const String kHarnessRpcPassword = 'Harness1!Rpc2Secret';

/// The wallet types this run should exercise.
///
/// Defaults to both. `KDF_HARNESS_WALLET_TYPE=hd|iguana` narrows it, which is
/// what makes the CI matrix real rather than decorative: without it both matrix
/// legs would run both derivation modes and report the same thing twice, and a
/// failure would not say which mode broke.
List<KdfWalletType> get harnessWalletTypes {
  final requested = Platform.environment['KDF_HARNESS_WALLET_TYPE']
      ?.trim()
      .toLowerCase();
  if (requested == null || requested.isEmpty) return KdfWalletType.values;
  return KdfWalletType.values
      .where((type) => type.name == requested)
      .toList(growable: false);
}

/// Wall-clock for each phase of bringing a wallet up.
///
/// Kept as separate phases on purpose. A single "login took N ms" number hides
/// which layer moved, and the phases have genuinely different owners: KDF boot
/// is the backend, `sdkInit` is config parsing, `signIn` is the auth mutex plus
/// identity RPCs, and the balance phases are activation.
class KdfHarnessMetrics {
  final Map<String, int> _phases = {};
  final Map<String, int> _counters = {};

  Map<String, int> get phases => Map.unmodifiable(_phases);

  /// Non-duration measurements - RPC volume, emission counts.
  ///
  /// Kept apart from [phases] so a regression gate can treat them differently:
  /// a duration is compared against a baseline with a tolerance, whereas a
  /// count is a shape observation that a machine should record and a human
  /// should read. Conflating them is how "480 identity RPCs per login" stayed
  /// invisible for as long as it did.
  Map<String, int> get counters => Map.unmodifiable(_counters);

  int? operator [](String phase) => _phases[phase];

  Future<T> measure<T>(String phase, Future<T> Function() body) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await body();
    } finally {
      stopwatch.stop();
      _phases[phase] = stopwatch.elapsedMilliseconds;
    }
  }

  void record(String phase, int milliseconds) => _phases[phase] = milliseconds;

  void count(String name, int value) => _counters[name] = value;

  Map<String, Object?> toJson() => {'phases': phases, 'counters': counters};

  @override
  String toString() => [
    ..._phases.entries.map((e) => '${e.key}=${e.value}ms'),
    ..._counters.entries.map((e) => '${e.key}=${e.value}'),
  ].join(' ');
}

/// Boots a real [KomodoDefiSdk] against a scripted fake KDF.
///
/// The SDK, auth, activation, pubkey and balance layers are all the production
/// ones - only the RPC backend is replaced. So a measurement here is the SDK's
/// own orchestration cost, isolated from network variance, and an assertion
/// here is about real behaviour rather than a mock of it.
///
/// The same class also fronts the **process tier** via [KdfHarness.process],
/// which spawns the real KDF binary. That tier needs a 120 MB build artifact,
/// the fixed port 7783 (the auth path never overrides `generateWithDefaults`'
/// default) and live electrum servers, so it belongs in an opt-in nightly job
/// rather than a per-PR gate - see the README.
class KdfHarness {
  KdfHarness._({
    required this.sdk,
    required this.framework,
    required this.metrics,
    required Directory workspace,
    required List<Secret> secrets,
    KdfScript? script,
    ReplayKdfOperations? operations,
    ProcessKdfOperations? processOperations,
    HttpOverrides? suppressedHttpOverrides,
  }) : _script = script,
       _operations = operations,
       _processOperations = processOperations,
       _suppressedHttpOverrides = suppressedHttpOverrides,
       _workspace = workspace,
       _secrets = secrets;

  final KomodoDefiSdk sdk;
  final KomodoDefiFramework framework;
  final KdfHarnessMetrics metrics;

  final KdfScript? _script;
  final ReplayKdfOperations? _operations;
  final ProcessKdfOperations? _processOperations;

  /// The script driving the replay backend.
  ///
  /// Throws on the process tier, where there is nothing to script: a real KDF
  /// decides its own responses. A test that reaches for this is a replay-tier
  /// test, and should say so by using [KdfHarness.replayed].
  KdfScript get script =>
      _script ??
      (throw StateError(
        'This harness is running a real KDF, which has no script. Use '
        'KdfHarness.replayed for tests that assert on RPC content or volume.',
      ));

  /// The replay backend. Throws on the process tier; see [script].
  ReplayKdfOperations get operations =>
      _operations ??
      (throw StateError(
        'This harness is running a real KDF. Use `processOperations` for the '
        'spawned-binary backend.',
      ));

  /// The spawned-KDF backend, or null on the replay tier.
  ProcessKdfOperations? get processOperations => _processOperations;

  /// True when a real KDF binary is behind this harness.
  bool get isProcessTier => _processOperations != null;

  /// The binding's HTTP stub, set aside by [KdfHarness.process] and put back
  /// in [dispose] so later replay tests stay hermetic.
  final HttpOverrides? _suppressedHttpOverrides;

  final Directory _workspace;
  final List<Secret> _secrets;

  /// Redacted log lines captured from the framework.
  final List<String> logs = [];

  /// Brings up an SDK that is running but **not** signed in, so the sign-in
  /// itself is measurable.
  ///
  /// The step order below is load-bearing; see the inline notes.
  static Future<KdfHarness> replayed({
    required KdfScript script,
    Duration rpcLatency = Duration.zero,
    KomodoDefiSdkConfig? config,
    bool requireIsolatedPort = true,
  }) async {
    // 1. Binding first - everything below touches platform channels.
    TestWidgetsFlutterBinding.ensureInitialized();

    final workspace = await Directory.systemTemp.createTemp('kdf_harness_');

    // 2. One password, used for both the host config and the value auth reads
    //    back out of secure storage.
    const rpcPassword = kHarnessRpcPassword;
    final secrets = <Secret>[const Secret(rpcPassword)];

    // 3. Prove the tier is hermetic instead of assuming it.
    //
    //    `TestWidgetsFlutterBinding` installs `_MockHttpOverrides`
    //    (flutter_test `src/_binding_io.dart`, `setupHttpOverrides`), which
    //    makes every `HttpClient` return an empty 400 and issue no request at
    //    all. That is what actually keeps this tier off the network: the
    //    "Error fetching seed nodes: Status code: 400" and
    //    "[EventStream][IO] Preflight: KDF returned status 400" lines in the
    //    output are the stub answering, not a real server.
    //
    //    It matters because two things here escape the `mm2Rpc` replay seam -
    //    the seed-node fetch in `KomodoDefiSdk.initialize` and SSE event
    //    streaming, which dials a hardcoded 127.0.0.1:7783. Under the stub
    //    neither can reach anything. With the override cleared - which
    //    [KdfHarness.process] does, because a real KDF needs real sockets -
    //    both would, and a replay measurement could quietly pick up a live
    //    KDF's balance events.
    //
    //    So assert the stub is in place rather than probing the port: the port
    //    probe can only ever see the stub's 400 and would be dead code.
    if (requireIsolatedPort) requireHermeticHttp();

    // 4. MANDATORY, and the single non-obvious trap in this whole class.
    //    `KomodoDefiSdk.fromFramework` passes `hostConfig: null` down to
    //    bootstrap, which mints its *own* rpc password for auth's LocalConfig
    //    by reading `rpc_password` out of secure storage. If that value does
    //    not match the one in the host config below, `startKdf` throws
    //    ArgumentError on a password mismatch, and the failure surfaces
    //    nowhere near this line.
    FlutterSecureStorage.setMockInitialValues({'rpc_password': rpcPassword});

    // 5. Isolate everything the SDK persists: Hive boxes, the pubkey cache,
    //    the activation config store and tx history all resolve through
    //    path_provider, so without this a harness run would read and write the
    //    developer's real wallet data.
    PathProviderPlatform.instance = _WorkspacePathProvider(workspace);

    final metrics = KdfHarnessMetrics();
    final operations = ReplayKdfOperations(script, rpcLatency: rpcLatency);
    final harnessLogs = <String>[];

    final framework = KomodoDefiFramework.createWithOperations(
      hostConfig: LocalConfig(rpcPassword: rpcPassword, https: false),
      kdfOperations: operations,
      // Redact sink-side: the framework echoes start parameters, which carry
      // the passphrase and both passwords.
      externalLogger: (line) => harnessLogs.add(redactSecrets(line, secrets)),
    );

    final sdk = KomodoDefiSdk.fromFramework(framework, config: config);
    await metrics.measure('sdk_init_ms', sdk.initialize);

    final harness = KdfHarness._(
      sdk: sdk,
      framework: framework,
      script: script,
      operations: operations,
      metrics: metrics,
      workspace: workspace,
      secrets: secrets,
    );
    harness.logs.addAll(harnessLogs);
    return harness;
  }

  /// Boots an SDK against the **real KDF binary**, or returns null.
  ///
  /// Null - never a throw - is the answer whenever the tier simply cannot run:
  /// no binary (the transformer has not fetched the 120 MB artifact), no seed,
  /// or [KdfProcessRequirements.environmentVariable] not set. Those are the
  /// normal states of a fresh clone and of every per-PR run, and a test that
  /// gets null should skip with the reason from [KdfProcessRequirements.check].
  ///
  /// Gating is on an explicit env var rather than on binary-existence, because
  /// the SDK's own `flutter-tests.yml` runs the build transformer: an existence
  /// check would not skip there, and a real KDF would spawn inside a workflow
  /// that has no timeout for it.
  ///
  /// The seed comes only from the environment ([KdfTestSeed.fromEnv]) and is
  /// wrapped in [Secret]. Never log it, never commit it, and never upload the
  /// workspace as a CI artifact - it contains the wallet database.
  static Future<KdfHarness?> process({
    required KdfWalletType walletType,
    String walletName = 'harness-wallet',
    String password = 'harness-Process1!',
    KomodoDefiSdkConfig? config,
    bool disableP2p = true,
    Duration startupTimeout = const Duration(seconds: 60),
    int rpcPort = kDefaultKdfRpcPort,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final requirements = await KdfProcessRequirements.check(port: rpcPort);
    if (!requirements.isSatisfied) return null;

    // The binding installs `_MockHttpOverrides`, which makes every HttpClient
    // return an empty 400 and issue no request (flutter_test
    // `src/_binding_io.dart`, `setupHttpOverrides`). That is exactly right for
    // the replay tier and fatal here: this tier's whole point is to talk to a
    // KDF over a real socket, and with the stub in place every RPC to the
    // process we just spawned answers 400. The symptom is not an obvious
    // networking error - it is `KDF RPC did not become ready within 15
    // seconds`, from `_waitUntilKdfRpcReady`, pointing at KDF rather than at
    // the test binding.
    //
    // Restored in [dispose] so a replay test later in the same run does not
    // silently regain egress; [requireHermeticHttp] fails loudly if it does.
    final suppressedHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;

    final workspace = await Directory.systemTemp.createTemp('kdf_process_');
    // KDF rejects any rpc password containing the word "password" ("Password
    // can't contain the word password", mm2:359), which the replay tier never
    // exercises because nothing validates it there. Kept in sync with the
    // replay tier's so neither reads as an example worth copying.
    const rpcPassword = kHarnessRpcPassword;
    final seed = requirements.seed!;
    final secrets = <Secret>[
      const Secret(rpcPassword),
      seed.value,
      Secret(password),
    ];

    // Same mandatory step as the replay tier, same reason: bootstrap mints
    // auth's rpc password out of secure storage and `startKdf` rejects a
    // mismatch far from the cause.
    FlutterSecureStorage.setMockInitialValues({'rpc_password': rpcPassword});
    PathProviderPlatform.instance = _WorkspacePathProvider(workspace);

    final harnessLogs = <String>[];
    void log(String line) => harnessLogs.add(redactSecrets(line, secrets));

    // One config object decides the port for everything downstream: the
    // startup JSON handed to the binary, the RPC client, and the SSE endpoint.
    // Before `LocalConfig` carried a port, those three could not agree on
    // anything other than 7783.
    final hostConfig = LocalConfig(
      rpcPassword: rpcPassword,
      https: false,
      port: rpcPort,
    );

    final operations = ProcessKdfOperations(
      binary: requirements.binary!,
      config: hostConfig,
      workspace: workspace,
      logCallback: log,
      startupTimeout: startupTimeout,
      disableP2p: disableP2p,
    );

    final metrics = KdfHarnessMetrics();
    final framework = KomodoDefiFramework.createWithOperations(
      hostConfig: hostConfig,
      kdfOperations: operations,
      externalLogger: log,
    );

    final sdk = KomodoDefiSdk.fromFramework(framework, config: config);
    await metrics.measure('sdk_init_ms', sdk.initialize);

    final harness = KdfHarness._(
      sdk: sdk,
      framework: framework,
      processOperations: operations,
      metrics: metrics,
      workspace: workspace,
      secrets: secrets,
      suppressedHttpOverrides: suppressedHttpOverrides,
    );
    harness.logs.addAll(harnessLogs);

    // `kdf_binary` boot is charged to its own phase: on the process tier this
    // is where the 120 MB binary starts and opens its RPC port, and folding it
    // into `auth_signin_ms` would make the two tiers' sign-in numbers
    // incomparable.
    try {
      await metrics.measure(
        'kdf_boot_and_signin_ms',
        () => harness.signIn(
          walletType: walletType,
          walletName: walletName,
          password: password,
          mnemonic: Mnemonic.plaintext(seed.value.reveal()),
        ),
      );
    } catch (error, stackTrace) {
      // A real KDF reports why it refused to start on its own stdout, and the
      // auth layer maps that to a generic `walletStartFailed` with no detail.
      // Re-raising with the captured (and redacted) log tail is the difference
      // between "invalid parameters" and "Cannot disable P2P while seed nodes
      // are configured". Teardown first: a half-started KDF still holds the
      // port.
      harness.logs.addAll(harnessLogs.skip(harness.logs.length));
      final tail = harness.logs.length > 40
          ? harness.logs.sublist(harness.logs.length - 40)
          : harness.logs;
      await harness.dispose();
      Error.throwWithStackTrace(
        StateError(
          'Process-tier sign-in failed: $error\n'
          '--- KDF log tail (redacted) ---\n${tail.join('\n')}',
        ),
        stackTrace,
      );
    }
    return harness;
  }

  /// Identity RPCs. Counted as a pair because they are issued as a pair:
  /// `_getActiveUser` reads the active wallet, then
  /// `_ensureAuthenticatedWalletIdentity` reads the pubkey hash, on every
  /// single `getActiveUser()` - and `getActiveUser` is called from the auth
  /// write lock by nearly every SDK subsystem.
  static const List<String> identityRpcMethods = [
    'get_wallet_names',
    'get_public_key_hash',
  ];

  /// Per-method call count from whichever backend is behind this harness.
  int callsTo(String method) =>
      _script?.callsTo(method) ?? _processOperations?.callsTo(method) ?? 0;

  int get _totalRpcCount =>
      _operations?.requests.length ?? _processOperations?.totalCalls ?? 0;

  int _identityRpcCount() =>
      identityRpcMethods.fold(0, (sum, method) => sum + callsTo(method));

  /// Registers (or signs into) a wallet and records `auth_signin_ms`.
  ///
  /// [walletType] is the HD switch. Everything else is incidental.
  ///
  /// Also records `identity_rpcs_per_signin` as a **delta** across this call,
  /// so bootstrap's own identity reads are not charged to the sign-in. The
  /// number is deliberately not asserted anywhere: it is the amplification
  /// signal (~480 per login in the field), and pinning an exact value would
  /// turn every legitimate call-site change into a red build. Record it, plot
  /// it, read it.
  Future<KdfUser> signIn({
    required KdfWalletType walletType,
    String walletName = 'harness-wallet',
    String password = 'harness-Password1!',
    Mnemonic? mnemonic,
    bool register = true,
  }) async {
    _secrets.add(Secret(password));
    final options = AuthOptions(
      derivationMethod: walletType == KdfWalletType.hd
          ? DerivationMethod.hdWallet
          : DerivationMethod.iguana,
    );
    final identityRpcsBefore = _identityRpcCount();
    final rpcsBefore = _totalRpcCount;
    final user = await metrics.measure('auth_signin_ms', () async {
      return register
          ? sdk.auth.register(
              walletName: walletName,
              password: password,
              options: options,
              mnemonic: mnemonic,
            )
          : sdk.auth.signIn(
              walletName: walletName,
              password: password,
              options: options,
            );
    });
    metrics
      ..count(
        'identity_rpcs_per_signin',
        _identityRpcCount() - identityRpcsBefore,
      )
      ..count('rpcs_per_signin', _totalRpcCount - rpcsBefore);
    return user;
  }

  /// Times the balance path for [assetId], split into the numbers that
  /// actually mean different things.
  ///
  /// | phase | what it is |
  /// |---|---|
  /// | `first_paint_ms` | the first `BalanceInfo` of any provenance |
  /// | `activation_ms` | when the asset reached [AssetActivationStatus.active] |
  /// | `first_post_activation_balance_ms` | the first balance that landed once the asset was actually enabled |
  ///
  /// **`first_paint_ms` is not a measure of activation, and gating on it alone
  /// would let activation regress to minutes with a green metric.** On a cold
  /// first-time asset in a new wallet, `BalanceManager` adds a synthetic zero
  /// *before* `_ensureAssetActivated` is called; on a warm start it emits a
  /// hydrated cached balance, also before activation. Both are legitimate
  /// paints and both are supposed to be fast - they are the whole point of the
  /// hydration work - but neither says anything about how long KDF took.
  ///
  /// Post-activation is resolved against the observed activation state rather
  /// than by counting emissions ("the second one"). Emission order is not a
  /// contract: the stale-balance guard, the polling fallback and the pubkey
  /// hint listener can each add one, so an ordinal would silently start
  /// measuring a different thing the moment any of them fires first.
  ///
  /// The two subscriptions cannot race in the direction that matters: the
  /// coordinator publishes `active` before `activateAsset` completes, and the
  /// post-activation emission is separated from that by a full `getBalance`
  /// round trip.
  Future<void> measureFirstBalance(AssetId assetId, {Duration? timeout}) async {
    final stopwatch = Stopwatch()..start();
    final firstPaint = Completer<void>();
    final postActivation = Completer<void>();
    final activated = Completer<void>();
    var emissions = 0;

    final activationSubscription = sdk
        .watchActivationStateOf(assetId)
        .listen((state) {
          if (state?.status == AssetActivationStatus.active &&
              !activated.isCompleted) {
            metrics.record('activation_ms', stopwatch.elapsedMilliseconds);
            activated.complete();
          }
        }, onError: (Object _) {});

    final subscription = sdk.balances.watchBalance(assetId).listen((_) {
      emissions++;
      if (!firstPaint.isCompleted) {
        metrics.record('first_paint_ms', stopwatch.elapsedMilliseconds);
        firstPaint.complete();
      }
      if (activated.isCompleted && !postActivation.isCompleted) {
        metrics.record(
          'first_post_activation_balance_ms',
          stopwatch.elapsedMilliseconds,
        );
        postActivation.complete();
      }
    }, onError: (Object _) {});

    try {
      await Future.wait([
        firstPaint.future,
        postActivation.future,
      ]).timeout(timeout ?? const Duration(seconds: 30));
    } on TimeoutException {
      // Leave whichever phases were reached recorded. A caller asserting on a
      // missing phase gets a clearer failure than a swallowed timeout, and the
      // emission count below says which side of the split fell short.
    } finally {
      metrics.count('balance_emissions', emissions);
      await subscription.cancel();
      await activationSubscription.cancel();
    }
  }

  /// Stops KDF, closes process-global storage and deletes the workspace.
  /// Safe to call twice.
  Future<void> dispose() async {
    // First, and outside every try: the process tier cleared the binding's
    // HTTP stub to get real sockets, and leaving it cleared silently hands
    // network access back to every replay test that runs after this one in the
    // same isolate. That is a wrong-measurement bug, not a crash, so it has to
    // be restored even when the teardown below throws.
    if (_suppressedHttpOverrides != null) {
      HttpOverrides.global = _suppressedHttpOverrides;
    }
    try {
      await sdk.dispose();
    } catch (_) {
      // Teardown is best-effort: a disposal failure must not mask the
      // assertion that actually failed.
    }
    try {
      // Explicit, and not reachable through `sdk.dispose()`: on the process
      // tier this is what kills the spawned KDF. Without it the binary was
      // orphaned (reparented to pid 1) still holding the fixed port, on a
      // database directory this method is about to delete - so the next run,
      // and every run after it, skipped with "port already in use".
      _processOperations?.dispose();
    } catch (_) {}
    try {
      await framework.dispose();
    } catch (_) {}
    try {
      // Hive is a process-global singleton and the SDK does not close its
      // boxes on dispose, so without this the *next* harness in the same test
      // file silently reuses this one's open boxes - pointed at a directory
      // this method is about to delete. The visible symptom is not a crash but
      // a wrong measurement: the second test hydrates the first test's
      // persisted pubkeys, `getPubkeys` returns from cache, and the balance
      // RPC that the test is there to observe never happens. Order-dependent,
      // and green on its own.
      await Hive.close();
    } catch (_) {}
    try {
      if (_workspace.existsSync()) {
        await _workspace.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// Points every path_provider lookup at the harness workspace.
class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this._workspace);

  final Directory _workspace;

  String _dir(String name) {
    final dir = Directory('${_workspace.path}/$name');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('tmp');

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');

  @override
  Future<String?> getLibraryPath() async => _dir('library');

  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');

  @override
  Future<String?> getExternalStoragePath() async => _dir('external');

  @override
  Future<List<String>?> getExternalCachePaths() async => [_dir('external')];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => [_dir('external')];
}
