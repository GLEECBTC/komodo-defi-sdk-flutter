#!/usr/bin/env python3
"""Generate endpoint-scoped GasFree RPC exceptions from KDF Rust enums."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ErrorEnum:
    rust_name: str
    dart_enum: str
    dart_exception: str
    source: str
    variants: tuple[str, ...]
    outer_error_type: str | None = None


ERROR_ENUMS = (
    ErrorEnum(
        rust_name="GasfreeWithdrawError",
        dart_enum="GaslessWithdrawErrorType",
        dart_exception="GaslessWithdrawException",
        source="mm2src/coins/eth/tron/gasfree/error.rs",
        variants=(
            "Unavailable",
            "PendingTransfer",
            "MaxFeeExceeded",
            "ProviderRejected",
            "InvalidProviderResponse",
            "TraceNotFound",
            "QuoteExpired",
            "InsufficientGasFreeBalance",
            "InsufficientGasFreeBalanceForActivation",
        ),
        outer_error_type="Gasless",
    ),
    ErrorEnum(
        rust_name="GasfreeAccountStatusError",
        dart_enum="GaslessAccountStatusErrorType",
        dart_exception="GaslessAccountStatusException",
        source="mm2src/mm2_main/src/rpc/lp_commands/gasless.rs",
        variants=(
            "CoinNotFound",
            "NotEthCoin",
            "CoinNotSupported",
            "GaslessNotConfigured",
            "TronRpcUnavailable",
            "ProviderIdentityMismatch",
            "GasfreeAddressMismatch",
            "TokenDecimalMismatch",
            "ProviderError",
            "InternalError",
        ),
    ),
    ErrorEnum(
        rust_name="GasfreeTraceStatusError",
        dart_enum="GaslessTraceStatusErrorType",
        dart_exception="GaslessTraceStatusException",
        source="mm2src/mm2_main/src/rpc/lp_commands/gasless.rs",
        variants=(
            "CoinNotFound",
            "NotEthCoin",
            "CoinNotSupported",
            "GaslessNotConfigured",
            "TraceNotFound",
            "InvalidTraceId",
            "ProviderError",
            "InternalError",
        ),
    ),
    ErrorEnum(
        rust_name="GasfreeTraceStreamingRequestError",
        dart_enum="GaslessTraceStreamingRequestErrorType",
        dart_exception="GaslessTraceStreamingRequestException",
        source=(
            "mm2src/mm2_main/src/rpc/streaming_activations/"
            "gasless_trace.rs"
        ),
        variants=(
            "EnableError",
            "CoinNotFound",
            "CoinNotSupported",
            "GaslessNotConfigured",
            "Internal",
        ),
    ),
)


def _enum_body(source: str, enum_name: str) -> str:
    match = re.search(rf"\bpub\s+enum\s+{re.escape(enum_name)}\s*\{{", source)
    if match is None:
        raise ValueError(f"Could not find Rust enum {enum_name}")

    start = match.end()
    depth = 1
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise ValueError(f"Rust enum {enum_name} is not closed")


def _variants(body: str) -> tuple[str, ...]:
    variants: list[str] = []
    depth = 0
    for line in body.splitlines():
        if depth == 0:
            match = re.match(r"\s*([A-Z][A-Za-z0-9_]*)\s*(?:\(|\{|,)", line)
            if match is not None:
                variants.append(match.group(1))
        depth += line.count("{") - line.count("}")
    return tuple(variants)


def _lower_camel(value: str) -> str:
    return value[0].lower() + value[1:]


def _render_enum(spec: ErrorEnum) -> str:
    rendered_entries = []
    for index, variant in enumerate(spec.variants):
        suffix = "," if index < len(spec.variants) - 1 else ";"
        entry = f"  {_lower_camel(variant)}('{variant}'){suffix}"
        if len(entry) <= 80:
            rendered_entries.append(entry)
        else:
            rendered_entries.append(
                f"  {_lower_camel(variant)}(\n"
                f"    '{variant}',\n"
                f"  ){suffix}"
            )
    entries = "\n".join(rendered_entries)
    return f"""\
enum {spec.dart_enum} implements GaslessRpcErrorType {{
{entries}

  const {spec.dart_enum}(this.wireValue);

  @override
  final String wireValue;

