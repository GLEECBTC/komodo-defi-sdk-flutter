import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to import externally stored swap records into KDF.
class ImportSwapsRequest
    extends BaseRequest<ImportSwapsResponse, GeneralErrorResponse> {
  ImportSwapsRequest({required String rpcPass, this.swaps = const []})
    : super(method: 'import_swaps', rpcPass: rpcPass, mmrpc: null);

  /// Raw swap records as exported by `my_recent_swaps` or compatible tooling.
  final List<dynamic> swaps;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'swaps': swaps};

  @override
  ImportSwapsResponse parse(Map<String, dynamic> json) =>
      ImportSwapsResponse.parse(json);
}

/// Response from importing swap records.
class ImportSwapsResponse extends BaseResponse {
  ImportSwapsResponse({required super.mmrpc, required this.result});

  factory ImportSwapsResponse.parse(JsonMap json) {
    return ImportSwapsResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      result: ImportSwapsResult.fromJson(json.value<JsonMap>('result')),
    );
  }

  /// Import result summary.
  final ImportSwapsResult result;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': result.toJson(),
  };
}

/// Swap import result split into imported UUIDs and skipped records.
class ImportSwapsResult {
  ImportSwapsResult({required this.imported, required this.skipped});

  factory ImportSwapsResult.fromJson(JsonMap json) {
    final skippedJson = json.valueOrNull<JsonMap>('skipped') ?? {};
    return ImportSwapsResult(
      imported: List<String>.from(
        json.valueOrNull<List<dynamic>>('imported') ?? [],
      ),
      skipped: skippedJson.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  /// UUIDs imported successfully.
  final List<String> imported;

  /// UUID or record identifiers skipped by KDF, with the skip reason.
  final Map<String, String> skipped;

  Map<String, dynamic> toJson() => {'imported': imported, 'skipped': skipped};
}
