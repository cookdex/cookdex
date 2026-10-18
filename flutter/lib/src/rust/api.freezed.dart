// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Amount {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Amount);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Amount()';
}


}

/// @nodoc
class $AmountCopyWith<$Res>  {
$AmountCopyWith(Amount _, $Res Function(Amount) __);
}


/// Adds pattern-matching-related methods to [Amount].
extension AmountPatterns on Amount {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Amount_Rational value)?  rational,TResult Function( Amount_Range value)?  range,TResult Function( Amount_ToTaste value)?  toTaste,TResult Function( Amount_Unspecified value)?  unspecified,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Amount_Rational() when rational != null:
return rational(_that);case Amount_Range() when range != null:
return range(_that);case Amount_ToTaste() when toTaste != null:
return toTaste(_that);case Amount_Unspecified() when unspecified != null:
return unspecified(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Amount_Rational value)  rational,required TResult Function( Amount_Range value)  range,required TResult Function( Amount_ToTaste value)  toTaste,required TResult Function( Amount_Unspecified value)  unspecified,}){
final _that = this;
switch (_that) {
case Amount_Rational():
return rational(_that);case Amount_Range():
return range(_that);case Amount_ToTaste():
return toTaste(_that);case Amount_Unspecified():
return unspecified(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Amount_Rational value)?  rational,TResult? Function( Amount_Range value)?  range,TResult? Function( Amount_ToTaste value)?  toTaste,TResult? Function( Amount_Unspecified value)?  unspecified,}){
final _that = this;
switch (_that) {
case Amount_Rational() when rational != null:
return rational(_that);case Amount_Range() when range != null:
return range(_that);case Amount_ToTaste() when toTaste != null:
return toTaste(_that);case Amount_Unspecified() when unspecified != null:
return unspecified(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int numerator,  int denominator)?  rational,TResult Function( int lowerNumerator,  int lowerDenominator,  int upperNumerator,  int upperDenominator)?  range,TResult Function()?  toTaste,TResult Function()?  unspecified,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Amount_Rational() when rational != null:
return rational(_that.numerator,_that.denominator);case Amount_Range() when range != null:
return range(_that.lowerNumerator,_that.lowerDenominator,_that.upperNumerator,_that.upperDenominator);case Amount_ToTaste() when toTaste != null:
return toTaste();case Amount_Unspecified() when unspecified != null:
return unspecified();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int numerator,  int denominator)  rational,required TResult Function( int lowerNumerator,  int lowerDenominator,  int upperNumerator,  int upperDenominator)  range,required TResult Function()  toTaste,required TResult Function()  unspecified,}) {final _that = this;
switch (_that) {
case Amount_Rational():
return rational(_that.numerator,_that.denominator);case Amount_Range():
return range(_that.lowerNumerator,_that.lowerDenominator,_that.upperNumerator,_that.upperDenominator);case Amount_ToTaste():
return toTaste();case Amount_Unspecified():
return unspecified();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int numerator,  int denominator)?  rational,TResult? Function( int lowerNumerator,  int lowerDenominator,  int upperNumerator,  int upperDenominator)?  range,TResult? Function()?  toTaste,TResult? Function()?  unspecified,}) {final _that = this;
switch (_that) {
case Amount_Rational() when rational != null:
return rational(_that.numerator,_that.denominator);case Amount_Range() when range != null:
return range(_that.lowerNumerator,_that.lowerDenominator,_that.upperNumerator,_that.upperDenominator);case Amount_ToTaste() when toTaste != null:
return toTaste();case Amount_Unspecified() when unspecified != null:
return unspecified();case _:
  return null;

}
}

}

/// @nodoc


class Amount_Rational extends Amount {
  const Amount_Rational({required this.numerator, required this.denominator}): super._();


 final  int numerator;
 final  int denominator;

/// Create a copy of Amount
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Amount_RationalCopyWith<Amount_Rational> get copyWith => _$Amount_RationalCopyWithImpl<Amount_Rational>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Amount_Rational&&(identical(other.numerator, numerator) || other.numerator == numerator)&&(identical(other.denominator, denominator) || other.denominator == denominator));
}


@override
int get hashCode {
    return Object.hash(runtimeType,numerator,denominator);
}

@override
String toString() {
    return 'Amount.rational(numerator: $numerator, denominator: $denominator)';
}


}

/// @nodoc
abstract mixin class $Amount_RationalCopyWith<$Res> implements $AmountCopyWith<$Res> {
  factory $Amount_RationalCopyWith(Amount_Rational value, $Res Function(Amount_Rational) _then) = _$Amount_RationalCopyWithImpl;
@useResult
$Res call({
 int numerator, int denominator
});




}
/// @nodoc
class _$Amount_RationalCopyWithImpl<$Res>
    implements $Amount_RationalCopyWith<$Res> {
  _$Amount_RationalCopyWithImpl(this._self, this._then);

  final Amount_Rational _self;
  final $Res Function(Amount_Rational) _then;

/// Create a copy of Amount
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? numerator = null,Object? denominator = null,}) {
  return _then(Amount_Rational(
numerator: null == numerator ? _self.numerator : numerator // ignore: cast_nullable_to_non_nullable
as int,denominator: null == denominator ? _self.denominator : denominator // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class Amount_Range extends Amount {
  const Amount_Range({required this.lowerNumerator, required this.lowerDenominator, required this.upperNumerator, required this.upperDenominator}): super._();


 final  int lowerNumerator;
 final  int lowerDenominator;
 final  int upperNumerator;
 final  int upperDenominator;

/// Create a copy of Amount
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Amount_RangeCopyWith<Amount_Range> get copyWith => _$Amount_RangeCopyWithImpl<Amount_Range>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Amount_Range&&(identical(other.lowerNumerator, lowerNumerator) || other.lowerNumerator == lowerNumerator)&&(identical(other.lowerDenominator, lowerDenominator) || other.lowerDenominator == lowerDenominator)&&(identical(other.upperNumerator, upperNumerator) || other.upperNumerator == upperNumerator)&&(identical(other.upperDenominator, upperDenominator) || other.upperDenominator == upperDenominator));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lowerNumerator,lowerDenominator,upperNumerator,upperDenominator);
}

