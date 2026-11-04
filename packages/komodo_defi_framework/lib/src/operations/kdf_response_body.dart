import 'dart:convert';

import 'package:http/http.dart' as http;

/// [response]'s body, decoded as the UTF-8 JSON KDF writes.
///
/// KDF labels almost none of its responses, and `Response.body` decodes an
/// unlabelled body as Latin-1, garbling any non-ASCII text: a wallet named
/// `Tëst` comes back from `get_wallet_names` as `TÃ«st`.
String kdfResponseBody(http.Response response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);
