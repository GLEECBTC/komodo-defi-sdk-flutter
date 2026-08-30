import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/dev_builds_artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/github_artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';

class ArtefactDownloaderFactory {
  static Map<String, ArtefactDownloader> fromBuildConfig(
    ApiBuildConfig buildConfig, {
    String? githubToken,
  }) {
    final sourceUrls = buildConfig.sourceUrls;
    final downloaders = <String, ArtefactDownloader>{};
    for (final sourceUrl in sourceUrls) {
      if (sourceUrl.startsWith('https://api.github.com/repos/')) {
        downloaders[sourceUrl] = createGithubArtefactDownloader(
          buildConfig,
          sourceUrl,
          githubToken: githubToken,
        );
      } else {
        downloaders[sourceUrl] = DevBuildsArtefactDownloader(
          apiBranch: buildConfig.branch,
          apiCommitHash: buildConfig.apiCommitHash,
          sourceUrl: sourceUrl,
        );
      }
    }
    return downloaders;
  }

  static ArtefactDownloader createGithubArtefactDownloader(
    ApiBuildConfig buildConfig,
    String sourceUrl, {
    String? githubToken,
  }) {
    final apiProvider = GithubApiProvider.withBaseUrl(
      baseUrl: sourceUrl,
      branch: buildConfig.branch,
      token: githubToken,
    );
    return GithubArtefactDownloader(
      apiCommitHash: buildConfig.apiCommitHash,
      apiBranch: buildConfig.branch,
      sourceUrl: sourceUrl,
      githubApiProvider: apiProvider,
    );
  }
}
