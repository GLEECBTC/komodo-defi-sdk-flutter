"""Exercise Linux packaging with real, freestanding ELF shared libraries.

No KDF download, Linux sysroot, or funded wallet is required. Tool overrides:
GLEEC_CMAKE, GLEEC_READELF, GLEEC_CLANG, and GLEEC_LLD.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[2]
RUNTIME_NAMES = ("kdf", "mm2", "libmm2.so", "libkdflib.so", "libkdflib_static.so")
EXPORTS = """
int mm2_main(void) { return 0; }
int mm2_main_status(void) { return 0; }
int mm2_stop(void) { return 0; }
"""


def tool(variable, names):
    override = os.environ.get(variable)
    if override:
        return shutil.which(override)
    return next((found for name in names if (found := shutil.which(name))), None)


class LinuxLibraryPackagingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmake = tool("GLEEC_CMAKE", ("cmake",))
        cls.readelf = tool("GLEEC_READELF", ("readelf", "llvm-readelf"))
        cls.clang = tool("GLEEC_CLANG", ("clang",))
        cls.lld = tool("GLEEC_LLD", ("ld.lld",))
        missing = [name for name, value in (
            ("GLEEC_CMAKE", cls.cmake), ("GLEEC_READELF", cls.readelf),
            ("GLEEC_CLANG", cls.clang), ("GLEEC_LLD", cls.lld),
        ) if not value]
        if missing:
            raise unittest.SkipTest("Required tools unavailable; set " + ", ".join(missing))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gleec-linux-packaging-")
        self.root = Path(self.temporary.name)
        self.binary = self.root / "linux/bin"
        self.binary.mkdir(parents=True)
        (self.root / "app_build").mkdir()
        self.library = self.binary / "libkdflib.so"
        self.compile_library()
        (self.binary / "kdf").write_bytes(b"unfunded test companion executable")
        self.manifest = {"api": {
            "api_commit_hash": "f" * 40,
            "platforms": {"linux": {
                "matching_pattern": r"^kdf_[a-f0-9]{7,40}-linux-x86-64\.zip$",
                "valid_zip_sha256_checksums": ["a" * 64], "path": "linux/bin",
            }},
        }}
        self.marker = {
            "api_commit_hash": "f" * 40, "checksums": ["a" * 64],
            "archive_sha256": "a" * 64,
        }
        self.refresh_digests()

    def tearDown(self):
        self.temporary.cleanup()

    def compile_library(self, source=EXPORTS, target="x86_64-unknown-linux-gnu", link_flags=None):
        source_path = self.root / "exports.c"
        object_path = self.root / "exports.o"
        source_path.write_text(source)
        compile_result = subprocess.run([
            self.clang, "--target=" + target, "-c", "-fPIC", "-ffreestanding",
            str(source_path), "-o", str(object_path),
        ], capture_output=True, text=True, timeout=30)
        self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
        result = subprocess.run([
            self.lld, *(link_flags if link_flags is not None else ["-shared"]),
            "-o", str(self.library), str(object_path),
        ], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def refresh_digests(self):
        entries = [[name, hashlib.sha256((self.binary / name).read_bytes()).hexdigest()]
                   for name in sorted(RUNTIME_NAMES) if (self.binary / name).exists()]
        core = next((digest for name, digest in entries if name in ("kdf", "mm2")), "0" * 64)
        self.marker["artifact_sha256"] = core
        self.marker["runtime_set_sha256"] = hashlib.sha256(
            json.dumps(entries, separators=(",", ":")).encode()).hexdigest()
        self.persist()

    def persist(self):
        (self.root / "app_build/build_config.json").write_text(json.dumps(self.manifest))
        (self.binary / ".api_last_updated_linux").write_text(json.dumps(self.marker))

    def validate(self, extra=()):
        return subprocess.run([
            self.cmake, f"-DKDF_FRAMEWORK_DIR={self.root}",
            f"-DKDF_READELF={self.readelf}", *extra, "-P",
            str(PACKAGE / "linux/validate_native_library.cmake"),
        ], capture_output=True, text=True, timeout=30)

    def accepts(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Verified pinned Linux x64", result.stdout)

    def rejects(self, message, extra=()):
        result = self.validate(extra)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)

    def test_accepts_matching_shared_library_and_provenance(self):
        self.accepts()

    def test_accepts_supported_static_named_shared_library(self):
        self.library.rename(self.binary / "libkdflib_static.so")
        self.refresh_digests()
        self.accepts()

    def test_accepts_both_supported_shared_libraries(self):
        shutil.copy2(self.library, self.binary / "libkdflib_static.so")
        self.refresh_digests()
        self.accepts()

    def test_accepts_legacy_mm2_companion_name(self):
        (self.binary / "kdf").rename(self.binary / "mm2")
        self.refresh_digests()
        self.accepts()

    def test_rejects_executable_only(self):
        self.library.unlink()
        self.refresh_digests()
        self.rejects("Missing verified Linux")

    def test_rejects_stale_commit(self):
        self.marker["api_commit_hash"] = "e" * 40
        self.persist()
        self.rejects("commit does not match")

    def test_rejects_unpinned_archive(self):
        self.marker["archive_sha256"] = "b" * 64
        self.persist()
        self.rejects("archive checksum does not match")

    def test_rejects_stale_checksum_set(self):
        self.marker["checksums"] = ["b" * 64]
        self.persist()
        self.rejects("archive checksum does not match")

    def test_rejects_modified_companion(self):
        (self.binary / "kdf").write_bytes(b"modified companion")
        self.rejects("runtime bytes do not match")

    def test_rejects_modified_shared_library(self):
        self.library.write_bytes(self.library.read_bytes() + b"modified library")
        self.rejects("runtime bytes do not match")

    def test_rejects_wrong_core_hash_even_with_correct_runtime_set(self):
        self.marker["artifact_sha256"] = "b" * 64
        self.persist()
        self.rejects("runtime bytes do not match")

    def test_rejects_extra_stale_supported_library(self):
        shutil.copy2(self.library, self.binary / "libkdflib_static.so")
        self.rejects("runtime bytes do not match")

    def test_rejects_extra_stale_legacy_library(self):
        (self.binary / "libmm2.so").write_bytes(b"stale library")
        self.rejects("runtime bytes do not match")

    def test_rejects_missing_core_companion(self):
        (self.binary / "kdf").unlink()
        self.refresh_digests()
        self.rejects("runtime bytes do not match")

    def test_rejects_ambiguous_core_companions(self):
        (self.binary / "mm2").write_bytes(b"second companion")
        self.refresh_digests()
        self.rejects("runtime bytes do not match")

    def test_rejects_symlinked_library(self):
        original = self.root / "outside.so"
        self.library.rename(original)
        self.library.symlink_to(original)
        self.rejects("Linked KDF runtime files")

    def test_rejects_symlinked_companion(self):
        original = self.root / "outside-kdf"
        (self.binary / "kdf").rename(original)
        (self.binary / "kdf").symlink_to(original)
        self.rejects("Linked KDF runtime files")

    def test_rejects_arm64_library(self):
        self.compile_library(target="aarch64-unknown-linux-gnu")
        self.refresh_digests()
        self.rejects("must be an x64 ELF shared library")

    def test_rejects_arm64_application(self):
        self.rejects("supports only linux-x64", ["-DFLUTTER_TARGET_PLATFORM=linux-arm64"])

    def test_rejects_pie_disguised_as_library(self):
        self.compile_library(link_flags=[
            "-pie", "-e", "mm2_main", "--dynamic-linker", "/lib64/ld-linux-x86-64.so.2",
        ])
        self.refresh_digests()
        self.rejects("executable-only (PIE)")

    def test_rejects_pie_without_interpreter(self):
        self.compile_library(link_flags=["-pie", "-e", "mm2_main", "--no-dynamic-linker"])
        self.refresh_digests()
        self.rejects("executable-only (PIE)")

    def test_rejects_truncated_header(self):
        self.library.write_bytes(self.library.read_bytes()[:20])
        self.refresh_digests()
        self.rejects("ELF header is truncated")

    def test_rejects_corrupt_program_headers(self):
        image = bytearray(self.library.read_bytes())
        struct.pack_into("<Q", image, 32, len(image) + 4096)
        self.library.write_bytes(image)
        self.refresh_digests()
        self.rejects("ELF structure could not be validated")

    def test_rejects_missing_export(self):
        self.compile_library(EXPORTS.replace("int mm2_stop(void) { return 0; }", ""))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_hidden_export(self):
        self.compile_library(EXPORTS.replace("int mm2_stop", '__attribute__((visibility("hidden"))) int mm2_stop'))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_weak_export(self):
        self.compile_library(EXPORTS.replace("int mm2_stop", "__attribute__((weak)) int mm2_stop"))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_object_instead_of_function_export(self):
        self.compile_library(EXPORTS.replace("int mm2_stop(void) { return 0; }", "int mm2_stop = 0;"))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_undefined_function_export(self):
        self.compile_library(EXPORTS.replace(
            "int mm2_stop(void) { return 0; }",
            "extern int mm2_stop(void); int invoke_stop(void) { return mm2_stop(); }",
        ))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_symbol_name_spoofing_readelf_columns(self):
        self.compile_library(EXPORTS.replace(
            "int mm2_stop(void) { return 0; }",
            'int impostor(void) __asm__("impostor FUNC GLOBAL DEFAULT 1 mm2_stop"); '
            "int impostor(void) { return 0; }",
        ))
        self.refresh_digests()
        self.rejects("missing the defined exported function mm2_stop")

    def test_rejects_symbol_name_spoofing_an_entire_readelf_row(self):
        for prefix in ("impostor", "impostor\\", "impostor;", "impostor\\;"):
            with self.subTest(prefix=prefix):
                label = json.dumps(prefix + "\n 9: 0000000000000001 1 FUNC GLOBAL DEFAULT 1 mm2_stop")
                self.compile_library(EXPORTS.replace(
                    "int mm2_stop(void) { return 0; }",
                    f"int impostor(void) __asm__({label}); "
                    "int impostor(void) { return 0; }",
                ))
                self.refresh_digests()
                self.rejects("Linux KDF")

    def test_plugin_bundles_only_shim_and_validated_libraries(self):
        shutil.copy2(self.library, self.binary / "libkdflib_static.so")
        shutil.copy2(self.library, self.binary / "libmm2.so")
        self.refresh_digests()
        shutil.copytree(PACKAGE / "linux", self.root / "linux", dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("bin"))
        shutil.copytree(PACKAGE / "src", self.root / "src")
        (self.root / "CMakeLists.txt").write_text('''
cmake_minimum_required(VERSION 3.15)
project(linux_packaging_fixture LANGUAGES C CXX)
add_library(flutter INTERFACE IMPORTED)
add_library(PkgConfig::GTK INTERFACE IMPORTED)
function(apply_standard_settings target)
endfunction()
add_subdirectory(linux)
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/bundled.txt"
  CONTENT "$<JOIN:${komodo_defi_framework_bundled_libraries},\\n>\\n")
''')
        result = subprocess.run([
            self.cmake, "-S", str(self.root), "-B", str(self.root / "build"),
            f"-DKDF_READELF={self.readelf}", "-DFLUTTER_TARGET_PLATFORM=linux-x64",
            f"-DCMAKE_C_COMPILER={self.clang}", f"-DCMAKE_CXX_COMPILER={self.clang}",
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        bundled = (self.root / "build/bundled.txt").read_text().splitlines()
        self.assertEqual(len(bundled), 3, bundled)
        self.assertIn("komodo_defi_framework", Path(bundled[0]).name)
        self.assertEqual({Path(path).resolve() for path in bundled[1:]}, {
            self.library.resolve(), (self.binary / "libkdflib_static.so").resolve(),
        })
        self.assertNotIn(str(self.binary / "kdf"), bundled)
        # Also guard against configure/install side effects targeting the user's
        # home, which are not represented in Flutter's exported bundle list.
        cmake_files = [self.root / "linux/CMakeLists.txt", self.root / "src/CMakeLists.txt"]
        cmake_files.extend((self.root / "build").rglob("cmake_install.cmake"))
        for path in cmake_files:
            self.assertNotIn(".local", path.read_text(), str(path))


if __name__ == "__main__":
    unittest.main()
