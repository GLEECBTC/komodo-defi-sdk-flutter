## 0.2.0 (2026-10-28)

 - **FEAT**(routed-swap): scripted fixtures exercise quote, execution,
   cancellation, persistence/restart, approval evidence and typed failures.
   Replay results do not establish live settlement or deployment readiness.
 - **CHORE**(deps): align SDK 0.9.0 workspace dependency constraints.

 - **TEST**(routed-swap): replay mutually exclusive exact/Max quote requests, concrete execution, exact accepted minima and startup commission propagation.

## 0.1.0

 - **TEST**(routed-swap): rebuild the scripted routed-swap KDF on the pinned
   engine's wire shapes:
   - omitted optional fields;
   - `stage` and `executed_route`;
   - same-chain runs;
   - typed cancel refusals;
   - history filters and paging;
   - two-approval runs;
   - restarts that reuse task ids.

   Add golden JSON taken from the engine's own serde tests.
 - **FEAT**: initial release. Launches pre-authenticated `KomodoDefiSdk`
   instances for tests and benchmarks - HD or iguana, against either a scripted
   fake KDF or the real binary - and reports sign-in, activation and
   first-balance timings. Not published (`publish_to: none`).
 - **FEAT**: replayed harnesses keep their mock secure storage per persistence
   workspace, so reopening a workspace preserves the SDK's cache encryption
   key; deleting the workspace on `dispose` clears it.
