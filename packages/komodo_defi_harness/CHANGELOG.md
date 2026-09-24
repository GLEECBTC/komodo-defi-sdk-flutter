## 0.1.0

 - **FEAT**: initial release. Launches pre-authenticated `KomodoDefiSdk`
   instances for tests and benchmarks - HD or iguana, against either a scripted
   fake KDF or the real binary - and reports sign-in, activation and
   first-balance timings. Not published (`publish_to: none`).
 - **FEAT**: replayed harnesses keep their mock secure storage per persistence
   workspace, so reopening a workspace preserves the SDK's cache encryption
   key; deleting the workspace on `dispose` clears it.
