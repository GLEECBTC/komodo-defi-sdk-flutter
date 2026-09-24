import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Whether the host has a usable policy for starting network activation.
enum ActivationPolicyStatus {
  /// A lookup is in progress; existing cached data remains usable.
  loading,

  /// A successful lookup permits activation of unrestricted assets.
  ready,

  /// A lookup failed; retained restrictions still apply.
  unavailable,
}

/// A policy answer and the last known asset restrictions.
final class ActivationPolicySnapshot {
  /// Creates an immutable policy snapshot.
  ActivationPolicySnapshot({
    required this.status,
    Set<AssetId> blockedAssets = const {},
  }) : blockedAssets = Set.unmodifiable(blockedAssets);

  /// Availability of the host's policy answer.
  final ActivationPolicyStatus status;

  /// Restrictions from the most recent successful answer.
  final Set<AssetId> blockedAssets;

  /// Whether this asset or one of its ancestors is restricted.
  bool isBlocked(AssetId asset) =>
      blockedAssets.contains(asset) ||
      (asset.parentId != null && isBlocked(asset.parentId!));

  /// Whether new network activation may start for this asset.
  bool canActivate(AssetId asset) =>
      status == ActivationPolicyStatus.ready && !isBlocked(asset);
}

/// An activation could not start or continue under the host's current policy.
final class ActivationPolicyException implements Exception {
  /// Records the rejected asset and policy status.
  const ActivationPolicyException(this.assetId, this.status);

  /// The asset whose activation was rejected.
  final AssetId assetId;

  /// The policy status at rejection.
  final ActivationPolicyStatus status;

  @override
  String toString() => status == ActivationPolicyStatus.ready
      ? 'Asset activation is restricted'
      : 'Asset activation is waiting for policy verification';
}

/// The host supplies policy; all SDK activation entry points enforce it.
///
/// Standalone SDK clients are unrestricted by default. Hosts requiring a
/// remote policy must install a loading snapshot before starting wallet work.
class ActivationPolicy {
  /// Starts with [initial], or an unrestricted policy for standalone clients.
  ActivationPolicy({ActivationPolicySnapshot? initial})
    : _current =
          initial ??
          ActivationPolicySnapshot(status: ActivationPolicyStatus.ready);

  ActivationPolicySnapshot _current;
  final _changes = StreamController<ActivationPolicySnapshot>.broadcast(
    sync: true,
  );

  /// The latest policy, including retained restrictions while unavailable.
  ActivationPolicySnapshot get current => _current;

  /// Synchronous updates so activation observes restrictions immediately.
  Stream<ActivationPolicySnapshot> get changes => _changes.stream;

  /// Publishes the host's latest policy answer.
  void update(ActivationPolicySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  /// Throws [ActivationPolicyException] when new activation is disallowed.
  void ensureAllowed(AssetId asset) {
    if (!_current.canActivate(asset)) {
      throw ActivationPolicyException(asset, _current.status);
    }
  }

  /// Throws [ActivationPolicyException] when an active asset is restricted.
  /// Unlike [ensureAllowed], ignores status, so cached activation survives a
  /// loading or unavailable policy.
  void ensureNotBlocked(AssetId asset) {
    if (_current.isBlocked(asset)) {
      throw ActivationPolicyException(asset, _current.status);
    }
  }

  /// Releases the policy stream after its consumers have stopped.
  Future<void> dispose() => _changes.close();
}
