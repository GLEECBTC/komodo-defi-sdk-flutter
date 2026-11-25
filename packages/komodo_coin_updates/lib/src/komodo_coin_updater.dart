import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:komodo_coin_updates/hive/hive_registrar.g.dart';
import 'package:logging/logging.dart';

/// A class that provides methods to initialize the Hive adapters for the Komodo
/// Coin Updates package.
class KomodoCoinUpdater {
  static final Logger _log = Logger('KomodoCoinUpdater');

  /// Hive's web backend ignores filesystem paths. Prefix the database names
  /// as well so a candidate cannot open production catalog or custom-token data.
  static String storageBoxName(
    String name, {
    String namespace = const String.fromEnvironment(
      'KDF_COINS_STORAGE_NAMESPACE',
    ),
  }) => namespace.isEmpty ? name : '${namespace}_$name';

  /// Initializes the Hive adapters for the Komodo Coin Updates package.
  ///
  /// This method is used to initialize the Hive adapters for the Komodo Coin
  /// Updates package.
  ///
  /// The [appFolder] is the path to the app folder.
  static Future<void> ensureInitialized(String appFolder) async {
    await Hive.initFlutter(appFolder);
    try {
      Hive.registerAdapters();
    } catch (e) {
      // Allow repeated initialization without crashing (duplicate registration)
      _log.fine('Hive adapters already registered; ignoring: $e');
    }
  }

  /// Initializes the Hive adapters for the Komodo Coin Updates package in an
  /// isolate.
  ///
  /// This method is used to initialize the Hive adapters for the Komodo Coin
  /// Updates package in an isolate.
  ///
  /// The [fullAppFolderPath] is the path to the full app folder.
  static void ensureInitializedIsolate(String fullAppFolderPath) {
    Hive.init(fullAppFolderPath);
    try {
      Hive.registerAdapters();
    } catch (e) {
      // Allow repeated initialization without crashing (duplicate registration)
      _log.fine('Hive adapters already registered (isolate); ignoring: $e');
    }
  }
}
