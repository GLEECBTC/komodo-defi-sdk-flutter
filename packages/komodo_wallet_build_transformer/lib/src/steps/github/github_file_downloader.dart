import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_progress_message.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/github_download_event.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/github_file_download_event.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/github/github_file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// A class that handles downloading files from a GitHub repository.
class GitHubFileDownloader {
  /// The [GitHubFileDownloader] class requires the [repoContentUrl]
  /// parameters to be provided during initialization. These parameters specify
  /// the API URL and content URL of the GitHub repository from which files will
  /// be downloaded.
  GitHubFileDownloader({
    required this.apiProvider,
    required this.repoContentUrl,
    this.sendPort,
  });

  final GithubApiProvider apiProvider;
  final String repoContentUrl;
  final SendPort? sendPort;
  static final _log = Logger('GitHubFileDownloader');

  int _totalFiles = 0;
  int _downloadedFiles = 0;
  int _skippedFiles = 0;

  double get progress =>
      ((_downloadedFiles + _skippedFiles) / _totalFiles) * 100;
  String get progressMessage => 'Progress: ${progress.toStringAsFixed(2)}%';
  String get downloadStats =>
      'Downloaded $_downloadedFiles files, skipped $_skippedFiles files';

  /// Asynchronously downloads the mapped files and folders for the [repoCommit]
  /// from the GitHub repository.
  Future<void> download(
    String repoCommit,
    Map<String, String> mappedFiles,
    Map<String, String> mappedFolders,
  ) async {
    final futures = [
      // ignore: avoid_redundant_argument_values
      downloadMappedFiles(repoCommit, mappedFiles, sequential: false),
      downloadMappedFolders(repoCommit, mappedFolders),
    ];
    await Future.wait(futures);
  }

  /// Downloads the mapped files and folders for the [repoCommit] synchronously.
  /// This method is expected to take significantly longer than the [download]
  /// method, as it performs the downloads sequentially, and is affected by
  /// network latency.
  Future<void> downloadSync(
    String repoCommit,
    Map<String, String> mappedFiles,
    Map<String, String> mappedFolders,
  ) async {
    await downloadMappedFiles(repoCommit, mappedFiles, sequential: true);
    await downloadMappedFoldersSync(repoCommit, mappedFolders);
  }

  /// Downloads and saves multiple files from a remote repository.
  ///
  /// The [repoCommit] parameter specifies the commit hash of the repository.
  /// The [mappedFiles] parameter is a map where the keys represent the local
  /// paths where the files will be saved, and the values represent the relative
  /// paths of the files in the repository.
  /// The [sequential] parameter determines whether the files should be
  /// downloaded sequentially or concurrently. By default, the files are
  /// downloaded concurrently.
  ///
  /// This method creates the necessary folders for the local paths and then
  /// iterates over each entry in the [mappedFiles] map. For each entry, it
  /// retrieves the file content from the remote repository using the provided
  /// commit hash and relative path, and saves it to the corresponding local
  /// path.
  ///
  /// Throws an [Exception] if any error occurs during the download or file
  /// saving process.
  Future<void> downloadMappedFiles(
    String repoCommit,
    Map<String, String> mappedFiles, {
    bool sequential = false,
  }) async {
    _totalFiles += mappedFiles.length;
    _log
      ..fine('Downloading ${mappedFiles.length} files')
      ..fine('Processed files: $_downloadedFiles/$_totalFiles');

    createFolders(mappedFiles.keys.toList());

    Future<void> downloadFile(MapEntry<String, String> entry) async {
      final localPath = entry.key;
      _log.finer('Downloading file: $localPath');

      try {
        final fileContent = await _fetchFileContent(entry.value, repoCommit);

        _log.finer('Downloaded file: $localPath');
        await File(localPath).writeAsString(fileContent);

        _downloadedFiles++;
        sendPort?.send(
          BuildProgressMessage(
            message: 'Downloading file: $localPath',
            progress: progress,
            success: true,
          ),
        );
      } catch (e) {
        _log.severe('Failed to download file: $localPath', e);
        rethrow;
      }
    }

    if (sequential) {
      await Future.forEach(mappedFiles.entries, downloadFile);
    } else {
      final downloadFutures = mappedFiles.entries.map(downloadFile);
      await Future.wait(downloadFutures);
    }
  }

