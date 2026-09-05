# Komodo DeFi Local Auth

Authentication and wallet management on top of the Komodo DeFi Framework. This package powers the `KomodoDefiSdk.auth` surface and can be used directly for custom flows.

[![License: MIT][license_badge]][license_link]

## Install

```sh
dart pub add komodo_defi_local_auth
```

## Getting started

```dart
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';

final framework = KomodoDefiFramework.create(
  hostConfig: LocalConfig(https: false, rpcPassword: 'your-secure-password'),
);

final auth = KomodoDefiLocalAuth(
  kdf: framework,
  hostConfig: LocalConfig(https: false, rpcPassword: 'your-secure-password'),
);
await auth.ensureInitialized();

// Register or sign in (HD wallet by default)
await auth.register(walletName: 'my_wallet', password: 'strong-pass');
```

## API highlights

- `signIn` / `register` (+ `signInStream` / `registerStream` for progress and HW flows)
- `authStateChanges` and `watchCurrentUser()`
- `currentUser`, `getUsers()`, `signOut()`
- Mnemonic management: `getMnemonicEncrypted()`, `getMnemonicPlainText()`, `updatePassword()`
- Wallet admin: `deleteWallet(...)`
- Trezor flows (PIN entry etc.) via streaming API

HD is enabled by default via `AuthOptions(derivationMethod: DerivationMethod.hdWallet)`. Override if you need legacy (Iguana) mode.

## With the SDK

Prefer using `KomodoDefiSdk` which wires and scopes auth, assets, balances, and the rest for you:

```dart
final sdk = KomodoDefiSdk();
await sdk.initialize();
await sdk.auth.signIn(walletName: 'my_wallet', password: 'pass');
```

## Migrating metadata writes

Metadata writes now require a non-null `expectedWalletId`. This is a breaking
change for callers and custom auth implementations. It applies to
`KomodoDefiAuth.setOrRemoveActiveUserKeyValue`,
`KomodoDefiAuth.updateActiveUserKeyValue`, and the underlying `IAuthService`
methods `setActiveUserMetadata` and `updateActiveUserMetadataKey`.

Capture the authenticated wallet identity when the operation starts, before
showing a backup prompt, exporting a wallet, or starting background setup. Carry
that same identity through every write and any rollback:

```dart
final user = await auth.currentUser;
if (user == null || !(user.walletId.pubkeyHash?.trim().isNotEmpty ?? false)) {
  return; // Restart the operation once wallet identity can be verified.
}
final expectedWalletId = user.walletId;

// Perform the work for this wallet, retaining expectedWalletId across awaits.
await auth.setOrRemoveActiveUserKeyValue(
  'has_backup',
  true,
  expectedWalletId: expectedWalletId,
);
```

The service checks both the expected identity and the freshly resolved active
identity under the authentication write lock. A missing or empty public-key hash
or a wallet mismatch throws `WalletChangedDisconnectException` before the
metadata transform or write. A name alone is insufficient because another wallet
can later reuse it. An identity lookup outage leaves ordinary wallet access
available but prevents these writes until identity can be verified.

On rejection, abort the stale operation. Do not fill in the parameter by reading
the latest active wallet immediately before persistence, or retry with that
wallet's identity. Custom implementations and test doubles must accept and
forward the required argument. Prefer atomic key updates to replacing the whole
metadata map, which can still overwrite concurrent changes for the same wallet.

## License

MIT

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