  static {spec.dart_enum}? tryParse(String value) {{
    for (final type in values) {{
      if (type.wireValue == value) return type;
    }}
    return null;
  }}
}}"""


def _render_exception(spec: ErrorEnum) -> str:
    extract_error = (
        f"""\
    final outer = _gaslessErrorEnvelope(json);
    if (outer == null || outer['error_type'] != '{spec.outer_error_type}') {{
      return null;
    }}
    final error = _asJsonMap(outer['error_data']);
    if (error == null) return null;"""
        if spec.outer_error_type is not None
        else """\
    final outer = _gaslessErrorEnvelope(json);
    if (outer == null) return null;
    final error = outer;"""
    )
    metadata_source = "outer"
    nested_to_json = (
        f"""

  @override
  JsonMap toJson() => {{
    'error_type': '{spec.outer_error_type}',
    'error_data': {{'error_type': errorType, 'error_data': errorData}},
    if (message != null) 'error': message,
    if (path != null) 'error_path': path,
    if (trace != null) 'error_trace': trace,
  }};"""
        if spec.outer_error_type is not None
        else ""
    )
    return f"""\
final class {spec.dart_exception}
    extends GaslessEndpointException<{spec.dart_enum}> {{
  const {spec.dart_exception}({{
    required super.type,
    super.errorData,
    super.message,
    super.path,
    super.trace,
  }});

  static {spec.dart_exception}? tryParse(JsonMap json) {{
{extract_error}
    final wireType = error['error_type'];
    if (wireType is! String) return null;
    final type = {spec.dart_enum}.tryParse(wireType);
    if (type == null) return null;
    return {spec.dart_exception}(
      type: type,
      errorData: error['error_data'],
      message: {metadata_source}['error'] is String
          ? {metadata_source}['error'] as String
          : {metadata_source}['message'] as String?,
      path: {metadata_source}['error_path'] as String?,
      trace: {metadata_source}['error_trace'] as String?,
    );
  }}{nested_to_json}
}}"""


def _render() -> str:
    enums = "\n\n".join(_render_enum(spec) for spec in ERROR_ENUMS)
    exceptions = "\n\n".join(_render_exception(spec) for spec in ERROR_ENUMS)
    sources = "\n".join(
        f"// - {source}" for source in dict.fromkeys(
            spec.source for spec in ERROR_ENUMS
        )
    )

    return f"""\
// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Generated by tool/generate_gasless_rpc_exceptions.py from:
{sources}

import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

abstract interface class GaslessRpcErrorType {{
  String get wireValue;
}}

abstract class GaslessEndpointException<T extends GaslessRpcErrorType>
    implements Exception {{
  const GaslessEndpointException({{
    required this.type,
    this.errorData,
    this.message,
    this.path,
    this.trace,
  }});

  final T type;
  final Object? errorData;
  final String? message;
  final String? path;
  final String? trace;

  String get errorType => type.wireValue;

  JsonMap toJson() => {{
    'error_type': errorType,
    'error_data': errorData,
    if (message != null) 'error': message,
    if (path != null) 'error_path': path,
    if (trace != null) 'error_trace': trace,
  }};

  @override
  String toString() =>
      '$runtimeType(errorType: $errorType, message: $message, path: $path)';
}}

{enums}

{exceptions}

JsonMap? _gaslessErrorEnvelope(JsonMap json) {{
  final result = _asJsonMap(json['result']);
  final rawDetails = result?['details'];
  final details =
      _asJsonMap(rawDetails) ??
      (rawDetails is String ? tryParseJson(rawDetails) : null);
  if (details != null) return details;

  final message = _asJsonMap(json['message']);
  if (message != null) return message;

  return json['error_type'] is String ? json : null;
}}

JsonMap? _asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kdf-root", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=(
            Path(__file__).resolve().parent.parent
            / "lib/src/models/gasless_rpc_exceptions.dart"
        ),
    )
    args = parser.parse_args()

    for spec in ERROR_ENUMS:
        source = (args.kdf_root / spec.source).read_text()
        actual = _variants(_enum_body(source, spec.rust_name))
        if actual != spec.variants:
            raise ValueError(
                f"{spec.rust_name} variants changed: "
                f"expected {spec.variants}, found {actual}"
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(_render())


if __name__ == "__main__":
    main()
