// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'zcash_params_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ZcashParamFile _$ZcashParamFileFromJson(Map<String, dynamic> json) =>
    _ZcashParamFile(
      fileName: json['file_name'] as String,
      sha256Hash: json['sha256_hash'] as String,
      expectedSize: (json['expected_size'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ZcashParamFileToJson(_ZcashParamFile instance) =>
    <String, dynamic>{
      'file_name': instance.fileName,
      'sha256_hash': instance.sha256Hash,
      'expected_size': instance.expectedSize,
    };

_ZcashParamsConfig _$ZcashParamsConfigFromJson(Map<String, dynamic> json) =>
    _ZcashParamsConfig(
      paramFiles: (json['param_files'] as List<dynamic>)
          .map((e) => ZcashParamFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      primaryUrl: json['primary_url'] as String? ?? 'https://z.cash/downloads/',
      backupUrl:
          json['backup_url'] as String? ??
          'https://komodoplatform.com/downloads/',
      downloadTimeoutSeconds:
          (json['download_timeout_seconds'] as num?)?.toInt() ?? 1800,
      maxRetries: (json['max_retries'] as num?)?.toInt() ?? 3,
      retryDelaySeconds: (json['retry_delay_seconds'] as num?)?.toInt() ?? 5,
      downloadBufferSize:
          (json['download_buffer_size'] as num?)?.toInt() ?? 1048576,
    );

Map<String, dynamic> _$ZcashParamsConfigToJson(_ZcashParamsConfig instance) =>
    <String, dynamic>{
      'param_files': instance.paramFiles,
      'primary_url': instance.primaryUrl,
      'backup_url': instance.backupUrl,
      'download_timeout_seconds': instance.downloadTimeoutSeconds,
      'max_retries': instance.maxRetries,
      'retry_delay_seconds': instance.retryDelaySeconds,
      'download_buffer_size': instance.downloadBufferSize,
    };
