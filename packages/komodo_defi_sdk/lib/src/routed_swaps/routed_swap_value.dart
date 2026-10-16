import 'package:collection/collection.dart';

/// Value equality over [props], for the routed-swap types.
///
/// Progress snapshots are compared on every poll so an unchanged swap does not
/// re-emit; identity equality would make every poll look like news.
mixin RoutedSwapValue {
  /// The fields that define equality.
  List<Object?> get props;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutedSwapValue &&
          other.runtimeType == runtimeType &&
          _equality.equals(props, other.props));

  @override
  int get hashCode => _equality.hash(props);
}
