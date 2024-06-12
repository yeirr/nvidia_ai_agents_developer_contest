import 'package:json_annotation/json_annotation.dart';

part 'response.g.dart';

@JsonSerializable(createToJson: true)
class BaseResponse {
  BaseResponse({
    this.data,
  });
  factory BaseResponse.fromJson(Map<String, dynamic> json) =>
      _$BaseResponseFromJson(json);

  /// Response body from server.
  @JsonKey(
    required: false,
    name: 'data',
    disallowNullValue: true,
    includeIfNull: false,
  )
  final Object? data;

  Map<String, dynamic> toJson() => _$BaseResponseToJson(this);
}
