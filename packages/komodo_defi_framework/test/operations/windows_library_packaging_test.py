"""Exercises the actual packaging guard using synthetic PE headers and hashes."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


class WindowsLibraryPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gleec-windows-packaging-")
        self.root = Path(self.temporary.name)
        self.binary = self.root / "windows/bin"
        self.binary.mkdir(parents=True)
        (self.root / "app_build").mkdir()
        self.library = self.binary / "kdflib.dll"
        image = bytearray(256)
        image[:2] = b"MZ"
        struct.pack_into("<I", image, 60, 128)
        image[128:134] = b"PE\0\0\x64\x86"
        struct.pack_into("<H", image, 150, 0x2022)
        self.library.write_bytes(image)
        (self.binary / "kdf.exe").write_bytes(b"synthetic companion")
        self.manifest = {"api": {
            "api_commit_hash": "f" * 40,
            "platforms": {"windows": {
                "matching_pattern": r"^kdf_[a-f0-9]{7,40}-win-x86-64\.zip$",
                "valid_zip_sha256_checksums": ["a" * 64], "path": "windows/bin",
            }},
        }}
        self.marker = {"api_commit_hash": "f" * 40, "checksums": ["a" * 64], "archive_sha256": "a" * 64}
        self.refresh_digests()

    def tearDown(self):
        self.temporary.cleanup()

    def refresh_digests(self):
        entries = [[name, hashlib.sha256((self.binary / name).read_bytes()).hexdigest()]
                   for name in ["kdf.exe", "kdflib.dll"]]
        self.marker["artifact_sha256"] = entries[0][1]
        self.marker["runtime_set_sha256"] = hashlib.sha256(json.dumps(entries, separators=(",", ":")).encode()).hexdigest()
        self.persist()

    def persist(self):
        (self.root / "app_build/build_config.json").write_text(json.dumps(self.manifest))
        (self.binary / ".api_last_updated_windows").write_text(json.dumps(self.marker))

    def validate(self, extra=()):
        guard = Path(__file__).resolve().parents[2] / "windows/validate_native_library.cmake"
        return subprocess.run([os.environ.get("GLEEC_CMAKE", "cmake"),
                               f"-DKDF_FRAMEWORK_DIR={self.root}", *extra, "-P", str(guard)],
                              capture_output=True, text=True)

    def rejects(self, message):
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def test_accepts_matching_x64_dll_and_runtime_provenance(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_executable_only(self):
        self.library.unlink()
        self.rejects("Missing verified Windows")

    def test_rejects_stale_commit(self):
        self.marker["api_commit_hash"] = "e" * 40
        self.persist()
        self.rejects("commit does not match")

    def test_rejects_unpinned_archive_checksum(self):
        self.marker["archive_sha256"] = "b" * 64
        self.persist()
        self.rejects("archive checksum does not match")

    def test_rejects_modified_dll_bytes(self):
        self.library.write_bytes(self.library.read_bytes() + b"changed")
        self.rejects("runtime bytes do not match")

    def test_rejects_stale_companion_library(self):
        (self.binary / "libkdflib.dll").write_bytes(b"old")
        self.rejects("runtime bytes do not match")

    def test_rejects_arm64_when_x64_is_required(self):
        image = bytearray(self.library.read_bytes())
        image[132:134] = b"\x64\xaa"
        self.library.write_bytes(image)
        self.refresh_digests()
        self.rejects("must be an x64 PE library")

    def test_rejects_an_arm64_application_with_x64_dll(self):
        result = self.validate(["-DFLUTTER_TARGET_PLATFORM=windows-arm64"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("supports only windows-x64", result.stderr)

    def test_rejects_executable_disguised_as_dll(self):
        image = bytearray(self.library.read_bytes())
        struct.pack_into("<H", image, 150, 0x22)
        self.library.write_bytes(image)
        self.refresh_digests()
        self.rejects("executable-only, not a DLL")

    def test_rejects_truncated_pe_header(self):
        self.library.write_bytes(self.library.read_bytes()[:64])
        self.refresh_digests()
        self.rejects("PE header is truncated")


if __name__ == "__main__":
    unittest.main()
