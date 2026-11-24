@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/native/open_file_limit.dart';

/// Darwin's `RLIM_INFINITY`; Linux's reads as -1 through a signed int.
const _darwinInfinity = 0x7fffffffffffffff;

final class _RLimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

typedef _RlimitNative = Int32 Function(Int32 resource, Pointer<_RLimit> limit);
typedef _RlimitDart = int Function(int resource, Pointer<_RLimit> limit);

final _libc = DynamicLibrary.process();
final _getrlimit = _libc.lookupFunction<_RlimitNative, _RlimitDart>(
  'getrlimit',
);
final _setrlimit = _libc.lookupFunction<_RlimitNative, _RlimitDart>(
  'setrlimit',
);
final _nofile = Platform.isMacOS ? 8 : 7;

(int, int) _readLimit() => using((arena) {
  final limit = arena<_RLimit>();
  expect(_getrlimit(_nofile, limit), 0);
  return (limit.ref.current, limit.ref.maximum);
});

void _setSoftLimit(int soft) => using((arena) {
  final limit = arena<_RLimit>();
  expect(_getrlimit(_nofile, limit), 0);
  limit.ref.current = soft;
  expect(_setrlimit(_nofile, limit), 0);
});

void main() {
  group('raisedOpenFileSoftLimit', () {
    test('raises the app default to the target under an unlimited hard', () {
      expect(raisedOpenFileSoftLimit(soft: 256, hard: _darwinInfinity), 10240);
      expect(raisedOpenFileSoftLimit(soft: 1024, hard: -1), 10240);
    });

    test('never asks for more than the hard limit', () {
      expect(raisedOpenFileSoftLimit(soft: 256, hard: 4096), 4096);
    });

    test('never lowers a limit that already suffices', () {
      expect(raisedOpenFileSoftLimit(soft: 10240, hard: -1), isNull);
      expect(raisedOpenFileSoftLimit(soft: 65536, hard: -1), isNull);
      expect(raisedOpenFileSoftLimit(soft: _darwinInfinity, hard: -1), isNull);
      expect(raisedOpenFileSoftLimit(soft: -1, hard: -1), isNull);
      expect(raisedOpenFileSoftLimit(soft: 4096, hard: 4096), isNull);
    });

    test('honours a custom target', () {
      expect(raisedOpenFileSoftLimit(soft: 256, hard: -1, target: 4096), 4096);
    });
  });

  test(
    'raises the real soft limit through setrlimit and reads it back',
    () {
      final (originalSoft, hard) = _readLimit();
      addTearDown(() => _setSoftLimit(originalSoft));
      _setSoftLimit(256);

      final change = raiseOpenFileSoftLimit();

      final expected = hard < 0 || hard > kOpenFileSoftLimitTarget
          ? kOpenFileSoftLimitTarget
          : hard;
      expect(change, isNotNull);
      expect(change!.before, 256);
      expect(change.requested, expected);
      expect(change.after, expected);
      expect(change.raised, isTrue);
      expect(_readLimit().$1, expected);

      final again = raiseOpenFileSoftLimit();
      expect(again!.requested, isNull, reason: 'already raised');
      expect(again.after, expected);
    },
    skip: Platform.isMacOS || Platform.isLinux
        ? false
        : 'needs a libc RLIMIT_NOFILE',
  );
}
