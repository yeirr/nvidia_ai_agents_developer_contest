import 'package:json_annotation/json_annotation.dart';

part 'request.g.dart';

// Annotation for the code generator to know that this class needs the JSON
// serialization logic to be generated.
@JsonSerializable()
class BaseRequest {
  BaseRequest({
    this.data,
  });

  factory BaseRequest.fromJson(Map<String, dynamic> json) =>
      _$BaseRequestFromJson(json);

  @JsonKey(
    name: 'data',
    disallowNullValue: true,
    includeIfNull: false,
  )
  final Object? data;

  Map<String, dynamic> toJson() => _$BaseRequestToJson(this);
}
