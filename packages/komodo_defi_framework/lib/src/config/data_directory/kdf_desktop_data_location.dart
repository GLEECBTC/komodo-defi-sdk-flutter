import 'package:komodo_defi_types/komodo_defi_types.dart';

/// KDF's data directory for [config], or null where the platform keeps
/// `Documents/.kdf`. [rpcPort] is where this app's KDF will listen.
typedef KdfDesktopDataResolver = Future<String?> Function(
  KdfDesktopDataDirectory config,
  int rpcPort,
);

/// Records that KDF came up on [dataDirectory] with a wallet open.
typedef KdfDataStartRecorder = Future<void> Function(String dataDirectory);
