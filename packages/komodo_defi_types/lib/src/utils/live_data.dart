import 'dart:async';
import 'package:flutter/foundation.dart';

/// A reactive data holder that provides synchronous access to a value while
/// allowing asynchronous refreshing and observing changes.
///
/// Extends [ChangeNotifier] to integrate with Flutter's state management ecosystem
/// and implements [ValueListenable] for compatibility with Flutter's APIs.
class LiveData<T> extends ChangeNotifier implements ValueListenable<T> {
  /// Creates a new [LiveData] with the given initial [value].
  ///
  /// [refreshFunction] is an optional function that returns a [Future] with the refreshed value.
  /// [equalityComparer] is an optional function to compare values for equality.
  LiveData(
    this._value, {
    Future<T> Function()? refreshFunction,
    bool Function(T a, T b)? equalityComparer,
  })  : _refreshFunction = refreshFunction,
        _equalityComparer = equalityComparer,
        _lastRefreshed = DateTime.now();

  /// Creates a [LiveData] instance that's connected to an existing [Stream].
  ///
  /// The [initialValue] is used until the stream emits its first value.
  /// [sourceStream] is the stream to listen to for new values.
  /// [equalityComparer] is an optional function to compare values for equality.
  factory LiveData.fromStream(
    T initialValue,
    Stream<T> sourceStream, {
    bool Function(T a, T b)? equalityComparer,
  }) {
    final liveData = LiveData(
      initialValue,
      equalityComparer: equalityComparer,
    );

    // Subscribe to the source stream and update the value when new items arrive
    liveData._sourceStreamSubscription = sourceStream.listen(
      (newValue) {
        liveData.value = newValue;
      },
      onError: (Object error) {
        liveData._setError(error);
      },
    );

    return liveData;
  }

  /// Creates a [LiveData] instance that periodically refreshes its value.
  ///
  /// [initialValue] is the starting value.
  /// [refreshFunction] provides new values.
  /// [interval] defines how often to refresh the value.
  /// [equalityComparer] is an optional function to compare values for equality.
  factory LiveData.periodic(
    T initialValue,
    Future<T> Function() refreshFunction,
    Duration interval, {
    bool Function(T a, T b)? equalityComparer,
    bool refreshImmediately = true,
  }) {
    final liveData = LiveData(
      initialValue,
      refreshFunction: refreshFunction,
      equalityComparer: equalityComparer,
    );

    if (refreshImmediately) {
      liveData.refresh();
    }

    // Set up periodic refresh
    liveData._periodicTimer = Timer.periodic(interval, (_) {
      liveData.refresh();
    });

    return liveData;
  }
  T _value;
  bool _isLoading = false;
  Object? _error;
  DateTime? _lastRefreshed;
  final Future<T> Function()? _refreshFunction;
  final bool Function(T a, T b)? _equalityComparer;
  StreamSubscription<T>? _sourceStreamSubscription;
  Timer? _periodicTimer;

  /// Get the current value synchronously.
  @override
  T get value => _value;

  /// Check if the value is currently being refreshed.
  bool get isLoading => _isLoading;

  /// Get any error that occurred during the last refresh.
  Object? get error => _error;

  /// Get the timestamp of when the value was last refreshed.
  DateTime? get lastRefreshed => _lastRefreshed;

  /// Set a new value directly.
  ///
  /// If the new value is different from the current value (based on the equality comparer),
  /// it will update the value and notify all listeners.
  set value(T newValue) {
    if (!_areEqual(_value, newValue)) {
      _value = newValue;
      _lastRefreshed = DateTime.now();
      _error = null;
      notifyListeners();
    }
  }

  /// Update the value using a transformation function.
  ///
  /// The [updateFn] takes the current value and returns a new value.
  /// If the new value is different from the current value, it will update
  /// and notify all listeners.
  void update(T Function(T currentValue) updateFn) {
    final newValue = updateFn(_value);
    if (!_areEqual(_value, newValue)) {
      _value = newValue;
      _lastRefreshed = DateTime.now();
      _error = null;
      notifyListeners();
    }
  }

  /// Refresh the value asynchronously using the provided refresh function.
  ///
  /// Returns a [Future] that completes with the current value (which may be
  /// updated if the refresh function returns a different value).
  /// If no refresh function was provided, it returns the current value immediately.
  Future<T> refresh() async {
    if (_refreshFunction == null) {
      return _value;
    }

    _setLoading(true);

    try {
      final newValue = await _refreshFunction();
      if (!_areEqual(_value, newValue)) {
        _value = newValue;
        _lastRefreshed = DateTime.now();
        _error = null;
        notifyListeners();
      } else {
        // Even if the value didn't change, we still update the lastRefreshed
        // and notify listeners about loading state change
        _lastRefreshed = DateTime.now();
        _error = null;
        notifyListeners();
      }
      return _value;
    } catch (error) {
      _setError(error);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh the value only if it's older than the specified duration.
  ///
  /// If the value was last refreshed more than [maxAge] ago, it will be refreshed.
  /// Otherwise, it will return the current value immediately.
  Future<T> refreshIfOlderThan(Duration maxAge) async {
    final now = DateTime.now();
    if (_lastRefreshed == null || now.difference(_lastRefreshed!) > maxAge) {
      return refresh();
    }
    return _value;
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(Object error) {
    _error = error;
    notifyListeners();
  }

  bool _areEqual(T a, T b) {
    if (_equalityComparer != null) {
      return _equalityComparer(a, b);
    }
    return a == b;
  }

  /// Provides a stream of values for backward compatibility and
  /// integration with StreamBuilder.
  ///
  /// Note: This creates a new stream each time, so cache the result
  /// if you need to access it multiple times.
  Stream<T> get stream {
    final controller = StreamController<T>.broadcast();

    // Add the current value immediately
    controller.add(_value);

    // Forward future changes to the stream
    void listener() {
      controller.add(_value);
    }

    addListener(listener);

    // Clean up when the stream is done
    controller.onCancel = () {
      removeListener(listener);
      controller.close();
    };

    return controller.stream;
  }

  /// Provides a stream of loading states for backward compatibility and
  /// integration with StreamBuilder.
  Stream<bool> get loadingStream {
    final controller = StreamController<bool>.broadcast();

    // Add the current loading state immediately
    controller.add(_isLoading);

    // Forward future changes to the stream
    void listener() {
      controller.add(_isLoading);
    }

    addListener(listener);

    // Clean up when the stream is done
    controller.onCancel = () {
      removeListener(listener);
      controller.close();
    };

    return controller.stream;
  }

  /// Provides a stream of errors for backward compatibility and
  /// integration with StreamBuilder.
  Stream<Object> get errorStream {
    final controller = StreamController<Object>.broadcast();

    // Forward future errors to the stream
    void listener() {
      if (_error != null) {
        controller.add(_error!);
      }
    }

    addListener(listener);

    // Clean up when the stream is done
    controller.onCancel = () {
      removeListener(listener);
      controller.close();
    };

    return controller.stream;
  }

  /// Adds a specialized listener that receives the current value.
  ///
  /// The [listener] is called immediately with the current value and then
  /// each time the value changes.
  VoidCallback addValueListener(void Function(T value) listener) {
    // Call immediately with current value
    listener(_value);

    // Create a wrapper that extracts the value
    void wrappedListener() {
      listener(_value);
    }

    // Add the wrapped listener
    addListener(wrappedListener);

    // Return a function that removes this specific listener
    return () => removeListener(wrappedListener);
  }

  @override
  void dispose() {
    _sourceStreamSubscription?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }
}
