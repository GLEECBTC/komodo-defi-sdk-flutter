## 0.1.1

 - **FIX**(android): open legacy encrypted shared preferences with
   `resetOnError: false`, so a read failure surfaces instead of silently
   clearing the legacy wallet data the migration exists to read.

## 0.1.0

 - **FEAT**(migration): add legacy wallet discovery, metadata parsing, password verification, import, and cleanup utilities.
 - **FIX**(migration): use a PointyCastle-based Argon2 verifier for WASM compatibility.
 - **FIX**(migration): guard unsupported platforms and wait for KDF RPC readiness before migration work.
