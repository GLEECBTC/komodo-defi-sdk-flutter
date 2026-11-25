// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coingecko_api_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
CoingeckoApiPlan _$CoingeckoApiPlanFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'demo':
      return _DemoPlan.fromJson(json);
    case 'analyst':
      return _AnalystPlan.fromJson(json);
    case 'lite':
      return _LitePlan.fromJson(json);
    case 'pro':
      return _ProPlan.fromJson(json);
    case 'enterprise':
      return _EnterprisePlan.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'runtimeType',
        'CoingeckoApiPlan',
        'Invalid union type "${json['runtimeType']}"!',
      );
  }
}

/// @nodoc
mixin _$CoingeckoApiPlan {
  int? get monthlyCallLimit;
  int? get rateLimitPerMinute;
  bool get attributionRequired;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CoingeckoApiPlanCopyWith<CoingeckoApiPlan> get copyWith =>
      _$CoingeckoApiPlanCopyWithImpl<CoingeckoApiPlan>(
        this as CoingeckoApiPlan,
        _$identity,
      );

  /// Serializes this CoingeckoApiPlan to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as CoingeckoApiPlan;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CoingeckoApiPlan &&
            (identical(other.monthlyCallLimit, _this.monthlyCallLimit) ||
                other.monthlyCallLimit == _this.monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, _this.rateLimitPerMinute) ||
                other.rateLimitPerMinute == _this.rateLimitPerMinute) &&
            (identical(other.attributionRequired, _this.attributionRequired) ||
                other.attributionRequired == _this.attributionRequired));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as CoingeckoApiPlan;
    return Object.hash(
      runtimeType,
      _this.monthlyCallLimit,
      _this.rateLimitPerMinute,
      _this.attributionRequired,
    );
  }

  @override
  String toString() {
    final _this = this as CoingeckoApiPlan;
    return 'CoingeckoApiPlan(monthlyCallLimit: ${_this.monthlyCallLimit}, rateLimitPerMinute: ${_this.rateLimitPerMinute}, attributionRequired: ${_this.attributionRequired})';
  }
}

/// @nodoc
abstract mixin class $CoingeckoApiPlanCopyWith<$Res> {
  factory $CoingeckoApiPlanCopyWith(
    CoingeckoApiPlan value,
    $Res Function(CoingeckoApiPlan) _then,
  ) = _$CoingeckoApiPlanCopyWithImpl;
  @useResult
  $Res call({
    int monthlyCallLimit,
    int rateLimitPerMinute,
    bool attributionRequired,
  });
}

