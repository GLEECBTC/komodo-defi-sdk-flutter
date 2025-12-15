import 'package:freezed_annotation/freezed_annotation.dart';

part 'zcash_params_config.freezed.dart';
part 'zcash_params_config.g.dart';

/// Configuration for a ZCash parameter file.
@freezed
abstract class ZcashParamFile with _$ZcashParamFile {
  @JsonSerializable(fieldRename: FieldRename.snake)
  /// Creates a ZCash parameter file configuration.
  const factory ZcashParamFile({
    /// The name of the parameter file.
    required String fileName,

    /// The expected SHA256 hash of the file for integrity verification.
    required String sha256Hash,

    /// The expected file size in bytes (optional, for progress reporting).
    int? expectedSize,
  }) = _ZcashParamFile;

  const ZcashParamFile._();

  /// Creates a ZcashParamFile instance from JSON.
  factory ZcashParamFile.fromJson(Map<String, dynamic> json) =>
      _$ZcashParamFileFromJson(json);
}

/// Configuration for ZCash parameter downloads.
@freezed
abstract class ZcashParamsConfig with _$ZcashParamsConfig {
  @JsonSerializable(fieldRename: FieldRename.snake)
  /// Creates a ZCash parameters configuration.
  const factory ZcashParamsConfig({
    /// List of ZCash parameter files to download.
    required List<ZcashParamFile> paramFiles,

    /// Primary download URL for ZCash parameters.
    @Default('https://z.cash/downloads/') String primaryUrl,

    /// Backup download URL for ZCash parameters.
    @Default('https://komodoplatform.com/downloads/') String backupUrl,

    /// Timeout duration for HTTP downloads in seconds.
    @Default(1800) int downloadTimeoutSeconds, // 30 minutes
    /// Maximum number of retry attempts for failed downloads.
    @Default(3) int maxRetries,

    /// Delay between retry attempts in seconds.
    @Default(5) int retryDelaySeconds,

    /// Buffer size for file downloads in bytes (1MB).
    @Default(1048576) int downloadBufferSize,
  }) = _ZcashParamsConfig;

  const ZcashParamsConfig._();

  /// Creates a ZcashParamsConfig instance from JSON.
  factory ZcashParamsConfig.fromJson(Map<String, dynamic> json) =>
      _$ZcashParamsConfigFromJson(json);

  /// Default configuration instance with only sapling parameters.
  static const ZcashParamsConfig defaultConfig = ZcashParamsConfig(
    paramFiles: [
      ZcashParamFile(
        fileName: 'sapling-spend.params',
        sha256Hash:
            '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13',
        expectedSize: 47958396,
      ),
      ZcashParamFile(
        fileName: 'sapling-output.params',
        sha256Hash:
            '2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4',
        expectedSize: 3592860,
      ),
    ],
  );

  /// Extended configuration instance with all parameter files including sprout.
  static const ZcashParamsConfig extendedConfig = ZcashParamsConfig(
    paramFiles: [
      ZcashParamFile(
        fileName: 'sapling-spend.params',
        sha256Hash:
            '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13',
        expectedSize: 47958396,
      ),
      ZcashParamFile(
        fileName: 'sapling-output.params',
        sha256Hash:
            '2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4',
        expectedSize: 3592860,
      ),
      ZcashParamFile(
        fileName: 'sprout-groth16.params',
        sha256Hash:
            'b685d700c60328498fbde589c8c7c484c722b788b265b72af448a5bf0ee55b50',
        expectedSize: 725523612,
      ),
    ],
  );

  /// List of all download URLs in order of preference.
  List<String> get downloadUrls => [primaryUrl, backupUrl];

  /// Names of the ZCash parameter files that need to be downloaded.
  List<String> get fileNames =>
      paramFiles.map((file) => file.fileName).toList();

  /// Timeout duration for HTTP downloads.
  Duration get downloadTimeout => Duration(seconds: downloadTimeoutSeconds);

  /// Delay between retry attempts.
  Duration get retryDelay => Duration(seconds: retryDelaySeconds);

  /// Gets the configuration for a given parameter file.
  /// Returns null if the file is not found.
  ZcashParamFile? getParamFile(String fileName) {
    try {
      return paramFiles.firstWhere((file) => file.fileName == fileName);
    } catch (e) {
      return null;
    }
  }

  /// Gets the expected file size for a given parameter file.
  /// Returns null if the file size is unknown.
  int? getExpectedFileSize(String fileName) {
    return getParamFile(fileName)?.expectedSize;
  }

  /// Gets the expected SHA256 hash for a given parameter file.
  /// Returns null if the hash is unknown.
  String? getExpectedHash(String fileName) {
    return getParamFile(fileName)?.sha256Hash;
  }

  /// Gets the total expected download size for all parameter files.
  int get totalExpectedSize {
    return paramFiles
        .where((file) => file.expectedSize != null)
        .fold(0, (sum, file) => sum + file.expectedSize!);
  }

  /// Validates that a filename is a known ZCash parameter file.
  bool isValidFileName(String fileName) {
    return fileNames.contains(fileName);
  }

  /// Gets the full download URL for a parameter file from a base URL.
  String getFileUrl(String baseUrl, String fileName) {
    var url = baseUrl;
    if (!url.endsWith('/')) {
      url += '/';
    }
    return '$url$fileName';
  }
}
