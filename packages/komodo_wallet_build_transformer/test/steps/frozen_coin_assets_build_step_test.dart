import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:komodo_wallet_build_transformer/src/steps/fetch_coin_assets_build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_file_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/coin_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/github/github_file.dart';
import 'package:test/test.dart';

const _commit = '2b0aefb78b184091ab086c66e513d8b03f5d5a01';
const _source = 'https://raw.githubusercontent.com/GLEECBTC/coins';
const _contents = '{"coin":"ETH"}';

CoinBuildConfig _config() => CoinBuildConfig(
  fetchAtBuildEnabled: true,
  bundledCoinsRepoCommit: _commit,
  updateCommitOnBuild: false,
  coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
  coinsRepoContentUrl: _source,
  coinsRepoBranch: 'master',
  runtimeUpdatesEnabled: true,
  mappedFiles: {'assets/config/coins.json': 'coins'},
  mappedFolders: {'assets/icons': 'icons'},
  concurrentDownloadsEnabled: false,
  cdnBranchMirrors: {'master': 'https://gleecbtc.github.io/coins'},
);

void main() {
  late Directory directory;
  late _PinnedApi api;
  late _Downloader downloader;
  late FetchCoinAssetsBuildStep step;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('frozen_coins_');
    api = _PinnedApi();
    downloader = _Downloader(api);
    step = FetchCoinAssetsBuildStep(
      artifactOutputDirectory: directory.path,
      config: _config(),
      downloader: downloader,
      originalBuildConfig: null,
      buildConfigOutput: File('${directory.path}/build_config.json'),
      githubApiProvider: api,
    );
    // The previous build used a branch CDN despite the pin. Correcting those
    // assets must request a rebuild so Flutter packages the corrected files.
    final coins = File('${directory.path}/assets/config/coins.json');
    await coins.parent.create(recursive: true);
    await coins.writeAsString('old');
  });

  tearDown(() async => directory.delete(recursive: true));

  test('frozen builds bypass branch CDN without changing runtime policy', () {
    final config = BuildConfig(
      apiConfig: ApiBuildConfig(
        apiCommitHash: _commit,
        branch: 'dev',
        fetchAtBuildEnabled: true,
        concurrentDownloadsEnabled: false,
        sourceUrls: [],
        platforms: {},
      ),
      coinCIConfig: _config(),
    );
    final built = FetchCoinAssetsBuildStep.withBuildConfig(
      config,
      step.buildConfigOutput,
      artifactOutputDirectory: directory,
    );
    expect(built.downloader.repoContentUrl, _source);
    expect(
      GitHubFileDownloader.resolveFileContentUri(
        repoContentUrl: built.downloader.repoContentUrl,
        filePath: 'coins',
        repoCommit: _commit,
      ).toString(),
      '$_source/$_commit/coins',
    );
    expect(built.config.runtimeUpdatesEnabled, isTrue);
    expect(
      built.config.effectiveContentUrl,
      'https://gleecbtc.github.io/coins',
    );
  });

  test('build and cache validation use only the pinned commit', () async {
    await expectLater(
      step.build(),
      throwsA(isA<BuildStepWithoutRevertException>()),
    );
    await File('${directory.path}/assets/icons/.gitkeep').writeAsString('');
    expect(downloader.downloadedCommit, _commit);
    expect(await step.canSkip(), isTrue);
    expect(api.fileRefs, everyElement(_commit));
    expect(api.directoryRefs, everyElement(_commit));
    expect(api.fileRefs, hasLength(3));
    expect(api.directoryRefs, hasLength(2));
    expect(step.buildConfigOutput.existsSync(), isFalse);
  });

  test('a same-sized corrupted cached file cannot skip validation', () async {
    await expectLater(
      step.build(),
      throwsA(isA<BuildStepWithoutRevertException>()),
    );
    await File(
      '${directory.path}/assets/config/coins.json',
    ).writeAsString(_contents.replaceFirst('ETH', 'BAD'));
    expect(await step.canSkip(), isFalse);
  });

  test('a corrupted cached icon cannot skip validation', () async {
    await expectLater(
      step.build(),
      throwsA(isA<BuildStepWithoutRevertException>()),
    );
    await File(
      '${directory.path}/assets/icons/ETH.png',
    ).writeAsBytes([3, 2, 1]);
    expect(await step.canSkip(), isFalse);
  });

  test('extra cached icons cannot enter a frozen build', () async {
    await expectLater(
      step.build(),
      throwsA(isA<BuildStepWithoutRevertException>()),
    );
    await File('${directory.path}/assets/icons/UNPINNED.png').writeAsBytes([1]);
    expect(await step.canSkip(), isFalse);
    await expectLater(step.build(), throwsStateError);
  });

  test('downloaded content must match the pinned blob hash', () async {
    downloader.corrupt = true;
    await expectLater(step.build(), throwsStateError);
  });
}

class _PinnedApi extends GithubApiProvider {
  _PinnedApi() : super(owner: 'GLEECBTC', repo: 'coins', branch: 'master');

  final fileRefs = <String?>[];
  final directoryRefs = <String>[];

  @override
  Future<String> getLatestCommitHash({String branch = 'master'}) =>
      throw StateError('Frozen builds must not read a branch head');

  @override
  Future<GitHubFile> getFileMetadata(String filePath, {String? ref}) async {
    fileRefs.add(ref);
    return _file('coins', utf8.encode(_contents));
  }

  @override
  Future<List<GitHubFile>> getDirectoryContents(
    String repoPath,
    String repoCommit,
  ) async {
    directoryRefs.add(repoCommit);
    return [
      _file('ETH.png', [1, 2, 3]),
    ];
  }

  GitHubFile _file(String name, List<int> bytes) => GitHubFile(
    name: name,
    path: name,
    sha: sha1.convert([
      ...utf8.encode('blob ${bytes.length}\x00'),
      ...bytes,
    ]).toString(),
    size: bytes.length,
    downloadUrl: '$_source/$_commit/$name',
    type: 'file',
  );
}

class _Downloader extends GitHubFileDownloader {
  _Downloader(GithubApiProvider api)
    : super(apiProvider: api, repoContentUrl: _source);

  String? downloadedCommit;
  bool corrupt = false;

  @override
  Future<void> downloadSync(
    String repoCommit,
    Map<String, String> mappedFiles,
    Map<String, String> mappedFolders,
  ) async {
    downloadedCommit = repoCommit;
    for (final file in mappedFiles.keys) {
      await File(file).writeAsString(
        corrupt ? _contents.replaceFirst('ETH', 'BAD') : _contents,
      );
    }
    for (final folder in mappedFolders.keys) {
      await Directory(folder).create(recursive: true);
      await File('$folder/ETH.png').writeAsBytes([1, 2, 3]);
    }
  }
}