@override
String toString() {
    return 'Amount.range(lowerNumerator: $lowerNumerator, lowerDenominator: $lowerDenominator, upperNumerator: $upperNumerator, upperDenominator: $upperDenominator)';
}


}

/// @nodoc
abstract mixin class $Amount_RangeCopyWith<$Res> implements $AmountCopyWith<$Res> {
  factory $Amount_RangeCopyWith(Amount_Range value, $Res Function(Amount_Range) _then) = _$Amount_RangeCopyWithImpl;
@useResult
$Res call({
 int lowerNumerator, int lowerDenominator, int upperNumerator, int upperDenominator
});




}
/// @nodoc
class _$Amount_RangeCopyWithImpl<$Res>
    implements $Amount_RangeCopyWith<$Res> {
  _$Amount_RangeCopyWithImpl(this._self, this._then);

  final Amount_Range _self;
  final $Res Function(Amount_Range) _then;

/// Create a copy of Amount
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lowerNumerator = null,Object? lowerDenominator = null,Object? upperNumerator = null,Object? upperDenominator = null,}) {
  return _then(Amount_Range(
lowerNumerator: null == lowerNumerator ? _self.lowerNumerator : lowerNumerator // ignore: cast_nullable_to_non_nullable
as int,lowerDenominator: null == lowerDenominator ? _self.lowerDenominator : lowerDenominator // ignore: cast_nullable_to_non_nullable
as int,upperNumerator: null == upperNumerator ? _self.upperNumerator : upperNumerator // ignore: cast_nullable_to_non_nullable
as int,upperDenominator: null == upperDenominator ? _self.upperDenominator : upperDenominator // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class Amount_ToTaste extends Amount {
  const Amount_ToTaste(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Amount_ToTaste);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Amount.toTaste()';
}


}




/// @nodoc


class Amount_Unspecified extends Amount {
  const Amount_Unspecified(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Amount_Unspecified);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Amount.unspecified()';
}


}




/// @nodoc
mixin _$CollectionEvent {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as CollectionEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionEvent&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as CollectionEvent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as CollectionEvent;
  return 'CollectionEvent(field0: ${_this.field0})';
}


}

/// @nodoc
class $CollectionEventCopyWith<$Res>  {
$CollectionEventCopyWith(CollectionEvent _, $Res Function(CollectionEvent) __);
}


/// Adds pattern-matching-related methods to [CollectionEvent].
extension CollectionEventPatterns on CollectionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CollectionEvent_Snapshot value)?  snapshot,TResult Function( CollectionEvent_Change value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CollectionEvent_Snapshot() when snapshot != null:
return snapshot(_that);case CollectionEvent_Change() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CollectionEvent_Snapshot value)  snapshot,required TResult Function( CollectionEvent_Change value)  change,}){
final _that = this;
switch (_that) {
case CollectionEvent_Snapshot():
return snapshot(_that);case CollectionEvent_Change():
return change(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CollectionEvent_Snapshot value)?  snapshot,TResult? Function( CollectionEvent_Change value)?  change,}){
final _that = this;
switch (_that) {
case CollectionEvent_Snapshot() when snapshot != null:
return snapshot(_that);case CollectionEvent_Change() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( CollectionSnapshot field0)?  snapshot,TResult Function( ChangeBatch field0)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CollectionEvent_Snapshot() when snapshot != null:
return snapshot(_that.field0);case CollectionEvent_Change() when change != null:
return change(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( CollectionSnapshot field0)  snapshot,required TResult Function( ChangeBatch field0)  change,}) {final _that = this;
switch (_that) {
case CollectionEvent_Snapshot():
return snapshot(_that.field0);case CollectionEvent_Change():
return change(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( CollectionSnapshot field0)?  snapshot,TResult? Function( ChangeBatch field0)?  change,}) {final _that = this;
switch (_that) {
case CollectionEvent_Snapshot() when snapshot != null:
return snapshot(_that.field0);case CollectionEvent_Change() when change != null:
return change(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class CollectionEvent_Snapshot extends CollectionEvent {
  const CollectionEvent_Snapshot(this.field0): super._();


@override final  CollectionSnapshot field0;

/// Create a copy of CollectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CollectionEvent_SnapshotCopyWith<CollectionEvent_Snapshot> get copyWith => _$CollectionEvent_SnapshotCopyWithImpl<CollectionEvent_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionEvent_Snapshot&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'CollectionEvent.snapshot(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CollectionEvent_SnapshotCopyWith<$Res> implements $CollectionEventCopyWith<$Res> {
  factory $CollectionEvent_SnapshotCopyWith(CollectionEvent_Snapshot value, $Res Function(CollectionEvent_Snapshot) _then) = _$CollectionEvent_SnapshotCopyWithImpl;
@useResult
$Res call({
 CollectionSnapshot field0
});




}
/// @nodoc
class _$CollectionEvent_SnapshotCopyWithImpl<$Res>
    implements $CollectionEvent_SnapshotCopyWith<$Res> {
  _$CollectionEvent_SnapshotCopyWithImpl(this._self, this._then);

  final CollectionEvent_Snapshot _self;
  final $Res Function(CollectionEvent_Snapshot) _then;

/// Create a copy of CollectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CollectionEvent_Snapshot(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CollectionSnapshot,
  ));
}


}

/// @nodoc


class CollectionEvent_Change extends CollectionEvent {
  const CollectionEvent_Change(this.field0): super._();


@override final  ChangeBatch field0;

/// Create a copy of CollectionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CollectionEvent_ChangeCopyWith<CollectionEvent_Change> get copyWith => _$CollectionEvent_ChangeCopyWithImpl<CollectionEvent_Change>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionEvent_Change&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'CollectionEvent.change(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CollectionEvent_ChangeCopyWith<$Res> implements $CollectionEventCopyWith<$Res> {
  factory $CollectionEvent_ChangeCopyWith(CollectionEvent_Change value, $Res Function(CollectionEvent_Change) _then) = _$CollectionEvent_ChangeCopyWithImpl;
@useResult
$Res call({
 ChangeBatch field0
});




}
/// @nodoc
class _$CollectionEvent_ChangeCopyWithImpl<$Res>
    implements $CollectionEvent_ChangeCopyWith<$Res> {
  _$CollectionEvent_ChangeCopyWithImpl(this._self, this._then);

  final CollectionEvent_Change _self;
  final $Res Function(CollectionEvent_Change) _then;

/// Create a copy of CollectionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CollectionEvent_Change(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChangeBatch,
  ));
}


}