/// @nodoc
class _$CoingeckoApiPlanCopyWithImpl<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  _$CoingeckoApiPlanCopyWithImpl(this._self, this._then);

  final CoingeckoApiPlan _self;
  final $Res Function(CoingeckoApiPlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? monthlyCallLimit = null,
    Object? rateLimitPerMinute = null,
    Object? attributionRequired = null,
  }) {
    return _then(
      _self.copyWith(
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit!
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
        rateLimitPerMinute: null == rateLimitPerMinute
            ? _self.rateLimitPerMinute!
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [CoingeckoApiPlan].
extension CoingeckoApiPlanPatterns on CoingeckoApiPlan {
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
    TResult Function(_DemoPlan value)? demo,
    TResult Function(_AnalystPlan value)? analyst,
    TResult Function(_LitePlan value)? lite,
    TResult Function(_ProPlan value)? pro,
    TResult Function(_EnterprisePlan value)? enterprise,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan() when demo != null:
        return demo(_that);
      case _AnalystPlan() when analyst != null:
        return analyst(_that);
      case _LitePlan() when lite != null:
        return lite(_that);
      case _ProPlan() when pro != null:
        return pro(_that);
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
    required TResult Function(_DemoPlan value) demo,
    required TResult Function(_AnalystPlan value) analyst,
    required TResult Function(_LitePlan value) lite,
    required TResult Function(_ProPlan value) pro,
    required TResult Function(_EnterprisePlan value) enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan():
        return demo(_that);
      case _AnalystPlan():
        return analyst(_that);
      case _LitePlan():
        return lite(_that);
      case _ProPlan():
        return pro(_that);
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
    TResult? Function(_DemoPlan value)? demo,
    TResult? Function(_AnalystPlan value)? analyst,
    TResult? Function(_LitePlan value)? lite,
    TResult? Function(_ProPlan value)? pro,
    TResult? Function(_EnterprisePlan value)? enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan() when demo != null:
        return demo(_that);
      case _AnalystPlan() when analyst != null:
        return analyst(_that);
      case _LitePlan() when lite != null:
        return lite(_that);
      case _ProPlan() when pro != null:
        return pro(_that);
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
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    demo,
    TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    analyst,
    TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    lite,
    TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    pro,
    TResult Function(
      int? monthlyCallLimit,
      int? rateLimitPerMinute,
      bool attributionRequired,
      bool hasSla,
    )?
    enterprise,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan() when demo != null:
        return demo(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _AnalystPlan() when analyst != null:
        return analyst(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _LitePlan() when lite != null:
        return lite(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _ProPlan() when pro != null:
        return pro(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _EnterprisePlan() when enterprise != null:
        return enterprise(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
          _that.hasSla,
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
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )
    demo,
    required TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )
    analyst,
    required TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )
    lite,
    required TResult Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )
    pro,
    required TResult Function(
      int? monthlyCallLimit,
      int? rateLimitPerMinute,
      bool attributionRequired,
      bool hasSla,
    )
    enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan():
        return demo(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _AnalystPlan():
        return analyst(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _LitePlan():
        return lite(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _ProPlan():
        return pro(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _EnterprisePlan():
        return enterprise(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
          _that.hasSla,
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
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    demo,
    TResult? Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    analyst,
    TResult? Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    lite,
    TResult? Function(
      int monthlyCallLimit,
      int rateLimitPerMinute,
      bool attributionRequired,
    )?
    pro,
    TResult? Function(
      int? monthlyCallLimit,
      int? rateLimitPerMinute,
      bool attributionRequired,
      bool hasSla,
    )?
    enterprise,
  }) {
    final _that = this;
    switch (_that) {
      case _DemoPlan() when demo != null:
        return demo(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _AnalystPlan() when analyst != null:
        return analyst(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _LitePlan() when lite != null:
        return lite(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _ProPlan() when pro != null:
        return pro(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
        );
      case _EnterprisePlan() when enterprise != null:
        return enterprise(
          _that.monthlyCallLimit,
          _that.rateLimitPerMinute,
          _that.attributionRequired,
          _that.hasSla,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DemoPlan extends CoingeckoApiPlan {
  const _DemoPlan({
    this.monthlyCallLimit = 10000,
    this.rateLimitPerMinute = 30,
    this.attributionRequired = true,
    String? $type,
  }) : $type = $type ?? 'demo',
       super._();
  factory _DemoPlan.fromJson(Map<String, dynamic> json) =>
      _$DemoPlanFromJson(json);

  @override
  @JsonKey()
  final int monthlyCallLimit;
  @override
  @JsonKey()
  final int rateLimitPerMinute;
  @override
  @JsonKey()
  final bool attributionRequired;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DemoPlanCopyWith<_DemoPlan> get copyWith =>
      __$DemoPlanCopyWithImpl<_DemoPlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DemoPlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DemoPlan &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, rateLimitPerMinute) ||
                other.rateLimitPerMinute == rateLimitPerMinute) &&
            (identical(other.attributionRequired, attributionRequired) ||
                other.attributionRequired == attributionRequired));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      monthlyCallLimit,
      rateLimitPerMinute,
      attributionRequired,
    );
  }

  @override
  String toString() {
    return 'CoingeckoApiPlan.demo(monthlyCallLimit: $monthlyCallLimit, rateLimitPerMinute: $rateLimitPerMinute, attributionRequired: $attributionRequired)';
  }
}

/// @nodoc
abstract mixin class _$DemoPlanCopyWith<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  factory _$DemoPlanCopyWith(_DemoPlan value, $Res Function(_DemoPlan) _then) =
      __$DemoPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    int monthlyCallLimit,
    int rateLimitPerMinute,
    bool attributionRequired,
  });
}

/// @nodoc
class __$DemoPlanCopyWithImpl<$Res> implements _$DemoPlanCopyWith<$Res> {
  __$DemoPlanCopyWithImpl(this._self, this._then);

  final _DemoPlan _self;
  final $Res Function(_DemoPlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? monthlyCallLimit = null,
    Object? rateLimitPerMinute = null,
    Object? attributionRequired = null,
  }) {
    return _then(
      _DemoPlan(
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
        rateLimitPerMinute: null == rateLimitPerMinute
            ? _self.rateLimitPerMinute
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _AnalystPlan extends CoingeckoApiPlan {
  const _AnalystPlan({
    this.monthlyCallLimit = 500000,
    this.rateLimitPerMinute = 500,
    this.attributionRequired = false,
    String? $type,
  }) : $type = $type ?? 'analyst',
       super._();
  factory _AnalystPlan.fromJson(Map<String, dynamic> json) =>
      _$AnalystPlanFromJson(json);

  @override
  @JsonKey()
  final int monthlyCallLimit;
  @override
  @JsonKey()
  final int rateLimitPerMinute;
  @override
  @JsonKey()
  final bool attributionRequired;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnalystPlanCopyWith<_AnalystPlan> get copyWith =>
      __$AnalystPlanCopyWithImpl<_AnalystPlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AnalystPlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnalystPlan &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, rateLimitPerMinute) ||
                other.rateLimitPerMinute == rateLimitPerMinute) &&
            (identical(other.attributionRequired, attributionRequired) ||
                other.attributionRequired == attributionRequired));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      monthlyCallLimit,
      rateLimitPerMinute,
      attributionRequired,
    );
  }

  @override
  String toString() {
    return 'CoingeckoApiPlan.analyst(monthlyCallLimit: $monthlyCallLimit, rateLimitPerMinute: $rateLimitPerMinute, attributionRequired: $attributionRequired)';
  }
}

/// @nodoc
abstract mixin class _$AnalystPlanCopyWith<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  factory _$AnalystPlanCopyWith(
    _AnalystPlan value,
    $Res Function(_AnalystPlan) _then,
  ) = __$AnalystPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    int monthlyCallLimit,
    int rateLimitPerMinute,
    bool attributionRequired,
  });
}

/// @nodoc
class __$AnalystPlanCopyWithImpl<$Res> implements _$AnalystPlanCopyWith<$Res> {
  __$AnalystPlanCopyWithImpl(this._self, this._then);

  final _AnalystPlan _self;
  final $Res Function(_AnalystPlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? monthlyCallLimit = null,
    Object? rateLimitPerMinute = null,
    Object? attributionRequired = null,
  }) {
    return _then(
      _AnalystPlan(
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
        rateLimitPerMinute: null == rateLimitPerMinute
            ? _self.rateLimitPerMinute
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _LitePlan extends CoingeckoApiPlan {
  const _LitePlan({
    this.monthlyCallLimit = 2000000,
    this.rateLimitPerMinute = 500,
    this.attributionRequired = false,
    String? $type,
  }) : $type = $type ?? 'lite',
       super._();
  factory _LitePlan.fromJson(Map<String, dynamic> json) =>
      _$LitePlanFromJson(json);

  @override
  @JsonKey()
  final int monthlyCallLimit;
  @override
  @JsonKey()
  final int rateLimitPerMinute;
  @override
  @JsonKey()
  final bool attributionRequired;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$LitePlanCopyWith<_LitePlan> get copyWith =>
      __$LitePlanCopyWithImpl<_LitePlan>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$LitePlanToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _LitePlan &&
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, rateLimitPerMinute) ||
                other.rateLimitPerMinute == rateLimitPerMinute) &&
            (identical(other.attributionRequired, attributionRequired) ||
                other.attributionRequired == attributionRequired));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      monthlyCallLimit,
      rateLimitPerMinute,
      attributionRequired,
    );
  }

  @override
  String toString() {
    return 'CoingeckoApiPlan.lite(monthlyCallLimit: $monthlyCallLimit, rateLimitPerMinute: $rateLimitPerMinute, attributionRequired: $attributionRequired)';
  }
}

