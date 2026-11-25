import 'package:komodo_defi_framework/src/native/backup_exclusion.dart';

/// The web has no KDF data directory to exclude.
BackupExclusion platformBackupExclusion() => keepInBackups;