/// @nodoc
mixin _$ConflictChoice {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConflictChoice);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConflictChoice()';
}


}

/// @nodoc
class $ConflictChoiceCopyWith<$Res>  {
$ConflictChoiceCopyWith(ConflictChoice _, $Res Function(ConflictChoice) __);
}


/// Adds pattern-matching-related methods to [ConflictChoice].
extension ConflictChoicePatterns on ConflictChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConflictChoice_Version value)?  version,TResult Function( ConflictChoice_KeepAll value)?  keepAll,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConflictChoice_Version() when version != null:
return version(_that);case ConflictChoice_KeepAll() when keepAll != null:
return keepAll(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConflictChoice_Version value)  version,required TResult Function( ConflictChoice_KeepAll value)  keepAll,}){
final _that = this;
switch (_that) {
case ConflictChoice_Version():
return version(_that);case ConflictChoice_KeepAll():
return keepAll(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConflictChoice_Version value)?  version,TResult? Function( ConflictChoice_KeepAll value)?  keepAll,}){
final _that = this;
switch (_that) {
case ConflictChoice_Version() when version != null:
return version(_that);case ConflictChoice_KeepAll() when keepAll != null:
return keepAll(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id)?  version,TResult Function()?  keepAll,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConflictChoice_Version() when version != null:
return version(_that.id);case ConflictChoice_KeepAll() when keepAll != null:
return keepAll();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id)  version,required TResult Function()  keepAll,}) {final _that = this;
switch (_that) {
case ConflictChoice_Version():
return version(_that.id);case ConflictChoice_KeepAll():
return keepAll();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id)?  version,TResult? Function()?  keepAll,}) {final _that = this;
switch (_that) {
case ConflictChoice_Version() when version != null:
return version(_that.id);case ConflictChoice_KeepAll() when keepAll != null:
return keepAll();case _:
  return null;

}
}

}

/// @nodoc


class ConflictChoice_Version extends ConflictChoice {
  const ConflictChoice_Version({required this.id}): super._();


 final  String id;

/// Create a copy of ConflictChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConflictChoice_VersionCopyWith<ConflictChoice_Version> get copyWith => _$ConflictChoice_VersionCopyWithImpl<ConflictChoice_Version>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConflictChoice_Version&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'ConflictChoice.version(id: $id)';
}


}

/// @nodoc
abstract mixin class $ConflictChoice_VersionCopyWith<$Res> implements $ConflictChoiceCopyWith<$Res> {
  factory $ConflictChoice_VersionCopyWith(ConflictChoice_Version value, $Res Function(ConflictChoice_Version) _then) = _$ConflictChoice_VersionCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$ConflictChoice_VersionCopyWithImpl<$Res>
    implements $ConflictChoice_VersionCopyWith<$Res> {
  _$ConflictChoice_VersionCopyWithImpl(this._self, this._then);

  final ConflictChoice_Version _self;
  final $Res Function(ConflictChoice_Version) _then;

/// Create a copy of ConflictChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(ConflictChoice_Version(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConflictChoice_KeepAll extends ConflictChoice {
  const ConflictChoice_KeepAll(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConflictChoice_KeepAll);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConflictChoice.keepAll()';
}


}




/// @nodoc
mixin _$DuplicateChoice {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DuplicateChoice);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DuplicateChoice()';
}


}

/// @nodoc
class $DuplicateChoiceCopyWith<$Res>  {
$DuplicateChoiceCopyWith(DuplicateChoice _, $Res Function(DuplicateChoice) __);
}


