import 'package:decimal/decimal.dart';
import 'package:komodo_defi_harness/src/kdf_script.dart';

/// One address in a scripted HD `task::account_balance` response.
class HdAddressFixture {
  const HdAddressFixture({
    required this.address,
    required this.derivationPath,
    this.chain = 'External',
    this.spendable = '0',
    this.unspendable = '0',
  });

  final String address;
  final String derivationPath;
  final String chain;
  final String spendable;
  final String unspendable;
}

/// Builds the [KdfScript] for a wallet: the login RPCs, plus whichever
/// activations and balance reads the caller needs.
///
/// This exists because the RPC set a login touches is not obvious from the
/// call sites, and an unscripted method throws (see [KdfScript]). Assembling
/// it by hand once per test produced a lot of duplicated JSON and, worse, hid
/// the moment a new RPC entered the login path behind N identical edits.
///
/// **Task ids are dispatched the way KDF dispatches them.** [KdfScript.sequence]
/// keeps one cursor per *method*, which is exactly right for a single asset and
/// wrong the moment two assets activate concurrently: `task::enable_utxo::status`
/// is the same method for both, so one shared cursor would hand asset B the
/// poll asset A was owed. So `::init` allocates a task id here and `::status`
/// resolves `params.task_id` back to the asset - a per-task cursor, which is
/// what `sequence()` models for the one-asset case and what KDF itself does.
class KdfWalletFixture {
  KdfWalletFixture({
    this.walletName = 'harness-wallet',
    this.walletExists = false,
    this.publicKeyHash = '0123456789abcdef0123456789abcdef01234567',
  });

  final String walletName;

  /// Whether `get_wallet_names` reports the wallet before KDF is started with
  /// it. Registration requires `false`; a plain sign-in requires `true`.
  final bool walletExists;

  /// Must be 40 lowercase hex characters or `_ensureAuthenticatedWalletIdentity`
  /// rejects it outright.
  final String publicKeyHash;

  final Set<String> _enabledCoins = <String>{};
  final Map<int, _Task> _tasks = <int, _Task>{};
  final Map<String, _UtxoActivationSpec> _utxoActivations = {};
  final Map<String, _EthActivationSpec> _ethActivations = {};
  final Map<String, _BalanceSpec> _balances = {};

  /// Methods the fixture should never answer, so the caller can model a KDF
  /// that accepted a request and then stopped making progress.
  final Set<String> _hangingMethods = <String>{};

  int _nextTaskId = 1;

  /// Marks [ticker] as already present in `get_enabled_coins`, i.e. a warm
  /// re-login rather than a first activation.
  void alreadyEnabled(String ticker) => _enabledCoins.add(ticker);

  /// Scripts a task-based UTXO/SmartChain activation.
  ///
  /// [inProgressPolls] is the number of `InProgress` statuses before `Ok`.
  /// Keep it above zero: a status that reports `Ok` on the very first poll
  /// hides the entire polling loop, which is where activation latency lives.
  void enableUtxo(String ticker, {int inProgressPolls = 2}) {
    _utxoActivations[ticker] = _UtxoActivationSpec(inProgressPolls);
  }

  /// Scripts a platform batch activation (`enable_eth_with_tokens`), which is
  /// a single non-task RPC rather than an init/status pair.
  void enableEthWithTokens(
    String platformTicker, {
    List<String> tokens = const [],
    String address = '0x0000000000000000000000000000000000000001',
    String spendable = '0',
    int currentBlock = 1,
  }) {
    _ethActivations[platformTicker] = _EthActivationSpec(
      tokens: tokens,
      address: address,
      spendable: spendable,
      currentBlock: currentBlock,
    );
  }

  /// Scripts the balance read for [ticker] in **both** derivation modes.
  ///
  /// Iguana resolves pubkeys through `my_balance`; HD resolves them through
  /// `task::scan_for_new_addresses` followed by `task::account_balance`. Which
  /// one runs is decided by [KdfWalletType] at sign-in, not by the fixture, so
  /// scripting both is what lets a single fixture serve the hd/iguana matrix.
  void balance(
    String ticker, {
    String address = 'RHarnessAddress000000000000000000',
    String spendable = '0',
    String unspendable = '0',
    List<HdAddressFixture>? hdAddresses,
    int accountBalanceInProgressPolls = 1,
  }) {
    _balances[ticker] = _BalanceSpec(
      address: address,
      spendable: spendable,
      unspendable: unspendable,
      hdAddresses:
          hdAddresses ??
          [
            HdAddressFixture(
              address: address,
              derivationPath: "m/44'/141'/0'/0/0",
              spendable: spendable,
              unspendable: unspendable,
            ),
          ],
      accountBalanceInProgressPolls: accountBalanceInProgressPolls,
    );
  }

  /// Never answer [method]. See [KdfScript.hang] - this is the shape the
  /// activation deadline exists for, and one a real KDF cannot be asked for.
  void hang(String method) => _hangingMethods.add(method);

