import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Service responsible for fetching and managing seed nodes from remote sources.
///
/// This service handles the downloading and parsing of seed node configurations
/// from the Komodo Platform repository.
class SeedNodeUpdater {
  /// Fetches and parses the seed nodes configuration from the Komodo Platform repository.
  ///
  /// Returns a list of [SeedNode] objects that can be used for P2P networking.
  ///
  /// The [config] parameter allows customization of the repository URL and CDN mirrors.
  /// This parameter is required to ensure consistent configuration across all components.
  ///
  /// The [httpClient] parameter allows injection of a custom HTTP client for testing.
  /// If not provided, a temporary client will be created and properly closed.
  ///
  /// The [timeout] parameter sets the maximum duration for the HTTP request.
  /// Defaults to 15 seconds to prevent indefinite hangs.
  ///
  /// Throws an exception if the seed nodes cannot be fetched or parsed.
  static Future<({List<SeedNode> seedNodes, int netId})> fetchSeedNodes({
    required AssetRuntimeUpdateConfig config,
    bool filterForWeb = kIsWeb,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Get the seed nodes file path from mapped files, or use default
    const seedNodesPath = 'seed-nodes.json';
    final mappedSeedNodesPath =
        config.mappedFiles['assets/config/seed_nodes.json'] ?? seedNodesPath;

    // Build the URL using the centralized logic
    final seedNodesUri = AssetRuntimeUpdateConfig.buildContentUrl(
      path: mappedSeedNodesPath,
      coinsRepoContentUrl: config.coinsRepoContentUrl,
      coinsRepoBranch: config.coinsRepoBranch,
      cdnBranchMirrors: config.cdnBranchMirrors,
    );

    try {
      final client = httpClient ?? http.Client();
      late final http.Response response;
      try {
        response = await client.get(seedNodesUri).timeout(timeout);
      } on TimeoutException {
        throw Exception('Timeout fetching seed nodes from $seedNodesUri');
      } finally {
        if (httpClient == null) client.close();
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch seed nodes. Status code: ${response.statusCode}',
        );
      }

      final seedNodesJson = jsonListFromString(response.body);
      var seedNodes = SeedNode.fromJsonList(seedNodesJson);

      // Filter nodes to the configured netId
      seedNodes = seedNodes.where((e) => e.netId == kDefaultNetId).toList();

      if (filterForWeb && kIsWeb) {
        seedNodes = seedNodes.where((e) => e.wss).toList();
      }

      if (seedNodes.isEmpty) {
        throw Exception('No seed nodes found for netid $kDefaultNetId');
      }

      return (seedNodes: seedNodes, netId: kDefaultNetId);
    } catch (e) {
      debugPrint('Error fetching seed nodes: $e');
      throw Exception('Failed to fetch or process seed nodes: $e');
    }
  }

  /// Converts a list of [SeedNode] objects to a list of strings in the format
  /// expected by the KDF startup configuration.
  ///
  /// This method extracts the host addresses from the seed nodes to create
  /// a simple string list that can be used in the startup configuration.
  static List<String> seedNodesToStringList(List<SeedNode> seedNodes) {
    return seedNodes.map((node) => node.host).toList();
  }
}
