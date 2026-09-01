import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:meta/meta.dart';

/// Where an asset sits in the activation lifecycle.
///
/// Distinct from [ActivationProgress], which describes the phases *within* one
/// activation attempt and is not asset-scoped. This is the durable, per-asset
/// answer to "is this asset usable yet".
///
/// There is deliberately no `inactive` member. Activation state is published as
/// a whole-map snapshot, so "not activated" is expressed by the asset being
/// **absent** from the map, and deactivation by its removal. Materialising an
/// `inactive` entry per catalogue asset would make every snapshot enormous for
/// no gain.
enum AssetActivationStatus {
  /// Activation has been requested and is in flight.
  activating,

  /// The asset is enabled in KDF.
  active,

  /// Activation was attempted and did not succeed.
  ///
  /// Carries an actionable [AssetActivationState.errorMessage]. Distinct from
  /// absence, which only means "not activated".
  failed,
}

/// The activation state of a single asset at a point in time.
///
/// Consumers should observe the SDK's activation-state stream rather than
/// polling the activated-assets set.
@immutable
class AssetActivationState extends Equatable {
  /// Creates a state record for [assetId].
  const AssetActivationState({
    required this.assetId,
    required this.status,
    this.errorMessage,
    this.sdkError,
  });

  /// Activation for [assetId] is in flight.
  const AssetActivationState.activating(this.assetId)
    : status = AssetActivationStatus.activating,
      errorMessage = null,
      sdkError = null;

  /// [assetId] is enabled in KDF.
  const AssetActivationState.active(this.assetId)
    : status = AssetActivationStatus.active,
      errorMessage = null,
      sdkError = null;

  /// Activation for [assetId] was attempted and did not succeed.
  const AssetActivationState.failed(
    this.assetId, {
    this.errorMessage,
    this.sdkError,
  }) : status = AssetActivationStatus.failed;

  /// The asset this record describes.
  final AssetId assetId;

  /// Where [assetId] sits in the activation lifecycle.
  final AssetActivationStatus status;

  /// Why activation failed. Null unless [status] is
  /// [AssetActivationStatus.failed].
  final String? errorMessage;

  /// Structured failure detail, when the activation reported one.
  final SdkError? sdkError;

  /// Whether activation is in flight.
  bool get isActivating => status == AssetActivationStatus.activating;

  /// Whether the asset is enabled and usable.
  bool get isActive => status == AssetActivationStatus.active;

  /// Whether activation was attempted and did not succeed.
  bool get isFailed => status == AssetActivationStatus.failed;

  @override
  List<Object?> get props => [assetId, status, errorMessage, sdkError];

  @override
  String toString() =>
      'AssetActivationState(${assetId.id}, ${status.name}'
      '${errorMessage == null ? '' : ', $errorMessage'})';
}
