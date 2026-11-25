import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location.dart';

/// The web keeps KDF's data in the browser, so there is nothing to resolve.
KdfDesktopDataResolver platformKdfDesktopDataResolver() =>
    (_, _) async => null;

KdfDataStartRecorder platformKdfDataStartRecorder() => (_) async {};
