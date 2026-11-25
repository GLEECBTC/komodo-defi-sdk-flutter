// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coinpaprika_api_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
CoinPaprikaApiPlan _$CoinPaprikaApiPlanFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'free':
      return _FreePlan.fromJson(json);
    case 'starter':
      return _StarterPlan.fromJson(json);
    case 'pro':
      return _ProPlan.fromJson(json);
    case 'business':
      return _BusinessPlan.fromJson(json);
    case 'ultimate':
      return _UltimatePlan.fromJson(json);
    case 'enterprise':
      return _EnterprisePlan.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'runtimeType',
        'CoinPaprikaApiPlan',
        'Invalid union type "${json['runtimeType']}"!',
      );
  }
}

/// @nodoc
mixin _$CoinPaprikaApiPlan {
  Duration? get ohlcHistoricalDataLimit;
  List<String> get availableIntervals;
  int? get monthlyCallLimit;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CoinPaprikaApiPlanCopyWith<CoinPaprikaApiPlan> get copyWith =>
      _$CoinPaprikaApiPlanCopyWithImpl<CoinPaprikaApiPlan>(
        this as CoinPaprikaApiPlan,
        _$identity,
      );

  /// Serializes this CoinPaprikaApiPlan to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as CoinPaprikaApiPlan;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CoinPaprikaApiPlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  _this.ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit ==
                    _this.ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _this.availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, _this.monthlyCallLimit) ||
                other.monthlyCallLimit == _this.monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as CoinPaprikaApiPlan;
    return Object.hash(
      runtimeType,
      _this.ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_this.availableIntervals),
      _this.monthlyCallLimit,
    );
  }

  @override
  String toString() {
    final _this = this as CoinPaprikaApiPlan;
    return 'CoinPaprikaApiPlan(ohlcHistoricalDataLimit: ${_this.ohlcHistoricalDataLimit}, availableIntervals: ${_this.availableIntervals}, monthlyCallLimit: ${_this.monthlyCallLimit})';
  }
}