  KdfScript build() {
    var walletActivated = walletExists;

    final script = KdfScript()
      ..reply('version', {'result': 'harness-replay'})
      ..reply('stream::shutdown_signal::enable', {
        'mmrpc': '2.0',
        'result': {'streamer_id': 'SHUTDOWN'},
      })
      // KDF answers this differently before and after the wallet is activated:
      // registration requires it absent, the post-sign-in identity check
      // requires it present. A constant answer cannot satisfy both.
      ..on('get_wallet_names', (_) {
        return {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': walletActivated ? [walletName] : <String>[],
            'activated_wallet': walletActivated ? walletName : null,
          },
        };
      })
      ..onKdfStart = ((startParams) {
        if ((startParams['wallet_name'] as String?)?.isNotEmpty ?? false) {
          walletActivated = true;
        }
      })
      ..reply('get_public_key_hash', {
        'mmrpc': '2.0',
        'result': {'public_key_hash': publicKeyHash},
      })
      // A deterministic, well-known test vector. The harness never talks to a
      // chain, so this cannot control funds.
      ..reply('get_mnemonic', {
        'mmrpc': '2.0',
        'result': {
          'format': 'plaintext',
          'mnemonic':
              'abandon abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon about',
        },
      })
      // The single source of truth for "is this asset active". Activation
      // flips entries in [_enabledCoins]; the coordinator then polls this with
      // forceRefresh until the coin shows up, so a fixture that forgets to
      // flip it produces the real "activated but never became available"
      // failure rather than a mock-shaped one.
      ..on('get_enabled_coins', (_) {
        return {
          'mmrpc': '2.0',
          'result': {
            'coins': _enabledCoins.map((t) => {'ticker': t}).toList(),
          },
        };
      });

    _scriptUtxoActivation(script);
    _scriptEthActivation(script);
    _scriptBalances(script);

    for (final method in _hangingMethods) {
      script.hang(method);
    }

