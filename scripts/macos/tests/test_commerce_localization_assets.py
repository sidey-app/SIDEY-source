from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]


class CommerceLocalizationAssetTests(unittest.TestCase):
    def test_generated_bundle_and_storekit_metadata_are_current(self):
        result = subprocess.run(
            [sys.executable, "scripts/macos/sync_commerce_localizations.py"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
if __name__ == "__main__":
    unittest.main()
