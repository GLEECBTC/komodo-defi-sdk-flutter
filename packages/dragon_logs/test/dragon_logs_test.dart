// ignore: unused_import
import 'dart:io';

import 'package:dragon_logs/dragon_logs.dart';
import 'package:dragon_logs/src/storage/file_log_storage.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'mock_path_provider_platform.dart';

void main() {
  group('Log export tests', () {
    WidgetsFlutterBinding.ensureInitialized();
    setUp(() async {
      PathProviderPlatform.instance = MockPathProviderPlatform();
      await DragonLogs.init();
    });

    tearDown(() async {
      await DragonLogs.clearLogs();
    });

    test('Test log export', () async {
      for (int i = 0; i < 10000; i++) {
        log('test', 'test message $i');
      }

      for (int i = 0; i < 100; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final logs =
          await DragonLogs.exportLogsStream().asyncMap((event) => event).join();
      expect(logs, isNotNull);
      expect(logs.length, greaterThan(0));
    });

    test('Test native log export order', () async {
      await DragonLogs.clearLogs();
      final logStorageLocation = await FileLogStorage.getLogFolderPath();

      // create 5 log files with 1000 logs each
      for (int i = 0; i < 20; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final monthWithPadding = date.month.toString().padLeft(2, '0');
        final dayWithPadding = date.day.toString().padLeft(2, '0');
        final logFile = File(
          '$logStorageLocation/APP-LOGS_${date.year}-$monthWithPadding-$dayWithPadding.log',
        );
        final logFileSink = logFile.openWrite();
        for (int j = 0; j < 1000; j++) {
          final currentDate = date.add(Duration(seconds: j));
          logFileSink.writeln('test message $j at $currentDate');
        }
        logFileSink.close();
      }

      // export the logs and check that they are in order
      final logs = await DragonLogs.exportLogsStream()
          .asyncMap((event) => '$event\n')
          .join();

      final logMessages = logs.split('\n');
      final logDates =
          logMessages.where((element) => element.contains(' at ')).map((
        logMessage,
      ) {
        final date = logMessage.split(' at ')[1];
        return DateTime.parse(date);
      }).toList();

      for (int i = 0; i < logDates.length - 1; i++) {
        expect(logDates[i].isBefore(logDates[i + 1]), isTrue);
      }
    });
  });
}
