import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class ScanForNewAddressesStatusRequest
    extends
        BaseRequest<ScanForNewAddressesStatusResponse, GeneralErrorResponse> {
  ScanForNewAddressesStatusRequest({
    required super.rpcPass,
    required this.taskId,
    this.forgetIfFinished = true,
  }) : super(method: 'task::scan_for_new_addresses::status');

  final int taskId;
  final bool forgetIfFinished;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'userpass': rpcPass,
      'method': method,
      'mmrpc': mmrpc,
      'params': {'task_id': taskId, 'forget_if_finished': forgetIfFinished},
    };
  }

  @override
  ScanForNewAddressesStatusResponse parse(Map<String, dynamic> json) =>
      ScanForNewAddressesStatusResponse.parse(json);
}

class ScanForNewAddressesStatusResponse extends BaseResponse {
  ScanForNewAddressesStatusResponse({
    required super.mmrpc,
    required this.status,
    this.details,
    this.error,
    this.statusDescription,
  });

  @override
  factory ScanForNewAddressesStatusResponse.parse(Map<String, dynamic> json) {
    final status = json.value<String>('result', 'status');
    final rawDetails = json.valueOrNull<dynamic>('result', 'details');

    ScanAddressesInfo? details;
    Exception? error;
    String? statusDescription;

    if (status == 'Ok' && rawDetails is Map<String, dynamic>) {
      details = ScanAddressesInfo.fromJson(rawDetails);
    } else if (status == 'Error' && rawDetails != null) {
      error = parseTaskErrorDetails(rawDetails);
      statusDescription = exceptionMessage(error);
    } else if (rawDetails != null) {
      statusDescription = rawDetails.toString();
    }

    return ScanForNewAddressesStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: status,
      details: details,
      error: error,
      statusDescription: statusDescription,
    );
  }

  final String status;
  final ScanAddressesInfo? details;
  final Exception? error;
  final String? statusDescription;

  @override
  Map<String, dynamic> toJson() {
    return {
      'mmrpc': mmrpc,
      'result': {
        'status': status,
        if (details != null) 'details': details!.toJson(),
        if (error != null) 'error': error.toString(),
        if (statusDescription != null) 'description': statusDescription,
      },
    };
  }
}
