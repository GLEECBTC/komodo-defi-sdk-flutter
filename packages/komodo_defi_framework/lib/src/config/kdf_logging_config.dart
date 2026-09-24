import 'package:flutter/foundation.dart';

/// A temporary configuration class to control logging behaviors.
///
/// This class is intended to be a temporary solution for controlling
/// logging verbosity and will be refactored into a more comprehensive
/// logging system in the future.
///
/// TODO: Replace with a proper logging system that allows for more granular control.
class KdfLoggingConfig {
  /// Private constructor to prevent instantiation.
  KdfLoggingConfig._();

  /// Whether verbose logging is enabled.
  ///
  /// When true, additional log messages will be included in the log stream,
  /// such as full RPC responses. Default is false to reduce log noise.
  static bool verboseLogging = false;

  static bool get debugLogging => KdfLoggingConfig.verboseLogging && kDebugMode;
}
