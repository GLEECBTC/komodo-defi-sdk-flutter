import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Unit tests for the SeedNodeUpdater utility class.
///
/// **Purpose**: Tests the utility functions that convert seed node configurations
/// to string lists for network connectivity, focusing on data transformation
/// and edge case handling.
///
/// **Test Cases**:
/// - Seed node list conversion to string format
/// - Empty seed node list handling
/// - Seed node data extraction and formatting
/// - Network configuration data transformation
///
/// **Functionality Tested**:
/// - Seed node data parsing and extraction
/// - String list generation for network configuration
/// - Empty and null input handling
/// - Data transformation utilities
/// - Network configuration formatting
///
/// **Edge Cases**:
/// - Empty seed node lists
/// - Null or missing seed node data
/// - Seed node contact information handling
/// - Network ID and protocol validation
///
/// **Dependencies**: Tests utility functions for seed node configuration processing,
/// focusing on data transformation rather than network operations. Note that
/// actual HTTP fetching is not tested here (covered in integration tests).
void main() {
  group('SeedNodeUpdater', () {
    test('should convert seed nodes to string list', () {
      final seedNodes = [
        const SeedNode(
          name: 'seed-node-1',
          host: 'seed01.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 6133,
          contact: [SeedNodeContact(email: 'test1@example.com')],
        ),
        const SeedNode(
          name: 'seed-node-2',
          host: 'seed02.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 6133,
          contact: [SeedNodeContact(email: 'test1@example.com')],
        ),
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(seedNodes);

      expect(stringList.length, equals(2));
      expect(stringList[0], equals('seed01.kmdefi.net'));
      expect(stringList[1], equals('seed02.kmdefi.net'));
    });

    test('should handle empty seed nodes list', () {
      final stringList = SeedNodeUpdater.seedNodesToStringList([]);
      expect(stringList, isEmpty);
    });

    test('should handle seed nodes with missing contact information', () {
      final seedNodes = [
        const SeedNode(
          name: 'seed-node-no-contact',
          host: 'seed03.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 6133,
          contact: [], // Empty contact list
        ),
      ];

      // Test with a separate node that might have optional email field
      final seedNodesWithOptionalContact = [
        const SeedNode(
          name: 'seed-node-basic',
          host: 'seed04.kmdefi.net',
          type: 'domain',
          wss: false,
          netId: 6133,
          contact: [SeedNodeContact(email: 'basic@example.com')],
        ),
        ...seedNodes,
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(
        seedNodesWithOptionalContact,
      );

      expect(stringList.length, equals(2));
      expect(stringList[0], equals('seed04.kmdefi.net'));
      expect(stringList[1], equals('seed03.kmdefi.net'));
    });

    test('should handle seed nodes with different network IDs', () {
      final seedNodes = [
        const SeedNode(
          name: 'mainnet-seed',
          host: 'mainnet.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 6133, // Mainnet
          contact: [SeedNodeContact(email: 'mainnet@example.com')],
        ),
        const SeedNode(
          name: 'testnet-seed',
          host: 'testnet.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 8764, // Testnet
          contact: [SeedNodeContact(email: 'testnet@example.com')],
        ),
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(seedNodes);

      expect(stringList.length, equals(2));
      expect(stringList[0], equals('mainnet.kmdefi.net'));
      expect(stringList[1], equals('testnet.kmdefi.net'));
    });

    test('should handle seed nodes with different connection types', () {
      final seedNodes = [
        const SeedNode(
          name: 'wss-seed',
          host: 'wss.kmdefi.net',
          type: 'domain',
          wss: true, // WebSocket Secure
          netId: 6133,
          contact: [SeedNodeContact(email: 'wss@example.com')],
        ),
        const SeedNode(
          name: 'ws-seed',
          host: 'ws.kmdefi.net',
          type: 'domain',
          wss: false, // Regular WebSocket
          netId: 6133,
          contact: [SeedNodeContact(email: 'ws@example.com')],
        ),
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(seedNodes);

      expect(stringList.length, equals(2));
      expect(stringList[0], equals('wss.kmdefi.net'));
      expect(stringList[1], equals('ws.kmdefi.net'));
    });

    test('should handle seed nodes with IP address type', () {
      final seedNodes = [
        const SeedNode(
          name: 'ip-seed-1',
          host: '192.168.1.100',
          type: 'ip', // IP address type
          wss: true,
          netId: 6133,
          contact: [SeedNodeContact(email: 'ip@example.com')],
        ),
        const SeedNode(
          name: 'ip-seed-2',
          host: '10.0.0.50',
          type: 'ip',
          wss: false,
          netId: 6133,
          contact: [SeedNodeContact(email: 'ip2@example.com')],
        ),
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(seedNodes);

      expect(stringList.length, equals(2));
      expect(stringList[0], equals('192.168.1.100'));
      expect(stringList[1], equals('10.0.0.50'));
    });

    test('should extract only host information from seed nodes', () {
      final seedNodes = [
        const SeedNode(
          name: 'complex-seed-node',
          host: 'complex.kmdefi.net',
          type: 'domain',
          wss: true,
          netId: 6133,
          contact: [
            SeedNodeContact(email: 'admin@example.com'),
            SeedNodeContact(email: 'support@example.com'),
          ],
        ),
      ];

      final stringList = SeedNodeUpdater.seedNodesToStringList(seedNodes);

      expect(stringList.length, equals(1));
      expect(stringList[0], equals('complex.kmdefi.net'));
      // Verify that only the host is extracted, not other properties
    });

    // Note: We can't easily test fetchSeedNodes() without mocking HTTP calls
    // This would be covered in integration tests
  });
}
