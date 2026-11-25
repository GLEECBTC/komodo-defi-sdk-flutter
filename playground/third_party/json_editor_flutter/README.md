# Playground compatibility copy

This is `json_editor_flutter` 1.4.2 from
[pub.dev](https://pub.dev/packages/json_editor_flutter/versions/1.4.2), matching
upstream commit [`dc9e6608030688f686ccfac4b15487d6a1b8a125`](https://github.com/SanjaySodani/json_editor_flutter/tree/dc9e6608030688f686ccfac4b15487d6a1b8a125).
It is private to the playground; SDK packages do not depend on it.

The library source and BSD 3-Clause license are unchanged. The only package
change raises the Dart SDK lower bound from 2.17 to 3.0. Flutter 3.50's const
`Flex` constructor compares `CrossAxisAlignment` enum values with `!=`.
Generalized constant equality requires Dart language version 3.0, while the
upstream package opts into 2.17 regardless of the installed Dart SDK. See
[Dart language issue 1811](https://github.com/dart-lang/language/issues/1811).

No compatible release or upstream commit was available on 2026-11-15. Replace
this path dependency with a hosted release once upstream raises its language
version to at least 3.0 (or provides an equivalent compatibility fix), then
remove this directory and rerun the playground release web build.

Provenance:

- [Original archive](https://pub.dev/api/archives/json_editor_flutter-1.4.2.tar.gz)
- Archive SHA-256: `851a6adbfb6ee794809a941d82dde0c9f8b6c2fcadabcbde386f1cb6bf27466a`
- Library SHA-256: `ab4ca3490088af67922b8913ac2aea18999e3aeefa6a9e786c223b9c387db941`
- The complete upstream license is retained in [LICENSE](LICENSE) and remains
  available to Flutter's license registry through this package dependency.

Keep the library source unchanged, including its formatting, so the limited
compatibility change remains auditable against the upstream archive.
The playground analyzer excludes this third-party source, as it did when the
dependency lived in the pub cache. Its compilation and behavior are checked by
the release web build and `test/json_editor_compatibility_test.dart`.
