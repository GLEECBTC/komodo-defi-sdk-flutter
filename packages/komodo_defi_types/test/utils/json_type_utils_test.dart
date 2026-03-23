import 'package:komodo_defi_types/src/utils/json_type_utils.dart';
import 'package:test/test.dart';

void main() {
  group('value<T> and valueOrNull<T> with List types', () {
    test('value<List<String>> returns typed list', () {
      final json = <String, dynamic>{
        'tags': ['alpha', 'beta', 'gamma'],
      };
      final result = json.value<List<String>>('tags');
      expect(result, isA<List<String>>());
      expect(result, ['alpha', 'beta', 'gamma']);
    });

    test('value<List<int>> returns typed list', () {
      final json = <String, dynamic>{
        'counts': [1, 2, 3],
      };
      final result = json.value<List<int>>('counts');
      expect(result, isA<List<int>>());
      expect(result, [1, 2, 3]);
    });

    test('value<List<double>> returns typed list', () {
      final json = <String, dynamic>{
        'prices': [1.5, 2.5, 3.5],
      };
      final result = json.value<List<double>>('prices');
      expect(result, isA<List<double>>());
      expect(result, [1.5, 2.5, 3.5]);
    });

    test('value<List<num>> returns typed list', () {
      final json = <String, dynamic>{
        'values': [1, 2.5, 3],
      };
      final result = json.value<List<num>>('values');
      expect(result, isA<List<num>>());
      expect(result, [1, 2.5, 3]);
    });

    test('value<List<bool>> returns typed list', () {
      final json = <String, dynamic>{
        'flags': [true, false, true],
      };
      final result = json.value<List<bool>>('flags');
      expect(result, isA<List<bool>>());
      expect(result, [true, false, true]);
    });

    test('value<List<JsonMap>> returns typed list', () {
      final json = <String, dynamic>{
        'items': [
          {'name': 'a'},
          {'name': 'b'},
        ],
      };
      final result = json.value<List<Map<String, dynamic>>>('items');
      expect(result, isA<List<Map<String, dynamic>>>());
      expect(result.length, 2);
      expect(result[0]['name'], 'a');
    });

    test('value<List<dynamic>> returns typed list', () {
      final json = <String, dynamic>{
        'mixed': [1, 'two', true],
      };
      final result = json.value<List<dynamic>>('mixed');
      expect(result, isA<List<dynamic>>());
      expect(result, [1, 'two', true]);
    });

    test('valueOrNull<List<String>> returns null for missing key', () {
      final json = <String, dynamic>{'other': 'value'};
      final result = json.valueOrNull<List<String>>('tags');
      expect(result, isNull);
    });

    test('valueOrNull<List<String>> returns list for existing key', () {
      final json = <String, dynamic>{
        'tags': ['a', 'b'],
      };
      final result = json.valueOrNull<List<String>>('tags');
      expect(result, isA<List<String>>());
      expect(result, ['a', 'b']);
    });

    test('valueOrNull<List<String>> returns null for null value', () {
      final json = <String, dynamic>{'tags': null};
      final result = json.valueOrNull<List<String>>('tags');
      expect(result, isNull);
    });
  });

  group('value<T> and valueOrNull<T> with Map types', () {
    test('value<JsonMap> returns nested map', () {
      final json = <String, dynamic>{
        'config': {'key': 'val'},
      };
      final result = json.value<Map<String, dynamic>>('config');
      expect(result, isA<Map<String, dynamic>>());
      expect(result['key'], 'val');
    });

    test('valueOrNull<JsonMap> returns null for missing key', () {
      final json = <String, dynamic>{'other': 1};
      final result = json.valueOrNull<Map<String, dynamic>>('config');
      expect(result, isNull);
    });
  });

  group('value<T> with primitive type conversions', () {
    test('int to String conversion', () {
      final json = <String, dynamic>{'count': 42};
      final result = json.value<String>('count');
      expect(result, '42');
    });

    test('bool from int (0 = false, 1 = true)', () {
      final json = <String, dynamic>{'flag': 1};
      final result = json.value<bool>('flag');
      expect(result, true);

      final json2 = <String, dynamic>{'flag': 0};
      final result2 = json2.value<bool>('flag');
      expect(result2, false);
    });

    test('int from num normalization', () {
      final json = <String, dynamic>{'count': 42.0};
      final result = json.value<int>('count');
      expect(result, 42);
    });

    test('double from num normalization', () {
      final json = <String, dynamic>{'price': 42};
      final result = json.value<double>('price');
      expect(result, 42.0);
    });

    test('String value passthrough', () {
      final json = <String, dynamic>{'name': 'hello'};
      final result = json.value<String>('name');
      expect(result, 'hello');
    });
  });

  group('nested key traversal', () {
    test('value with nested keys', () {
      final json = <String, dynamic>{
        'outer': {
          'inner': 'deep',
        },
      };
      final result = json.value<String>('outer', 'inner');
      expect(result, 'deep');
    });

    test('valueOrNull with missing nested key returns null', () {
      final json = <String, dynamic>{
        'outer': {'other': 'value'},
      };
      final result = json.valueOrNull<String>('outer', 'inner');
      expect(result, isNull);
    });
  });

  group('tryGetStringList', () {
    test('returns list for valid string list', () {
      final json = <String, dynamic>{
        'items': ['a', 'b'],
      };
      expect(json.tryGetStringList('items'), ['a', 'b']);
    });

    test('returns null for missing key', () {
      final json = <String, dynamic>{'other': 1};
      expect(json.tryGetStringList('items'), isNull);
    });

    test('returns null for non-list value', () {
      final json = <String, dynamic>{'items': 'not a list'};
      expect(json.tryGetStringList('items'), isNull);
    });
  });
}
