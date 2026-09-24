import 'package:intl/intl.dart';

import 'logger_interface.dart';

class ConsoleLogger extends LoggerInterface {
  ConsoleLogger._internal();

  factory ConsoleLogger() {
    return _instance;
  }

  static final ConsoleLogger _instance = ConsoleLogger._internal();

  @override
  Future<void> init() async {}

  @override
  void log(String key, String message, {Map<String, dynamic>? metadata}) async {
    final now = DateTime.now();
    final dateString = DateFormat('HH:mm:ss.SSS').format(now);
    print('$dateString $key] $message');
  }

  @override
  Stream<String> exportLogsStream() {
    throw UnimplementedError();
  }

  // @override
  // Future<void> appendRawLog(String message) async {
  //   log('RAW', message);
  // }
}
