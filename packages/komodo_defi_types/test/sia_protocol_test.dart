import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonMap;
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  group('SiaProtocol parsing', () {
    test('parses server_url from nodes when server_url not set', () {
      final json = {
        'type': 'SIA',
        'required_confirmations': 1,
        'nodes': [
          {'url': 'https://api.siascan.com/wallet/api'},
        ],
      };

      final protocol = SiaProtocol.fromJson(JsonMap.of(json));
      expect(protocol.serverUrl, 'https://api.siascan.com/wallet/api');
      expect(protocol.requiredConfirmations, 1);
      expect(protocol.supportsMultipleAddresses, false);
    });

    test('prefers direct server_url when present', () {
      final json = {
        'type': 'SIA',
        'server_url': 'https://custom.siascan/wallet/api',
        'nodes': [
          {'url': 'https://api.siascan.com/wallet/api'},
        ],
      };

      final protocol = SiaProtocol.fromJson(JsonMap.of(json));
      expect(protocol.serverUrl, 'https://custom.siascan/wallet/api');
    });

    test('does not support tx history streaming', () {
      final json = {
        'type': 'SIA',
        'nodes': [
          {'url': 'https://api.siascan.com/wallet/api'},
        ],
      };

      final protocol = SiaProtocol.fromJson(JsonMap.of(json));
      expect(protocol.supportsTxHistoryStreaming(isChildAsset: false), false);
      // confirm that the parameters have no effect (optional and required)
      expect(protocol.supportsTxHistoryStreaming(isChildAsset: true), false);
    });
  });
}
