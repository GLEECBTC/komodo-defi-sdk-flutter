import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The open-file soft limit native builds ask for before starting KDF.
///
/// iOS and macOS apps start at 256 (`NOFILE`) with an unlimited hard limit;
/// Foundation lifts that to 2560 the first time `NSFileHandle` or `CFSocket`
/// is initialized, which a Flutter app's font loading does. Any app may raise
/// its own soft limit further. The kernel caps it at `kern.maxfilesperproc`,
/// which XNU leaves at `OPEN_MAX` (10240) on devices with less than 12 GB of
/// RAM, so asking for more gains nothing on most iPhones. Linux desktops
/// usually start at 1024.
const int kOpenFileSoftLimitTarget = 10240;

/// The soft limit to set, or `null` when [soft] already suffices.
///
/// Never lowers a limit, and never asks for more than [hard]. A negative value
/// is a 64-bit `RLIM_INFINITY` read as a signed integer, which is unlimited.
int? raisedOpenFileSoftLimit({
  required int soft,
  required int hard,
  int target = kOpenFileSoftLimitTarget,
}) {
  if (soft < 0) return null;
  final ceiling = hard < 0 ? target : (hard < target ? hard : target);
  return soft < ceiling ? ceiling : null;
}

/// The outcome of [raiseOpenFileSoftLimit], for logging.
final class OpenFileLimitChange {
  const OpenFileLimitChange({
    required this.before,
    required this.after,
    required this.requested,
  });

  /// The soft limit before the call.
  final int before;

  /// The soft limit read back after the call.
  final int after;

  /// The value passed to `setrlimit`, or `null` if none was needed.
  final int? requested;

  bool get raised => after > before;

  @override
  String toString() => requested == null
      ? 'open-file limit already $before'
      : raised
      ? 'open-file limit raised from $before to $after'
      : 'open-file limit stays at $before (asked for $requested)';
}

/// Raises this process's `RLIMIT_NOFILE` soft limit to at most [target].
///
/// Returns `null` where the limit cannot be read: web, Windows, 32-bit builds,
/// or a libc without the symbols. Failures to raise are reported, not thrown;
/// the process keeps the limit it had.
OpenFileLimitChange? raiseOpenFileSoftLimit({
  int target = kOpenFileSoftLimitTarget,
}) {
  final resource = _rlimitNofile;
  if (resource == null) return null;
  final calls = _RlimitCalls.lookup();
  if (calls == null) return null;

  return using((arena) {
    final limit = arena<_RLimit>();
    if (calls.get(resource, limit) != 0) return null;
    final before = limit.ref.current;
    final requested = raisedOpenFileSoftLimit(
      soft: before,
      hard: limit.ref.maximum,
      target: target,
    );
    if (requested != null) {
      limit.ref.current = requested;
      calls.set(resource, limit);
    }
    final after = calls.get(resource, limit) == 0 ? limit.ref.current : before;
    return OpenFileLimitChange(
      before: before,
      after: after,
      requested: requested,
    );
  });
}

/// `RLIMIT_NOFILE` for this platform, where `rlim_t` is 64-bit.
int? get _rlimitNofile {
  if (sizeOf<IntPtr>() != 8) return null;
  if (Platform.isIOS || Platform.isMacOS) return 8;
  if (Platform.isLinux || Platform.isAndroid) return 7;
  return null;
}

final class _RLimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

typedef _RlimitNative = Int32 Function(Int32 resource, Pointer<_RLimit> limit);
typedef _RlimitDart = int Function(int resource, Pointer<_RLimit> limit);

final class _RlimitCalls {
  const _RlimitCalls(this.get, this.set);

  final _RlimitDart get;
  final _RlimitDart set;

  static _RlimitCalls? lookup() {
    final libc = DynamicLibrary.process();
    if (!libc.providesSymbol('getrlimit') ||
        !libc.providesSymbol('setrlimit')) {
      return null;
    }
    return _RlimitCalls(
      libc.lookupFunction<_RlimitNative, _RlimitDart>('getrlimit'),
      libc.lookupFunction<_RlimitNative, _RlimitDart>('setrlimit'),
    );
  }
}