/// Adds pattern-matching-related methods to [DuplicateChoice].
extension DuplicateChoicePatterns on DuplicateChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DuplicateChoice_KeepBoth value)?  keepBoth,TResult Function( DuplicateChoice_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth() when keepBoth != null:
return keepBoth(_that);case DuplicateChoice_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DuplicateChoice_KeepBoth value)  keepBoth,required TResult Function( DuplicateChoice_Replace value)  replace,}){
final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth():
return keepBoth(_that);case DuplicateChoice_Replace():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DuplicateChoice_KeepBoth value)?  keepBoth,TResult? Function( DuplicateChoice_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth() when keepBoth != null:
return keepBoth(_that);case DuplicateChoice_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keepBoth,TResult Function( String id)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth() when keepBoth != null:
return keepBoth();case DuplicateChoice_Replace() when replace != null:
return replace(_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keepBoth,required TResult Function( String id)  replace,}) {final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth():
return keepBoth();case DuplicateChoice_Replace():
return replace(_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keepBoth,TResult? Function( String id)?  replace,}) {final _that = this;
switch (_that) {
case DuplicateChoice_KeepBoth() when keepBoth != null:
return keepBoth();case DuplicateChoice_Replace() when replace != null:
return replace(_that.id);case _:
  return null;

}
}

}

/// @nodoc


class DuplicateChoice_KeepBoth extends DuplicateChoice {
  const DuplicateChoice_KeepBoth(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DuplicateChoice_KeepBoth);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DuplicateChoice.keepBoth()';
}


}




/// @nodoc


class DuplicateChoice_Replace extends DuplicateChoice {
  const DuplicateChoice_Replace({required this.id}): super._();


 final  String id;

/// Create a copy of DuplicateChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DuplicateChoice_ReplaceCopyWith<DuplicateChoice_Replace> get copyWith => _$DuplicateChoice_ReplaceCopyWithImpl<DuplicateChoice_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DuplicateChoice_Replace&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'DuplicateChoice.replace(id: $id)';
}


}

/// @nodoc
abstract mixin class $DuplicateChoice_ReplaceCopyWith<$Res> implements $DuplicateChoiceCopyWith<$Res> {
  factory $DuplicateChoice_ReplaceCopyWith(DuplicateChoice_Replace value, $Res Function(DuplicateChoice_Replace) _then) = _$DuplicateChoice_ReplaceCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$DuplicateChoice_ReplaceCopyWithImpl<$Res>
    implements $DuplicateChoice_ReplaceCopyWith<$Res> {
  _$DuplicateChoice_ReplaceCopyWithImpl(this._self, this._then);

  final DuplicateChoice_Replace _self;
  final $Res Function(DuplicateChoice_Replace) _then;

/// Create a copy of DuplicateChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(DuplicateChoice_Replace(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ProviderOutput {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProviderOutput);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ProviderOutput()';
}


}

/// @nodoc
class $ProviderOutputCopyWith<$Res>  {
$ProviderOutputCopyWith(ProviderOutput _, $Res Function(ProviderOutput) __);
}