  Future<String> _fetchFileContent(
    String relativeFilePath,
    String repoCommit,
  ) async {
    final fileContentUrl = resolveFileContentUri(
      repoContentUrl: repoContentUrl,
      filePath: relativeFilePath,
      repoCommit: repoCommit,
    );

    _log.fine('Fetching file content from: $fileContentUrl');

    final response = await http.get(fileContentUrl);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download file: $fileContentUrl'
        '[${response.statusCode}]: ${response.reasonPhrase}',
      );
    }

    return response.body;
  }

  static Uri resolveFileContentUri({
    required String repoContentUrl,
    required String filePath,
    required String repoCommit,
  }) {
    final pathUri = Uri.tryParse(filePath);
    if (pathUri != null &&
        (pathUri.scheme.toLowerCase() == 'http' ||
            pathUri.scheme.toLowerCase() == 'https')) {
      return pathUri;
    }

    final normalizedBase = repoContentUrl.endsWith('/')
        ? repoContentUrl.substring(0, repoContentUrl.length - 1)
        : repoContentUrl;
    final normalizedPath = filePath.startsWith('/')
        ? filePath.substring(1)
        : filePath;

    final isRawContentUrl = normalizedBase.contains(
      'raw.githubusercontent.com',
    );
    final resolvedUrl = isRawContentUrl
        ? '$normalizedBase/$repoCommit/$normalizedPath'
        : '$normalizedBase/$normalizedPath';

    return Uri.parse(resolvedUrl);
  }

  String _buildFileDownloadUrl(String filePath, String repoCommit) {
    return resolveFileContentUri(
      repoContentUrl: repoContentUrl,
      filePath: filePath,
      repoCommit: repoCommit,
    ).toString();
  }

  /// Downloads the mapped folders from a GitHub repository at a specific commit
  ///
  /// The [repoCommit] parameter specifies the commit hash of the repository.
  /// The [mappedFolders] parameter is a map where the keys represent the
  /// local paths where the files will be downloaded, and the values represent
  /// the corresponding paths in the GitHub repository.
  /// The [timeout] parameter specifies the maximum duration for the
  /// download operation.
  ///
  /// This method iterates over each entry in the [mappedFolders] map and
  /// creates the necessary local folders. Then, it retrieves the list of files
  /// in the GitHub repository at the specified [repoCommit]. For each file, it
  /// initiates a download using the [downloadFile] method.
  ///
  /// Throws an exception if any of the download operations fail.
  Future<void> downloadMappedFolders(
    String repoCommit,
    Map<String, String> mappedFolders, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final folderContents = await _getMappedFolderContents(
      mappedFolders,
      repoCommit,
    );

    final List<Future<void>> downloadFutures = folderContents.entries.map((
      entry,
    ) async {
      _log.fine('Downloading ${entry.value.length} files from ${entry.key}');
      await _downloadFolderContents(entry.key, entry.value, repoCommit);
    }).toList();

    await Future.wait(downloadFutures);

    sendPort?.send(
      const BuildProgressMessage(
        message: '\nDownloaded all files',
        progress: 100,
        success: true,
        finished: true,
      ),
    );
  }

  Future<void> downloadMappedFoldersSync(
    String repoCommit,
    Map<String, String> mappedFolders, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final folderContents = await _getMappedFolderContents(
      mappedFolders,
      repoCommit,
    );
    for (final entry in folderContents.entries) {
      _log.fine('Downloading ${entry.value.length} files from ${entry.key}');
      await _downloadFolderContentsSync(entry.key, entry.value, repoCommit);
    }

    sendPort?.send(
      const BuildProgressMessage(
        message: '\nDownloaded all files',
        progress: 100,
        success: true,
        finished: true,
      ),
    );
  }

  Future<void> _downloadFolderContentsSync(
    String key,
    List<GitHubFile> value,
    String repoCommit,
  ) async {
    final filesWithCdn = value
        .map(
          (file) => file.copyWith(
            downloadUrl: _buildFileDownloadUrl(file.path, repoCommit),
          ),
        )
        .toList();

    await for (final GitHubFileDownloadEvent event in downloadFiles(
      filesWithCdn,
      key,
    )) {
      switch (event.event) {
        case GitHubDownloadEvent.downloaded:
          _downloadedFiles++;
          sendProgressMessage(
            'Downloading file: ${event.localPath}',
            success: true,
          );
        case GitHubDownloadEvent.skipped:
          _skippedFiles++;
          sendProgressMessage(
            'Skipped file: ${event.localPath}',
            success: true,
          );
        case GitHubDownloadEvent.failed:
          sendProgressMessage('Failed to download file: ${event.localPath}');
      }
    }
  }

  Future<void> _downloadFolderContents(
    String key,
    List<GitHubFile> value,
    String repoCommit,
  ) async {
    final List<Future<void>> downloadFutures = value.map((file) async {
      final fileWithCdn = file.copyWith(
        downloadUrl: _buildFileDownloadUrl(file.path, repoCommit),
      );
      await for (final GitHubFileDownloadEvent event in downloadFiles([
        fileWithCdn,
      ], key)) {
        switch (event.event) {
          case GitHubDownloadEvent.downloaded:
            _downloadedFiles++;
            sendProgressMessage(
              'Downloading file: ${event.localPath}',
              success: true,
            );
          case GitHubDownloadEvent.skipped:
            _skippedFiles++;
            sendProgressMessage(
              'Skipped file: ${event.localPath}',
              success: true,
            );
          case GitHubDownloadEvent.failed:
            sendProgressMessage('Failed to download file: ${event.localPath}');
        }
      }
    }).toList();

    await Future.wait(downloadFutures);
  }

  Future<Map<String, List<GitHubFile>>> _getMappedFolderContents(
    Map<String, String> mappedFolders,
    String repoCommit,
  ) async {
    final folderContents = <String, List<GitHubFile>>{};

    for (final entry in mappedFolders.entries) {
      createFolders(mappedFolders.keys.toList());
      final localPath = entry.key;
      final repoPath = entry.value;
      final coins = await apiProvider.getDirectoryContents(
        repoPath,
        repoCommit,
      );

      _totalFiles += coins.length;
      folderContents[localPath] = coins;
    }
    return folderContents;
  }

  /// Sends a progress message to the specified [sendPort].
  ///
  /// The [message] parameter is the content of the progress message.
  /// The [success] parameter indicates whether the progress was successful.
  void sendProgressMessage(String message, {bool success = false}) {
    _log.fine(message);
    sendPort?.send(
      BuildProgressMessage(
        message: message,
        progress: progress,
        success: success,
      ),
    );
  }

  /// Downloads a file from GitHub.
  ///
  /// This method takes a [GitHubFile] object and a [localDir] path as input,
  /// and downloads the file to the specified local directory.
  ///
  /// If the file already exists locally and has the same SHA as the GitHub
  /// file, the download is skipped and a [GitHubFileDownloadEvent] with the
  /// event type
  /// [GitHubDownloadEvent.skipped] is returned.
  ///
  /// If the file does not exist locally or has a different SHA, the file is
  /// downloaded from the GitHub URL specified in the [GitHubFile] object.
  /// The downloaded file is saved to the local directory and a
  /// [GitHubFileDownloadEvent] with the event type
  /// [GitHubDownloadEvent.downloaded] is returned.
  ///
  /// If an error occurs during the download process, an exception is thrown.
  ///
  /// Returns a [GitHubFileDownloadEvent] object containing the event type and
  /// the local path of the downloaded file.
  static Future<GitHubFileDownloadEvent> downloadFile(
    GitHubFile item,
    String localDir,
  ) async {
    final coinName = path.basenameWithoutExtension(item.name);
    final outputPath = path.join(localDir, item.name);

    final localFile = File(outputPath);
    if (localFile.existsSync()) {
      final localFileSha = calculateGithubSha1(outputPath);
      if (localFileSha == item.sha) {
        return GitHubFileDownloadEvent(
          event: GitHubDownloadEvent.skipped,
          localPath: outputPath,
        );
      }
    }

    try {
      _log.finer('Downloading icon for $coinName: ${item.downloadUrl}');
      final fileResponse = await http.read(Uri.parse(item.downloadUrl));
      if (fileResponse.isEmpty) {
        throw Exception('Failed to download file: ${item.downloadUrl}');
      }

      await File(outputPath).writeAsBytes(fileResponse.codeUnits);
      return GitHubFileDownloadEvent(
        event: GitHubDownloadEvent.downloaded,
        localPath: outputPath,
      );
    } catch (e) {
      _log.severe('Failed to download icon for $coinName: $e');
      rethrow;
    }
  }

  /// Downloads multiple files from GitHub and yields download events.
  ///
  /// Given a list of [files] and a [localDir], this method downloads each file
  /// and yields a [GitHubFileDownloadEvent] for each file.
  /// The [GitHubFileDownloadEvent] contains information about the download
  /// event, such as whether the file was successfully downloaded or skipped,
  /// and the [localDir] where the file was saved.
  ///
  /// Example usage:
  /// ```dart
  /// List<GitHubFile> files = [...];
  /// String localDir = '/path/to/local/directory';
  /// Stream<GitHubFileDownloadEvent> downloadStream =
  ///   downloadFiles(files, localDir);
  /// await for (GitHubFileDownloadEvent event in downloadStream) {
  /// }
  /// ```
  static Stream<GitHubFileDownloadEvent> downloadFiles(
    List<GitHubFile> files,
    String localDir,
  ) async* {
    for (final file in files) {
      yield await downloadFile(file, localDir);
    }
  }

  /// Reverts the changes made to a Git file at the specified [filePath].
  /// Returns `true` if the changes were successfully reverted,
  /// `false` otherwise.
  static Future<bool> revertChangesToGitFile(String filePath) async {
    final result = await Process.run('git', <String>['checkout', filePath]);

    if (result.exitCode != 0) {
      _log.severe('Failed to revert changes to $filePath');
      return false;
    } else {
      _log.info('Reverted changes to $filePath');
      return true;
    }
  }

  /// Reverts changes made to a Git file or deletes it if it exists.
  ///
  /// This method takes a [filePath] as input and reverts any changes made to
  /// the Git file located at that path.
  /// If the file does not exist or the revert operation fails, the file
  /// is deleted.
  ///
  /// Example usage:
  /// ```dart
  /// await revertOrDeleteGitFile('/Users/francois/Repos/komodo/komodo-wallet-archive/app_build/fetch_coin_assets.dart');
  /// ```
  static Future<void> revertOrDeleteGitFile(String filePath) async {
    final result = await revertChangesToGitFile(filePath);
    if (!result && File(filePath).existsSync()) {
      _log.info('Deleting $filePath');
      await File(filePath).delete();
    }
  }

  /// Reverts or deletes the specified git files.
  ///
  /// This method takes a list of file paths and iterates over each path,
  /// calling the [revertOrDeleteGitFile] method to revert or delete the file.
  ///
  /// Example usage:
  /// ```dart
  /// List<String> filePaths = ['/path/to/file1', '/path/to/file2'];
  /// await revertOrDeleteGitFiles(filePaths);
  /// ```
  static Future<void> revertOrDeleteGitFiles(List<String> filePaths) async {
    for (final filePath in filePaths) {
      await revertOrDeleteGitFile(filePath);
    }
  }
}

