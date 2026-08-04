import 'package:komodo_defi_sdk/src/zcash_params/models/zcash_params_config.dart';
import 'package:test/test.dart';

void main() {
  group('ZcashParamFile', () {
    group('constructor', () {
      test('creates instance with all parameters', () {
        const file = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
          expectedSize: 1024,
        );

        expect(file.fileName, equals('test.params'));
        expect(file.sha256Hash, equals('abc123'));
        expect(file.expectedSize, equals(1024));
      });

      test('creates instance without expected size', () {
        const file = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
        );

        expect(file.fileName, equals('test.params'));
        expect(file.sha256Hash, equals('abc123'));
        expect(file.expectedSize, isNull);
      });
    });

    group('JSON serialization', () {
      test('can serialize and deserialize', () {
        const original = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
          expectedSize: 1024,
        );

        final json = original.toJson();
        final deserialized = ZcashParamFile.fromJson(json);

        expect(deserialized, equals(original));
      });

      test('handles null expected size', () {
        const original = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
        );

        final json = original.toJson();
        final deserialized = ZcashParamFile.fromJson(json);

        expect(deserialized, equals(original));
        expect(deserialized.expectedSize, isNull);
      });
    });

    group('equality', () {
      test('returns true for identical files', () {
        const file1 = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
          expectedSize: 1024,
        );
        const file2 = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
          expectedSize: 1024,
        );

        expect(file1, equals(file2));
        expect(file1.hashCode, equals(file2.hashCode));
      });

      test('returns false for different files', () {
        const file1 = ZcashParamFile(
          fileName: 'test1.params',
          sha256Hash: 'abc123',
        );
        const file2 = ZcashParamFile(
          fileName: 'test2.params',
          sha256Hash: 'abc123',
        );

        expect(file1, isNot(equals(file2)));
      });
    });

    group('copyWith', () {
      test('creates copy with modifications', () {
        const original = ZcashParamFile(
          fileName: 'test.params',
          sha256Hash: 'abc123',
          expectedSize: 1024,
        );

        final copied = original.copyWith(fileName: 'modified.params');

        expect(copied.fileName, equals('modified.params'));
        expect(copied.sha256Hash, equals('abc123'));
        expect(copied.expectedSize, equals(1024));
        expect(copied, isNot(equals(original)));
      });
    });
  });

  group('ZcashParamsConfig', () {
    late ZcashParamsConfig config;

    setUp(() {
      config = ZcashParamsConfig.defaultConfig;
    });

    group('constructor', () {
      test('creates instance with all parameters', () {
        expect(config.primaryUrl, equals('https://z.cash/downloads/'));
        expect(
          config.backupUrl,
          equals('https://komodoplatform.com/downloads/'),
        );
        expect(config.downloadTimeoutSeconds, equals(1800));
        expect(config.maxRetries, equals(3));
        expect(config.retryDelaySeconds, equals(5));
        expect(config.downloadBufferSize, equals(1048576));
        expect(config.paramFiles.length, equals(2));
      });

      test('creates instance with custom values', () {
        const customConfig = ZcashParamsConfig(
          paramFiles: [],
          primaryUrl: 'https://custom.com/',
          backupUrl: 'https://backup.com/',
          downloadTimeoutSeconds: 3600,
          maxRetries: 5,
          retryDelaySeconds: 10,
          downloadBufferSize: 2097152,
        );

        expect(customConfig.primaryUrl, equals('https://custom.com/'));
        expect(customConfig.backupUrl, equals('https://backup.com/'));
        expect(customConfig.downloadTimeoutSeconds, equals(3600));
        expect(customConfig.maxRetries, equals(5));
        expect(customConfig.retryDelaySeconds, equals(10));
        expect(customConfig.downloadBufferSize, equals(2097152));
        expect(customConfig.paramFiles, isEmpty);
      });
    });

    group('default configuration', () {
      test('has correct default values', () {
        expect(
          ZcashParamsConfig.defaultConfig.primaryUrl,
          equals('https://z.cash/downloads/'),
        );
        expect(
          ZcashParamsConfig.defaultConfig.backupUrl,
          equals('https://komodoplatform.com/downloads/'),
        );
        expect(ZcashParamsConfig.defaultConfig.paramFiles.length, equals(2));
      });

      test('has all required parameter files', () {
        final fileNames = ZcashParamsConfig.defaultConfig.fileNames;
        expect(fileNames, contains('sapling-spend.params'));
        expect(fileNames, contains('sapling-output.params'));
      });

      test('does not include sprout-groth16.params', () {
        final fileNames = ZcashParamsConfig.defaultConfig.fileNames;
        expect(fileNames, isNot(contains('sprout-groth16.params')));
      });

      test('all parameter files have hashes', () {
        for (final file in ZcashParamsConfig.defaultConfig.paramFiles) {
          expect(file.sha256Hash, isNotEmpty);
          expect(file.sha256Hash.length, equals(64)); // SHA256 is 64 hex chars
        }
      });
    });

    group('extended configuration', () {
      test('has correct default values', () {
        expect(
          ZcashParamsConfig.extendedConfig.primaryUrl,
          equals('https://z.cash/downloads/'),
        );
        expect(
          ZcashParamsConfig.extendedConfig.backupUrl,
          equals('https://komodoplatform.com/downloads/'),
        );
        expect(ZcashParamsConfig.extendedConfig.paramFiles.length, equals(3));
      });

      test('has all parameter files including sprout', () {
        final fileNames = ZcashParamsConfig.extendedConfig.fileNames;
        expect(fileNames, contains('sapling-spend.params'));
        expect(fileNames, contains('sapling-output.params'));
        expect(fileNames, contains('sprout-groth16.params'));
      });

      test('all parameter files have hashes', () {
        for (final file in ZcashParamsConfig.extendedConfig.paramFiles) {
          expect(file.sha256Hash, isNotEmpty);
          expect(file.sha256Hash.length, equals(64)); // SHA256 is 64 hex chars
        }
      });

      test('fileNames returns correct list', () {
        expect(
          ZcashParamsConfig.extendedConfig.fileNames,
          equals([
            'sapling-spend.params',
            'sapling-output.params',
            'sprout-groth16.params',
          ]),
        );
      });

      test('totalExpectedSize calculates correctly', () {
        final expectedTotal = ZcashParamsConfig.extendedConfig.paramFiles
            .where((file) => file.expectedSize != null)
            .fold(0, (sum, file) => sum + file.expectedSize!);

        expect(
          ZcashParamsConfig.extendedConfig.totalExpectedSize,
          equals(expectedTotal),
        );
        expect(
          ZcashParamsConfig.extendedConfig.totalExpectedSize,
          greaterThan(700 * 1024 * 1024),
        ); // > 700MB
      });
    });

    group('computed properties', () {
      test('downloadUrls returns correct list', () {
        expect(
          config.downloadUrls,
          equals([
            'https://z.cash/downloads/',
            'https://komodoplatform.com/downloads/',
          ]),
        );
      });

      test('fileNames returns correct list', () {
        expect(
          config.fileNames,
          equals(['sapling-spend.params', 'sapling-output.params']),
        );
      });

      test('downloadTimeout returns correct duration', () {
        expect(config.downloadTimeout, equals(const Duration(seconds: 1800)));
      });

      test('retryDelay returns correct duration', () {
        expect(config.retryDelay, equals(const Duration(seconds: 5)));
      });

      test('totalExpectedSize calculates correctly', () {
        final expectedTotal = config.paramFiles
            .where((file) => file.expectedSize != null)
            .fold(0, (sum, file) => sum + file.expectedSize!);

        expect(config.totalExpectedSize, equals(expectedTotal));
      });
    });

    group('getParamFile', () {
      test('returns correct file for known file names', () {
        final file = config.getParamFile('sapling-spend.params');
        expect(file, isNotNull);
        expect(file!.fileName, equals('sapling-spend.params'));
        expect(
          file.sha256Hash,
          equals(
            '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13',
          ),
        );
      });

      test('returns null for unknown file names', () {
        final file = config.getParamFile('unknown.params');
        expect(file, isNull);
      });

      test('returns null for empty string', () {
        final file = config.getParamFile('');
        expect(file, isNull);
      });

      test('is case sensitive', () {
        final file = config.getParamFile('SAPLING-SPEND.PARAMS');
        expect(file, isNull);
      });
    });

    group('getExpectedFileSize', () {
      test('returns correct size for known files', () {
        final size = config.getExpectedFileSize('sapling-spend.params');
        expect(size, equals(47958396));
      });

      test('returns null for unknown files', () {
        final size = config.getExpectedFileSize('unknown.params');
        expect(size, isNull);
      });

      test('returns null for files without expected size', () {
        const configWithoutSize = ZcashParamsConfig(
          paramFiles: [
            ZcashParamFile(fileName: 'test.params', sha256Hash: 'abc123'),
          ],
        );

        final size = configWithoutSize.getExpectedFileSize('test.params');
        expect(size, isNull);
      });
    });

    group('getExpectedHash', () {
      test('returns correct hash for known files', () {
        final hash = config.getExpectedHash('sapling-spend.params');
        expect(
          hash,
          equals(
            '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13',
          ),
        );
      });

      test('returns null for unknown files', () {
        final hash = config.getExpectedHash('unknown.params');
        expect(hash, isNull);
      });

      test('returns null for empty file name', () {
        final hash = config.getExpectedHash('');
        expect(hash, isNull);
      });
    });

    group('isValidFileName', () {
      test('returns true for all known file names', () {
        for (final fileName in config.fileNames) {
          expect(
            config.isValidFileName(fileName),
            isTrue,
            reason: '$fileName should be valid',
          );
        }
      });

      test('returns false for unknown file names', () {
        expect(config.isValidFileName('unknown.params'), isFalse);
        expect(config.isValidFileName('test.txt'), isFalse);
        expect(config.isValidFileName(''), isFalse);
      });

      test('is case sensitive', () {
        expect(config.isValidFileName('SAPLING-SPEND.PARAMS'), isFalse);
        expect(config.isValidFileName('Sapling-Spend.Params'), isFalse);
      });
    });

    group('getFileUrl', () {
      test('constructs correct URL with trailing slash', () {
        const baseUrl = 'https://example.com/';
        const fileName = 'test.params';

        final url = config.getFileUrl(baseUrl, fileName);
        expect(url, equals('https://example.com/test.params'));
      });

      test('adds trailing slash when missing', () {
        const baseUrl = 'https://example.com';
        const fileName = 'test.params';

        final url = config.getFileUrl(baseUrl, fileName);
        expect(url, equals('https://example.com/test.params'));
      });

      test('works with primary URL', () {
        const fileName = 'sapling-spend.params';

        final url = config.getFileUrl(config.primaryUrl, fileName);
        expect(
          url,
          equals('https://z.cash/downloads/sapling-spend.params'),
        );
      });

      test('works with backup URL', () {
        const fileName = 'sapling-output.params';

        final url = config.getFileUrl(config.backupUrl, fileName);
        expect(
          url,
          equals('https://komodoplatform.com/downloads/sapling-output.params'),
        );
      });

      test('handles empty file name', () {
        const baseUrl = 'https://example.com/';
        const fileName = '';

        final url = config.getFileUrl(baseUrl, fileName);
        expect(url, equals('https://example.com/'));
      });

      test('handles multiple trailing slashes', () {
        const baseUrl = 'https://example.com///';
        const fileName = 'test.params';

        final url = config.getFileUrl(baseUrl, fileName);
        expect(url, equals('https://example.com///test.params'));
      });
    });

    // TODO: Fix JSON serialization for nested objects
    // group('JSON serialization', () {
    //   test('can serialize and deserialize complete config', () {
    //     final json = config.toJson();
    //     final deserialized = ZcashParamsConfig.fromJson(json);

    //     expect(deserialized, equals(config));
    //     expect(
    //       deserialized.paramFiles.length,
    //       equals(config.paramFiles.length),
    //     );

    //     for (int i = 0; i < config.paramFiles.length; i++) {
    //       expect(deserialized.paramFiles[i], equals(config.paramFiles[i]));
    //     }
    //   });

    //   test('handles empty param files list', () {
    //     const emptyConfig = ZcashParamsConfig(paramFiles: []);
    //     final json = emptyConfig.toJson();
    //     final deserialized = ZcashParamsConfig.fromJson(json);

    //     expect(deserialized, equals(emptyConfig));
    //     expect(deserialized.paramFiles, isEmpty);
    //   });
    // });

    group('equality and hashCode', () {
      test('returns true for identical configs', () {
        final config2 = ZcashParamsConfig(
          paramFiles: config.paramFiles,
          primaryUrl: config.primaryUrl,
          backupUrl: config.backupUrl,
          downloadTimeoutSeconds: config.downloadTimeoutSeconds,
          maxRetries: config.maxRetries,
          retryDelaySeconds: config.retryDelaySeconds,
          downloadBufferSize: config.downloadBufferSize,
        );

        expect(config2, equals(config));
        expect(config2.hashCode, equals(config.hashCode));
      });

      test('returns false for different configs', () {
        const config2 = ZcashParamsConfig(
          paramFiles: [],
          primaryUrl: 'https://different.com/',
        );

        expect(config2, isNot(equals(config)));
      });
    });

    group('copyWith', () {
      test('creates copy with modifications', () {
        final copied = config.copyWith(primaryUrl: 'https://modified.com/');

        expect(copied.primaryUrl, equals('https://modified.com/'));
        expect(copied.backupUrl, equals(config.backupUrl));
        expect(copied.paramFiles, equals(config.paramFiles));
        expect(copied, isNot(equals(config)));
      });

      test('creates identical copy when no modifications', () {
        final copied = config.copyWith();

        expect(copied, equals(config));
        expect(identical(copied, config), isFalse);
      });
    });

    group('edge cases', () {
      test('handles very long file names', () {
        final longFileName = 'very-long-file-name' * 10 + '.params';
        expect(config.isValidFileName(longFileName), isFalse);
        expect(config.getExpectedFileSize(longFileName), isNull);
      });

      test('handles special characters in URLs', () {
        const baseUrl = 'https://example.com/path with spaces/';
        const fileName = 'test.params';

        final url = config.getFileUrl(baseUrl, fileName);
        expect(url, equals('https://example.com/path with spaces/test.params'));
      });

      test('validates all expected file sizes are reasonable', () {
        for (final file in config.paramFiles) {
          if (file.expectedSize != null) {
            expect(
              file.expectedSize,
              greaterThan(1024 * 1024),
              reason: '${file.fileName} should be at least 1MB',
            );
            expect(
              file.expectedSize,
              lessThan(1024 * 1024 * 1024),
              reason: '${file.fileName} should be less than 1GB',
            );
          }
        }
      });

      test('validates all hashes are correct format', () {
        for (final file in config.paramFiles) {
          expect(file.sha256Hash.length, equals(64));
          expect(RegExp(r'^[a-f0-9]+$').hasMatch(file.sha256Hash), isTrue);
        }
      });
    });

    group('consistency checks', () {
      test('all URLs are properly formatted', () {
        for (final url in config.downloadUrls) {
          expect(url.startsWith('https://'), isTrue);
          expect(Uri.tryParse(url), isNotNull);
        }
      });

      test('all file names have correct extension', () {
        for (final fileName in config.fileNames) {
          expect(
            fileName.endsWith('.params'),
            isTrue,
            reason: 'File $fileName should have .params extension',
          );
        }
      });

      test('timeout values are reasonable', () {
        expect(config.downloadTimeoutSeconds, greaterThan(0));
        expect(config.downloadTimeoutSeconds, lessThan(7200)); // < 2 hours

        expect(config.retryDelaySeconds, greaterThan(0));
        expect(config.retryDelaySeconds, lessThan(60)); // < 1 minute

        expect(config.maxRetries, greaterThan(0));
        expect(config.maxRetries, lessThan(10));
      });

      test('buffer size is reasonable', () {
        expect(config.downloadBufferSize, greaterThan(1024)); // > 1KB
        expect(config.downloadBufferSize, lessThan(10 * 1024 * 1024)); // < 10MB
      });
    });
  });
}
