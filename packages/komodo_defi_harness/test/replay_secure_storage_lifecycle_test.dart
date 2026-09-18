import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

void main() {
  test('replay keys follow workspace lifetime without going to disk', () async {
    final workspace = await Directory.systemTemp.createTemp('replay_keys_');
    KdfHarness? active;
    addTearDown(() async {
      await active?.dispose();
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    });

    active = await KdfHarness.replayed(
      script: KdfWalletFixture().build(),
      workspace: workspace,
      deleteWorkspaceOnDispose: false,
    );
    const storage = FlutterSecureStorage();
    await storage.write(key: 'harness-key', value: 'in-memory-only-sentinel');
    await active.dispose();

    active = await KdfHarness.replayed(
      script: KdfWalletFixture().build(),
      workspace: workspace,
    );
    expect(await storage.read(key: 'harness-key'), 'in-memory-only-sentinel');
    await active.dispose();
    expect(workspace.existsSync(), isFalse);

    // Reusing a deleted path is a fresh device fixture with no former keys.
    await workspace.create();
    active = await KdfHarness.replayed(
      script: KdfWalletFixture().build(),
      workspace: workspace,
    );
    expect(await storage.read(key: 'harness-key'), isNull);
  });
}
