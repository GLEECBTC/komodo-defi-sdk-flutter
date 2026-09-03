/// Test harness for launching pre-authenticated KDF instances.
///
/// See `README.md` for why the default tier replays scripted responses rather
/// than spawning the real KDF binary.
library;

export 'src/kdf_binary.dart';
export 'src/kdf_fixture.dart';
export 'src/kdf_harness.dart';
export 'src/kdf_port.dart';
export 'src/kdf_process_requirements.dart';
export 'src/kdf_script.dart';
export 'src/process_kdf_operations.dart';
export 'src/replay_kdf_operations.dart';
export 'src/secret.dart';
