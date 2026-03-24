import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Represents URL patterns for blockchain explorers
class ExplorerUrlPattern {
  const ExplorerUrlPattern({
    this.baseUrl,
    this.txPattern,
    this.addressPattern,
    this.blockPattern,
  });

  factory ExplorerUrlPattern.fromJson(JsonMap config) {
    final baseUrl = _normalizePatternValue(
      config.valueOrNull<String>('explorer_url'),
    );
    if (baseUrl == null) return const ExplorerUrlPattern();

    // Add scheme if missing
    final urlString = baseUrl.startsWith('http') ? baseUrl : 'https://$baseUrl';
    return ExplorerUrlPattern(
      baseUrl: Uri.tryParse(urlString),
      txPattern: _normalizePatternValue(
        config.valueOrNull<String>('explorer_tx_url'),
      ),
      addressPattern: _normalizePatternValue(
        config.valueOrNull<String>('explorer_address_url'),
      ),
      blockPattern: _normalizePatternValue(
        config.valueOrNull<String>('explorer_block_url'),
      ),
    );
  }

  final Uri? baseUrl;
  final String? txPattern;
  final String? addressPattern;
  final String? blockPattern;

  /// Builds a URL by combining base URL with a pattern and parameters
  Uri? buildUrl(String? pattern, Map<String, String> params) {
    if (baseUrl == null || pattern == null || pattern.isEmpty) return null;

    try {
      var url = pattern;
      // Replace placeholders if they exist
      for (final entry in params.entries) {
        if (entry.value.isEmpty) return null;
        final placeholder = '{${entry.key}}';
        if (url.contains(placeholder)) {
          url = url.replaceAll(placeholder, Uri.encodeComponent(entry.value));
        }
      }

      // If no placeholders were found, append the first param value
      if (params.isNotEmpty && url == pattern) {
        url = '$url${Uri.encodeComponent(params.values.first)}';
      }

      final resolvedBaseUrl = baseUrl;
      if (resolvedBaseUrl == null) return null;

      if (resolvedBaseUrl.fragment.isNotEmpty && !url.startsWith('#')) {
        final baseFragment = resolvedBaseUrl.fragment;
        final normalizedBaseFragment = baseFragment.endsWith('/')
            ? baseFragment
            : '$baseFragment/';
        final normalizedUrl = url.startsWith('/') ? url.substring(1) : url;

        return resolvedBaseUrl.replace(
          fragment: '$normalizedBaseFragment$normalizedUrl',
        );
      }

      return resolvedBaseUrl.resolve(url);
    } catch (e) {
      return null;
    }
  }

  static String? _normalizePatternValue(String? value) {
    if (value == null) return null;

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

/// Mixin to provide explorer URL functionality to Protocol classes
mixin ExplorerUrlMixin {
  ExplorerUrlPattern get explorerPattern;
  bool get needs0xPrefix => false;

  Uri? explorerTxUrl(String txHash) {
    if (txHash.isEmpty) return null;

    final hash = needs0xPrefix && !txHash.startsWith('0x')
        ? '0x$txHash'
        : txHash;

    return explorerPattern.buildUrl(explorerPattern.txPattern, {
      'HASH': hash,
      'TX': hash,
    });
  }

  Uri? explorerAddressUrl(String address) {
    if (address.isEmpty) return null;

    return explorerPattern.buildUrl(explorerPattern.addressPattern, {
      'ADDRESS': address,
    });
  }

  Uri? explorerBlockUrl(String blockId) {
    if (blockId.isEmpty) return null;

    return explorerPattern.buildUrl(explorerPattern.blockPattern, {
      'BLOCK': blockId,
    });
  }
}
