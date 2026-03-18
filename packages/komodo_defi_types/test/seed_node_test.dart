import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('SeedNode', () {
    test('should create SeedNode from JSON', () {
      final json = {
        'name': 'seed-node-1',
        'host': 'seed01.kmdefi.net',
        'type': 'domain',
        'wss': true,
        'netid': 6133,
        'contact': [
          {'email': 'admin@example.com'},
        ],
      };

      final seedNode = SeedNode.fromJson(json);

      expect(seedNode.name, equals('seed-node-1'));
      expect(seedNode.host, equals('seed01.kmdefi.net'));
      expect(seedNode.contact.length, equals(1));
      expect(seedNode.contact.first.email, equals('admin@example.com'));
    });

    test('should convert SeedNode to JSON', () {
      const seedNode = SeedNode(
        name: 'seed-node-2',
        host: 'seed02.kmdefi.net',
        type: 'domain',
        wss: true,
        netId: 6133,
        contact: [SeedNodeContact(email: 'test@example.com')],
      );

      final json = seedNode.toJson();
      final contacts = json['contact'] as List<Object?>?;

      expect(json['name'], equals('seed-node-2'));
      expect(json['host'], equals('seed02.kmdefi.net'));
      expect(contacts, isNotNull);
      expect(contacts, isA<List<dynamic>>());
      final nonNullContacts = contacts!;
      expect(nonNullContacts.length, equals(1));

      final contact = nonNullContacts.first! as Map<String, Object?>;
      expect(contact['email'], equals('test@example.com'));
    });

    test('should create list of SeedNodes from JSON list', () {
      final jsonList = [
        {
          'name': 'seed-node-1',
          'host': 'seed01.kmdefi.net',
          'type': 'domain',
          'wss': true,
          'netid': 6133,
          'contact': [
            {'email': ''},
          ],
        },
        {
          'name': 'seed-node-2',
          'host': 'seed02.kmdefi.net',
          'type': 'domain',
          'wss': true,
          'netid': 6133,
          'contact': [
            {'email': ''},
          ],
        },
      ];

      final seedNodes = SeedNode.fromJsonList(jsonList);

      expect(seedNodes.length, equals(2));
      expect(seedNodes[0].name, equals('seed-node-1'));
      expect(seedNodes[0].host, equals('seed01.kmdefi.net'));
      expect(seedNodes[1].name, equals('seed-node-2'));
      expect(seedNodes[1].host, equals('seed02.kmdefi.net'));
    });

    test('should handle equality correctly', () {
      const seedNode1 = SeedNode(
        name: 'test',
        host: 'example.com',
        type: 'domain',
        wss: true,
        netId: 6133,
        contact: [SeedNodeContact(email: 'test@example.com')],
      );

      const seedNode2 = SeedNode(
        name: 'test',
        host: 'example.com',
        type: 'domain',
        wss: true,
        netId: 6133,
        contact: [SeedNodeContact(email: 'test@example.com')],
      );

      const seedNode3 = SeedNode(
        name: 'different',
        host: 'example.com',
        type: 'domain',
        wss: true,
        netId: 6133,
        contact: [SeedNodeContact(email: 'test@example.com')],
      );

      expect(seedNode1, equals(seedNode2));
      expect(seedNode1, isNot(equals(seedNode3)));
    });
  });

  group('SeedNodeContact', () {
    test('should create SeedNodeContact from JSON', () {
      final json = {'email': 'test@example.com'};
      final contact = SeedNodeContact.fromJson(json);

      expect(contact.email, equals('test@example.com'));
    });

    test('should convert SeedNodeContact to JSON', () {
      const contact = SeedNodeContact(email: 'test@example.com');
      final json = contact.toJson();

      expect(json['email'], equals('test@example.com'));
    });
  });
}
