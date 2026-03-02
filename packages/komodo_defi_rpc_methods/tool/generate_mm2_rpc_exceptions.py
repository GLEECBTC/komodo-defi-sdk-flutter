#!/usr/bin/env python3
import argparse
from collections import Counter
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Union

DEFAULT_REPO_URL = "https://github.com/KomodoPlatform/komodo-defi-framework.git"


@dataclass
class SerdeAttrs:
    tag: Optional[str] = None
    content: Optional[str] = None
    rename_all: Optional[str] = None
    rename: Optional[str] = None
    other: bool = False


@dataclass
class FieldDef:
    name: str
    rust_type: str
    json_name: Optional[str] = None
    serde_rename: Optional[str] = None


@dataclass
class EnumVariantDef:
    name: str
    fields: list[FieldDef]
    kind: str  # unit | tuple | struct
    serde_rename: Optional[str] = None
    serde_other: bool = False


@dataclass
class EnumDef:
    rust_name: str
    dart_name: str
    serde: SerdeAttrs
    variants: list[EnumVariantDef] = field(default_factory=list)


@dataclass
class StructDef:
    rust_name: str
    dart_name: str
    serde: SerdeAttrs
    fields: list[FieldDef]
    kind: str  # unit | tuple | struct


@dataclass
class AliasDef:
    rust_name: str
    dart_name: str
    target_type: str


@dataclass
class ExternalDef:
    rust_name: str
    dart_name: str
    kind: str  # wrapper or alias
    base_type: str


def split_top_level(value: str) -> list[str]:
    items: list[str] = []
    current: list[str] = []
    depth_angle = depth_paren = depth_brace = depth_bracket = 0
    in_string = False
    string_char = ""
    escape = False
    raw_hashes: Optional[int] = None

    i = 0
    while i < len(value):
        ch = value[i]

        if in_string:
            current.append(ch)
            if raw_hashes is not None:
                if ch == '"' and value[i + 1 : i + 1 + raw_hashes] == "#" * raw_hashes:
                    if raw_hashes:
                        current.append("#" * raw_hashes)
                        i += raw_hashes
                    in_string = False
                    raw_hashes = None
            else:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == string_char:
                    in_string = False
            i += 1
            continue

        if ch == "r":
            j = i + 1
            hash_count = 0
            while j < len(value) and value[j] == "#":
                hash_count += 1
                j += 1
            if j < len(value) and value[j] == '"':
                in_string = True
                string_char = '"'
                raw_hashes = hash_count
                current.append(value[i : j + 1])
                i = j + 1
                continue

        if ch in ("\"", "'"):
            in_string = True
            string_char = ch
            raw_hashes = None
            current.append(ch)
            i += 1
            continue

        if ch == "<":
            depth_angle += 1
        elif ch == ">":
            depth_angle = max(0, depth_angle - 1)
        elif ch == "(":
            depth_paren += 1
        elif ch == ")":
            depth_paren = max(0, depth_paren - 1)
        elif ch == "{":
            depth_brace += 1
        elif ch == "}":
            depth_brace = max(0, depth_brace - 1)
        elif ch == "[":
            depth_bracket += 1
        elif ch == "]":
            depth_bracket = max(0, depth_bracket - 1)

        if (
            ch == ","
            and depth_angle == 0
            and depth_paren == 0
            and depth_brace == 0
            and depth_bracket == 0
        ):
            item = "".join(current).strip()
            if item:
                items.append(item)
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    tail = "".join(current).strip()
    if tail:
        items.append(tail)
    return items


def strip_line_comment(value: str) -> str:
    if "//" in value:
        return value.split("//", 1)[0].rstrip()
    return value.rstrip()


def extract_preceding_attrs(source: str, start_idx: int) -> str:
    head = source[:start_idx].splitlines()
    attrs: list[str] = []
    i = len(head) - 1
    while i >= 0:
        line = head[i].strip()
        if not line:
            break
        if line.startswith("#["):
            attrs.insert(0, line)
            i -= 1
            continue
        break
    return "\n".join(attrs)


def parse_serde_attrs(attr_text: str) -> SerdeAttrs:
    attrs = SerdeAttrs()
    if not attr_text:
        return attrs
    if "serde" not in attr_text:
        return attrs
    tag_match = re.search(r'tag\s*=\s*"([^"]+)"', attr_text)
    if tag_match:
        attrs.tag = tag_match.group(1)
    content_match = re.search(r'content\s*=\s*"([^"]+)"', attr_text)
    if content_match:
        attrs.content = content_match.group(1)
    rename_all_match = re.search(r'rename_all\s*=\s*"([^"]+)"', attr_text)
    if rename_all_match:
        attrs.rename_all = rename_all_match.group(1)
    rename_match = re.search(r'rename\s*=\s*"([^"]+)"', attr_text)
    if rename_match:
        attrs.rename = rename_match.group(1)
    if re.search(r'\bother\b', attr_text):
        attrs.other = True
    return attrs


def split_attr_lines(lines: list[str]) -> tuple[list[str], list[str]]:
    attr_lines: list[str] = []
    rest_lines: list[str] = []
    in_attr = False
    bracket_depth = 0
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#[") or in_attr:
            attr_lines.append(line)
            bracket_depth += line.count("[")
            bracket_depth -= line.count("]")
            if bracket_depth <= 0:
                in_attr = False
                bracket_depth = 0
            else:
                in_attr = True
            continue
        rest_lines.append(line)
    return attr_lines, rest_lines


def words_from_identifier(name: str) -> list[str]:
    spaced = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", name)
    spaced = re.sub(r"[^0-9A-Za-z]+", " ", spaced)
    return [part for part in spaced.strip().split() if part]


def apply_rename_all(name: str, rename_all: Optional[str]) -> str:
    if not rename_all:
        return name
    words = words_from_identifier(name)
    if rename_all == "lowercase":
        return "".join(words).lower()
    if rename_all == "UPPERCASE":
        return "".join(words).upper()
    if rename_all == "snake_case":
        return "_".join(word.lower() for word in words)
    if rename_all == "SCREAMING_SNAKE_CASE":
        return "_".join(word.upper() for word in words)
    if rename_all == "kebab-case":
        return "-".join(word.lower() for word in words)
    if rename_all == "camelCase":
        if not words:
            return name
        return words[0].lower() + "".join(w.title() for w in words[1:])
    if rename_all == "PascalCase":
        return "".join(w.title() for w in words)
    return name


def extract_block(source: str, start_idx: int, open_ch: str, close_ch: str) -> tuple[str, int]:
    depth = 0
    i = start_idx
    body_chars: list[str] = []
    while i < len(source):
        ch = source[i]
        if ch == open_ch:
            depth += 1
            if depth == 1:
                i += 1
                continue
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return "".join(body_chars), i
        if depth >= 1:
            body_chars.append(ch)
        i += 1
    return "".join(body_chars), i


def parse_named_fields(body: str, rename_all: Optional[str]) -> list[FieldDef]:
    fields: list[FieldDef] = []
    for raw in split_top_level(body):
        raw = strip_line_comment(raw).strip()
        if not raw:
            continue
        lines = [line for line in raw.splitlines() if line.strip()]
        attr_lines, rest_lines = split_attr_lines(lines)
        attr_text = "\n".join(attr_lines)
        rest = " ".join(rest_lines).strip()
        serde = parse_serde_attrs(attr_text)
        m = re.match(r"(?:pub(?:\([^)]*\))?\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)", rest)
        if not m:
            continue
        name = m.group(1)
        ty = m.group(2).strip()
        json_name = serde.rename or apply_rename_all(name, rename_all)
        fields.append(
            FieldDef(
                name=name,
                rust_type=ty,
                json_name=json_name,
                serde_rename=serde.rename,
            )
        )
    return fields


def parse_enum_variants(body: str, rename_all: Optional[str]) -> list[EnumVariantDef]:
    variants: list[EnumVariantDef] = []
    for raw in split_top_level(body):
        raw = strip_line_comment(raw).strip()
        if not raw:
            continue
        lines = [line for line in raw.splitlines() if line.strip()]
        attr_lines, rest_lines = split_attr_lines(lines)
        attr_text = "\n".join(attr_lines)
        rest = " ".join(rest_lines).strip()
        serde = parse_serde_attrs(attr_text)
        if "{" in rest:
            name = rest.split("{", 1)[0].strip()
            block_body, _ = extract_block(rest, rest.index("{"), "{", "}")
            fields = parse_named_fields(block_body, None)
            variants.append(
                EnumVariantDef(
                    name=name,
                    fields=fields,
                    kind="struct",
                    serde_rename=serde.rename,
                    serde_other=serde.other,
                )
            )
        elif "(" in rest:
            name = rest.split("(", 1)[0].strip()
            block_body, _ = extract_block(rest, rest.index("("), "(", ")")
            tuple_fields = [
                FieldDef(name=str(idx), rust_type=ty.strip())
                for idx, ty in enumerate(split_top_level(block_body))
            ]
            variants.append(
                EnumVariantDef(
                    name=name,
                    fields=tuple_fields,
                    kind="tuple",
                    serde_rename=serde.rename,
                    serde_other=serde.other,
                )
            )
        else:
            name = rest.strip()
            if "=" in name:
                name = name.split("=", 1)[0].strip()
            if not name:
                continue
            variants.append(
                EnumVariantDef(
                    name=name,
                    fields=[],
                    kind="unit",
                    serde_rename=serde.rename,
                    serde_other=serde.other,
                )
            )
    return variants


