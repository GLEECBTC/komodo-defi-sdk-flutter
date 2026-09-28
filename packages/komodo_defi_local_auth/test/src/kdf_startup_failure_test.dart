import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/kdf_startup_failure.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  group('authExceptionForKdfStartup', () {
    test('reads initError as an incorrect password when one was sent', () {
      final exception = authExceptionForKdfStartup(
        KdfStartupResult.initError,
        walletPasswordSent: true,
      );

      expect(exception.type, AuthExceptionType.incorrectPassword);
      expect(exception.message, 'Incorrect password or invalid seed');
    });

    test('reads initError as a failed start when no password was sent', () {
      final exception = authExceptionForKdfStartup(
        KdfStartupResult.initError,
        walletPasswordSent: false,
      );

      expect(exception.type, AuthExceptionType.walletStartFailed);
      expect(exception.details, {'kdf_error': 'initError'});
    });

    for (final walletPasswordSent in [true, false]) {
      group('with walletPasswordSent: $walletPasswordSent', () {
        for (final result in [
          KdfStartupResult.configError,
          KdfStartupResult.invalidParams,
          KdfStartupResult.spawnError,
          KdfStartupResult.unknownError,
        ]) {
          test('reports ${result.name} as a failed start', () {
            final exception = authExceptionForKdfStartup(
              result,
              walletPasswordSent: walletPasswordSent,
            );

            expect(exception.type, AuthExceptionType.walletStartFailed);
            expect(exception.details, {'kdf_error': result.name});
          });
        }

        test('reports alreadyRunning as a running wallet', () {
          final exception = authExceptionForKdfStartup(
            KdfStartupResult.alreadyRunning,
            walletPasswordSent: walletPasswordSent,
          );

          expect(exception.type, AuthExceptionType.walletAlreadyRunning);
        });

        test('rejects ok, which is not a failure', () {
          expect(
            () => authExceptionForKdfStartup(
              KdfStartupResult.ok,
              walletPasswordSent: walletPasswordSent,
            ),
            throwsArgumentError,
          );
        });
      });
    }
  });
}
