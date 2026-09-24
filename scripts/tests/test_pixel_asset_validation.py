from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib


sys.path.insert(0, str(Path(__file__).parents[1]))
import validate_pixel_assets as assets  # noqa: E402


SCRIPT = Path(__file__).parents[1] / "validate_pixel_assets.py"


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", checksum)
    )


def rgba_png(*, include_srgb: bool) -> bytes:
    header = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    chunks = [png_chunk(b"IHDR", header)]
    if include_srgb:
        chunks.append(png_chunk(b"sRGB", b"\x00"))
    chunks.extend(
        (
            png_chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\xff")),
            png_chunk(b"IEND", b""),
        )
    )
    return assets.PNG_SIGNATURE + b"".join(chunks)


class PngValidationTests(unittest.TestCase):
    def test_invalid_signature_uses_domain_specific_error(self):
        with self.assertRaisesRegex(
            assets.PixelAssetValidationError,
            "fixture.png: invalid PNG signature",
        ):
            assets.decode_rgba_png(b"not a png", "fixture.png")

    def test_missing_srgb_chunk_is_rejected(self):
        with self.assertRaisesRegex(
            assets.PixelAssetValidationError,
            "fixture.png: missing sRGB chunk",
        ):
            assets.decode_rgba_png(
                rgba_png(include_srgb=False),
                "fixture.png",
            )


class ManifestValidationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.asset_root = Path(temporary.name) / "assets" / "v1"
        self.asset_root.mkdir(parents=True)
        (self.asset_root.parent / "PAID_ASSET_LICENSE.md").write_text(
            "license",
            encoding="utf-8",
        )
        self.licensing = {
            "paid_asset_license": "../PAID_ASSET_LICENSE.md",
            "paid_character_ids": ["paid_character"],
            "paid_throwable_ids": ["paid_throwable"],
            "paid_bubble_ids": ["paid_bubble"],
        }
        self.patch_asset_root = patch.object(
            assets,
            "ASSET_ROOT",
            self.asset_root,
        )
        self.patch_asset_root.start()
        self.addCleanup(self.patch_asset_root.stop)

    def test_unapproved_schema_is_rejected(self):
        manifest = {
            "schema_version": 2,
            "approval": {"status": "draft"},
        }
        with self.assertRaisesRegex(
            assets.PixelAssetValidationError,
            "asset manifest is not the approved schema v2 contract",
        ):
            assets.validate_manifest_header(manifest)

    def test_duplicate_paid_identifier_is_rejected(self):
        self.licensing["paid_character_ids"] = [
            "paid_character",
            "paid_character",
        ]
        with self.assertRaisesRegex(
            assets.PixelAssetValidationError,
            "duplicate paid character ID",
        ):
            self.validate_licensing()

    def test_free_character_cannot_use_paid_throwable(self):
        mapping = {
            "paid_character": "paid_throwable",
            "free_character": "paid_throwable",
        }
        with self.assertRaisesRegex(
            assets.PixelAssetValidationError,
            "a free character references a paid throwable",
        ):
            self.validate_licensing(mapping)

    def validate_licensing(self, mapping=None):
        if mapping is None:
            mapping = {
                "paid_character": "paid_throwable",
                "free_character": "free_throwable",
            }
        assets.validate_licensing(
            {"licensing": self.licensing},
            {"paid_character", "free_character"},
            {"paid_throwable", "free_throwable"},
            {"paid_bubble", "free_bubble"},
            mapping,
        )


class CommandLineContractTests(unittest.TestCase):
    def test_unknown_argument_keeps_failure_prefix_and_exit_status(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--unknown"],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("pixel asset validation failed: "))
        self.assertIn("--unknown", result.stderr)


if __name__ == "__main__":
    unittest.main()
