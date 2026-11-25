import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

/// Lets an engine start be configured on the VM: package assets are read from
/// source, and an unusable coins URL makes seed nodes come from the bundled
/// fallback instead of a network request.
void useSourceAssets(TestWidgetsFlutterBinding binding) {
  late Directory home;
  setUpAll(() async {
    home = await Directory.systemTemp.createTemp('local-auth-test-');
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(_pathProvider, (_) async => home.path)
      ..setMockMessageHandler('flutter/assets', _sourceAsset);
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(_pathProvider, null)
      ..setMockMessageHandler('flutter/assets', null);
    await home.delete(recursive: true);
  });
}

Future<ByteData?> _sourceAsset(ByteData? message) async {
  final key = utf8.decode(message!.buffer.asUint8List());
  if (key.endsWith('app_build/build_config.json')) {
    return ByteData.sublistView(
      Uint8List.fromList(
        utf8.encode(
          '{"coins":{"coins_repo_content_url":"http://[",'
          '"cdn_branch_mirrors":{}}}',
        ),
      ),
    );
  }
  if (!key.startsWith('packages/')) return null;
  final source = File('../${key.substring('packages/'.length)}');
  if (!source.existsSync()) return null;
  return ByteData.sublistView(await source.readAsBytes());
}
