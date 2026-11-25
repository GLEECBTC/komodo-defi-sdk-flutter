/// Marks a directory, and everything later created in it, as excluded from
/// the device backups a platform makes of app data.
///
/// Never throws. A directory left in backups is no worse than before, while a
/// failed start would lock the user out of their wallet.
typedef BackupExclusion = void Function(String directoryPath);

/// Leaves backups as the platform makes them.
void keepInBackups(String directoryPath) {}
