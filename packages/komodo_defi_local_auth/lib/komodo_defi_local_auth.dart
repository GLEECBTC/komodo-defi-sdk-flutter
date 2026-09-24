/// A package responsible for managing and abstracting out an authentication
/// service on top of the API's methods
library komodo_defi_local_auth;

export 'src/auth/_auth_index.dart'
    show AuthenticationState, AuthenticationStatus;
export 'src/komodo_defi_local_auth.dart';
export 'src/trezor/_trezor_index.dart';
