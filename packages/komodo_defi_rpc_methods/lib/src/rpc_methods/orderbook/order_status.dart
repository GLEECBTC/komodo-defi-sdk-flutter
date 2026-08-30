import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get status for a maker or taker order.
class OrderStatusRequest
    extends BaseRequest<OrderStatusResponse, GeneralErrorResponse> {
  OrderStatusRequest({required String rpcPass, required this.uuid})
    : super(method: 'order_status', rpcPass: rpcPass, mmrpc: null);

  /// Order UUID.
  final String uuid;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'uuid': uuid};

  @override
  OrderStatusResponse parse(Map<String, dynamic> json) =>
      OrderStatusResponse.parse(json);
}

/// Response from `order_status`.
///
/// KDF returns the order payload in legacy maker/taker-specific shapes, so the
/// SDK keeps the raw order JSON while still typing the envelope.
class OrderStatusResponse extends BaseResponse {
  OrderStatusResponse({
    required super.mmrpc,
    required this.type,
    required this.order,
    this.cancellationReason,
  });

  factory OrderStatusResponse.parse(JsonMap json) {
    final source = json.valueOrNull<JsonMap>('result') ?? json;
    return OrderStatusResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      type: source.value<String>('type'),
      order: source.value<JsonMap>('order'),
      cancellationReason: source.valueOrNull<String>('cancellation_reason'),
    );
  }

  /// Order side/type as returned by KDF, typically `Maker` or `Taker`.
  final String type;

  /// Raw maker or taker order payload.
  final JsonMap order;

  /// Optional cancellation reason when the order is no longer active.
  final String? cancellationReason;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'type': type,
    'order': order,
    if (cancellationReason != null) 'cancellation_reason': cancellationReason,
  };
}
