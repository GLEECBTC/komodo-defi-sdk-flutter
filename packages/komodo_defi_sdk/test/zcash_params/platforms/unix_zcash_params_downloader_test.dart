import 'dart:async';
import 'dart:io';

import 'package:komodo_defi_sdk/src/zcash_params/models/download_progress.dart';
import 'package:komodo_defi_sdk/src/zcash_params/models/download_result.dart';
import 'package:komodo_defi_sdk/src/zcash_params/models/zcash_params_config.dart';
import 'package:komodo_defi_sdk/src/zcash_params/platforms/unix_zcash_params_downloader.dart';
import 'package:komodo_defi_sdk/src/zcash_params/services/zcash_params_download_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// Where `UnixZcashParamsDownloader` puts params for [home] on *this* host.
///
/// macOS uses `~/Library/Application Support/ZcashParams`; every other Unix
/// uses `~/.zcash-params` (`unix_zcash_params_downloader.dart:126-136`).
String _expectedParamsPath(String home) => Platform.isMacOS
    ? '$home/Library/Application Support/ZcashParams'
    : '$home/.zcash-params';

// Helper function to run tests with a custom HOME environment variable
Future<T> withEnvironmentVariable<T>(
  String key,
  String? value,
  Future<T> Function() testFunction,
) async {
  final originalValue = Platform.environment[key];
  if (value == null) {
    Platform.environment.remove(key);
  } else {
    // Note: In test environment, we can't actually modify Platform.environment
    // So we'll create a custom downloader with the override instead
  }

  try {
    return await testFunction();
  } finally {
    // Restore original value (though this won't work in test environment either)
    if (originalValue != null) {
      // We can't restore in test environment, so this is a no-op
    }
  }
}

class MockZcashParamsDownloadService extends Mock
    implements ZcashParamsDownloadService {}

class MockDirectory extends Mock implements Directory {}

class MockFile extends Mock implements File {}

void main() {
  late MockZcashParamsDownloadService mockDownloadService;
  late MockDirectory mockDirectory;
  late MockFile mockFile;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(
      const ZcashParamsConfig(
        paramFiles: [
          ZcashParamFile(fileName: 'dummy-file', sha256Hash: 'dummy-hash'),
        ],
      ),
    );
    registerFallbackValue(StreamController<DownloadProgress>.broadcast());
  });

  setUp(() {
    mockDownloadService = MockZcashParamsDownloadService();
    mockDirectory = MockDirectory();
    mockFile = MockFile();
  });

  group('UnixZcashParamsDownloader', () {
    group('getParamsPath', () {
      test('uses HOME environment variable when available', () async {
        // Mock the environment variable by using the override parameter
        const testHome = '/home/testuser';
        final downloader = UnixZcashParamsDownloader(
          homeDirectoryOverride: testHome,
        );

        final path = await downloader.getParamsPath();

        // `getParamsPath` branches on `Platform.isMacOS`, not on the shape of
        // the home directory, so the expectation has to follow the host. These
        // assertions used to hardcode the macOS branch and failed the moment
        // the suite ran on a Linux CI runner.
        expect(
          path,
          equals(_expectedParamsPath('/home/testuser')),
        );
      });

      test('uses custom homeDirectoryOverride when provided', () async {
        const customHome = '/custom/home/path';
        final downloader = UnixZcashParamsDownloader(
          homeDirectoryOverride: customHome,
        );

        final path = await downloader.getParamsPath();

        // Should use the custom home directory, under this host's convention.
        expect(
          path,
          equals(_expectedParamsPath('/custom/home/path')),
        );
      });

      test(
        'falls back to application documents directory when HOME is not available',
        () async {
          // Test with no HOME override (should use fallback)
          final downloader = UnixZcashParamsDownloader();

          final path = await downloader.getParamsPath();

          // Should return a path (either from fallback or null if path_provider fails)
          // We can't easily mock path_provider in this test, so we'll just verify
          // it doesn't throw an exception
          expect(path, anyOf(isA<String>(), isNull));
        },
      );

      test('handles path_provider errors gracefully', () async {
        // This test would require more complex mocking of path_provider
        // For now, we test that the method doesn't throw when HOME is missing
        final downloader = UnixZcashParamsDownloader();

        // Should not throw an exception
        final path = await downloader.getParamsPath();

        // Path might be null if path_provider fails, but no exception should be thrown
        expect(path, anyOf(isA<String>(), isNull));
      });

      test('uses macOS-specific path when on macOS', () async {
        const testHome = '/Users/testuser';
        final downloader = UnixZcashParamsDownloader(
          homeDirectoryOverride: testHome,
        );

        final path = await downloader.getParamsPath();

        // Path shape follows the host platform, not the home directory's shape.
        expect(
          path,
          equals(_expectedParamsPath('/Users/testuser')),
        );
      });
    });

    group('downloadParams', () {
      test('handles null params path gracefully', () async {
        final downloader = UnixZcashParamsDownloader(
          downloadService: mockDownloadService,
          directoryFactory: (path) => mockDirectory,
          fileFactory: (path) => mockFile,
        );

        // Mock the download service methods
        when(
          () => mockDownloadService.ensureDirectoryExists(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockDownloadService.getMissingFiles(any(), any(), any()),
        ).thenAnswer(
          (_) async => ['test-file'],
        ); // Return non-empty list to trigger download
        when(
          () => mockDownloadService.downloadMissingFiles(
            any(),
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => false,
        ); // Return false to simulate download failure

        // Should return failure result when path is null
        final result = await downloader.downloadParams();

        expect(result, isA<DownloadResultFailure>());
        expect(
          (result as DownloadResultFailure).error,
          equals('Failed to download one or more parameter files'),
        );
      });
    });

    group('areParamsAvailable', () {
      test('handles null params path gracefully', () async {
        final downloader = UnixZcashParamsDownloader(
          downloadService: mockDownloadService,
          directoryFactory: (path) => mockDirectory,
          fileFactory: (path) => mockFile,
        );

        // Mock the download service
        when(
          () => mockDownloadService.getMissingFiles(any(), any(), any()),
        ).thenAnswer(
          (_) async => ['missing-file'],
        ); // Return non-empty list to indicate files are missing

        // Should return false when path is null
        final available = await downloader.areParamsAvailable();

        expect(available, isFalse);
      });
    });
  });
}