/// @nodoc
abstract mixin class _$LitePlanCopyWith<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  factory _$LitePlanCopyWith(_LitePlan value, $Res Function(_LitePlan) _then) =
      __$LitePlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    int monthlyCallLimit,
    int rateLimitPerMinute,
    bool attributionRequired,
  });
}

/// @nodoc
class __$LitePlanCopyWithImpl<$Res> implements _$LitePlanCopyWith<$Res> {
  __$LitePlanCopyWithImpl(this._self, this._then);

  final _LitePlan _self;
  final $Res Function(_LitePlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? monthlyCallLimit = null,
    Object? rateLimitPerMinute = null,
    Object? attributionRequired = null,
  }) {
    return _then(
      _LitePlan(
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
        rateLimitPerMinute: null == rateLimitPerMinute
            ? _self.rateLimitPerMinute
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _ProPlan extends CoingeckoApiPlan {
  const _ProPlan({
    this.monthlyCallLimit = 5000000,
    this.rateLimitPerMinute = 1000,
    this.attributionRequired = false,
    String? $type,
  }) : $type = $type ?? 'pro',
       super._();
  factory _ProPlan.fromJson(Map<String, dynamic> json) =>
      _$ProPlanFromJson(json);

  @override
  @JsonKey()
  final int monthlyCallLimit;
  @override
  @JsonKey()
  final int rateLimitPerMinute;
  @override
  @JsonKey()
  final bool attributionRequired;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoingeckoApiPlan
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
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, rateLimitPerMinute) ||
                other.rateLimitPerMinute == rateLimitPerMinute) &&
            (identical(other.attributionRequired, attributionRequired) ||
                other.attributionRequired == attributionRequired));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      monthlyCallLimit,
      rateLimitPerMinute,
      attributionRequired,
    );
  }

  @override
  String toString() {
    return 'CoingeckoApiPlan.pro(monthlyCallLimit: $monthlyCallLimit, rateLimitPerMinute: $rateLimitPerMinute, attributionRequired: $attributionRequired)';
  }
}

