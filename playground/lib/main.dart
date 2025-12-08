import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework_example/services/secure_storage_service.dart';
import 'package:komodo_defi_framework_example/widgets/request_playground.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:url_launcher/url_launcher_string.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: MyApp()));
}

class ConfigureDialog extends StatefulWidget {
  const ConfigureDialog({super.key});

  @override
  _ConfigureDialogState createState() => _ConfigureDialogState();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// Generate a random 32 character password for the RPC userpass
String _generateDefaultRpcPassword() =>
    SecurityUtils.generatePasswordSecure(32);

class _ConfigureDialogState extends State<ConfigureDialog> {
  String _selectedHostType = 'local';
  String _selectedProtocol = 'https';
  // Always false and disabled until fully implemented
  bool? _exposeHttp = false;
  // HD wallet mode toggle
  bool _enableHdWallet = false;
  // Flag to determine whether to save wallet password
  bool _saveWalletPassword = false;
  final TextEditingController _walletNameController = TextEditingController();
  final TextEditingController _walletPasswordController =
      TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _awsRegionController = TextEditingController();
  final TextEditingController _awsAccessKeyController = TextEditingController();
  final TextEditingController _awsSecretKeyController = TextEditingController();
  final TextEditingController _awsInstanceTypeController =
      TextEditingController();
  final TextEditingController _rpcPasswordController = TextEditingController(
    text: _generateDefaultRpcPassword(),
  );

  // Controllers for seed node configuration
  final TextEditingController _seedNode1Controller = TextEditingController();
  final TextEditingController _seedNode2Controller = TextEditingController();
  final TextEditingController _seedNode3Controller = TextEditingController();

  // P2P configuration state
  bool _disableP2p = false;
  bool _iAmSeed = false;
  bool _isBootstrapNode = false;

  void _hostTypeChanged(String? value) {
    if (value == null) {
      return;
    }

    setState(() {
      // If current is local and changed to anything else, clear the RPC password
      if (_selectedHostType == 'local' && value != 'local') {
        _rpcPasswordController.text = '';
      } else if (_selectedHostType != 'local' && value == 'local') {
        _rpcPasswordController.text = _generateDefaultRpcPassword();
      }

      _selectedHostType = value;
    });
  }

  bool _passwordVisible = false;
  void _togglePasswordVisibility() {
    setState(() => _passwordVisible = !_passwordVisible);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure KDF'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 300,
          minHeight: 300,
          maxWidth: 300,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: _selectedHostType,
                onChanged: _hostTypeChanged,
                items: const [
                  DropdownMenuItem(
                    value: 'local',
                    child: Text('Embedded Binary'),
                  ),
                  DropdownMenuItem(
                    value: 'remote',
                    child: Text('Network (LAN/Internet)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws',
                    enabled: false,
                    child: Text('AWS (Unavailable)'),
                  ),
                  DropdownMenuItem(
                    value: 'digital-ocean',
                    enabled: false,
                    child: Text('Digital Ocean (Unavailable)'),
                  ),
                ],
              ),
              if (_selectedHostType == 'local') ...[
                TextField(
                  controller: _walletNameController,
                  decoration: const InputDecoration(labelText: 'Wallet Name'),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _walletPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Wallet Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: _togglePasswordVisibility,
                    ),
                  ),
                  obscureText: !_passwordVisible,
                ),

                const SizedBox(height: 16),