def find_type_definition(
    rust_name: str,
    dart_name: str,
    rust_files: list[Path],
    preferred_segments: Optional[list[str]] = None,
) -> Optional[Union[EnumDef, StructDef, AliasDef]]:
    name_pattern = re.compile(rf"\b(enum|struct|type)\s+{re.escape(rust_name)}\b")

    def score_path(path: Path) -> int:
        if not preferred_segments:
            return 0
        parts = path.as_posix().split("/")
        score = 0
        for seg in preferred_segments:
            if seg in parts:
                score += 1
        return score

    matches: list[tuple[int, Path, re.Match[str], str]] = []
    for path in rust_files:
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            continue
        match = name_pattern.search(text)
        if match:
            matches.append((score_path(path), path, match, text))

    if not matches:
        return None

    matches.sort(key=lambda item: item[0], reverse=True)
    _score, _path, match, text = matches[0]

    kind = match.group(1)
    attr_text = extract_preceding_attrs(text, match.start())
    serde = parse_serde_attrs(attr_text)

    # Find body start (skip generics)
    i = match.end()
    depth_angle = 0
    body_start = None
    while i < len(text):
        ch = text[i]
        if ch == "<":
            depth_angle += 1
        elif ch == ">":
            depth_angle = max(0, depth_angle - 1)
        elif depth_angle == 0 and ch in "{(;":
            body_start = i
            break
        i += 1

    if kind == "type":
        if body_start is None:
            return None
        rhs_start = text.find("=", match.end())
        if rhs_start == -1:
            return None
        rhs_end = text.find(";", rhs_start)
        if rhs_end == -1:
            return None
        target = text[rhs_start + 1 : rhs_end].strip()
        return AliasDef(rust_name=rust_name, dart_name=dart_name, target_type=target)

    if body_start is None:
        return None

    if text[body_start] == "{":
        body, _ = extract_block(text, body_start, "{", "}")
        if kind == "struct":
            fields = parse_named_fields(body, serde.rename_all)
            return StructDef(
                rust_name=rust_name,
                dart_name=dart_name,
                serde=serde,
                fields=fields,
                kind="struct",
            )
        variants = parse_enum_variants(body, serde.rename_all)
        return EnumDef(
            rust_name=rust_name,
            dart_name=dart_name,
            serde=serde,
            variants=variants,
        )

    if text[body_start] == "(" and kind == "struct":
        body, _ = extract_block(text, body_start, "(", ")")
        tuple_fields = [
            FieldDef(name=str(idx), rust_type=ty.strip())
            for idx, ty in enumerate(split_top_level(body))
        ]
        return StructDef(
            rust_name=rust_name,
            dart_name=dart_name,
            serde=serde,
            fields=tuple_fields,
            kind="tuple",
        )

    if text[body_start] == ";" and kind == "struct":
        return StructDef(
            rust_name=rust_name,
            dart_name=dart_name,
            serde=serde,
            fields=[],
            kind="unit",
        )

    return None



def parse_args() -> argparse.Namespace:
    package_root = Path(__file__).resolve().parent.parent
    default_out = package_root / "lib" / "src" / "models" / "mm2_rpc_exceptions.dart"

    parser = argparse.ArgumentParser(
        description=(
            "Generate Mm2 RPC exceptions from the Komodo DeFi Framework source."
        )
    )
    parser.add_argument(
        "--mm2-repo",
        "-r",
        help="Path to a local komodo-defi-framework checkout.",
    )
    parser.add_argument(
        "--repo-url",
        default=DEFAULT_REPO_URL,
        help="Git URL used when cloning the API repository.",
    )
    parser.add_argument(
        "--out",
        default=str(default_out),
        help="Output path for generated Dart exceptions.",
    )
    parser.add_argument(
        "--no-clone",
        action="store_true",
        help="Require --mm2-repo instead of cloning into a temp directory.",
    )
    parser.add_argument(
        "--fix",
        dest="fix",
        action="store_true",
        help="Run `dart fix --apply` on the generated file.",
    )
    parser.add_argument(
        "--no-fix",
        dest="fix",
        action="store_false",
        help="Skip running `dart fix --apply` on the generated file.",
    )
    parser.set_defaults(fix=True)
    return parser.parse_args()


def run(cmd: list[str], cwd: Optional[Path] = None) -> None:
    subprocess.run(cmd, check=True, cwd=str(cwd) if cwd else None)


def resolve_mm2_repo(args: argparse.Namespace) -> tuple[Path, Optional[tempfile.TemporaryDirectory]]:
    if args.mm2_repo:
        repo_path = Path(args.mm2_repo).expanduser().resolve()
        if not repo_path.exists():
            raise SystemExit(f"--mm2-repo path does not exist: {repo_path}")
        return repo_path, None

    if args.no_clone:
        raise SystemExit("Provide --mm2-repo or allow cloning by removing --no-clone.")

    tmp_dir = tempfile.TemporaryDirectory(prefix="kdf-mm2-")
    repo_path = Path(tmp_dir.name) / "komodo-defi-framework"
    run(["git", "clone", "--depth", "1", args.repo_url, str(repo_path)])
    return repo_path, tmp_dir