/// @nodoc
abstract mixin class $CoinPaprikaApiPlanCopyWith<$Res> {
  factory $CoinPaprikaApiPlanCopyWith(
    CoinPaprikaApiPlan value,
    $Res Function(CoinPaprikaApiPlan) _then,
  ) = _$CoinPaprikaApiPlanCopyWithImpl;
  @useResult
  $Res call({
    Duration ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class _$CoinPaprikaApiPlanCopyWithImpl<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  _$CoinPaprikaApiPlanCopyWithImpl(this._self, this._then);

  final CoinPaprikaApiPlan _self;
  final $Res Function(CoinPaprikaApiPlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ohlcHistoricalDataLimit = null,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _self.copyWith(
        ohlcHistoricalDataLimit: null == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit!
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration,
        availableIntervals: null == availableIntervals
            ? _self.availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit!
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [CoinPaprikaApiPlan].
extension CoinPaprikaApiPlanPatterns on CoinPaprikaApiPlan {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_FreePlan value)? free,
    TResult Function(_StarterPlan value)? starter,
    TResult Function(_ProPlan value)? pro,
    TResult Function(_BusinessPlan value)? business,
    TResult Function(_UltimatePlan value)? ultimate,
    TResult Function(_EnterprisePlan value)? enterprise,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan() when free != null:
        return free(_that);
      case _StarterPlan() when starter != null:
        return starter(_that);
      case _ProPlan() when pro != null:
        return pro(_that);
      case _BusinessPlan() when business != null:
        return business(_that);
      case _UltimatePlan() when ultimate != null:
        return ultimate(_that);
      case _EnterprisePlan() when enterprise != null:
        return enterprise(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_FreePlan value) free,
    required TResult Function(_StarterPlan value) starter,
    required TResult Function(_ProPlan value) pro,
    required TResult Function(_BusinessPlan value) business,
    required TResult Function(_UltimatePlan value) ultimate,
    required TResult Function(_EnterprisePlan value) enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan():
        return free(_that);
      case _StarterPlan():
        return starter(_that);
      case _ProPlan():
        return pro(_that);
      case _BusinessPlan():
        return business(_that);
      case _UltimatePlan():
        return ultimate(_that);
      case _EnterprisePlan():
        return enterprise(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_FreePlan value)? free,
    TResult? Function(_StarterPlan value)? starter,
    TResult? Function(_ProPlan value)? pro,
    TResult? Function(_BusinessPlan value)? business,
    TResult? Function(_UltimatePlan value)? ultimate,
    TResult? Function(_EnterprisePlan value)? enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan() when free != null:
        return free(_that);
      case _StarterPlan() when starter != null:
        return starter(_that);
      case _ProPlan() when pro != null:
        return pro(_that);
      case _BusinessPlan() when business != null:
        return business(_that);
      case _UltimatePlan() when ultimate != null:
        return ultimate(_that);
      case _EnterprisePlan() when enterprise != null:
        return enterprise(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    free,
    TResult Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    starter,
    TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    pro,
    TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    business,
    TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    ultimate,
    TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int? monthlyCallLimit,
    )?
    enterprise,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan() when free != null:
        return free(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _StarterPlan() when starter != null:
        return starter(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _ProPlan() when pro != null:
        return pro(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _BusinessPlan() when business != null:
        return business(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _UltimatePlan() when ultimate != null:
        return ultimate(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _EnterprisePlan() when enterprise != null:
        return enterprise(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )
    free,
    required TResult Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )
    starter,
    required TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )
    pro,
    required TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )
    business,
    required TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )
    ultimate,
    required TResult Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int? monthlyCallLimit,
    )
    enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan():
        return free(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _StarterPlan():
        return starter(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _ProPlan():
        return pro(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _BusinessPlan():
        return business(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _UltimatePlan():
        return ultimate(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _EnterprisePlan():
        return enterprise(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    free,
    TResult? Function(
      Duration ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    starter,
    TResult? Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    pro,
    TResult? Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    business,
    TResult? Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int monthlyCallLimit,
    )?
    ultimate,
    TResult? Function(
      Duration? ohlcHistoricalDataLimit,
      List<String> availableIntervals,
      int? monthlyCallLimit,
    )?
    enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _FreePlan() when free != null:
        return free(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _StarterPlan() when starter != null:
        return starter(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _ProPlan() when pro != null:
        return pro(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _BusinessPlan() when business != null:
        return business(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _UltimatePlan() when ultimate != null:
        return ultimate(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _EnterprisePlan() when enterprise != null:
        return enterprise(
          _that.ohlcHistoricalDataLimit,
          _that.availableIntervals,
          _that.monthlyCallLimit,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _FreePlan extends CoinPaprikaApiPlan {
  const _FreePlan({
    this.ohlcHistoricalDataLimit = const Duration(days: 365),
    List<String> availableIntervals = CoinPaprikaIntervals.freeDefaults,
    this.monthlyCallLimit = 20000,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'free',
       super._();
  factory _FreePlan.fromJson(Map<String, dynamic> json) =>
      _$FreePlanFromJson(json);

  @override
  @JsonKey()
  final Duration ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  @JsonKey()
  final int monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$FreePlanCopyWith<_FreePlan> get copyWith =>
      __$FreePlanCopyWithImpl<_FreePlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$FreePlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _FreePlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.free(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$FreePlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$FreePlanCopyWith(_FreePlan value, $Res Function(_FreePlan) _then) =
      __$FreePlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class __$FreePlanCopyWithImpl<$Res> implements _$FreePlanCopyWith<$Res> {
  __$FreePlanCopyWithImpl(this._self, this._then);

  final _FreePlan _self;
  final $Res Function(_FreePlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = null,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _FreePlan(
        ohlcHistoricalDataLimit: null == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _StarterPlan extends CoinPaprikaApiPlan {
  const _StarterPlan({
    this.ohlcHistoricalDataLimit = const Duration(days: 1825),
    List<String> availableIntervals = CoinPaprikaIntervals.premiumDefaults,
    this.monthlyCallLimit = 400000,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'starter',
       super._();
  factory _StarterPlan.fromJson(Map<String, dynamic> json) =>
      _$StarterPlanFromJson(json);

  @override
  @JsonKey()
  final Duration ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  @JsonKey()
  final int monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$StarterPlanCopyWith<_StarterPlan> get copyWith =>
      __$StarterPlanCopyWithImpl<_StarterPlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$StarterPlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _StarterPlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.starter(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$StarterPlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$StarterPlanCopyWith(
    _StarterPlan value,
    $Res Function(_StarterPlan) _then,
  ) = __$StarterPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class __$StarterPlanCopyWithImpl<$Res> implements _$StarterPlanCopyWith<$Res> {
  __$StarterPlanCopyWithImpl(this._self, this._then);

  final _StarterPlan _self;
  final $Res Function(_StarterPlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = null,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _StarterPlan(
        ohlcHistoricalDataLimit: null == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _ProPlan extends CoinPaprikaApiPlan {
  const _ProPlan({
    this.ohlcHistoricalDataLimit,
    List<String> availableIntervals = CoinPaprikaIntervals.premiumDefaults,
    this.monthlyCallLimit = 1000000,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'pro',
       super._();
  factory _ProPlan.fromJson(Map<String, dynamic> json) =>
      _$ProPlanFromJson(json);

  @override
  final Duration? ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  @JsonKey()
  final int monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ProPlanCopyWith<_ProPlan> get copyWith =>
      __$ProPlanCopyWithImpl<_ProPlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ProPlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ProPlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.pro(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$ProPlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$ProPlanCopyWith(_ProPlan value, $Res Function(_ProPlan) _then) =
      __$ProPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration? ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class __$ProPlanCopyWithImpl<$Res> implements _$ProPlanCopyWith<$Res> {
  __$ProPlanCopyWithImpl(this._self, this._then);

  final _ProPlan _self;
  final $Res Function(_ProPlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = freezed,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _ProPlan(
        ohlcHistoricalDataLimit: freezed == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration?,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _BusinessPlan extends CoinPaprikaApiPlan {
  const _BusinessPlan({
    this.ohlcHistoricalDataLimit,
    List<String> availableIntervals = CoinPaprikaIntervals.premiumDefaults,
    this.monthlyCallLimit = 5000000,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'business',
       super._();
  factory _BusinessPlan.fromJson(Map<String, dynamic> json) =>
      _$BusinessPlanFromJson(json);

  @override
  final Duration? ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  @JsonKey()
  final int monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$BusinessPlanCopyWith<_BusinessPlan> get copyWith =>
      __$BusinessPlanCopyWithImpl<_BusinessPlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$BusinessPlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _BusinessPlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.business(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$BusinessPlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$BusinessPlanCopyWith(
    _BusinessPlan value,
    $Res Function(_BusinessPlan) _then,
  ) = __$BusinessPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration? ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class __$BusinessPlanCopyWithImpl<$Res>
    implements _$BusinessPlanCopyWith<$Res> {
  __$BusinessPlanCopyWithImpl(this._self, this._then);

  final _BusinessPlan _self;
  final $Res Function(_BusinessPlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = freezed,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _BusinessPlan(
        ohlcHistoricalDataLimit: freezed == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration?,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _UltimatePlan extends CoinPaprikaApiPlan {
  const _UltimatePlan({
    this.ohlcHistoricalDataLimit,
    List<String> availableIntervals = CoinPaprikaIntervals.premiumDefaults,
    this.monthlyCallLimit = 10000000,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'ultimate',
       super._();
  factory _UltimatePlan.fromJson(Map<String, dynamic> json) =>
      _$UltimatePlanFromJson(json);

  @override
  final Duration? ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  @JsonKey()
  final int monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$UltimatePlanCopyWith<_UltimatePlan> get copyWith =>
      __$UltimatePlanCopyWithImpl<_UltimatePlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$UltimatePlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _UltimatePlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.ultimate(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$UltimatePlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$UltimatePlanCopyWith(
    _UltimatePlan value,
    $Res Function(_UltimatePlan) _then,
  ) = __$UltimatePlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration? ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int monthlyCallLimit,
  });
}

/// @nodoc
class __$UltimatePlanCopyWithImpl<$Res>
    implements _$UltimatePlanCopyWith<$Res> {
  __$UltimatePlanCopyWithImpl(this._self, this._then);

  final _UltimatePlan _self;
  final $Res Function(_UltimatePlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = freezed,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = null,
  }) {
    return _then(
      _UltimatePlan(
        ohlcHistoricalDataLimit: freezed == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration?,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _EnterprisePlan extends CoinPaprikaApiPlan {
  const _EnterprisePlan({
    this.ohlcHistoricalDataLimit,
    List<String> availableIntervals = CoinPaprikaIntervals.premiumDefaults,
    this.monthlyCallLimit,
    String? $type,
  }) : _availableIntervals = availableIntervals,
       $type = $type ?? 'enterprise',
       super._();
  factory _EnterprisePlan.fromJson(Map<String, dynamic> json) =>
      _$EnterprisePlanFromJson(json);

  @override
  final Duration? ohlcHistoricalDataLimit;
  final List<String> _availableIntervals;
  @override
  @JsonKey()
  List<String> get availableIntervals {
    if (_availableIntervals is EqualUnmodifiableListView)
      return _availableIntervals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableIntervals);
  }

  @override
  final int? monthlyCallLimit;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$EnterprisePlanCopyWith<_EnterprisePlan> get copyWith =>
      __$EnterprisePlanCopyWithImpl<_EnterprisePlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$EnterprisePlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _EnterprisePlan &&
            (identical(
                  other.ohlcHistoricalDataLimit,
                  ohlcHistoricalDataLimit,
                ) ||
                other.ohlcHistoricalDataLimit == ohlcHistoricalDataLimit) &&
            const DeepCollectionEquality().equals(
              other.availableIntervals,
              _availableIntervals,
            ) &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ohlcHistoricalDataLimit,
      const DeepCollectionEquality().hash(_availableIntervals),
      monthlyCallLimit,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaApiPlan.enterprise(ohlcHistoricalDataLimit: $ohlcHistoricalDataLimit, availableIntervals: $availableIntervals, monthlyCallLimit: $monthlyCallLimit)';
  }
}

/// @nodoc
abstract mixin class _$EnterprisePlanCopyWith<$Res>
    implements $CoinPaprikaApiPlanCopyWith<$Res> {
  factory _$EnterprisePlanCopyWith(
    _EnterprisePlan value,
    $Res Function(_EnterprisePlan) _then,
  ) = __$EnterprisePlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    Duration? ohlcHistoricalDataLimit,
    List<String> availableIntervals,
    int? monthlyCallLimit,
  });
}

/// @nodoc
class __$EnterprisePlanCopyWithImpl<$Res>
    implements _$EnterprisePlanCopyWith<$Res> {
  __$EnterprisePlanCopyWithImpl(this._self, this._then);

  final _EnterprisePlan _self;
  final $Res Function(_EnterprisePlan) _then;

  /// Create a copy of CoinPaprikaApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ohlcHistoricalDataLimit = freezed,
    Object? availableIntervals = null,
    Object? monthlyCallLimit = freezed,
  }) {
    return _then(
      _EnterprisePlan(
        ohlcHistoricalDataLimit: freezed == ohlcHistoricalDataLimit
            ? _self.ohlcHistoricalDataLimit
            : ohlcHistoricalDataLimit // ignore: cast_nullable_to_non_nullable
                  as Duration?,
        availableIntervals: null == availableIntervals
            ? _self._availableIntervals
            : availableIntervals // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        monthlyCallLimit: freezed == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}