                // Add checkbox for wallet password storage option
                CheckboxListTile(
                  value: _saveWalletPassword,
                  onChanged: (value) {
                    setState(() {
                      _saveWalletPassword = value!;
                    });
                  },
                  title: const Text('Save Wallet Password'),
                  subtitle: const Text(
                    'Store the wallet password in secure storage for convenience (use with caution)',
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _passphraseController,
                  decoration: const InputDecoration(
                    labelText: 'Mnemonic/Seed (Optional)',
                    hintText: 'Import existing seed',
                    helperText:
                        'Warning: Never stored, only used during wallet creation',
                    helperStyle: TextStyle(color: Colors.orange),
                  ),
                ),

                const SizedBox(height: 16),

                // HD wallet mode toggle
                CheckboxListTile(
                  value: _enableHdWallet,
                  onChanged: (value) {
                    setState(() {
                      _enableHdWallet = value!;
                    });
                  },
                  title: const Text('Enable HD Wallet'),
                  subtitle: const Text(
                    'Hierarchical Deterministic wallet mode allows for generating multiple addresses from a single seed',
                  ),
                ),
              ],
              if (_selectedHostType == 'local' && kIsWeb) ...[
                CheckboxListTile(
                  value: false,
                  onChanged: null, // Disabled until fully implemented
                  title: const Text('Expose WASM via HTTP'),
                  subtitle: const Text(
                    'Enable this to access the WASM instance through a REST API. '
                    'Accessible at http://localhost:3777',
                  ),
                ),
              ],
              if (_selectedHostType == 'remote') ...[
                DropdownButtonFormField<String>(
                  value: _selectedProtocol,
                  onChanged: (value) => _selectedProtocolChanged(value!),
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  items: const [
                    DropdownMenuItem(value: 'http', child: Text('http')),
                    DropdownMenuItem(
                      value: 'https',
                      child: Text('https (Requires special configuration)'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _rpcPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'RPC Password (userpass)',
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _ipController,
                  decoration: InputDecoration(
                    labelText: 'Host or IP Address',
                    hintText: 'e.g. 123.456.789.012 or example.com',
                    suffixIcon: _selectedHostType == 'remote'
                        ? IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remote Access Setup'),
                                content: SingleChildScrollView(
                                  child: SelectableText(
                                    _remoteAccessTooltipMessage(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),

                const SizedBox(height: 16),

                // Add seed node configuration
                const Text(
                  'Seed Nodes Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Disable P2P'),
                  subtitle: const Text(
                    'Disables network functionality (removes seed nodes)',
                  ),
                  value: _disableP2p,
                  onChanged: (value) {
                    setState(() {
                      _disableP2p = value ?? false;
                      if (_disableP2p) {
                        // Clear seed node fields when P2P is disabled
                        _seedNode1Controller.clear();
                        _seedNode2Controller.clear();
                        _seedNode3Controller.clear();
                        _iAmSeed = false;
                        _isBootstrapNode = false;
                      }
                    });
                  },
                ),

                // Only show seed node configuration if P2P is not disabled
                if (!_disableP2p) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _seedNode1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Seed Node 1',
                      hintText: 'seed01.kmdefi.net',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _seedNode2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Seed Node 2 (Optional)',
                      hintText: 'seed02.kmdefi.net',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _seedNode3Controller,
                    decoration: const InputDecoration(
                      labelText: 'Seed Node 3 (Optional)',
                      hintText: 'seed03.kmdefi.net',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('I am Seed'),
                    subtitle: const Text('Run as a seed node'),
                    value: _iAmSeed,
                    onChanged: (value) {
                      setState(() {
                        _iAmSeed = value ?? false;
                        if (!_iAmSeed) {
                          _isBootstrapNode = false;
                        }
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Is Bootstrap Node'),
                    subtitle: const Text(
                      'Run as a bootstrap node (requires I am Seed)',
                    ),
                    value: _isBootstrapNode,
                    onChanged: _iAmSeed
                        ? (value) {
                            setState(() {
                              _isBootstrapNode = value ?? false;
                            });
                          }
                        : null, // Disable if not a seed node
                  ),
                ],
              ],
              if (_selectedHostType == 'aws') ...[
                TextField(
                  controller: _awsRegionController,
                  decoration: const InputDecoration(labelText: 'AWS Region'),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _awsAccessKeyController,
                  decoration: const InputDecoration(
                    labelText: 'AWS Access Key',
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _awsSecretKeyController,
                  decoration: const InputDecoration(
                    labelText: 'AWS Secret Key',
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _awsInstanceTypeController,
                  decoration: const InputDecoration(labelText: 'Instance Type'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            // Validate required fields before saving
            if (_selectedHostType == 'remote') {
              if (_ipController.text.isEmpty) {
                _showMessage(context, 'Please enter a host or IP address');
                return;
              }
              if (_portController.text.isEmpty) {
                _showMessage(context, 'Please enter a port number');
                return;
              }
              if (_rpcPasswordController.text.isEmpty) {
                _showMessage(context, 'Please enter an RPC password');
                return;
              }
            } else if (_selectedHostType == 'local') {
              // For local configs, ensure wallet name and password are set
              if (_walletNameController.text.isEmpty) {
                _showMessage(context, 'Please enter a wallet name');
                return;
              }
              if (_walletPasswordController.text.isEmpty) {
                _showMessage(context, 'Please enter a wallet password');
                return;
              }
            }

            await _saveConfiguration();
            IKdfHostConfig config;

            // Determine the host configuration.
            switch (_selectedHostType) {
              case 'remote':
                // Use int.tryParse to safely handle port conversion
                final portNumber = int.tryParse(_portController.text);
                if (portNumber == null) {
                  _showMessage(context, 'Invalid port number format');
                  return;
                }
                config = RemoteConfig(
                  rpcPassword: _rpcPasswordController.text,
                  ipAddress: _ipController.text,
                  port: portNumber,
                  https: _selectedProtocol == 'https',
                );
                break;
              case 'aws':
                config = AwsConfig(
                  rpcPassword: _rpcPasswordController.text,
                  region: _awsRegionController.text,
                  accessKey: _awsAccessKeyController.text,
                  secretKey: _awsSecretKeyController.text,
                  instanceType: _awsInstanceTypeController.text,
                  https: _selectedProtocol == 'https',
                );
                break;
              case 'local':
              default:
                config = LocalConfig(
                  rpcPassword: _rpcPasswordController.text,
                  https: _selectedProtocol == 'https',
                );
                break;
            }

            Navigator.of(context).pop({
              'config': config,
              'walletName': _walletNameController.text,
              'walletPassword': _walletPasswordController.text,
              'passphrase': _passphraseController.text,
              'hostType': _selectedHostType,
              'ipAddress': _ipController.text,
              'port': _portController.text,
              'protocol': _selectedProtocol,
              'exposeHttp': _exposeHttp,
              'enableHdWallet': _enableHdWallet,
              'savePassphrase': _saveWalletPassword,
              'seedNode1': _seedNode1Controller.text,
              'seedNode2': _seedNode2Controller.text,
              'seedNode3': _seedNode3Controller.text,
              'disableP2p': _disableP2p,
              'iAmSeed': _iAmSeed,
              'isBootstrapNode': _isBootstrapNode,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _selectedProtocolChanged(String value) {
    if (value == 'http') {
      _showHttpWarning(context);
    }
    setState(() {
      _selectedProtocol = value;
    });
  }

  void _showHttpWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Warning: HTTP is not secure'),
          content: const Text(
            'You have selected HTTP, which is not secure as your RPC password will be sent in plain text, which can be intercepted by malicious actors. '
            'For remotely accessible KDF instances, it is recommended to use a strong (32+ character) RPC password and set the connection to HTTPS.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _remoteAccessTooltipMessage() {
    return '''
1. Setup a server to run KDF and ensure the necessary ports are exposed. Default is `7783`. This can easily be set up using our docker image: https://hub.docker.com/r/komodoofficial/komodo-defi-framework
2. (Optional) Generate a private and public key and set the paths as environment variables using `MM_CERT_PATH` and `MM_CERT_KEY_PATH` or add them to the launch parameter.
3. Set the following parameters in MM2.json or pass them as CLI parameters:
```json
"https": true,
"rpc_local_only": false,
"rpcip": "0.0.0.0",
```
4. If using Docker, run the container with the following comand:
```bash
docker run -p 7783:7783 -v "\$(pwd)":/app -w /app komodoofficial/komodo-defi-framework:dev-latest
```
''';
  }

  @override
  void initState() {
    super.initState();
    _loadSavedConfiguration();
  }

  Future<void> _loadSavedConfiguration() async {
    final secureStorage = SecureStorageService();
    // Host type is stored in 'lastUsedConfig' object with the rest of the host config
    String? savedConfigData = await secureStorage.read(key: 'lastUsedConfig');
    Map<String, dynamic>? savedConfig = savedConfigData != null
        ? jsonDecode(savedConfigData)
        : null;

    String? savedHostType = savedConfig?['hostType'];
    String? savedWalletName = await secureStorage.read(key: 'walletName');
    String? savedIp = await secureStorage.read(key: 'ipAddress');
    String? savedWalletPassword = await secureStorage.read(
      key: 'walletPassword',
    );
    String? savedPort = await secureStorage.read(key: 'port');
    String? savedProtocol = await secureStorage.read(key: 'protocol');
    String? savedAwsRegion = await secureStorage.read(key: 'awsRegion');
    String? savedAwsAccessKey = await secureStorage.read(key: 'awsAccessKey');
    String? savedAwsSecretKey = await secureStorage.read(key: 'awsSecretKey');
    String? savedAwsInstanceType = await secureStorage.read(
      key: 'awsInstanceType',
    );
    String? savedRpcPassword = await secureStorage.read(key: 'rpc_password');
    // We ignore the stored exposeHttp value as the feature is disabled
    // Load HD wallet setting
    String? savedHdWallet = await secureStorage.read(key: 'enableHdWallet');
    // Load seed node configuration
    String? savedSeedNode1 = await secureStorage.read(key: 'seedNode1');
    String? savedSeedNode2 = await secureStorage.read(key: 'seedNode2');
    String? savedSeedNode3 = await secureStorage.read(key: 'seedNode3');
    String? savedDisableP2p = await secureStorage.read(key: 'disableP2p');
    String? savedIAmSeed = await secureStorage.read(key: 'iAmSeed');
    String? savedIsBootstrapNode = await secureStorage.read(
      key: 'isBootstrapNode',
    );

    setState(() {
      _selectedHostType = savedHostType ?? 'local';
      _walletNameController.text = savedWalletName ?? '';
      _passphraseController.text =
          ''; // We don't store/restore the passphrase for security
      _walletPasswordController.text = savedWalletPassword ?? '';
      _ipController.text = savedIp ?? '';
      _portController.text = savedPort ?? '7783';
      _selectedProtocol = savedProtocol ?? 'https';
      _awsRegionController.text = savedAwsRegion ?? '';
      _awsAccessKeyController.text = savedAwsAccessKey ?? '';
      _awsSecretKeyController.text = savedAwsSecretKey ?? '';
      _awsInstanceTypeController.text = savedAwsInstanceType ?? '';
      _rpcPasswordController.text =
          savedRpcPassword ?? _generateDefaultRpcPassword();
      _exposeHttp = false; // Always false until fully implemented
      _enableHdWallet = savedHdWallet?.toLowerCase() == 'true' ? true : false;
      // Load seed node configuration
      _seedNode1Controller.text = savedSeedNode1 ?? '';
      _seedNode2Controller.text = savedSeedNode2 ?? '';
      _seedNode3Controller.text = savedSeedNode3 ?? '';
      _disableP2p = savedDisableP2p?.toLowerCase() == 'true' ? true : false;
      _iAmSeed = savedIAmSeed?.toLowerCase() == 'true' ? true : false;
      _isBootstrapNode = savedIsBootstrapNode?.toLowerCase() == 'true'
          ? true
          : false;
    });
  }

  Future<void> _saveConfiguration() async {
    final secureStorage = SecureStorageService();
    await secureStorage.write(key: 'hostType', value: _selectedHostType);
    await secureStorage.write(
      key: 'walletName',
      value: _walletNameController.text,
    );
    await secureStorage.write(
      key: 'walletPassword',
      value: _walletPasswordController.text,
    );
    await secureStorage.write(key: 'ipAddress', value: _ipController.text);
    await secureStorage.write(key: 'port', value: _portController.text);
    await secureStorage.write(key: 'protocol', value: _selectedProtocol);
    await secureStorage.write(
      key: 'awsRegion',
      value: _awsRegionController.text,
    );
    await secureStorage.write(
      key: 'awsAccessKey',
      value: _awsAccessKeyController.text,
    );
    await secureStorage.write(
      key: 'awsSecretKey',
      value: _awsSecretKeyController.text,
    );
    await secureStorage.write(
      key: 'awsInstanceType',
      value: _awsInstanceTypeController.text,
    );
    await secureStorage.write(
      key: 'rpc_password',
      value: _rpcPasswordController.text,
    );
    await secureStorage.write(
      key: 'exposeHttp',
      value: _exposeHttp?.toString() ?? 'false',
    );
    // Save HD wallet setting
    await secureStorage.write(
      key: 'enableHdWallet',
      value: _enableHdWallet.toString(),
    );
    // Save seed node configuration
    await secureStorage.write(
      key: 'seedNode1',
      value: _seedNode1Controller.text,
    );
    await secureStorage.write(
      key: 'seedNode2',
      value: _seedNode2Controller.text,
    );
    await secureStorage.write(
      key: 'seedNode3',
      value: _seedNode3Controller.text,
    );
    await secureStorage.write(key: 'disableP2p', value: _disableP2p.toString());
    await secureStorage.write(key: 'iAmSeed', value: _iAmSeed.toString());
    await secureStorage.write(
      key: 'isBootstrapNode',
      value: _isBootstrapNode.toString(),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MyAppState extends State<MyApp> {
  KomodoDefiFramework? _kdfFramework;
  String? _statusMessage;
  String? _version;
  bool _isRunning = false;
  bool _showRequestPlayground = true;
  IKdfHostConfig? _kdfHostConfig;
  final _logController = StreamController<String>.broadcast();
  final ScrollController _scrollController = ScrollController();
  final List<String> _logMessages = [];

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool get _canInteract => _kdfFramework != null;

  // Check if the current configuration is a remote config
  bool _isRemoteConfig() {
    if (_kdfHostConfig == null) return false;
    return _kdfHostConfig.runtimeType.toString() == 'RemoteConfig';
  }

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium;
    const verticalSpacerSmall = SizedBox(height: 12);
    const horizontalSpacerSmall = SizedBox(width: 12);
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Komodo DeFi Framework Flutter Playground'),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.code),
                onPressed: () {
                  launchUrlString(
                    'https://github.com/GLEECBTC/komodo-defi-sdk-flutter/tree/dev',
                  );
                },
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _configure,
                    label: const Text('Configure'),
                    icon: const Icon(Icons.settings),
                  ),
                  horizontalSpacerSmall,
                  Tooltip(
                    message: _isRemoteConfig()
                        ? 'For remote configurations, KDF must be started on the server'
                        : 'Start the Komodo DeFi Framework',
                    child: FilledButton.icon(
                      onPressed:
                          _isRunning || !_canInteract || _isRemoteConfig()
                          ? null
                          : _startKdf,
                      label: const Text('Start KDF'),
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
                  horizontalSpacerSmall,
                  ElevatedButton.icon(
                    onPressed: _isRunning ? _stopKdf : null,
                    label: const Text('Stop KDF'),
                    icon: const Icon(Icons.stop),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  horizontalSpacerSmall,
                  OutlinedButton.icon(
                    onPressed: _checkStatus,
                    label: const Text('Refresh Status'),
                    icon: const Icon(Icons.refresh),
                  ),
                  horizontalSpacerSmall,
                  OutlinedButton.icon(
                    onPressed: _canInteract && _isRunning
                        ? () => setState(
                            () => _showRequestPlayground =
                                !_showRequestPlayground,
                          )
                        : null,
                    label: Text(
                      _showRequestPlayground
                          ? 'Hide Playground'
                          : 'Show Playground',
                    ),
                    icon: Icon(
                      _showRequestPlayground
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                  horizontalSpacerSmall,
                  ElevatedButton.icon(
                    onPressed: () => RequestHistoryService.showHistory(context),
                    label: const Text('History'),
                    icon: const Icon(Icons.history),
                  ),
                ],
              ),
              verticalSpacerSmall,
              Wrap(
                spacing: 16,
                children: [
                  Text(
                    'Status: ${_statusMessage ?? 'Unknown'}',
                    style: textStyle,
                  ),
                  Text('Version: ${_version ?? 'Unknown'}', style: textStyle),
                  Text(
                    'Host type: ${_kdfFramework?.operationsName ?? 'None selected'} ${_kdfHostConfig is RemoteConfig ? "(Remote - Manual Start Required)" : ""}',
                    style: textStyle,
                  ),
                ],
              ),

              const Divider(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Logs:', style: textStyle),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              color: Colors.black,
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  child: StreamBuilder<String>(
                                    stream: _logController.stream,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        _logMessages.add(snapshot.data!);

                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (_scrollController
                                                  .hasClients) {
                                                _scrollController.jumpTo(
                                                  _scrollController
                                                      .position
                                                      .maxScrollExtent,
                                                );
                                              }
                                            });
                                      }

                                      if (_logMessages.isEmpty) {
                                        return const Text(
                                          'No logs available.',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Courier',
                                          ),
                                        );
                                      }

                                      return SelectableText(
                                        key: const Key('log_text'),
                                        _logMessages.join('\n'),
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontFamily: 'Courier',
                                          fontSize: 16,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showRequestPlayground) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Material(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: RequestPlayground(
                                    key: const Key('request_playground'),
                                    executeRequest: (rpcInput) async {
                                      if (_kdfFramework == null ||
                                          !_isRunning) {
                                        _showMessage('KDF is not running.');
                                        throw Exception('KDF is not running.');
                                      }

                                      // Check if userpass is set to the placeholder and replace it
                                      final modifiedInput =
                                          Map<String, dynamic>.from(rpcInput);
                                      if (modifiedInput.containsKey(
                                            'userpass',
                                          ) &&
                                          modifiedInput['userpass'] ==
                                              '{{userpass}}') {
                                        // Replace with actual RPC password from config
                                        modifiedInput['userpass'] =
                                            _kdfHostConfig?.rpcPassword ?? '';
                                      }

                                      return (await _kdfFramework!.executeRpc(
                                        modifiedInput,
                                      )).toJsonString();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logController.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_kdfFramework == null) {
      _showMessage('Please configure the framework first.');
      return;
    }

    final status = await _kdfFramework!.kdfMainStatus();

    final version = MainStatus.rpcIsUp == status
        ? await _kdfFramework!.version()
        : 'N/A';
    setState(() {
      _isRunning = status == MainStatus.rpcIsUp;
      _statusMessage = status.toString();
      _version = version;
    });

    // Show a message if status is checked for a remote configuration
    if (_kdfHostConfig is RemoteConfig && !_isRunning) {
      _showMessage(
        'Starting KDF is not available for remote configurations. KDF must be started on the remote server.',
      );
    }
  }

  void _configure() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const ConfigureDialog(),
    );

    if (result == null) {
      return;
    }

    final IKdfHostConfig config = result['config'];
    final String walletName = result['walletName'];
    final String walletPassword = result['walletPassword'];
    // We get the passphrase from the UI but don't store it
    final String? passphrase = result['passphrase'];
    final bool enableHdWallet = result['enableHdWallet'] ?? false;
    final bool saveWalletPassword = result['savePassphrase'] ?? false;
    // Ignore exposeHttp as the feature is disabled

    setState(() {
      _kdfHostConfig = config;
      // Always create with standard operations
      _kdfFramework = KomodoDefiFramework.create(
        hostConfig: config,
        externalLogger: _logController.add,
      );
    });

    await _saveConfig(config);

    // Save startup data
    final secureStorage = SecureStorageService();
    await secureStorage.write(key: 'walletName', value: walletName);

    // Only save wallet password if explicitly enabled by user
    if (saveWalletPassword) {
      await secureStorage.write(key: 'walletPassword', value: walletPassword);
    } else {
      // Clear any previously stored wallet password if save is disabled
      await secureStorage.write(key: 'walletPassword', value: '');
    }

    // Note: We never save passphrase/seed to secure storage for security reasons
    // We only use it during wallet creation with the current session
    if (passphrase?.isNotEmpty ?? false) {
      _logController.add(
        'Note: Using provided seed for wallet creation only (not stored)',
      );
    }

    await secureStorage.write(
      key: 'enableHdWallet',
      value: enableHdWallet.toString(),
    );

    // Save seed node configuration from the dialog
    final String seedNode1 = result['seedNode1'] ?? '';
    final String seedNode2 = result['seedNode2'] ?? '';
    final String seedNode3 = result['seedNode3'] ?? '';
    final bool disableP2p = result['disableP2p'] ?? false;
    final bool iAmSeed = result['iAmSeed'] ?? false;
    final bool isBootstrapNode = result['isBootstrapNode'] ?? false;

    await secureStorage.write(key: 'seedNode1', value: seedNode1);
    await secureStorage.write(key: 'seedNode2', value: seedNode2);
    await secureStorage.write(key: 'seedNode3', value: seedNode3);
    await secureStorage.write(key: 'disableP2p', value: disableP2p.toString());
    await secureStorage.write(key: 'iAmSeed', value: iAmSeed.toString());
    await secureStorage.write(
      key: 'isBootstrapNode',
      value: isBootstrapNode.toString(),
    );

    // Check status after configuration is complete
    _checkStatus();
  }

  Future<void> _loadSavedData() async {
    final secureStorage = SecureStorageService();
    String? savedConfig = await secureStorage.read(key: 'lastUsedConfig');
    // Ignore the exposeHttp setting as the feature is disabled

    if (savedConfig != null) {
      final configMap = jsonDecode(savedConfig) as Map<String, dynamic>;
      _kdfHostConfig = _configFromMap(configMap);
      setState(() {
        // Always create with standard operations, exposeHttp feature is disabled
        _kdfFramework = KomodoDefiFramework.create(
          hostConfig: _kdfHostConfig!,
          externalLogger: _logController.add,
        );
      });
      _checkStatus();
    }
  }

  IKdfHostConfig _configFromMap(Map<String, dynamic> map) {
    final bool useHttps = map['https'] == true;
    switch (map['hostType']) {
      case 'local':
        return LocalConfig(rpcPassword: map['rpc_password'], https: useHttps);
      case 'remote':
        return RemoteConfig(
          rpcPassword: map['rpc_password'],
          ipAddress: map['ipAddress'],
          port: int.tryParse(map['port']?.toString() ?? '') ?? 7783,
          https: useHttps,
        );
      case 'aws':
        return AwsConfig(
          rpcPassword: map['rpc_password'],
          region: map['region'],
          accessKey: map['accessKey'],
          secretKey: map['secretKey'],
          instanceType: map['instanceType'],
          https: useHttps,
        );
      default:
        throw Exception('Invalid/unsupported host type: ${map['hostType']}');
    }
  }

  Future<void> _saveConfig(IKdfHostConfig config) async {
    final Map<String, dynamic> connectionParams = config.getConnectionParams();

    // Add the host type to the saved configuration
    String hostType = '';
    if (config is LocalConfig) {
      hostType = 'local';
    } else if (config is RemoteConfig) {
      hostType = 'remote';
    } else if (config is AwsConfig) {
      hostType = 'aws';
    }
    connectionParams['hostType'] = hostType;

    final secureStorage = SecureStorageService();
    await secureStorage.write(
      key: 'lastUsedConfig',
      value: jsonEncode(connectionParams),
    );
  }

  void _showMessage(String message) {
    _scaffoldMessengerKey.currentState!.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _startKdf() async {
    _statusMessage = null;

    if (_kdfFramework == null || _kdfHostConfig == null) {
      _showMessage('Please configure the framework first.');
      return;
    }

    // Load saved startup data
    final secureStorage = SecureStorageService();
    final walletName = await secureStorage.read(key: 'walletName') ?? '';
    final walletPassword =
        await secureStorage.read(key: 'walletPassword') ?? '';

    // Note: We don't use passphrase from storage for security reasons
    // It should be provided each time in the configuration dialog if needed

    final enableHdWallet = await secureStorage.read(key: 'enableHdWallet');
    final useHdWallet = enableHdWallet?.toLowerCase() == 'true';

    // Load seed node configuration
    final seedNode1 = await secureStorage.read(key: 'seedNode1') ?? '';
    final seedNode2 = await secureStorage.read(key: 'seedNode2') ?? '';
    final seedNode3 = await secureStorage.read(key: 'seedNode3') ?? '';
    final disableP2p = await secureStorage.read(key: 'disableP2p');
    final iAmSeed = await secureStorage.read(key: 'iAmSeed');
    final isBootstrapNode = await secureStorage.read(key: 'isBootstrapNode');

    // Build seed nodes list if P2P is not disabled
    List<String>? seedNodes;
    if (disableP2p?.toLowerCase() != 'true') {
      seedNodes = [
        if (seedNode1.isNotEmpty) seedNode1,
        if (seedNode2.isNotEmpty) seedNode2,
        if (seedNode3.isNotEmpty) seedNode3,
      ];
      // Use empty list if no seed nodes configured (will use defaults)
      if (seedNodes.isEmpty) seedNodes = null;
    }

    try {
      // Show a dialog to enter passphrase if this is not a new wallet creation
      // For existing wallets, no passphrase needed as it was already used during wallet creation

      final KdfStartupConfig
      startupConfig = await KdfStartupConfig.generateWithDefaults(
        allowWeakPassword: true,
        enableHd: useHdWallet,
        walletName: walletName,
        walletPassword: walletPassword,
        rpcPassword: _kdfHostConfig!.rpcPassword,
        // No seed passed during normal startups - seed is only used during wallet creation
        seed: null,
        // Add seed node configuration
        seedNodes: seedNodes,
        disableP2p: disableP2p?.toLowerCase() == 'true',
        iAmSeed: iAmSeed?.toLowerCase() == 'true',
        isBootstrapNode: isBootstrapNode?.toLowerCase() == 'true',
      );

      final result = await _kdfFramework!.startKdf(startupConfig);

      setState(() {
        _statusMessage = 'KDF running: $result';
        _isRunning = result.isStartingOrAlreadyRunning();
      });

      if (!result.isStartingOrAlreadyRunning()) {
        _showMessage('Failed to start KDF: $result');
      } else {
        _showMessage('KDF started successfully');
      }
    } catch (e) {
      String errorMessage = 'Failed to start KDF: $e';

      // Provide more specific error messages for common issues
      if (e == KdfStartupResult.initError) {
        errorMessage =
            'Authentication error. Please check your wallet password and ensure it is strong enough.';
      } else if (e == KdfStartupResult.alreadyRunning) {
        errorMessage = 'KDF is already running.';
      } else if (e == KdfStartupResult.configError) {
        errorMessage =
            'Configuration error. Please check your wallet settings.';
      }

      setState(() {
        _statusMessage = errorMessage;
        _isRunning = false;
      });

      _showMessage(errorMessage);
    }
  }

  void _stopKdf() async {
    if (_kdfFramework == null) {
      _showMessage('Please configure the framework first.');
      return;
    }

    try {
      final result = await _kdfFramework!.kdfStop();
      setState(() {
        _statusMessage = 'KDF stopped: $result';
        _isRunning = false;
      });

      _checkStatus().ignore();
    } catch (e) {
      _showMessage('Failed to stop KDF: $e');
    }
  }
}