    return script;
  }

  void _scriptUtxoActivation(KdfScript script) {
    if (_utxoActivations.isEmpty) return;

    script
      ..on('task::enable_utxo::init', (request) {
        final ticker = _stringParam(request, 'ticker');
        final spec =
            _utxoActivations[ticker] ??
            (throw StateError(
              'No UTXO activation scripted for "$ticker". Add one with '
              'fixture.enableUtxo("$ticker").',
            ));
        final taskId = _nextTaskId++;
        _tasks[taskId] = _Task(
          ticker: ticker,
          remainingPolls: spec.inProgressPolls,
        );
        return {
          'mmrpc': '2.0',
          'result': {'task_id': taskId},
        };
      })
      ..on('task::enable_utxo::status', (request) {
        final task = _taskFor(request);
        if (task.remainingPolls > 0) {
          task.remainingPolls--;
          // These are the real KDF status strings; the strategy maps them to
          // progress percentages, so using them keeps the progress stream
          // shaped like production.
          return _taskInProgress(
            task.remainingPolls > 0
                ? 'ConnectingElectrum'
                : 'LoadingBlockchain',
          );
        }
        _enabledCoins.add(task.ticker);
        // `TaskStatusResponse.parse` reads `result.details` as a String.
        return {
          'mmrpc': '2.0',
          'result': {'status': 'Ok', 'details': 'activated'},
        };
      });
  }

  void _scriptEthActivation(KdfScript script) {
    if (_ethActivations.isEmpty) return;

    script.on('enable_eth_with_tokens', (request) {
      final ticker = _stringParam(request, 'ticker');
      final spec =
          _ethActivations[ticker] ??
          (throw StateError(
            'No eth-with-tokens activation scripted for "$ticker". Add one '
            'with fixture.enableEthWithTokens("$ticker").',
          ));
      _enabledCoins
        ..add(ticker)
        ..addAll(spec.tokens);

      final balances = <String, dynamic>{
        for (final t in [ticker, ...spec.tokens])
          t: {
            'spendable': t == ticker ? spec.spendable : '0',
            'unspendable': '0',
          },
      };
      return {
        'mmrpc': '2.0',
        'result': {
          'current_block': spec.currentBlock,
          'wallet_balance': {
            'wallet_type': 'Iguana',
            'accounts': [
              {
                'account_index': 0,
                'derivation_path': "m/44'/60'/0'",
                'total_balance': balances,
                'addresses': [
                  {
                    'address': spec.address,
                    'derivation_path': "m/44'/60'/0'/0/0",
                    'chain': 'External',
                    'balance': balances,
                  },
                ],
              },
            ],
          },
          'nfts_infos': <String, dynamic>{},
        },
      };
    });
  }

  void _scriptBalances(KdfScript script) {
    if (_balances.isEmpty) return;

    script
      // Iguana: SingleAddressStrategy.
      ..on('my_balance', (request) {
        final coin = request['coin'] as String? ?? '';
        final spec = _balanceSpecFor(coin);
        // `BalanceInfo.fromJson` uses `singleWhere` over the total/balance
        // aliases, so emitting both `balance` and `total` throws.
        return {
          'address': spec.address,
          'balance': spec.total,
          'unspendable_balance': spec.unspendable,
          'coin': coin,
        };
      })
      // HD: the scan runs on every fresh pubkey fetch, ahead of the balance
      // read. This is the pair `test_integration` never exercised.
      ..on('task::scan_for_new_addresses::init', (request) {
        final coin = _stringParam(request, 'coin');
        final taskId = _nextTaskId++;
        _tasks[taskId] = _Task(ticker: coin, remainingPolls: 0);
        return {
          'mmrpc': '2.0',
          'result': {'task_id': taskId},
        };
      })
      ..on('task::scan_for_new_addresses::status', (request) {
        // Resolved for its side effect: an unknown task_id is a scripting bug
        // and should fail here rather than yield a plausible empty scan.
        _taskFor(request);
        return {
          'mmrpc': '2.0',
          'result': {
            'status': 'Ok',
            'details': {
              'account_index': 0,
              'derivation_path': "m/44'/141'/0'",
              'new_addresses': <Map<String, dynamic>>[],
            },
          },
        };
      })
      ..on('task::account_balance::init', (request) {
        final coin = _stringParam(request, 'coin');
        final spec = _balanceSpecFor(coin);
        final taskId = _nextTaskId++;
        _tasks[taskId] = _Task(
          ticker: coin,
          remainingPolls: spec.accountBalanceInProgressPolls,
        );
        return {
          'mmrpc': '2.0',
          'result': {'task_id': taskId},
        };
      })
      ..on('task::account_balance::status', (request) {
        final task = _taskFor(request);
        if (task.remainingPolls > 0) {
          task.remainingPolls--;
          return _taskInProgress('RequestingAccountBalance');
        }
        final spec = _balanceSpecFor(task.ticker);
        final totalBalance = {
          task.ticker: {
            'spendable': spec.spendable,
            'unspendable': spec.unspendable,
          },
        };
        return {
          'mmrpc': '2.0',
          'result': {
            'status': 'Ok',
            'details': {
              'account_index': 0,
              'derivation_path': "m/44'/141'/0'",
              'total_balance': totalBalance,
              'addresses': [
                for (final address in spec.hdAddresses)
                  {
                    'address': address.address,
                    'derivation_path': address.derivationPath,
                    'chain': address.chain,
                    'balance': {
                      task.ticker: {
                        'spendable': address.spendable,
                        'unspendable': address.unspendable,
                      },
                    },
                  },
              ],
            },
          },
        };
      });
  }

  _BalanceSpec _balanceSpecFor(String ticker) {
    return _balances[ticker] ??
        (throw StateError(
          'No balance scripted for "$ticker". Add one with '
          'fixture.balance("$ticker").',
        ));
  }

  _Task _taskFor(Map<String, dynamic> request) {
    final params = request['params'];
    final taskId = params is Map ? params['task_id'] as int? : null;
    final task = _tasks[taskId];
    if (task == null) {
      throw StateError(
        'Status polled for unknown task_id $taskId. The fixture allocates ids '
        'in ::init, so this means a status poll arrived for a task that was '
        'never started.',
      );
    }
    return task;
  }

  static String _stringParam(Map<String, dynamic> request, String key) {
    final params = request['params'];
    if (params is Map && params[key] is String) return params[key] as String;
    throw StateError('Request is missing params.$key: $request');
  }

  static Map<String, dynamic> _taskInProgress(String status) => {
    'mmrpc': '2.0',
    'result': {'status': status, 'details': status},
  };
}

class _Task {
  _Task({required this.ticker, required this.remainingPolls});

  final String ticker;
  int remainingPolls;
}

class _UtxoActivationSpec {
  const _UtxoActivationSpec(this.inProgressPolls);

  final int inProgressPolls;
}

class _EthActivationSpec {
  const _EthActivationSpec({
    required this.tokens,
    required this.address,
    required this.spendable,
    required this.currentBlock,
  });

  final List<String> tokens;
  final String address;
  final String spendable;
  final int currentBlock;
}

class _BalanceSpec {
  const _BalanceSpec({
    required this.address,
    required this.spendable,
    required this.unspendable,
    required this.hdAddresses,
    required this.accountBalanceInProgressPolls,
  });

  final String address;
  final String spendable;
  final String unspendable;
  final List<HdAddressFixture> hdAddresses;
  final int accountBalanceInProgressPolls;

  /// `my_balance` reports a total plus the unspendable part, where the HD
  /// response reports spendable and unspendable. Derive the total so both
  /// scripted shapes describe the same balance.
  String get total =>
      (Decimal.parse(spendable) + Decimal.parse(unspendable)).toString();
}