/// Adds pattern-matching-related methods to [ProviderOutput].
extension ProviderOutputPatterns on ProviderOutput {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProviderOutput_Retry value)?  retry,TResult Function( ProviderOutput_Recipe value)?  recipe,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProviderOutput_Retry() when retry != null:
return retry(_that);case ProviderOutput_Recipe() when recipe != null:
return recipe(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProviderOutput_Retry value)  retry,required TResult Function( ProviderOutput_Recipe value)  recipe,}){
final _that = this;
switch (_that) {
case ProviderOutput_Retry():
return retry(_that);case ProviderOutput_Recipe():
return recipe(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProviderOutput_Retry value)?  retry,TResult? Function( ProviderOutput_Recipe value)?  recipe,}){
final _that = this;
switch (_that) {
case ProviderOutput_Retry() when retry != null:
return retry(_that);case ProviderOutput_Recipe() when recipe != null:
return recipe(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  retry,TResult Function( Recipe field0)?  recipe,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ProviderOutput_Retry() when retry != null:
return retry();case ProviderOutput_Recipe() when recipe != null:
return recipe(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  retry,required TResult Function( Recipe field0)  recipe,}) {final _that = this;
switch (_that) {
case ProviderOutput_Retry():
return retry();case ProviderOutput_Recipe():
return recipe(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  retry,TResult? Function( Recipe field0)?  recipe,}) {final _that = this;
switch (_that) {
case ProviderOutput_Retry() when retry != null:
return retry();case ProviderOutput_Recipe() when recipe != null:
return recipe(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ProviderOutput_Retry extends ProviderOutput {
  const ProviderOutput_Retry(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProviderOutput_Retry);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ProviderOutput.retry()';
}


}




/// @nodoc


class ProviderOutput_Recipe extends ProviderOutput {
  const ProviderOutput_Recipe(this.field0): super._();


 final  Recipe field0;

/// Create a copy of ProviderOutput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProviderOutput_RecipeCopyWith<ProviderOutput_Recipe> get copyWith => _$ProviderOutput_RecipeCopyWithImpl<ProviderOutput_Recipe>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProviderOutput_Recipe&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ProviderOutput.recipe(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ProviderOutput_RecipeCopyWith<$Res> implements $ProviderOutputCopyWith<$Res> {
  factory $ProviderOutput_RecipeCopyWith(ProviderOutput_Recipe value, $Res Function(ProviderOutput_Recipe) _then) = _$ProviderOutput_RecipeCopyWithImpl;
@useResult
$Res call({
 Recipe field0
});




}
/// @nodoc
class _$ProviderOutput_RecipeCopyWithImpl<$Res>
    implements $ProviderOutput_RecipeCopyWith<$Res> {
  _$ProviderOutput_RecipeCopyWithImpl(this._self, this._then);

  final ProviderOutput_Recipe _self;
  final $Res Function(ProviderOutput_Recipe) _then;

/// Create a copy of ProviderOutput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ProviderOutput_Recipe(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Recipe,
  ));
}


}

/// @nodoc
mixin _$ShoppingEdit {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShoppingEdit()';
}


}

/// @nodoc
class $ShoppingEditCopyWith<$Res>  {
$ShoppingEditCopyWith(ShoppingEdit _, $Res Function(ShoppingEdit) __);
}


/// Adds pattern-matching-related methods to [ShoppingEdit].
extension ShoppingEditPatterns on ShoppingEdit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ShoppingEdit_AddManual value)?  addManual,TResult Function( ShoppingEdit_Edit value)?  edit,TResult Function( ShoppingEdit_Check value)?  check,TResult Function( ShoppingEdit_Remove value)?  remove,TResult Function( ShoppingEdit_Move value)?  move,TResult Function( ShoppingEdit_ReorderItems value)?  reorderItems,TResult Function( ShoppingEdit_AddCategory value)?  addCategory,TResult Function( ShoppingEdit_RenameCategory value)?  renameCategory,TResult Function( ShoppingEdit_DeleteCategory value)?  deleteCategory,TResult Function( ShoppingEdit_ReorderCategories value)?  reorderCategories,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ShoppingEdit_AddManual() when addManual != null:
return addManual(_that);case ShoppingEdit_Edit() when edit != null:
return edit(_that);case ShoppingEdit_Check() when check != null:
return check(_that);case ShoppingEdit_Remove() when remove != null:
return remove(_that);case ShoppingEdit_Move() when move != null:
return move(_that);case ShoppingEdit_ReorderItems() when reorderItems != null:
return reorderItems(_that);case ShoppingEdit_AddCategory() when addCategory != null:
return addCategory(_that);case ShoppingEdit_RenameCategory() when renameCategory != null:
return renameCategory(_that);case ShoppingEdit_DeleteCategory() when deleteCategory != null:
return deleteCategory(_that);case ShoppingEdit_ReorderCategories() when reorderCategories != null:
return reorderCategories(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ShoppingEdit_AddManual value)  addManual,required TResult Function( ShoppingEdit_Edit value)  edit,required TResult Function( ShoppingEdit_Check value)  check,required TResult Function( ShoppingEdit_Remove value)  remove,required TResult Function( ShoppingEdit_Move value)  move,required TResult Function( ShoppingEdit_ReorderItems value)  reorderItems,required TResult Function( ShoppingEdit_AddCategory value)  addCategory,required TResult Function( ShoppingEdit_RenameCategory value)  renameCategory,required TResult Function( ShoppingEdit_DeleteCategory value)  deleteCategory,required TResult Function( ShoppingEdit_ReorderCategories value)  reorderCategories,}){
final _that = this;
switch (_that) {
case ShoppingEdit_AddManual():
return addManual(_that);case ShoppingEdit_Edit():
return edit(_that);case ShoppingEdit_Check():
return check(_that);case ShoppingEdit_Remove():
return remove(_that);case ShoppingEdit_Move():
return move(_that);case ShoppingEdit_ReorderItems():
return reorderItems(_that);case ShoppingEdit_AddCategory():
return addCategory(_that);case ShoppingEdit_RenameCategory():
return renameCategory(_that);case ShoppingEdit_DeleteCategory():
return deleteCategory(_that);case ShoppingEdit_ReorderCategories():
return reorderCategories(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ShoppingEdit_AddManual value)?  addManual,TResult? Function( ShoppingEdit_Edit value)?  edit,TResult? Function( ShoppingEdit_Check value)?  check,TResult? Function( ShoppingEdit_Remove value)?  remove,TResult? Function( ShoppingEdit_Move value)?  move,TResult? Function( ShoppingEdit_ReorderItems value)?  reorderItems,TResult? Function( ShoppingEdit_AddCategory value)?  addCategory,TResult? Function( ShoppingEdit_RenameCategory value)?  renameCategory,TResult? Function( ShoppingEdit_DeleteCategory value)?  deleteCategory,TResult? Function( ShoppingEdit_ReorderCategories value)?  reorderCategories,}){
final _that = this;
switch (_that) {
case ShoppingEdit_AddManual() when addManual != null:
return addManual(_that);case ShoppingEdit_Edit() when edit != null:
return edit(_that);case ShoppingEdit_Check() when check != null:
return check(_that);case ShoppingEdit_Remove() when remove != null:
return remove(_that);case ShoppingEdit_Move() when move != null:
return move(_that);case ShoppingEdit_ReorderItems() when reorderItems != null:
return reorderItems(_that);case ShoppingEdit_AddCategory() when addCategory != null:
return addCategory(_that);case ShoppingEdit_RenameCategory() when renameCategory != null:
return renameCategory(_that);case ShoppingEdit_DeleteCategory() when deleteCategory != null:
return deleteCategory(_that);case ShoppingEdit_ReorderCategories() when reorderCategories != null:
return reorderCategories(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  addManual,TResult Function( String id,  String text)?  edit,TResult Function( List<String> ids,  bool checked)?  check,TResult Function( List<String> ids)?  remove,TResult Function( String id,  String categoryId,  String? beforeId)?  move,TResult Function( String categoryId,  List<String> ids)?  reorderItems,TResult Function( String name)?  addCategory,TResult Function( String id,  String name)?  renameCategory,TResult Function( String id)?  deleteCategory,TResult Function( List<String> ids)?  reorderCategories,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ShoppingEdit_AddManual() when addManual != null:
return addManual(_that.text);case ShoppingEdit_Edit() when edit != null:
return edit(_that.id,_that.text);case ShoppingEdit_Check() when check != null:
return check(_that.ids,_that.checked);case ShoppingEdit_Remove() when remove != null:
return remove(_that.ids);case ShoppingEdit_Move() when move != null:
return move(_that.id,_that.categoryId,_that.beforeId);case ShoppingEdit_ReorderItems() when reorderItems != null:
return reorderItems(_that.categoryId,_that.ids);case ShoppingEdit_AddCategory() when addCategory != null:
return addCategory(_that.name);case ShoppingEdit_RenameCategory() when renameCategory != null:
return renameCategory(_that.id,_that.name);case ShoppingEdit_DeleteCategory() when deleteCategory != null:
return deleteCategory(_that.id);case ShoppingEdit_ReorderCategories() when reorderCategories != null:
return reorderCategories(_that.ids);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  addManual,required TResult Function( String id,  String text)  edit,required TResult Function( List<String> ids,  bool checked)  check,required TResult Function( List<String> ids)  remove,required TResult Function( String id,  String categoryId,  String? beforeId)  move,required TResult Function( String categoryId,  List<String> ids)  reorderItems,required TResult Function( String name)  addCategory,required TResult Function( String id,  String name)  renameCategory,required TResult Function( String id)  deleteCategory,required TResult Function( List<String> ids)  reorderCategories,}) {final _that = this;
switch (_that) {
case ShoppingEdit_AddManual():
return addManual(_that.text);case ShoppingEdit_Edit():
return edit(_that.id,_that.text);case ShoppingEdit_Check():
return check(_that.ids,_that.checked);case ShoppingEdit_Remove():
return remove(_that.ids);case ShoppingEdit_Move():
return move(_that.id,_that.categoryId,_that.beforeId);case ShoppingEdit_ReorderItems():
return reorderItems(_that.categoryId,_that.ids);case ShoppingEdit_AddCategory():
return addCategory(_that.name);case ShoppingEdit_RenameCategory():
return renameCategory(_that.id,_that.name);case ShoppingEdit_DeleteCategory():
return deleteCategory(_that.id);case ShoppingEdit_ReorderCategories():
return reorderCategories(_that.ids);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  addManual,TResult? Function( String id,  String text)?  edit,TResult? Function( List<String> ids,  bool checked)?  check,TResult? Function( List<String> ids)?  remove,TResult? Function( String id,  String categoryId,  String? beforeId)?  move,TResult? Function( String categoryId,  List<String> ids)?  reorderItems,TResult? Function( String name)?  addCategory,TResult? Function( String id,  String name)?  renameCategory,TResult? Function( String id)?  deleteCategory,TResult? Function( List<String> ids)?  reorderCategories,}) {final _that = this;
switch (_that) {
case ShoppingEdit_AddManual() when addManual != null:
return addManual(_that.text);case ShoppingEdit_Edit() when edit != null:
return edit(_that.id,_that.text);case ShoppingEdit_Check() when check != null:
return check(_that.ids,_that.checked);case ShoppingEdit_Remove() when remove != null:
return remove(_that.ids);case ShoppingEdit_Move() when move != null:
return move(_that.id,_that.categoryId,_that.beforeId);case ShoppingEdit_ReorderItems() when reorderItems != null:
return reorderItems(_that.categoryId,_that.ids);case ShoppingEdit_AddCategory() when addCategory != null:
return addCategory(_that.name);case ShoppingEdit_RenameCategory() when renameCategory != null:
return renameCategory(_that.id,_that.name);case ShoppingEdit_DeleteCategory() when deleteCategory != null:
return deleteCategory(_that.id);case ShoppingEdit_ReorderCategories() when reorderCategories != null:
return reorderCategories(_that.ids);case _:
  return null;

}
}

}

