from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).parents[1] / "skills"))
import verify_release_consistency as verification  # noqa: E402


class ReleaseConsistencyTests(unittest.TestCase):
    def test_retired_pending_appcast_option_fails_safely(self):
        with patch.object(
            sys,
            "argv",
            ["verify_release_consistency.py", "--allow-pending-appcast"],
        ):
            with redirect_stderr(StringIO()) as error:
                self.assertEqual(verification.main(), 1)
        self.assertIn(
            "direct macOS release workflow is retired",
            error.getvalue(),
        )


if __name__ == "__main__":
    unittest.main()
