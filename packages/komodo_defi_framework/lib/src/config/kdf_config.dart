import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// The port KDF listens on when nothing says otherwise.
const int kDefaultKdfRpcPort = 7783;

/// Define IKdfHostConfig as an abstract interface class
sealed class IKdfHostConfig {
  IKdfHostConfig({
    required this.rpcPassword,
    required this.https,
    this.port = kDefaultKdfRpcPort,
  });

  /// Each host config must implement the `getConnectionParams` method.
  Map<String, dynamic> getConnectionParams();

  final String rpcPassword;
  final bool https;

  /// The RPC port for this host.
  ///
  /// Hoisted from [RemoteConfig] so every host config has one. It used to
  /// exist only there, which meant a locally started KDF had nowhere to put a
  /// port: the auth path builds its startup config with
  /// `KdfStartupConfig.generateWithDefaults` and passes only the password
  /// (`auth_service_kdf_extension.dart`), so the `rpcPort = 7783` default won
  /// every time. The port was not merely defaulted, it was unreachable - which
  /// is why two KDF instances could never coexist on one machine, and why a
  /// test harness spawning a real KDF had to run single-threaded.
  final int port;

  /// Where to send RPCs for this host.
  Uri get rpcUrl;
}

/// LocalConfig class now implements IKdfHostConfig interface
class LocalConfig extends IKdfHostConfig {
  LocalConfig({
    required super.https,
    required super.rpcPassword,
    super.port,
  });

  factory LocalConfig.fromJson(JsonMap json) {
    return LocalConfig(
      https: json.value<bool>('https'),
      rpcPassword: json.value<String>('rpc_password'),
      port: json.valueOrNull<int>('port') ?? kDefaultKdfRpcPort,
    );
  }

  /// Always loopback: a local KDF is started with `rpc_local_only`.
  @override
  Uri get rpcUrl =>
      Uri.parse('${https ? 'https' : 'http'}://127.0.0.1:$port');

  @override
  Map<String, dynamic> getConnectionParams() => {
        'https': https,
        'rpc_password': rpcPassword,
        'rpcport': port,
      };

  Map<String, dynamic> toJson() {
    return {
      'https': https,
      'rpc_password': rpcPassword,
      'port': port,
    };
  }
}

/// RemoteConfig class now implements IKdfHostConfig interface
class RemoteConfig extends IKdfHostConfig {
  RemoteConfig({
    required this.ipAddress,
    required int port,
    required super.rpcPassword,
    required super.https,
  }) : super(port: port);

  factory RemoteConfig.fromJson(JsonMap json) {
    return RemoteConfig(
      ipAddress: json.value<String>('ip_address'),
      port: json.value<int>('port'),
      rpcPassword: json.value<String>('rpc_password'),
      https: json.value<bool>('https'),
    );
  }

  final String ipAddress;

  @override
  Uri get rpcUrl =>
      Uri.parse('${https ? 'https' : 'http'}://$ipAddress:$port');

  @override
  Map<String, dynamic> getConnectionParams() => {
        'rpcip': '0.0.0.0',
        'myipaddr': ipAddress,
        'rpcport': port,
        'rpc_local_only': false,
        'rpccors': '*',
        'userpass': rpcPassword,
      };

  Map<String, dynamic> toJson() {
    return {
      'ip_address': ipAddress,
      'port': port,
      'rpc_password': rpcPassword,
      'https': https,
    };
  }
}

/// AwsConfig class now implements IKdfHostConfig interface
class AwsConfig extends IKdfHostConfig {
  AwsConfig({
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.instanceType,
    required super.rpcPassword,
    required super.https,
    this.instanceId,
    this.keyName,
    this.securityGroup,
    this.amiId,
  });

  factory AwsConfig.fromJson(JsonMap json) {
    return AwsConfig(
      region: json.value<String>('region'),
      accessKey: json.value<String>('access_key'),
      secretKey: json.value<String>('secret_key'),
      instanceType: json.value<String>('instance_type'),
      instanceId: json.valueOrNull<String?>('instance_id'),
      keyName: json.valueOrNull<String?>('key_name'),
      securityGroup: json.valueOrNull<String?>('security_group'),
      amiId: json.valueOrNull<String?>('ami_id'),
      rpcPassword: json.value<String>('rpc_password'),
      https: json.value<bool>('https'),
    );
  }

  /// Provisioned hosts are addressed by the caller once the instance exists;
  /// this keeps the sealed interface total.
  @override
  Uri get rpcUrl =>
      Uri.parse('${https ? 'https' : 'http'}://127.0.0.1:$port');

  final String region;
  final String accessKey;
  final String secretKey;
  final String instanceType;
  final String? instanceId;
  final String? keyName;
  final String? securityGroup;
  final String? amiId;

  @override
  Map<String, dynamic> getConnectionParams() => {
        'aws_config': {
          'region': region,
          'access_key': accessKey,
          'secret_key': secretKey,
          'instance_type': instanceType,
          if (instanceId != null) 'instance_id': instanceId,
          if (keyName != null) 'key_name': keyName,
          if (securityGroup != null) 'security_group': securityGroup,
          if (amiId != null) 'ami_id': amiId,
        },
      };

  Map<String, dynamic> toJson() {
    return {
      'region': region,
      'access_key': accessKey,
      'secret_key': secretKey,
      'instance_type': instanceType,
      'instance_id': instanceId,
      'key_name': keyName,
      'security_group': securityGroup,
      'ami_id': amiId,
      'rpc_password': rpcPassword,
      'https': https,
    };
  }
}

/// DigitalOceanConfig class now implements IKdfHostConfig interface
class DigitalOceanConfig extends IKdfHostConfig {
  DigitalOceanConfig({
    required this.apiToken,
    required super.rpcPassword,
    required super.https,
    this.dropletId,
    this.dropletRegion = 'nyc1',
    this.dropletSize = 's-1vcpu-1gb',
    this.sshKeyId,
    this.image = 'ubuntu-20-04-x64',
  });

  factory DigitalOceanConfig.fromJson(JsonMap json) {
    return DigitalOceanConfig(
      apiToken: json.value<String>('api_token'),
      dropletId: json.valueOrNull<String?>('droplet_id'),
      dropletRegion: json.value<String>('droplet_region', 'nyc1'),
      dropletSize: json.value<String>('droplet_size', 's-1vcpu-1gb'),
      sshKeyId: json.valueOrNull<String?>('ssh_key_id'),
      image: json.value<String>('image', 'ubuntu-20-04-x64'),
      rpcPassword: json.value<String>('rpc_password'),
      https: json.value<bool>('https'),
    );
  }

  /// See the note on [AwsConfig.rpcUrl].
  @override
  Uri get rpcUrl =>
      Uri.parse('${https ? 'https' : 'http'}://127.0.0.1:$port');

  final String apiToken;
  final String? dropletId;
  final String dropletRegion;
  final String dropletSize;
  final String? sshKeyId;
  final String image;

  @override
  Map<String, dynamic> getConnectionParams() => {
        'digitalocean_config': {
          'api_token': apiToken,
          if (dropletId != null) 'droplet_id': dropletId,
          'droplet_region': dropletRegion,
          'droplet_size': dropletSize,
          if (sshKeyId != null) 'ssh_key_id': sshKeyId,
          'image': image,
        },
      };

  Map<String, dynamic> toJson() {
    return {
      'api_token': apiToken,
      'droplet_id': dropletId,
      'droplet_region': dropletRegion,
      'droplet_size': dropletSize,
      'ssh_key_id': sshKeyId,
      'image': image,
      'rpc_password': rpcPassword,
      'https': https,
    };
  }
}