/// @nodoc


class ShoppingEdit_AddManual extends ShoppingEdit {
  const ShoppingEdit_AddManual({required this.text}): super._();


 final  String text;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_AddManualCopyWith<ShoppingEdit_AddManual> get copyWith => _$ShoppingEdit_AddManualCopyWithImpl<ShoppingEdit_AddManual>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_AddManual&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'ShoppingEdit.addManual(text: $text)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_AddManualCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_AddManualCopyWith(ShoppingEdit_AddManual value, $Res Function(ShoppingEdit_AddManual) _then) = _$ShoppingEdit_AddManualCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ShoppingEdit_AddManualCopyWithImpl<$Res>
    implements $ShoppingEdit_AddManualCopyWith<$Res> {
  _$ShoppingEdit_AddManualCopyWithImpl(this._self, this._then);

  final ShoppingEdit_AddManual _self;
  final $Res Function(ShoppingEdit_AddManual) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ShoppingEdit_AddManual(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShoppingEdit_Edit extends ShoppingEdit {
  const ShoppingEdit_Edit({required this.id, required this.text}): super._();


 final  String id;
 final  String text;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_EditCopyWith<ShoppingEdit_Edit> get copyWith => _$ShoppingEdit_EditCopyWithImpl<ShoppingEdit_Edit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_Edit&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,text);
}

@override
String toString() {
    return 'ShoppingEdit.edit(id: $id, text: $text)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_EditCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_EditCopyWith(ShoppingEdit_Edit value, $Res Function(ShoppingEdit_Edit) _then) = _$ShoppingEdit_EditCopyWithImpl;
@useResult
$Res call({
 String id, String text
});




}
/// @nodoc
class _$ShoppingEdit_EditCopyWithImpl<$Res>
    implements $ShoppingEdit_EditCopyWith<$Res> {
  _$ShoppingEdit_EditCopyWithImpl(this._self, this._then);

  final ShoppingEdit_Edit _self;
  final $Res Function(ShoppingEdit_Edit) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,}) {
  return _then(ShoppingEdit_Edit(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShoppingEdit_Check extends ShoppingEdit {
  const ShoppingEdit_Check({required  List<String> ids, required this.checked}): _ids = ids,super._();


 final  List<String> _ids;
 List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}

 final  bool checked;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_CheckCopyWith<ShoppingEdit_Check> get copyWith => _$ShoppingEdit_CheckCopyWithImpl<ShoppingEdit_Check>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_Check&&const DeepCollectionEquality().equals(other.ids, _ids)&&(identical(other.checked, checked) || other.checked == checked));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_ids),checked);
}

