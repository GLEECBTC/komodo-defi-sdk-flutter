# Dragon Logs

<p align="center">
<a href="https://pub.dev/packages/dragon_logs"><img src="https://img.shields.io/pub/v/dragon_logs.svg" alt="Pub"></a>
</p>

A lightweight, high-throughput cross-platform logging framework for Flutter with persisted log storage.

Maintained by [GLEEC](https://www.gleec.com).

## Overview

Dragon Logs aims to simplify the logging and log storage process in your Flutter apps by ensuring it's efficient, easy to use, and uniform across different platforms. With its high-performance novel storage method for web, OPFS, Dragon Logs stands out as a modern solution for your logging needs.

## Roadmap

- ✅ Cross-platform log storage
- ✅ Cross-platform logs download
- ✅ Flutter web wasm support
- ⬜ Web multi-threading support
- ⬜ Log levels (e.g. debug, info, warning, error)
- ⬜ Performance metrics (in progress)
- ⬜ Compressed file export
- ⬜ Dev environment configurable logging filters for console
- ⬜ Stacktrace formatting
- ⬜ Log analytics

Your feedback and contributions to help achieve these features would be much appreciated!

## Installation

```sh
flutter pub add dragon_logs
```

# Dragon Logs API Documentation and Usage

Dragon Logs is a lightweight, high-throughput logging framework designed for Flutter applications. This document provides an overview of the main API and usage instructions to help developers quickly integrate and use the package in their Flutter applications.

## API Overview

### Initialization

#### `init()`

Initialize the logger. This method prepares the logger for use and ensures any old logs beyond the set maximum storage size are deleted.

This method must be called after Widget binding has been initialized and before logging is attempted.

Usage:

```dart
await DragonLogs.init();
```

### Metadata Management

#### `setSessionMetadata(Map<String, dynamic> metadata)`

Set session metadata that can be attached to logs. This is useful for attaching session-specific information such as user IDs, device information, etc.

Usage:

```dart
DragonLogs.setSessionMetadata({
  'userID': '12345',
  'device': 'Pixel 4a',
  'appVersion': '1.0.0'
});
```

#### `clearSessionMetadata()`

Clear any session metadata that was previously set.

Usage:

```dart
DragonLogs.clearSessionMetadata();
```

### Logging

#### `log(String message, [String key = 'LOG'])`

Log a message with an optional key. The message will be stored with any session metadata that's currently set.

Usage:

```dart
log('This is a sample log message.');
log('User logged in', 'USER_ACTION');
```

### Exporting Logs

#### `exportLogsStream() -> Stream<String>`

Get a stream of all stored logs. This is useful if you want to process logs in a streaming manner, e.g., for streaming uploads.

The stream events do not guarantee a uniform payload. Some events may contain a single log entry or a split log entry, while others may contain the entire log history for a given day. Appending all events to a single string (without any separators) represents the entire log history as is stored on the device.

**NB**: The stream will not emit any logs that are added after the stream is created and it completes after emitting all stored logs.

**NB**: It is highly recommended to not use **toList()** or store the entire stream in memory for extremely large log histories as this may cause memory issues. Prefer using lazy iterables where possible.

Usage:

```dart
  final logsStream = DragonLogs.exportLogsStream();

  File file = File('${getApplicationCacheDirectory}}/output.txt');

  file = await file.exists() ? file : await file.create(recursive: true);

  final logFileSink = file.openWrite(mode: FileMode.append);

  for (final log in await logsStream) {
    logFileSink.writeln(log);
  }

  await logFileSink.close();
```

#### `exportLogsString() -> Future<String>`

Get all stored logs as a single concatenated string.

**NB**: This method is not recommended for extremely large log histories as it may cause memory issues. Prefer using the stream-based API where possible.

Usage:

```dart
final logsString = await DragonLogs.exportLogsString();
print(logsString);
```

#### `exportLogsToDownload() -> Future<void>`

Export the stored logs, preparing them for download. The exact behavior may vary depending on platform specifics. The files are stored in the app's documents directory. On non-web platforms, the files are exported using the system's save-as or share dialog. On web, the files are downloaded to the default downloads directory.

Usage:

```dart
await DragonLogs.exportLogsToDownload();
```

### Utilities

#### `getLogFolderSize() -> Future<int>`

Get the current size of the log storage folder in bytes. This excludes generated export files.

Usage:

```dart
final sizeInBytes = await DragonLogs.getLogFolderSize();
print('Log folder size: $sizeInBytes bytes');
```

#### `perfomanceMetricsSummary -> String` (COMING SOON)

Get a summary of the logger's performance metrics.

Usage:

```dart
final metricsSummary = DragonLogs.perfomanceMetricsSummary;
print(metricsSummary);
```

## Contributing

Dragon Logs welcomes contributions from the community. Whether it's a bug report, feature suggestion, or a code contribution, we value all feedback. Please read the [CONTRIBUTING.md](link_to_contributing.md) file for detailed instructions.

## License

This project is licensed under the MIT License. See the [LICENSE](link_to_license_file) file for more details.

---

Made with ❤️ by [GLEEC](https://www.gleec.com)
