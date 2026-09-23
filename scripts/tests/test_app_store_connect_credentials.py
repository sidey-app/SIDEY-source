from __future__ import annotations

from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from app_store_connect.auth import CredentialError, load_credentials  # noqa: E402


class AppStoreConnectCredentialTests(unittest.TestCase):
    def test_accepts_ci_secret_pem_without_reading_a_file(self) -> None:
        credentials = load_credentials(
            {
                "APP_STORE_CONNECT_ISSUER_ID": "issuer",
                "APP_STORE_CONNECT_KEY_ID": "key",
                "APP_STORE_CONNECT_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----",
            }
        )

        self.assertEqual(credentials[:2], ("issuer", "key"))

    def test_rejects_every_filesystem_key_option(self) -> None:
        with self.assertRaisesRegex(CredentialError, "Filesystem"):
            load_credentials(
                {
                    "APP_STORE_CONNECT_ISSUER_ID": "issuer",
                    "APP_STORE_CONNECT_KEY_ID": "key",
                    "APP_STORE_CONNECT_PRIVATE_KEY_PATH": "/tmp/AuthKey.p8",
                }
            )

    @patch("app_store_connect.auth.subprocess.run")
    def test_reads_local_key_only_from_named_macos_keychain_item(self, run) -> None:
        run.return_value.stdout = "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n"

        credentials = load_credentials(
            {
                "APP_STORE_CONNECT_ISSUER_ID": "issuer",
                "APP_STORE_CONNECT_KEY_ID": "KEY123",
            }
        )

        self.assertEqual(credentials[2].splitlines()[0], "-----BEGIN PRIVATE KEY-----")
        command = run.call_args.args[0]
        self.assertEqual(command[0], "/usr/bin/security")
        self.assertIn("SIDEY.AppStoreConnect.APIKey", command)
        self.assertIn("KEY123", command)


if __name__ == "__main__":
    unittest.main()