@override
String toString() {
    return 'ShoppingEdit.check(ids: $ids, checked: $checked)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_CheckCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_CheckCopyWith(ShoppingEdit_Check value, $Res Function(ShoppingEdit_Check) _then) = _$ShoppingEdit_CheckCopyWithImpl;
@useResult
$Res call({
 List<String> ids, bool checked
});




}
/// @nodoc
class _$ShoppingEdit_CheckCopyWithImpl<$Res>
    implements $ShoppingEdit_CheckCopyWith<$Res> {
  _$ShoppingEdit_CheckCopyWithImpl(this._self, this._then);

  final ShoppingEdit_Check _self;
  final $Res Function(ShoppingEdit_Check) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ids = null,Object? checked = null,}) {
  return _then(ShoppingEdit_Check(
ids: null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,checked: null == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ShoppingEdit_Remove extends ShoppingEdit {
  const ShoppingEdit_Remove({required  List<String> ids}): _ids = ids,super._();


 final  List<String> _ids;
 List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}


/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_RemoveCopyWith<ShoppingEdit_Remove> get copyWith => _$ShoppingEdit_RemoveCopyWithImpl<ShoppingEdit_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_Remove&&const DeepCollectionEquality().equals(other.ids, _ids));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_ids));
}

@override
String toString() {
    return 'ShoppingEdit.remove(ids: $ids)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_RemoveCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_RemoveCopyWith(ShoppingEdit_Remove value, $Res Function(ShoppingEdit_Remove) _then) = _$ShoppingEdit_RemoveCopyWithImpl;
@useResult
$Res call({
 List<String> ids
});




}
/// @nodoc
class _$ShoppingEdit_RemoveCopyWithImpl<$Res>
    implements $ShoppingEdit_RemoveCopyWith<$Res> {
  _$ShoppingEdit_RemoveCopyWithImpl(this._self, this._then);

  final ShoppingEdit_Remove _self;
  final $Res Function(ShoppingEdit_Remove) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ids = null,}) {
  return _then(ShoppingEdit_Remove(
ids: null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class ShoppingEdit_Move extends ShoppingEdit {
  const ShoppingEdit_Move({required this.id, required this.categoryId, this.beforeId}): super._();


 final  String id;
 final  String categoryId;
 final  String? beforeId;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_MoveCopyWith<ShoppingEdit_Move> get copyWith => _$ShoppingEdit_MoveCopyWithImpl<ShoppingEdit_Move>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_Move&&(identical(other.id, id) || other.id == id)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.beforeId, beforeId) || other.beforeId == beforeId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,categoryId,beforeId);
}

@override
String toString() {
    return 'ShoppingEdit.move(id: $id, categoryId: $categoryId, beforeId: $beforeId)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_MoveCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_MoveCopyWith(ShoppingEdit_Move value, $Res Function(ShoppingEdit_Move) _then) = _$ShoppingEdit_MoveCopyWithImpl;
@useResult
$Res call({
 String id, String categoryId, String? beforeId
});




}
/// @nodoc
class _$ShoppingEdit_MoveCopyWithImpl<$Res>
    implements $ShoppingEdit_MoveCopyWith<$Res> {
  _$ShoppingEdit_MoveCopyWithImpl(this._self, this._then);

  final ShoppingEdit_Move _self;
  final $Res Function(ShoppingEdit_Move) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? categoryId = null,Object? beforeId = freezed,}) {
  return _then(ShoppingEdit_Move(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,beforeId: freezed == beforeId ? _self.beforeId : beforeId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ShoppingEdit_ReorderItems extends ShoppingEdit {
  const ShoppingEdit_ReorderItems({required this.categoryId, required  List<String> ids}): _ids = ids,super._();


 final  String categoryId;
 final  List<String> _ids;
 List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}


/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_ReorderItemsCopyWith<ShoppingEdit_ReorderItems> get copyWith => _$ShoppingEdit_ReorderItemsCopyWithImpl<ShoppingEdit_ReorderItems>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_ReorderItems&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&const DeepCollectionEquality().equals(other.ids, _ids));
}


@override
int get hashCode {
    return Object.hash(runtimeType,categoryId,const DeepCollectionEquality().hash(_ids));
}

@override
String toString() {
    return 'ShoppingEdit.reorderItems(categoryId: $categoryId, ids: $ids)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_ReorderItemsCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_ReorderItemsCopyWith(ShoppingEdit_ReorderItems value, $Res Function(ShoppingEdit_ReorderItems) _then) = _$ShoppingEdit_ReorderItemsCopyWithImpl;
@useResult
$Res call({
 String categoryId, List<String> ids
});




}
/// @nodoc
class _$ShoppingEdit_ReorderItemsCopyWithImpl<$Res>
    implements $ShoppingEdit_ReorderItemsCopyWith<$Res> {
  _$ShoppingEdit_ReorderItemsCopyWithImpl(this._self, this._then);

  final ShoppingEdit_ReorderItems _self;
  final $Res Function(ShoppingEdit_ReorderItems) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? categoryId = null,Object? ids = null,}) {
  return _then(ShoppingEdit_ReorderItems(
categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,ids: null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class ShoppingEdit_AddCategory extends ShoppingEdit {
  const ShoppingEdit_AddCategory({required this.name}): super._();


 final  String name;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_AddCategoryCopyWith<ShoppingEdit_AddCategory> get copyWith => _$ShoppingEdit_AddCategoryCopyWithImpl<ShoppingEdit_AddCategory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_AddCategory&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'ShoppingEdit.addCategory(name: $name)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_AddCategoryCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_AddCategoryCopyWith(ShoppingEdit_AddCategory value, $Res Function(ShoppingEdit_AddCategory) _then) = _$ShoppingEdit_AddCategoryCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$ShoppingEdit_AddCategoryCopyWithImpl<$Res>
    implements $ShoppingEdit_AddCategoryCopyWith<$Res> {
  _$ShoppingEdit_AddCategoryCopyWithImpl(this._self, this._then);

  final ShoppingEdit_AddCategory _self;
  final $Res Function(ShoppingEdit_AddCategory) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(ShoppingEdit_AddCategory(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShoppingEdit_RenameCategory extends ShoppingEdit {
  const ShoppingEdit_RenameCategory({required this.id, required this.name}): super._();


 final  String id;
 final  String name;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_RenameCategoryCopyWith<ShoppingEdit_RenameCategory> get copyWith => _$ShoppingEdit_RenameCategoryCopyWithImpl<ShoppingEdit_RenameCategory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_RenameCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name);
}

@override
String toString() {
    return 'ShoppingEdit.renameCategory(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_RenameCategoryCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_RenameCategoryCopyWith(ShoppingEdit_RenameCategory value, $Res Function(ShoppingEdit_RenameCategory) _then) = _$ShoppingEdit_RenameCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$ShoppingEdit_RenameCategoryCopyWithImpl<$Res>
    implements $ShoppingEdit_RenameCategoryCopyWith<$Res> {
  _$ShoppingEdit_RenameCategoryCopyWithImpl(this._self, this._then);

  final ShoppingEdit_RenameCategory _self;
  final $Res Function(ShoppingEdit_RenameCategory) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(ShoppingEdit_RenameCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShoppingEdit_DeleteCategory extends ShoppingEdit {
  const ShoppingEdit_DeleteCategory({required this.id}): super._();


 final  String id;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_DeleteCategoryCopyWith<ShoppingEdit_DeleteCategory> get copyWith => _$ShoppingEdit_DeleteCategoryCopyWithImpl<ShoppingEdit_DeleteCategory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_DeleteCategory&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'ShoppingEdit.deleteCategory(id: $id)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_DeleteCategoryCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_DeleteCategoryCopyWith(ShoppingEdit_DeleteCategory value, $Res Function(ShoppingEdit_DeleteCategory) _then) = _$ShoppingEdit_DeleteCategoryCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$ShoppingEdit_DeleteCategoryCopyWithImpl<$Res>
    implements $ShoppingEdit_DeleteCategoryCopyWith<$Res> {
  _$ShoppingEdit_DeleteCategoryCopyWithImpl(this._self, this._then);

  final ShoppingEdit_DeleteCategory _self;
  final $Res Function(ShoppingEdit_DeleteCategory) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(ShoppingEdit_DeleteCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShoppingEdit_ReorderCategories extends ShoppingEdit {
  const ShoppingEdit_ReorderCategories({required  List<String> ids}): _ids = ids,super._();


 final  List<String> _ids;
 List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}


/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingEdit_ReorderCategoriesCopyWith<ShoppingEdit_ReorderCategories> get copyWith => _$ShoppingEdit_ReorderCategoriesCopyWithImpl<ShoppingEdit_ReorderCategories>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingEdit_ReorderCategories&&const DeepCollectionEquality().equals(other.ids, _ids));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_ids));
}

@override
String toString() {
    return 'ShoppingEdit.reorderCategories(ids: $ids)';
}


}

/// @nodoc
abstract mixin class $ShoppingEdit_ReorderCategoriesCopyWith<$Res> implements $ShoppingEditCopyWith<$Res> {
  factory $ShoppingEdit_ReorderCategoriesCopyWith(ShoppingEdit_ReorderCategories value, $Res Function(ShoppingEdit_ReorderCategories) _then) = _$ShoppingEdit_ReorderCategoriesCopyWithImpl;
@useResult
$Res call({
 List<String> ids
});




}
/// @nodoc
class _$ShoppingEdit_ReorderCategoriesCopyWithImpl<$Res>
    implements $ShoppingEdit_ReorderCategoriesCopyWith<$Res> {
  _$ShoppingEdit_ReorderCategoriesCopyWithImpl(this._self, this._then);

  final ShoppingEdit_ReorderCategories _self;
  final $Res Function(ShoppingEdit_ReorderCategories) _then;

/// Create a copy of ShoppingEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ids = null,}) {
  return _then(ShoppingEdit_ReorderCategories(
ids: null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