/// Creates folders based on the provided list of folder paths.
///
/// If a folder path includes a file extension, the parent directory of the file
/// will be used instead. The function creates the folders if they don't
/// already exist.
///
/// Example:
/// ```dart
/// List<String> folders = ['/path/to/folder1', '/path/to/folder2/file.txt'];
/// createFolders(folders);
/// ```
void createFolders(List<String> folders) {
  for (var folder in folders) {
    if (path.extension(folder).isNotEmpty) {
      folder = path.dirname(folder);
    }

    final dir = Directory(folder);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }
}

/// Calculates the SHA-1 hash value of a file.
///
/// Reads the contents of the file at the given [filePath] and calculates
/// the SHA-1 hash value using the `sha1` algorithm. Returns the hash value
/// as a string.
///
/// Throws an exception if the file cannot be read or if an error occurs
/// during the hashing process.
Future<String> calculateFileSha1(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final digest = sha1.convert(bytes);
  return digest.toString();
}

/// Calculates the SHA-1 hash of a list of bytes.
///
/// Takes a [bytes] parameter, which is a list of integers representing the
/// bytes.
/// Returns the SHA-1 hash as a string.
String calculateBlobSha1(List<int> bytes) {
  final digest = sha1.convert(bytes);
  return digest.toString();
}

/// Calculates the SHA1 hash of a file located at the given [filePath].
///
/// The function reads the file as bytes, encodes it as a blob, and then
/// calculates the SHA1 hash of the blob. The resulting hash is returned
/// as a [String].
String calculateGithubSha1(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final blob =
      utf8.encode('blob ${bytes.length}${String.fromCharCode(0)}') + bytes;
  final digest = calculateBlobSha1(blob);
  return digest;
}