def generate_lines(enums: list[dict], mm2_repo_root: Path) -> list[str]:

    def sanitize_type_name(name: str) -> str:
        name = name.replace("::", " ")
        name = re.sub(r"[^0-9A-Za-z]+", " ", name)
        parts = [part for part in name.split() if part]
        if not parts:
            return "Unknown"
        formatted_parts = []
        for part in parts:
            if len(part) == 1:
                formatted_parts.append(part.upper())
            else:
                formatted_parts.append(part[0].upper() + part[1:])
        return "".join(formatted_parts)

    def split_generic(s: str) -> tuple[str, str]:
        depth = 0
        current: list[str] = []
        parts: list[str] = []
        for ch in s:
            if ch in "<({[":
                depth += 1
            elif ch in ">)}]":
                depth -= 1
            elif ch == "," and depth == 0:
                parts.append("".join(current).strip())
                current = []
                continue
            current.append(ch)
        parts.append("".join(current).strip())
        if len(parts) != 2:
            raise ValueError(f"Expected two generic arguments, got {parts}")
        return parts[0], parts[1]

    def pascal_case(name: str) -> str:
        name = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", name)
        name = re.sub(r"[^0-9A-Za-z]+", " ", name)
        parts = [part for part in name.split() if part]
        if not parts:
            return "Unknown"
        formatted = []
        for part in parts:
            if len(part) == 1:
                formatted.append(part.upper())
            else:
                formatted.append(part[0].upper() + part[1:])
        return "".join(formatted)

    def camel_case(name: str) -> str:
        base = pascal_case(name)
        return base[0].lower() + base[1:] if base else "value"

    # Names reserved by the base MmRpcException and Dart keywords we avoid colliding with.
    reserved_field_names = {
        "message",
        "path",
        "trace",
        "errorType",
    }
    reserved_enum_members = {
        "as",
        "assert",
        "async",
        "await",
        "break",
        "case",
        "catch",
        "class",
        "const",
        "continue",
        "default",
        "deferred",
        "do",
        "dynamic",
        "else",
        "enum",
        "export",
        "extends",
        "extension",
        "external",
        "factory",
        "false",
        "final",
        "finally",
        "for",
        "Function",
        "get",
        "hashCode",
        "hide",
        "if",
        "implements",
        "import",
        "in",
        "index",
        "interface",
        "is",
        "late",
        "library",
        "mixin",
        "name",
        "new",
        "noSuchMethod",
        "null",
        "operator",
        "part",
        "required",
        "rethrow",
        "return",
        "runtimeType",
        "set",
        "show",
        "static",
        "super",
        "switch",
        "this",
        "throw",
        "toString",
        "true",
        "try",
        "typedef",
        "var",
        "void",
        "while",
        "with",
        "yield",
        "values",
    }

    def enum_member_name(name: str) -> str:
        candidate = camel_case(name)
        candidate = re.sub(r'[^0-9A-Za-z_]', '_', candidate)
        if not candidate:
            candidate = 'unknown'
        if candidate[0].isdigit():
            candidate = f'v{candidate}'
        if candidate in reserved_enum_members:
            candidate = f"{candidate}Value"
        return candidate

    def make_safe_field_name(original_name: str, used_names: set[str]) -> str:
        candidate = camel_case(original_name)
        if candidate in reserved_field_names:
            candidate = candidate + "Data"
        while candidate in used_names:
            candidate = candidate + "_"
        used_names.add(candidate)
        return candidate

    primitive_rust_types = {
        "bool",
        "char",
        "u8",
        "u16",
        "u32",
        "u64",
        "usize",
        "i8",
        "i16",
        "i32",
        "i64",
        "isize",
        "f32",
        "f64",
        "String",
        "str",
    }

    external_type_map: dict[str, ExternalDef] = {
        "BigDecimal": ExternalDef(
            rust_name="BigDecimal",
            dart_name="BigDecimal",
            kind="wrapper",
            base_type="String",
        ),
        "BigUint": ExternalDef(
            rust_name="BigUint",
            dart_name="BigUint",
            kind="wrapper",
            base_type="String",
        ),
        "U256": ExternalDef(
            rust_name="U256", dart_name="U256", kind="wrapper", base_type="String"
        ),
        "PathBuf": ExternalDef(
            rust_name="PathBuf",
            dart_name="PathBuf",
            kind="wrapper",
            base_type="String",
        ),
        "H256Json": ExternalDef(
            rust_name="H256Json",
            dart_name="H256Json",
            kind="wrapper",
            base_type="String",
        ),
        "H160Json": ExternalDef(
            rust_name="H160Json",
            dart_name="H160Json",
            kind="wrapper",
            base_type="String",
        ),
        "Duration": ExternalDef(
            rust_name="Duration",
            dart_name="Mm2Duration",
            kind="duration",
            base_type="Duration",
        ),
        "Json": ExternalDef(
            rust_name="Json",
            dart_name="JsonValue",
            kind="json",
            base_type="dynamic",
        ),
        "serde_json::Value": ExternalDef(
            rust_name="serde_json::Value",
            dart_name="JsonValue",
            kind="json",
            base_type="dynamic",
        ),
        "serde_json::value::Value": ExternalDef(
            rust_name="serde_json::value::Value",
            dart_name="JsonValue",
            kind="json",
            base_type="dynamic",
        ),
    }

    def strip_wrappers(type_str: str) -> str:
        type_str = type_str.strip()
        if type_str.startswith("&"):
            type_str = type_str.lstrip("&").strip()
        wrapper_prefixes = [
            "Option<",
            "Vec<",
            "VecDeque<",
            "HashMap<",
            "BTreeMap<",
            "HashSet<",
            "BTreeSet<",
            "MmRpcResult<",
        ]
        for prefix in wrapper_prefixes:
            if type_str.startswith(prefix) and type_str.endswith(">"):
                return strip_wrappers(type_str[len(prefix) : -1])
        return type_str

    def base_rust_name(type_str: str) -> str:
        return strip_wrappers(type_str)

    error_enum_names = {enum["enum_name"] for enum in enums}
    error_type_enum_names = {
        f"{sanitize_type_name(name)}Type" for name in error_enum_names
    }

    # Build referenced types from error enums
    referenced_types: set[str] = set()
    type_references: dict[str, set[str]] = {}
    for enum in enums:
        for variant in enum["variants"]:
            for field in variant["fields"]:
                base = base_rust_name(field["type"])
                referenced_types.add(base)
                type_references.setdefault(base, set()).add(enum.get("file", ""))

    def preferred_segments_for_type(rust_type: str) -> Optional[list[str]]:
        refs = type_references.get(rust_type)
        if not refs:
            return None
        # Use the first reference as a heuristic for file location
        ref = sorted(refs)[0]
        parts = Path(ref).parts
        return list(parts)

    # Index Rust files for type discovery
    mm2src = mm2_repo_root / "mm2src"
    skip_dirs = {"mm2_test_helpers", "adex_cli", "target", "tests"}
    rust_files: list[Path] = []
    for path in mm2src.rglob("*.rs"):
        if any(part in skip_dirs for part in path.parts):
            continue
        rust_files.append(path)

    rust_to_dart: dict[str, str] = {}
    enum_defs: dict[str, EnumDef] = {}
    struct_defs: dict[str, StructDef] = {}
    external_defs: dict[str, ExternalDef] = {}
    alias_defs: dict[str, str] = {}

    # Register error enums and externals
    for name in error_enum_names:
        rust_to_dart[name] = sanitize_type_name(name)
    for key, ext in external_type_map.items():
        rust_to_dart[key] = ext.dart_name
        external_defs[ext.dart_name] = ext

    def register_type(rust_type: str) -> None:
        rust_type = rust_type.strip()
        if not rust_type or rust_type in primitive_rust_types:
            return
        if rust_type == "Uuid":
            rust_to_dart[rust_type] = "String"
            return
        if rust_type in rust_to_dart:
            return
        dart_name = sanitize_type_name(rust_type) if "::" in rust_type else rust_type
        rust_to_dart[rust_type] = dart_name

        if rust_type in error_enum_names:
            return
        if rust_type in external_type_map:
            external_defs[dart_name] = external_type_map[rust_type]
            return

        rust_base = rust_type.split("::")[-1]
        defn = find_type_definition(
            rust_base,
            dart_name,
            rust_files,
            preferred_segments_for_type(rust_type),
        )
        if defn is None:
            alias_defs[dart_name] = "Map<String, dynamic>"
            return

        if isinstance(defn, AliasDef):
            # Resolve aliases to primitives as wrapper classes
            target = defn.target_type.strip()
            dart_target = None
            if target in primitive_rust_types:
                dart_target = "int" if target not in ["String", "str", "bool"] else ("String" if target in ["String", "str"] else "bool")
            if target in ["f32", "f64"]:
                dart_target = "double"
            if dart_target is None:
                register_type(target)
                dart_target = rust_to_dart.get(target, "dynamic")
            external_defs[dart_name] = ExternalDef(
                rust_name=defn.rust_name,
                dart_name=defn.dart_name,
                kind="alias",
                base_type=dart_target,
            )
            return

        if isinstance(defn, StructDef):
            struct_defs[dart_name] = defn
            for field in defn.fields:
                register_type(base_rust_name(field.rust_type))
            return

        if isinstance(defn, EnumDef):
            enum_defs[dart_name] = defn
            for variant in defn.variants:
                for field in variant.fields:
                    register_type(base_rust_name(field.rust_type))
            return

    for rust_type in referenced_types:
        register_type(rust_type)

    def convert_type(type_str: str) -> dict[str, str]:
        type_str = type_str.strip()
        if type_str.startswith("&"):
            return convert_type(type_str.lstrip("&").strip())
        if type_str.startswith("Option<") and type_str.endswith(">"):
            inner = convert_type(type_str[7:-1])
            dart_t = inner["dart_type"]
            if not dart_t.endswith("?"):
                dart_t = f"{dart_t}?"
            return {**inner, "dart_type": dart_t}
        if type_str.startswith("Vec<") and type_str.endswith(">"):
            inner = convert_type(type_str[4:-1])
            return {**inner, "dart_type": f"List<{inner['dart_type']}>"}
        if type_str.startswith("VecDeque<") and type_str.endswith(">"):
            inner = convert_type(type_str[9:-1])
            return {**inner, "dart_type": f"List<{inner['dart_type']}>"}
        if type_str.startswith("HashMap<") and type_str.endswith(">"):
            key, value = split_generic(type_str[8:-1])
            key_type = convert_type(key)
            value_type = convert_type(value)
            return {
                **value_type,
                "dart_type": f"Map<{key_type['dart_type']}, {value_type['dart_type']}>",
            }
        if type_str.startswith("BTreeMap<") and type_str.endswith(">"):
            key, value = split_generic(type_str[9:-1])
            key_type = convert_type(key)
            value_type = convert_type(value)
            return {
                **value_type,
                "dart_type": f"Map<{key_type['dart_type']}, {value_type['dart_type']}>",
            }
        if type_str.startswith("BTreeSet<") and type_str.endswith(">"):
            inner = convert_type(type_str[9:-1])
            return {**inner, "dart_type": f"List<{inner['dart_type']}>"}
        if type_str.startswith("HashSet<") and type_str.endswith(">"):
            inner = convert_type(type_str[8:-1])
            return {**inner, "dart_type": f"List<{inner['dart_type']}>"}

        if type_str in primitive_rust_types:
            if type_str in ["String", "str"]:
                return {"dart_type": "String"}
            if type_str in ["bool"]:
                return {"dart_type": "bool"}
            if type_str in ["f32", "f64"]:
                return {"dart_type": "double"}
            return {"dart_type": "int"}

        if type_str in ["MmNumber", "Number"]:
            return {"dart_type": "String"}

        if type_str == "Uuid":
            return {"dart_type": "String"}

        if type_str.startswith("MmRpcResult<") and type_str.endswith(">"):
            inner = convert_type(type_str[12:-1])
            return {**inner, "dart_type": inner["dart_type"]}

        if type_str == "RpcError":
            return {"dart_type": "String"}

        if type_str == "UserAction":
            return {"dart_type": "dynamic"}

        if type_str in ["PathBuf", "Path"]:
            dart_name = rust_to_dart.get(type_str, "PathBuf")
            return {"dart_type": dart_name}

        if type_str in ["serde_json::Value", "Json", "serde_json::value::Value"]:
            dart_name = rust_to_dart.get(type_str, "JsonValue")
            return {"dart_type": dart_name}

        if "::" in type_str:
            clean = sanitize_type_name(type_str)
            return {"dart_type": rust_to_dart.get(type_str, clean)}

        return {"dart_type": rust_to_dart.get(type_str, type_str)}

    custom_types: set[str] = set()
    custom_types.update(enum_defs.keys())
    custom_types.update(struct_defs.keys())
    custom_types.update(external_defs.keys())
    custom_types.update(sanitize_type_name(name) for name in error_enum_names)
    custom_types.update(error_type_enum_names)

    def is_custom_type(dart_type: str) -> bool:
        return dart_type in custom_types

    def dart_value_from_json(dart_type: str, json_expr: str) -> str:
        if dart_type.endswith("?"):
            inner = dart_type[:-1]
            inner_expr = dart_value_from_json(inner, json_expr)
            return f"{json_expr} == null ? null : {inner_expr}"
        if dart_type.startswith("List<") and dart_type.endswith(">"):
            inner = dart_type[5:-1]
            if is_custom_type(inner):
                return f"({json_expr} as List<dynamic>).map((e) => {inner}.fromJson(e)).toList()"
            return f"List<{inner}>.from({json_expr} as List)"
        if dart_type.startswith("Map<"):
            return f"{json_expr} as {dart_type}"
        if is_custom_type(dart_type):
            return f"{dart_type}.fromJson({json_expr})"
        if dart_type == "int":
            return f"_intFromJson({json_expr})"
        if dart_type == "double":
            return f"_doubleFromJson({json_expr})"
        if dart_type == "String":
            return f"_stringFromJson({json_expr})"
        if dart_type == "bool":
            return f"{json_expr} as bool"
        return f"{json_expr} as {dart_type}"

    def dart_value_to_json(dart_type: str, value_expr: str) -> str:
        if dart_type.endswith("?"):
            inner = dart_type[:-1]
            inner_expr = dart_value_to_json(inner, f"{value_expr}!")
            return f"{value_expr} == null ? null : {inner_expr}"
        if dart_type.startswith("List<") and dart_type.endswith(">"):
            inner = dart_type[5:-1]
            if is_custom_type(inner):
                return f"{value_expr}.map((e) => e.toJson()).toList()"
            return value_expr
        if dart_type.startswith("Map<"):
            return value_expr
        if is_custom_type(dart_type):
            return f"{value_expr}.toJson()"
        return value_expr

    # Extract unit variants from a Rust enum declaration within a source file.
    def extract_unit_variants_from_rust_enum(file_path: str, enum_name: str) -> list[str]:
        try:
            with open(file_path, "r", encoding="utf-8") as rf:
                source = rf.read()
        except FileNotFoundError:
            return []

        start = source.find(f"pub enum {enum_name}")
        if start == -1:
            return []
        brace_open = source.find("{", start)
        if brace_open == -1:
            return []
        depth = 1
        i = brace_open + 1
        body_chars: list[str] = []
        while i < len(source) and depth > 0:
            ch = source[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            if depth > 0:
                body_chars.append(ch)
            i += 1
        body = "".join(body_chars)

        unit_variants: list[str] = []
        for raw_line in body.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "(" in line or "{" in line:
                continue
            m_name = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*,?$", line)
            if m_name:
                unit_variants.append(m_name.group(1))

        return unit_variants

    # Heuristic: find stringified error parameter types inside `impl <EnumName>` blocks
    # that construct variants with `error: <param>.to_string()`.
    def find_stringified_error_param_types(enum_name: str, file_path: str) -> set[str]:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            return set()

        param_types: set[str] = set()

        for m_err in re.finditer(
            r"error\s*:\s*([A-Za-z_]\w*)\.to_string\(\)", content
        ):
            ident = m_err.group(1)
            fn_start = content.rfind("fn ", 0, m_err.start())
            if fn_start == -1:
                continue
            params_open = content.find("(", fn_start)
            if params_open == -1 or params_open > m_err.start():
                continue
            depth = 1
            i = params_open + 1
            while i < len(content) and depth > 0:
                ch = content[i]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                i += 1
            params_close = i - 1 if depth == 0 else -1
            if params_close == -1:
                continue
            params_src = content[params_open + 1 : params_close]
            m_param = re.search(
                rf"\b{re.escape(ident)}\s*:\s*([A-Za-z_][A-Za-z0-9_:]*)",
                params_src,
            )
            if m_param:
                param_types.add(m_param.group(1))

        return param_types

    def find_enum_file(enum_name: str) -> Optional[str]:
        for path in rust_files:
            try:
                txt = path.read_text(encoding="utf-8")
            except Exception:
                continue
            if f"pub enum {enum_name}" in txt:
                return str(path)
        return None

    lines: list[str] = []
    lines.append("// GENERATED CODE - DO NOT MODIFY BY HAND.")
    lines.append("// Generated by tool/generate_mm2_rpc_exceptions.py.")
    lines.append("// ignore_for_file: public_member_api_docs, constant_identifier_names")
    lines.append("")
    lines.append("library mm2_rpc_exceptions;")
    lines.append("")
    lines.append("import 'package:komodo_defi_types/komodo_defi_type_utils.dart';")
    lines.append("")
    lines.append("int _intFromJson(dynamic value) {")
    lines.append("  if (value is int) {")
    lines.append("    return value;")
    lines.append("  }")
    lines.append("  if (value is num) {")
    lines.append("    return value.toInt();")
    lines.append("  }")
    lines.append("  if (value is String) {")
    lines.append("    return int.parse(value);")
    lines.append("  }")
    lines.append("  throw ArgumentError('Invalid int value: $value');")
    lines.append("}")
    lines.append("")
    lines.append("double _doubleFromJson(dynamic value) {")
    lines.append("  if (value is double) {")
    lines.append("    return value;")
    lines.append("  }")
    lines.append("  if (value is num) {")
    lines.append("    return value.toDouble();")
    lines.append("  }")
    lines.append("  if (value is String) {")
    lines.append("    return double.parse(value);")
    lines.append("  }")
    lines.append("  throw ArgumentError('Invalid double value: $value');")
    lines.append("}")
    lines.append("")
    lines.append("String _stringFromJson(dynamic value) {")
    lines.append("  if (value == null) {")
    lines.append("    return '';")
    lines.append("  }")
    lines.append("  return value.toString();")
    lines.append("}")
    lines.append("")
    lines.append("JsonMap _asJsonMap(dynamic json) {")
    lines.append("  if (json is JsonMap) {")
    lines.append("    return json;")
    lines.append("  }")
    lines.append("  if (json is Map) {")
    lines.append("    try {")
    lines.append("      return convertToJsonMap(json);")
    lines.append("    } catch (_) {")
    lines.append("      return json.map(")
    lines.append("        (key, value) => MapEntry(key.toString(), value),")
    lines.append("      );")
    lines.append("    }")
    lines.append("  }")
    lines.append("  return <String, dynamic>{};")
    lines.append("}")
    lines.append("")
    lines.append("List<dynamic> _asJsonList(dynamic json) {")
    lines.append("  if (json is List) {")
    lines.append("    return List<dynamic>.from(json);")
    lines.append("  }")
    lines.append("  return <dynamic>[];")
    lines.append("}")
    lines.append("")

    # External / alias wrappers
    for ext in sorted(external_defs.values(), key=lambda e: e.dart_name):
        if ext.kind == "duration":
            lines.append(f"final class {ext.dart_name} {{")
            lines.append(f"  const {ext.dart_name}(this.value);")
            lines.append(f"")
            lines.append(f"  factory {ext.dart_name}.fromJson(dynamic json) {{")
            lines.append("    if (json is Map<String, dynamic>) {")
            lines.append("      final secs = json['secs'] ?? json['seconds'] ?? 0;")
            lines.append("      final nanos = json['nanos'] ?? 0;")
            lines.append("      final seconds = _intFromJson(secs);")
            lines.append("      final nanoseconds = _intFromJson(nanos);")
            lines.append(
                "      return Mm2Duration(Duration(microseconds: seconds * 1000000 + (nanoseconds ~/ 1000)));"
            )
            lines.append("    }")
            lines.append("    if (json is int || json is num || json is String) {")
            lines.append("      return Mm2Duration(Duration(seconds: _intFromJson(json)));")
            lines.append("    }")
            lines.append("    throw ArgumentError('Invalid duration value: $json');")
            lines.append("  }")
            lines.append("")
            lines.append("  final Duration value;")
            lines.append("")
            lines.append("  Map<String, dynamic> toJson() {")
            lines.append("    final seconds = value.inSeconds;")
            lines.append(
                "    final nanoseconds = (value.inMicroseconds - seconds * 1000000) * 1000;"
            )
            lines.append("    return {'secs': seconds, 'nanos': nanoseconds};")
            lines.append("  }")
            lines.append("}")
            lines.append("")
            continue

        if ext.kind == "json":
            lines.append(f"final class {ext.dart_name} {{")
            lines.append(f"  const {ext.dart_name}(this.value);")
            lines.append("")
            lines.append(f"  factory {ext.dart_name}.fromJson(dynamic json) {{")
            lines.append(f"    return {ext.dart_name}(json);")
            lines.append("  }")
            lines.append("")
            lines.append("  final dynamic value;")
            lines.append("")
            lines.append("  dynamic toJson() => value;")
            lines.append("}")
            lines.append("")
            continue

        lines.append(f"final class {ext.dart_name} {{")
        lines.append(f"  const {ext.dart_name}(this.value);")
        lines.append("")
        lines.append(f"  factory {ext.dart_name}.fromJson(dynamic json) {{")
        from_expr = dart_value_from_json(ext.base_type, "json")
        lines.append(f"    return {ext.dart_name}({from_expr});")
        lines.append("  }")
        lines.append("")
        lines.append(f"  final {ext.base_type} value;")
        lines.append("")
        to_expr = dart_value_to_json(ext.base_type, "value")
        lines.append(f"  dynamic toJson() => {to_expr};")
        lines.append("}")
        lines.append("")

    # Struct models
    for struct in sorted(struct_defs.values(), key=lambda s: s.dart_name):
        class_name = struct.dart_name
        lines.append(f"final class {class_name} {{")
        if struct.kind == "tuple":
            tuple_fields: list[tuple[str, str]] = []
            for idx, field in enumerate(struct.fields):
                dart_t = convert_type(field.rust_type)["dart_type"]
                name = "value" if len(struct.fields) == 1 else f"value{idx}"
                tuple_fields.append((name, dart_t))
            params = ", ".join([f"this.{name}" for name, _ in tuple_fields])
            lines.append(f"  const {class_name}({params});")
            lines.append("")
            lines.append(f"  factory {class_name}.fromJson(dynamic json) {{")
            if len(tuple_fields) == 1:
                name, dart_t = tuple_fields[0]
                expr = dart_value_from_json(dart_t, "json")
                lines.append(f"    return {class_name}({expr});")
            else:
                lines.append("    final list = _asJsonList(json);")
                args = ", ".join(
                    dart_value_from_json(dart_t, f"list[{idx}]")
                    for idx, (_name, dart_t) in enumerate(tuple_fields)
                )
                lines.append(f"    return {class_name}({args});")
            lines.append("  }")
            lines.append("")
            for name, dart_t in tuple_fields:
                lines.append(f"  final {dart_t} {name};")
            lines.append("")
            lines.append("  dynamic toJson() {")
            if len(tuple_fields) == 1:
                expr = dart_value_to_json(tuple_fields[0][1], tuple_fields[0][0])
                lines.append(f"    return {expr};")
            else:
                expr_list = ", ".join(
                    dart_value_to_json(t, n) for n, t in tuple_fields
                )
                lines.append(f"    return [{expr_list}];")
            lines.append("  }")
            lines.append("}")
            lines.append("")
            continue

        if struct.kind == "unit":
            lines.append(f"  const {class_name}();")
            lines.append("")
            lines.append(f"  factory {class_name}.fromJson() => const {class_name}();")
            lines.append("")
            lines.append("  dynamic toJson() => null;")
            lines.append("}")
            lines.append("")
            continue

        required_fields: list[tuple[FieldDef, str]] = []
        optional_fields: list[tuple[FieldDef, str]] = []
        for field in struct.fields:
            dart_t = convert_type(field.rust_type)["dart_type"]
            if dart_t.endswith("?"):
                optional_fields.append((field, dart_t))
            else:
                required_fields.append((field, dart_t))
        ctor_parts = [f"required this.{f.name}" for f, _ in required_fields] + [
            f"this.{f.name}" for f, _ in optional_fields
        ]
        ctor_params = ", ".join(ctor_parts)
        lines.append(f"  const {class_name}({{{ctor_params}}});")
        lines.append("")
        lines.append(f"  factory {class_name}.fromJson(JsonMap json) {{")
        lines.append(f"    return {class_name}(")
        for field, dart_t in required_fields + optional_fields:
            json_key = field.json_name or field.name
            accessor = (
                f"json.value<dynamic>('{json_key}')"
                if not dart_t.endswith("?")
                else f"json.valueOrNull<dynamic>('{json_key}')"
            )
            expr = dart_value_from_json(dart_t, accessor)
            lines.append(f"      {field.name}: {expr},")
        lines.append("    );")
        lines.append("  }")
        lines.append("")
        for field, dart_t in required_fields + optional_fields:
            lines.append(f"  final {dart_t} {field.name};")
        lines.append("")
        lines.append("  JsonMap toJson() => {")
        for field, dart_t in required_fields + optional_fields:
            json_key = field.json_name or field.name
            expr = dart_value_to_json(dart_t, field.name)
            lines.append(f"    '{json_key}': {expr},")
        lines.append("  };")
        lines.append("}")
        lines.append("")

    # Enum models (non-error enums)
    for enum_def in sorted(enum_defs.values(), key=lambda e: e.dart_name):
        def is_unit_only(enum_def):
            return all(v.kind == 'unit' and not v.fields for v in enum_def.variants)

        if is_unit_only(enum_def) and not enum_def.serde.tag and not enum_def.serde.content:
            rename_all = enum_def.serde.rename_all
            enum_name = enum_def.dart_name
            variants = []
            json_to_member = []
            for variant in enum_def.variants:
                json_name = variant.serde_rename or apply_rename_all(variant.name, rename_all)
                member_name = enum_member_name(variant.name)
                variants.append(member_name)
                json_to_member.append((json_name, member_name))

            if 'unknown' not in variants:
                variants.append('unknown')

            lines.append(f"enum {enum_name} {{")
            lines.append(f"  {', '.join(variants)};" )
            lines.append("")
            lines.append(f"  static {enum_name} fromJson(dynamic json) {{")
            lines.append("    String? value;")
            lines.append("    if (json is Map && json.isNotEmpty) {")
            lines.append("      value = json.keys.first.toString();")
            lines.append("    } else {")
            lines.append("      value = _stringFromJson(json);")
            lines.append("    }")
            lines.append("    switch (value) {")
            for json_name, member_name in json_to_member:
                lines.append(f"      case '{json_name}':")
                lines.append(f"        return {enum_name}.{member_name};")
            lines.append("      default:")
            lines.append(f"        return {enum_name}.unknown;")
            lines.append("    }")
            lines.append("  }")
            lines.append("")
            lines.append("  String toJson() {")
            lines.append("    switch (this) {")
            for json_name, member_name in json_to_member:
                lines.append(f"      case {enum_name}.{member_name}:")
                lines.append(f"        return '{json_name}';")
            lines.append(f"      case {enum_name}.unknown:")
            lines.append("        return 'unknown';")
            lines.append("    }")
            lines.append("  }")
            lines.append("}")
            lines.append("")
            continue


        class_name = enum_def.dart_name
        tag = enum_def.serde.tag
        content = enum_def.serde.content
        rename_all = enum_def.serde.rename_all

        lines.append(f"sealed class {class_name} {{")
        lines.append(f"  const {class_name}({{required this.type}});")
        lines.append("")
        lines.append("  final String type;")
        lines.append("")
        lines.append(f"  factory {class_name}.fromJson(dynamic json) {{")
        if tag and content:
            lines.append("    final map = _asJsonMap(json);")
            lines.append(f"    final type = map.valueOrNull<String>('{tag}');")
            lines.append(f"    final data = map.valueOrNull<dynamic>('{content}');")
            lines.append("    switch (type) {")
            for variant in enum_def.variants:
                variant_name = variant.serde_rename or apply_rename_all(
                    variant.name, rename_all
                )
                variant_class = f"{class_name}{pascal_case(variant.name)}"
                lines.append(f"      case '{variant_name}':")
                call = f"{variant_class}.fromJson(data)"
                if variant.kind == "unit":
                    call = f"{variant_class}.fromJson()"
                lines.append(f"        return {call};")
            lines.append("    }")
            lines.append(f"    return {class_name}Unknown(type: type, data: data);")
        elif tag:
            lines.append("    final map = _asJsonMap(json);")
            lines.append(f"    final type = map.valueOrNull<String>('{tag}');")
            lines.append("    switch (type) {")
            for variant in enum_def.variants:
                variant_name = variant.serde_rename or apply_rename_all(
                    variant.name, rename_all
                )
                variant_class = f"{class_name}{pascal_case(variant.name)}"
                lines.append(f"      case '{variant_name}':")
                call = f"{variant_class}.fromJson(map)"
                if variant.kind == "unit":
                    call = f"{variant_class}.fromJson()"
                lines.append(f"        return {call};")
            lines.append("    }")
            lines.append(f"    return {class_name}Unknown(type: type, data: map);")
        else:
            lines.append("    if (json is String) {")
            lines.append("      switch (json) {")
            for variant in enum_def.variants:
                variant_name = variant.serde_rename or apply_rename_all(
                    variant.name, rename_all
                )
                variant_class = f"{class_name}{pascal_case(variant.name)}"
                lines.append(f"        case '{variant_name}':")
                call = f"{variant_class}.fromJson(null)"
                if variant.kind == "unit":
                    call = f"{variant_class}.fromJson()"
                lines.append(f"          return {call};")
            lines.append("      }")
            lines.append(f"      return {class_name}Unknown(type: json, data: json);")
            lines.append("    }")
            lines.append("    if (json is Map<String, dynamic> && json.isNotEmpty) {")
            lines.append("      final entry = json.entries.first;")
            lines.append("      switch (entry.key) {")
            for variant in enum_def.variants:
                variant_name = variant.serde_rename or apply_rename_all(
                    variant.name, rename_all
                )
                variant_class = f"{class_name}{pascal_case(variant.name)}"
                lines.append(f"        case '{variant_name}':")
                call = f"{variant_class}.fromJson(entry.value)"
                if variant.kind == "unit":
                    call = f"{variant_class}.fromJson()"
                lines.append(f"          return {call};")
            lines.append("      }")
            lines.append(
                f"      return {class_name}Unknown(type: entry.key, data: entry.value);"
            )
            lines.append("    }")
            lines.append(f"    return {class_name}Unknown(type: null, data: json);")
        lines.append("  }")
        lines.append("")
        lines.append("  JsonMap toJson();")
        lines.append("}")
        lines.append("")

        # Variant classes
        for variant in enum_def.variants:
            variant_class = f"{class_name}{pascal_case(variant.name)}"
            variant_name = variant.serde_rename or apply_rename_all(
                variant.name, rename_all
            )
            fields = variant.fields
            lines.append(f"final class {variant_class} extends {class_name} {{")
            if variant.kind == "struct":
                required_fields = []
                optional_fields = []
                for field in fields:
                    dart_t = convert_type(field.rust_type)["dart_type"]
                    if dart_t.endswith("?"):
                        optional_fields.append((field, dart_t))
                    else:
                        required_fields.append((field, dart_t))
                ctor_parts = [f"required this.{f.name}" for f, _ in required_fields] + [
                    f"this.{f.name}" for f, _ in optional_fields
                ]
                ctor_params = ", ".join(ctor_parts)
                lines.append(
                    f"  const {variant_class}({{{ctor_params}}}) : super(type: '{variant_name}');"
                )
                lines.append("")
                lines.append(f"  factory {variant_class}.fromJson(dynamic json) {{")
                lines.append("    final map = _asJsonMap(json);")
                lines.append(f"    return {variant_class}(")
                for field, dart_t in required_fields + optional_fields:
                    json_key = field.json_name or field.name
                    accessor = (
                        f"map.valueOrNull<dynamic>('{json_key}')"
                        if dart_t.endswith("?")
                        else f"map.value<dynamic>('{json_key}')"
                    )
                    expr = dart_value_from_json(dart_t, accessor)
                    lines.append(f"      {field.name}: {expr},")
                lines.append("    );")
                lines.append("  }")
                lines.append("")
                for field, dart_t in required_fields + optional_fields:
                    lines.append(f"  final {dart_t} {field.name};")
                lines.append("")
                lines.append("  @override")
                lines.append("  JsonMap toJson() => {")
                if tag and content:
                    lines.append(f"    '{tag}': '{variant_name}',")
                    lines.append(f"    '{content}': {{")
                    for field, dart_t in required_fields + optional_fields:
                        json_key = field.json_name or field.name
                        expr = dart_value_to_json(dart_t, field.name)
                        lines.append(f"      '{json_key}': {expr},")
                    lines.append("    },")
                elif tag:
                    lines.append(f"    '{tag}': '{variant_name}',")
                    for field, dart_t in required_fields + optional_fields:
                        json_key = field.json_name or field.name
                        expr = dart_value_to_json(dart_t, field.name)
                        lines.append(f"    '{json_key}': {expr},")
                else:
                    lines.append(f"    '{variant_name}': {{")
                    for field, dart_t in required_fields + optional_fields:
                        json_key = field.json_name or field.name
                        expr = dart_value_to_json(dart_t, field.name)
                        lines.append(f"      '{json_key}': {expr},")
                    lines.append("    },")
                lines.append("  };")
                lines.append("}")
                lines.append("")
            elif variant.kind == "tuple":
                tuple_fields: list[tuple[str, str]] = []
                for idx, field in enumerate(fields):
                    dart_t = convert_type(field.rust_type)["dart_type"]
                    tuple_fields.append(
                        (f"value{idx}" if len(fields) > 1 else "value", dart_t)
                    )
                params = ", ".join([f"this.{name}" for name, _ in tuple_fields])
                lines.append(
                    f"  const {variant_class}({params}) : super(type: '{variant_name}');"
                )
                lines.append("")
                lines.append(f"  factory {variant_class}.fromJson(dynamic json) {{")
                if len(fields) == 1:
                    name, dart_t = tuple_fields[0]
                    expr = dart_value_from_json(dart_t, "json")
                    lines.append(f"    return {variant_class}({expr});")
                else:
                    lines.append("    final list = _asJsonList(json);")
                    args = ", ".join(
                        dart_value_from_json(dart_t, f"list[{idx}]")
                        for idx, (_name, dart_t) in enumerate(tuple_fields)
                    )
                    lines.append(f"    return {variant_class}({args});")
                lines.append("  }")
                lines.append("")
                for name, dart_t in tuple_fields:
                    lines.append(f"  final {dart_t} {name};")
                lines.append("")
                lines.append("  @override")
                lines.append("  JsonMap toJson() => {")
                if tag and content:
                    lines.append(f"    '{tag}': '{variant_name}',")
                    if len(fields) == 1:
                        expr = dart_value_to_json(
                            tuple_fields[0][1], tuple_fields[0][0]
                        )
                        lines.append(f"    '{content}': {expr},")
                    else:
                        expr_list = ", ".join(
                            dart_value_to_json(t, n) for n, t in tuple_fields
                        )
                        lines.append(f"    '{content}': [{expr_list}],")
                elif tag:
                    lines.append(f"    '{tag}': '{variant_name}',")
                else:
                    if len(fields) == 1:
                        expr = dart_value_to_json(
                            tuple_fields[0][1], tuple_fields[0][0]
                        )
                        lines.append(f"    '{variant_name}': {expr},")
                    else:
                        expr_list = ", ".join(
                            dart_value_to_json(t, n) for n, t in tuple_fields
                        )
                        lines.append(f"    '{variant_name}': [{expr_list}],")
                lines.append("  };")
                lines.append("}")
                lines.append("")
            else:
                lines.append(
                    f"  const {variant_class}() : super(type: '{variant_name}');"
                )
                lines.append("")
                lines.append(
                    f"  factory {variant_class}.fromJson() => const {variant_class}();"
                )
                lines.append("")
                lines.append("  @override")
                lines.append("  JsonMap toJson() => {")
                if tag:
                    lines.append(f"    '{tag}': '{variant_name}',")
                    if content:
                        lines.append(f"    '{content}': null,")
                else:
                    lines.append(f"    '{variant_name}': null,")
                lines.append("  };")
                lines.append("}")
                lines.append("")

        # Unknown variant
        lines.append(f"final class {class_name}Unknown extends {class_name} {{")
        lines.append(
            f"  const {class_name}Unknown({{required String? type, required this.data}})"
            f" : super(type: type ?? 'unknown');"
        )
        lines.append("")
        lines.append("  final dynamic data;")
        lines.append("")
        lines.append("  @override")
        lines.append("  JsonMap toJson() => {")
        if tag and content:
            lines.append(f"    '{tag}': type,")
            lines.append(f"    '{content}': data,")
        elif tag:
            lines.append(f"    '{tag}': type,")
            lines.append("    'data': data,")
        else:
            lines.append("    'type': type,")
            lines.append("    'data': data,")
        lines.append("  };")
        lines.append("}")
        lines.append("")

    # Error enum data models (string-backed discriminators)
    for enum in enums:
        enum_name = sanitize_type_name(enum["enum_name"])
        lines.append(f"sealed class {enum_name} {{")
        lines.append(f"  const {enum_name}({{required this.errorType}});")
        lines.append("")
        lines.append("  final String errorType;")
        lines.append("")
        lines.append(f"  factory {enum_name}.fromJson(dynamic json) {{")
        lines.append("    final map = _asJsonMap(json);")
        lines.append("    final type = map.valueOrNull<String>('error_type');")
        lines.append("    final data = map.valueOrNull<dynamic>('error_data');")
        lines.append("    switch (type) {")
        for variant in enum["variants"]:
            if variant.get("serde_other"):
                continue
            variant_class = f"{enum_name}{pascal_case(variant['name'])}"
            variant_type = variant.get("serde_rename") or variant["name"]
            lines.append(f"      case '{variant_type}':")
            if not variant["fields"]:
                lines.append(f"        return {variant_class}.fromJson();")
            else:
                lines.append(f"        return {variant_class}.fromJson(data);")
        lines.append("      default:")
        lines.append(
            f"        return {enum_name}Unknown(rawErrorType: type, data: data);"
        )
        lines.append("    }")
        lines.append("  }")
        lines.append("")
        lines.append("  JsonMap toJson();")
        lines.append("}")
        lines.append("")

        for variant in enum["variants"]:
            variant_type = variant.get("serde_rename") or variant["name"]
            if variant.get("serde_other"):
                variant_type = "unknown"
            variant_class = f"{enum_name}{pascal_case(variant['name'])}"
            fields = variant["fields"]
            is_struct = bool(fields) and not all(field["name"].isdigit() for field in fields)
            is_tuple = bool(fields) and all(field["name"].isdigit() for field in fields)

            lines.append(f"final class {variant_class} extends {enum_name} {{")
            if is_struct:
                field_defs: list[tuple[str, str, str]] = []
                used_param_names: set[str] = set(reserved_field_names)
                for field in fields:
                    field_type = convert_type(field["type"])["dart_type"]
                    json_key = field.get("serde_rename") or field["name"]
                    field_name = make_safe_field_name(field["name"], used_param_names)
                    field_defs.append((field_name, field_type, json_key))

                required_params: list[str] = []
                optional_params: list[str] = []
                for fname, ftype, _json_key in field_defs:
                    if ftype.endswith("?"):
                        optional_params.append(f"this.{fname}")
                    else:
                        required_params.append(f"required this.{fname}")
                params_parts = required_params + optional_params
                params = ", ".join(params_parts)
                lines.append(
                    f"  const {variant_class}({{{params}}}) : super(errorType: '{variant_type}');"
                )
                lines.append("")
                lines.append(f"  factory {variant_class}.fromJson(dynamic json) {{")
                lines.append("    final map = _asJsonMap(json);")
                lines.append(f"    return {variant_class}(")
                for fname, ftype, json_key in field_defs:
                    accessor = (
                        f"map.valueOrNull<dynamic>('{json_key}')"
                        if ftype.endswith("?")
                        else f"map.value<dynamic>('{json_key}')"
                    )
                    expr = dart_value_from_json(ftype, accessor)
                    lines.append(f"      {fname}: {expr},")
                lines.append("    );")
                lines.append("  }")
                lines.append("")
                for fname, ftype, _json_key in field_defs:
                    lines.append(f"  final {ftype} {fname};")
                lines.append("")
                lines.append("  @override")
                lines.append("  JsonMap toJson() => {")
                lines.append("    'error_type': errorType,")
                lines.append("    'error_data': {")
                for fname, ftype, json_key in field_defs:
                    expr = dart_value_to_json(ftype, fname)
                    lines.append(f"      '{json_key}': {expr},")
                lines.append("    },")
                lines.append("  };")
            elif is_tuple:
                if len(fields) == 1:
                    field_type = convert_type(fields[0]["type"])["dart_type"]
                    lines.append(
                        f"  const {variant_class}(this.value) : super(errorType: '{variant_type}');"
                    )
                    lines.append("")
                    lines.append(f"  factory {variant_class}.fromJson(dynamic json) {{")
                    expr = dart_value_from_json(field_type, "json")
                    lines.append(f"    return {variant_class}({expr});")
                    lines.append("  }")
                    lines.append("")
                    lines.append(f"  final {field_type} value;")
                    lines.append("")
                    lines.append("  @override")
                    lines.append("  JsonMap toJson() => {")
                    lines.append("    'error_type': errorType,")
                    expr = dart_value_to_json(field_type, "value")
                    lines.append(f"    'error_data': {expr},")
                    lines.append("  };")
                else:
                    params = ", ".join(f"this.value{idx}" for idx in range(len(fields)))
                    lines.append(
                        f"  const {variant_class}({params}) : super(errorType: '{variant_type}');"
                    )
                    lines.append("")
                    lines.append(f"  factory {variant_class}.fromJson(dynamic json) {{")
                    lines.append("    final list = _asJsonList(json);")
                    args = ", ".join(
                        dart_value_from_json(
                            convert_type(field["type"])["dart_type"], f"list[{idx}]"
                        )
                        for idx, field in enumerate(fields)
                    )
                    lines.append(f"    return {variant_class}({args});")
                    lines.append("  }")
                    lines.append("")
                    for idx, field in enumerate(fields):
                        field_type = convert_type(field["type"])["dart_type"]
                        lines.append(f"  final {field_type} value{idx};")
                    lines.append("")
                    lines.append("  @override")
                    lines.append("  JsonMap toJson() => {")
                    lines.append("    'error_type': errorType,")
                    expr_list = ", ".join(
                        dart_value_to_json(
                            convert_type(field["type"])["dart_type"], f"value{idx}"
                        )
                        for idx, field in enumerate(fields)
                    )
                    lines.append(f"    'error_data': [{expr_list}],")
                    lines.append("  };")
            else:
                lines.append(
                    f"  const {variant_class}() : super(errorType: '{variant_type}');"
                )
                lines.append("")
                lines.append(
                    f"  factory {variant_class}.fromJson() => const {variant_class}();"
                )
                lines.append("")
                lines.append("  @override")
                lines.append("  JsonMap toJson() => {")
                lines.append("    'error_type': errorType,")
                lines.append("    'error_data': null,")
                lines.append("  };")

            lines.append("}")
            lines.append("")

        lines.append(f"final class {enum_name}Unknown extends {enum_name} {{")
        lines.append(
            f"  const {enum_name}Unknown({{required this.data, this.rawErrorType}})"
            " : super(errorType: 'unknown');"
        )
        lines.append("")
        lines.append("  final String? rawErrorType;")
        lines.append("  final dynamic data;")
        lines.append("")
        lines.append("  @override")
        lines.append("  JsonMap toJson() => {")
        lines.append("    'error_type': rawErrorType ?? errorType,")
        lines.append("    'error_data': data,")
        lines.append("  };")
        lines.append("}")
        lines.append("")

    # Alias typedefs for unresolved types
    if alias_defs:
        for alias, base in sorted(alias_defs.items()):
            lines.append(f"typedef {alias} = {base};")
            lines.append("")

    lines.append("sealed class MmRpcException implements Exception {")
    lines.append("  const MmRpcException({")
    lines.append("    required this.errorType,")
    lines.append("    this.message,")
    lines.append("    this.path,")
    lines.append("    this.trace,")
    lines.append("  });")
    lines.append("")
    lines.append("  final String errorType;")
    lines.append("  final String? message;")
    lines.append("  final String? path;")
    lines.append("  final String? trace;")
    lines.append("")
    lines.append("  @override")
    lines.append(
        "  String toString() => 'MmRpcException(type: $errorType, message: $message, path: $path)';"
    )
    lines.append("}")
    lines.append("")

    for enum in enums:
        enum_name = sanitize_type_name(enum["enum_name"])
        base_name = pascal_case(enum["enum_name"]) + "Exception"
        lines.append(f"sealed class {base_name} extends MmRpcException {{")
        lines.append(
            f"  const {base_name}({{required super.errorType, super.message, super.path, super.trace}});"
        )
        lines.append("}")
        lines.append("")

        for variant in enum["variants"]:
            variant_type = variant.get("serde_rename") or variant["name"]
            if variant.get("serde_other"):
                variant_type = "unknown"
            class_name = (
                f"{pascal_case(enum['enum_name'])}{pascal_case(variant['name'])}Exception"
            )
            fields = variant["fields"]
            is_struct = bool(fields) and not all(
                field["name"].isdigit() for field in fields
            )
            is_tuple = bool(fields) and all(
                field["name"].isdigit() for field in fields
            )

            lines.append(f"final class {class_name} extends {base_name} {{")

            if is_struct:
                field_defs: list[tuple[str, str]] = []
                used_param_names: set[str] = set(reserved_field_names)
                for field in fields:
                    field_type = convert_type(field["type"])["dart_type"]
                    field_name = make_safe_field_name(field["name"], used_param_names)
                    field_defs.append((field_name, field_type))

                required_params: list[str] = []
                optional_params: list[str] = []
                for fname, ftype in field_defs:
                    if ftype.endswith("?"):
                        optional_params.append(f"this.{fname}")
                    else:
                        required_params.append(f"required this.{fname}")
                params_parts = required_params + optional_params + [
                    "super.message",
                    "super.path",
                    "super.trace",
                ]
                params = ", ".join(params_parts)
                lines.append(
                    f"  const {class_name}({{{params}}}) : super(errorType: '{variant_type}');"
                )

                for fname, ftype in field_defs:
                    lines.append(f"  final {ftype} {fname};")
            elif is_tuple:
                if len(fields) == 1:
                    field_type = convert_type(fields[0]["type"])["dart_type"]
                    lines.append(
                        f"  const {class_name}(this.value, {{super.message, super.path, super.trace}})"
                        f" : super(errorType: '{variant_type}');"
                    )
                    lines.append(f"  final {field_type} value;")
                else:
                    params = ", ".join(f"this.value{idx}" for idx in range(len(fields)))
                    lines.append(
                        f"  const {class_name}({params}, {{super.message, super.path, super.trace}})"
                        f" : super(errorType: '{variant_type}');"
                    )
                    for idx, field in enumerate(fields):
                        field_type = convert_type(field["type"])["dart_type"]
                        lines.append(f"  final {field_type} value{idx};")
            else:
                lines.append(
                    f"  const {class_name}({{super.message, super.path, super.trace}})"
                    f" : super(errorType: '{variant_type}');"
                )

            lines.append("}")
            lines.append("")

    emitted_extra_classes: set[str] = set()

    # Generic support: for any RPC enum where a variant contains an `error: String`
    # field and its impl converts a typed error to string, synthesize specific
    # subclasses for unit variants of that typed error.
    for enum in enums:
        enum_name = sanitize_type_name(enum["enum_name"])
        stringified_mappings = enum.get("stringified_from") or []
        if stringified_mappings:
            name_to_variant = {v["name"]: v for v in enum["variants"]}

            for mapping in stringified_mappings:
                target_variant_name = mapping.get("target_variant")
                source_type_name = mapping.get("source_type")
                unit_variants = mapping.get("unit_variants") or []
                if not target_variant_name or target_variant_name not in name_to_variant:
                    continue

                target_variant = name_to_variant[target_variant_name]
                if not any(
                    f["name"] == "error" and f["type"] == "String"
                    for f in target_variant["fields"]
                ):
                    continue

                variant_type_name = (
                    target_variant.get("serde_rename") or target_variant["name"]
                )
                if target_variant.get("serde_other"):
                    variant_type_name = "unknown"

                for unit in unit_variants:
                    class_name = (
                        f"{pascal_case(enum['enum_name'])}{pascal_case(unit)}Exception"
                    )
                    if class_name in emitted_extra_classes:
                        continue

                    lines.append(
                        f"// Auto-generated from {source_type_name} unit variant {unit} mapped through stringified error field"
                    )
                    lines.append(
                        f"final class {class_name} extends {pascal_case(enum['enum_name']) + 'Exception'} {{"
                    )

                    field_defs: list[tuple[str, str]] = []
                    ctor_required: list[str] = []
                    ctor_optional: list[str] = []
                    used_names: set[str] = set(reserved_field_names)
                    for fld in target_variant["fields"]:
                        if fld["name"] == "error":
                            continue
                        dart_t = convert_type(fld["type"])["dart_type"]
                        dart_n = make_safe_field_name(fld["name"], used_names)
                        field_defs.append((dart_n, dart_t))
                        if dart_t.endswith("?"):
                            ctor_optional.append(f"this.{dart_n}")
                        else:
                            ctor_required.append(f"required this.{dart_n}")

                    ctor_params = ", ".join(
                        ctor_required
                        + ctor_optional
                        + ["super.message", "super.path", "super.trace"]
                    )
                    lines.append(
                        f"  const {class_name}({{{ctor_params}}}) : super(errorType: '{variant_type_name}');"
                    )

                    for dart_n, dart_t in field_defs:
                        lines.append(f"  final {dart_t} {dart_n};")

                    lines.append("}")
                    lines.append("")
                    emitted_extra_classes.add(class_name)
            continue

        file_path = os.path.join(mm2_repo_root, enum.get("file", ""))
        stringified_param_types = find_stringified_error_param_types(
            enum["enum_name"], file_path
        )
        if not stringified_param_types:
            continue

        variants_with_error_field = []
        for v in enum["variants"]:
            if any(
                f["name"] == "error" and f["type"] == "String" for f in v["fields"]
            ):
                variants_with_error_field.append(v)

        if not variants_with_error_field:
            continue

        for rust_type_name in sorted(stringified_param_types):
            enum_file = find_enum_file(rust_type_name)
            if not enum_file:
                continue
            unit_variants = extract_unit_variants_from_rust_enum(enum_file, rust_type_name)
            if not unit_variants:
                continue

            for unit in unit_variants:
                class_name = (
                    f"{pascal_case(enum['enum_name'])}{pascal_case(unit)}Exception"
                )
                if class_name in emitted_extra_classes:
                    continue

                target_variant = variants_with_error_field[0]
                variant_type_name = (
                    target_variant.get("serde_rename") or target_variant["name"]
                )
                if target_variant.get("serde_other"):
                    variant_type_name = "unknown"

                lines.append(
                    f"// Auto-generated from {rust_type_name} unit variant {unit} mapped through stringified error field"
                )
                lines.append(
                    f"final class {class_name} extends {pascal_case(enum['enum_name']) + 'Exception'} {{"
                )

                field_defs: list[tuple[str, str]] = []
                ctor_required: list[str] = []
                ctor_optional: list[str] = []
                used_names: set[str] = set(reserved_field_names)
                for fld in variants_with_error_field[0]["fields"]:
                    if fld["name"] == "error":
                        continue
                    dart_t = convert_type(fld["type"])["dart_type"]
                    dart_n = make_safe_field_name(fld["name"], used_names)
                    field_defs.append((dart_n, dart_t))
                    if dart_t.endswith("?"):
                        ctor_optional.append(f"this.{dart_n}")
                    else:
                        ctor_required.append(f"required this.{dart_n}")

                ctor_params = ", ".join(
                    ctor_required
                    + ctor_optional
                    + ["super.message", "super.path", "super.trace"]
                )
                lines.append(
                    f"  const {class_name}({{{ctor_params}}}) : super(errorType: '{variant_type_name}');"
                )

                for dart_n, dart_t in field_defs:
                    lines.append(f"  final {dart_t} {dart_n};")

                lines.append("}")
                lines.append("")
                emitted_extra_classes.add(class_name)

    variant_type_counts = Counter(
        (
            variant.get("serde_rename") or variant["name"]
        )
        for enum in enums
        for variant in enum["variants"]
        if not variant.get("serde_other")
    )
    ambiguous_error_types = sorted(
        error_type
        for error_type, count in variant_type_counts.items()
        if count > 1
    )

    # Generate KdfErrorRegistry class for automatic error parsing
    lines.append("/// Registry for parsing KDF RPC error responses into typed exceptions.")
    lines.append("///")
    lines.append("/// This class provides automatic conversion of error responses to typed")
    lines.append("/// [MmRpcException] subclasses based on the `error_type` field.")
    lines.append("abstract final class KdfErrorRegistry {")
    lines.append("  KdfErrorRegistry._();")
    lines.append("")
    lines.append("  /// Attempts to parse a JSON error response into a typed [MmRpcException].")
    lines.append("  ///")
    lines.append("  /// Returns `null` if the error type is not recognized or if the JSON")
    lines.append("  /// does not contain an `error_type` field.")
    lines.append("  ///")
    lines.append("  /// Example:")
    lines.append("  /// ```dart")
    lines.append("  /// final exception = KdfErrorRegistry.tryParse(errorJson);")
    lines.append("  /// if (exception != null) {")
    lines.append("  ///   throw exception;")
    lines.append("  /// }")
    lines.append("  /// ```")
    lines.append("  static MmRpcException? tryParse(JsonMap json) {")
    lines.append("    final errorType = json['error_type'] as String?;")
    lines.append("    if (errorType == null) return null;")
    lines.append("    if (_ambiguousErrorTypes.contains(errorType)) return null;")
    lines.append("")
    lines.append("    final errorData = json['error_data'];")
    lines.append("    final message = json['error'] as String? ?? json['message'] as String?;")
    lines.append("    final path = json['error_path'] as String?;")
    lines.append("    final trace = json['error_trace'] as String?;")
    lines.append("")
    lines.append("    final parser = _errorParsers[errorType];")
    lines.append("    if (parser == null) return null;")
    lines.append("")
    lines.append("    return parser(errorData, message, path, trace);")
    lines.append("  }")
    lines.append("")
    lines.append("  /// Checks if the given error type string is a known KDF error type.")
    lines.append("  static bool isKnownErrorType(String errorType) {")
    lines.append("    return _errorParsers.containsKey(errorType);")
    lines.append("  }")
    lines.append("")
    lines.append("  /// Returns all known error type strings.")
    lines.append("  static Iterable<String> get knownErrorTypes => _errorParsers.keys;")
    lines.append("")
    lines.append("  /// Error types that are emitted by multiple RPC namespaces.")
    lines.append("  ///")
    lines.append("  /// These are intentionally excluded from automatic typed parsing")
    lines.append("  /// because `error_type` alone is not enough to disambiguate them.")
    lines.append("  static const Set<String> _ambiguousErrorTypes = {")
    for error_type in ambiguous_error_types:
        lines.append(f"    '{error_type}',")
    lines.append("  };")
    lines.append("")

    # Build the error parsers map
    lines.append("  static final _errorParsers = (() {")
    lines.append("    final parsers = <String, MmRpcException Function(dynamic errorData, String? message, String? path, String? trace)>{};")

    for enum in enums:
        enum_name = sanitize_type_name(enum["enum_name"])
        for variant in enum["variants"]:
            if variant.get("serde_other"):
                continue
            variant_type = variant.get("serde_rename") or variant["name"]
            exception_class_name = f"{pascal_case(enum['enum_name'])}{pascal_case(variant['name'])}Exception"
            fields = variant["fields"]
            is_struct = bool(fields) and not all(field["name"].isdigit() for field in fields)
            is_tuple = bool(fields) and all(field["name"].isdigit() for field in fields)

            if is_struct:
                # For struct variants, we need to parse the error_data as a map
                field_defs: list[tuple[str, str, str]] = []
                used_param_names: set[str] = set(reserved_field_names)
                for field in fields:
                    field_type = convert_type(field["type"])["dart_type"]
                    json_key = field.get("serde_rename") or field["name"]
                    field_name = make_safe_field_name(field["name"], used_param_names)
                    field_defs.append((field_name, field_type, json_key))

                lines.append(
                    f"    parsers['{variant_type}'] = (errorData, message, path, trace) {{"
                )
                lines.append("      final map = _asJsonMap(errorData);")
                lines.append(f"      return {exception_class_name}(")
                for fname, ftype, json_key in field_defs:
                    accessor = (
                        f"map.valueOrNull<dynamic>('{json_key}')"
                        if ftype.endswith("?")
                        else f"map.value<dynamic>('{json_key}')"
                    )
                    expr = dart_value_from_json(ftype, accessor)
                    lines.append(f"        {fname}: {expr},")
                lines.append("        message: message,")
                lines.append("        path: path,")
                lines.append("        trace: trace,")
                lines.append("      );")
                lines.append("    };")
            elif is_tuple:
                if len(fields) == 1:
                    field_type = convert_type(fields[0]["type"])["dart_type"]
                    expr = dart_value_from_json(field_type, "errorData")
                    lines.append(
                        f"    parsers['{variant_type}'] = (errorData, message, path, trace) => {exception_class_name}({expr}, message: message, path: path, trace: trace);"
                    )
                else:
                    lines.append(
                        f"    parsers['{variant_type}'] = (errorData, message, path, trace) {{"
                    )
                    lines.append("      final list = _asJsonList(errorData);")
                    args = ", ".join(
                        dart_value_from_json(
                            convert_type(field["type"])["dart_type"], f"list[{idx}]"
                        )
                        for idx, field in enumerate(fields)
                    )
                    lines.append(
                        f"      return {exception_class_name}({args}, message: message, path: path, trace: trace);"
                    )
                    lines.append("    };")
            else:
                # Unit variant - no error_data
                lines.append(
                    f"    parsers['{variant_type}'] = (errorData, message, path, trace) => {exception_class_name}(message: message, path: path, trace: trace);"
                )

    lines.append("    return parsers;")
    lines.append("  })();")
    lines.append("}")
    lines.append("")

    return lines


def run_dart_tools(target: str, apply_fix: bool) -> None:
    dart = shutil.which("dart")
    if not dart:
        return

    try:
        subprocess.run([dart, "format", target], check=False)
    except Exception:
        return

    if not apply_fix:
        return

    try:
        subprocess.run([dart, "fix", "--apply", target], check=False)
    except Exception:
        return


def main() -> None:
    args = parse_args()
    mm2_repo_root, tmp_dir = resolve_mm2_repo(args)

    try:
        error_enums_path = mm2_repo_root / "tools" / "error_enums.json"
        if not error_enums_path.exists():
            raise SystemExit(
                f"error_enums.json not found at {error_enums_path}. "
                "Ensure the komodo-defi-framework repository is available."
            )

        with error_enums_path.open("r", encoding="utf-8") as f:
            enums = json.load(f)

        lines = generate_lines(enums, mm2_repo_root)

        output_file = Path(args.out).expanduser().resolve()
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text("\n".join(lines), encoding="utf-8")

        run_dart_tools(str(output_file), apply_fix=args.fix)
    finally:
        if tmp_dir is not None:
            tmp_dir.cleanup()


if __name__ == "__main__":
    main()
