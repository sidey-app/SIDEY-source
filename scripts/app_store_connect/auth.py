"""App Store Connect credentials without filesystem private keys."""

from __future__ import annotations

import base64
import json
import os
import subprocess
import time
from typing import Mapping


KEYCHAIN_SERVICE = "SIDEY.AppStoreConnect.APIKey"


class CredentialError(RuntimeError):
    """Raised for missing or unsafe App Store Connect credentials."""


def load_credentials(environment: Mapping[str, str] | None = None) -> tuple[str, str, str]:
    environment = os.environ if environment is None else environment
    forbidden = (
        "APP_STORE_CONNECT_PRIVATE_KEY_PATH",
        "ASC_PRIVATE_KEY_PATH",
        "API_PRIVATE_KEYS_DIR",
    )
    present = [name for name in forbidden if environment.get(name)]
    if present:
        raise CredentialError(
            "Filesystem App Store Connect keys are forbidden: " + ", ".join(present)
        )
    issuer_id = environment.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_id = environment.get("APP_STORE_CONNECT_KEY_ID", "").strip()
    if not issuer_id or not key_id:
        raise CredentialError(
            "APP_STORE_CONNECT_ISSUER_ID and APP_STORE_CONNECT_KEY_ID are required"
        )
    private_key = environment.get("APP_STORE_CONNECT_PRIVATE_KEY", "").strip()
    if not private_key:
        try:
            completed = subprocess.run(
                [
                    "/usr/bin/security",
                    "find-generic-password",
                    "-s",
                    KEYCHAIN_SERVICE,
                    "-a",
                    key_id,
                    "-w",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise CredentialError(
                "Set APP_STORE_CONNECT_PRIVATE_KEY in CI or store it in macOS Keychain "
                f"service {KEYCHAIN_SERVICE} with account {key_id}"
            ) from error
        private_key = completed.stdout.strip()
    if "BEGIN PRIVATE KEY" not in private_key:
        raise CredentialError("The App Store Connect private key must be PEM text")
    return issuer_id, key_id, private_key


def _base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    if first < 0x80:
        return first, offset + 1
    count = first & 0x7F
    return int.from_bytes(data[offset + 1 : offset + 1 + count], "big"), offset + 1 + count


def _der_signature_to_raw(signature: bytes) -> bytes:
    if not signature or signature[0] != 0x30:
        raise CredentialError("OpenSSL returned an invalid ES256 signature")
    sequence_length, offset = _read_der_length(signature, 1)
    if offset + sequence_length != len(signature) or signature[offset] != 0x02:
        raise CredentialError("OpenSSL returned an invalid ES256 signature")
    r_length, r_offset = _read_der_length(signature, offset + 1)
    r = signature[r_offset : r_offset + r_length]
    offset = r_offset + r_length
    if offset >= len(signature) or signature[offset] != 0x02:
        raise CredentialError("OpenSSL returned an invalid ES256 signature")
    s_length, s_offset = _read_der_length(signature, offset + 1)
    s = signature[s_offset : s_offset + s_length]
    if s_offset + s_length != len(signature):
        raise CredentialError("OpenSSL returned an invalid ES256 signature")
    return r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")


def _sign_es256(payload: bytes, private_key: str) -> bytes:
    read_fd, write_fd = os.pipe()
    try:
        os.write(write_fd, private_key.encode("utf-8"))
        os.close(write_fd)
        write_fd = -1
        completed = subprocess.run(
            ["/usr/bin/openssl", "dgst", "-sha256", "-sign", f"/dev/fd/{read_fd}"],
            input=payload,
            capture_output=True,
            pass_fds=(read_fd,),
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CredentialError("Unable to sign the App Store Connect JWT with OpenSSL") from error
    finally:
        os.close(read_fd)
        if write_fd >= 0:
            os.close(write_fd)
    return _der_signature_to_raw(completed.stdout)


def generate_token(
    issuer_id: str,
    key_id: str,
    private_key: str,
    *,
    now: int | None = None,
) -> str:
    issued_at = int(time.time()) if now is None else now
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {
        "iss": issuer_id,
        "iat": issued_at,
        "exp": issued_at + 15 * 60,
        "aud": "appstoreconnect-v1",
    }
    encoded_header = _base64url(json.dumps(header, separators=(",", ":")).encode())
    encoded_claims = _base64url(json.dumps(claims, separators=(",", ":")).encode())
    signing_input = f"{encoded_header}.{encoded_claims}".encode("ascii")
    return f"{signing_input.decode()}.{_base64url(_sign_es256(signing_input, private_key))}"
