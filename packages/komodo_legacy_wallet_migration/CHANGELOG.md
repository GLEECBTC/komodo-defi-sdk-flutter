## 0.1.1

 - **FIX**(android): open legacy encrypted shared preferences with
   `resetOnError: false`, so a read failure surfaces instead of silently
   clearing the legacy wallet data the migration exists to read.
 - **FIX**(deps): raise the `flutter_secure_storage` lower bound off the
   `10.0.0-beta.4` pre-release to `^10.0.0`. It already resolved to a stable
   10.x, and pub warns when a stable release depends on a pre-release.

## 0.1.0

 - **FEAT**(migration): add legacy wallet discovery, metadata parsing, password verification, import, and cleanup utilities.
 - **FIX**(migration): use a PointyCastle-based Argon2 verifier for WASM compatibility.
 - **FIX**(migration): guard unsupported platforms and wait for KDF RPC readiness before migration work.
