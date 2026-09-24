abstract class LoggerInterface {
  void log(String key, String message, {Map<String, dynamic>? metadata});

  Future<void> init();

  Stream<String> exportLogsStream();

  // Future<void> appendRawLog(String message);

  String formatMessage(
    String key,
    String message,
    DateTime date, {
    Map<String, dynamic>? metadata,
    Duration? appRunDuration,
  }) {
    final formattedMetadata = metadata == null || metadata.isEmpty
        ? ''
        : '__metadata: ${metadata.toString()}';
    final appRunDurationString =
        appRunDuration == null ? null : 'T+:$appRunDuration';
    final dateString = _formatDate(date);

    return '$dateString$appRunDurationString [$key] $message$formattedMetadata';
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();

    return '${utc.year}-${utc.month}-${utc.day}: '
        '${utc.hour}:${utc.minute}:${utc.second}.${utc.millisecond}';
  }
}
