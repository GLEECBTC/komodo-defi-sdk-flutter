import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class EvmNode {
  EvmNode({required this.url, bool? komodoProxy, bool? guiAuth})
    : komodoProxy = komodoProxy ?? guiAuth ?? false;

  factory EvmNode.fromJson(JsonMap json) {
    return EvmNode(
      url: json.value<String>('url'),
      komodoProxy:
          json.valueOrNull<bool>('komodo_proxy') ??
          json.valueOrNull<bool>('gui_auth') ??
          false,
    );
  }

  final String url;
  final bool komodoProxy;

  bool get guiAuth => komodoProxy;

  Map<String, dynamic> toJson() => {'url': url, 'komodo_proxy': komodoProxy};
}