/// @nodoc
abstract mixin class _$ProPlanCopyWith<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  factory _$ProPlanCopyWith(_ProPlan value, $Res Function(_ProPlan) _then) =
      __$ProPlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    int monthlyCallLimit,
    int rateLimitPerMinute,
    bool attributionRequired,
  });
}

/// @nodoc
class __$ProPlanCopyWithImpl<$Res> implements _$ProPlanCopyWith<$Res> {
  __$ProPlanCopyWithImpl(this._self, this._then);

  final _ProPlan _self;
  final $Res Function(_ProPlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? monthlyCallLimit = null,
    Object? rateLimitPerMinute = null,
    Object? attributionRequired = null,
  }) {
    return _then(
      _ProPlan(
        monthlyCallLimit: null == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int,
        rateLimitPerMinute: null == rateLimitPerMinute
            ? _self.rateLimitPerMinute
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _EnterprisePlan extends CoingeckoApiPlan {
  const _EnterprisePlan({
    this.monthlyCallLimit,
    this.rateLimitPerMinute,
    this.attributionRequired = false,
    this.hasSla = true,
    String? $type,
  }) : $type = $type ?? 'enterprise',
       super._();
  factory _EnterprisePlan.fromJson(Map<String, dynamic> json) =>
      _$EnterprisePlanFromJson(json);

  @override
  final int? monthlyCallLimit;
  @override
  final int? rateLimitPerMinute;
  @override
  @JsonKey()
  final bool attributionRequired;
  @JsonKey()
  final bool hasSla;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of CoingeckoApiPlan
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
            (identical(other.monthlyCallLimit, monthlyCallLimit) ||
                other.monthlyCallLimit == monthlyCallLimit) &&
            (identical(other.rateLimitPerMinute, rateLimitPerMinute) ||
                other.rateLimitPerMinute == rateLimitPerMinute) &&
            (identical(other.attributionRequired, attributionRequired) ||
                other.attributionRequired == attributionRequired) &&
            (identical(other.hasSla, hasSla) || other.hasSla == hasSla));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      monthlyCallLimit,
      rateLimitPerMinute,
      attributionRequired,
      hasSla,
    );
  }

  @override
  String toString() {
    return 'CoingeckoApiPlan.enterprise(monthlyCallLimit: $monthlyCallLimit, rateLimitPerMinute: $rateLimitPerMinute, attributionRequired: $attributionRequired, hasSla: $hasSla)';
  }
}

/// @nodoc
abstract mixin class _$EnterprisePlanCopyWith<$Res>
    implements $CoingeckoApiPlanCopyWith<$Res> {
  factory _$EnterprisePlanCopyWith(
    _EnterprisePlan value,
    $Res Function(_EnterprisePlan) _then,
  ) = __$EnterprisePlanCopyWithImpl;
  @override
  @useResult
  $Res call({
    int? monthlyCallLimit,
    int? rateLimitPerMinute,
    bool attributionRequired,
    bool hasSla,
  });
}

/// @nodoc
class __$EnterprisePlanCopyWithImpl<$Res>
    implements _$EnterprisePlanCopyWith<$Res> {
  __$EnterprisePlanCopyWithImpl(this._self, this._then);

  final _EnterprisePlan _self;
  final $Res Function(_EnterprisePlan) _then;

  /// Create a copy of CoingeckoApiPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? monthlyCallLimit = freezed,
    Object? rateLimitPerMinute = freezed,
    Object? attributionRequired = null,
    Object? hasSla = null,
  }) {
    return _then(
      _EnterprisePlan(
        monthlyCallLimit: freezed == monthlyCallLimit
            ? _self.monthlyCallLimit
            : monthlyCallLimit // ignore: cast_nullable_to_non_nullable
                  as int?,
        rateLimitPerMinute: freezed == rateLimitPerMinute
            ? _self.rateLimitPerMinute
            : rateLimitPerMinute // ignore: cast_nullable_to_non_nullable
                  as int?,
        attributionRequired: null == attributionRequired
            ? _self.attributionRequired
            : attributionRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
        hasSla: null == hasSla
            ? _self.hasSla
            : hasSla // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}
