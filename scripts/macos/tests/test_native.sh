#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && /bin/pwd -P)
python3 "$SIDEY_REPO_ROOT/scripts/macos/verify_content_assets.py"
SIDEY_CREATED_TEST_DIR=false

python3 -m unittest discover -s "$SIDEY_REPO_ROOT/scripts/macos/tests"

if [ -n "${SIDEY_TEST_DERIVED_DATA:-}" ]; then
	SIDEY_TEST_DIR=$SIDEY_TEST_DERIVED_DATA
else
	SIDEY_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-native-tests.XXXXXX")
	SIDEY_CREATED_TEST_DIR=true
fi

cleanup() {
	if [ "$SIDEY_CREATED_TEST_DIR" = true ]; then
		rm -rf "$SIDEY_TEST_DIR"
	fi
}
trap cleanup EXIT HUP INT TERM

# The App Store host owns all common XCTest coverage.
xcodebuild \
    -project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
    -scheme SIDEYAppStore \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$SIDEY_TEST_DIR/app-store" \
    -disableAutomaticPackageResolution \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= \
    SIDEY_RUN_BACKEND_INTEGRATION="${SIDEY_RUN_BACKEND_INTEGRATION:-0}" \
    SIDEY_SUPABASE_URL="${SIDEY_SUPABASE_URL:-}" \
    SIDEY_SUPABASE_PUBLISHABLE_KEY="${SIDEY_SUPABASE_PUBLISHABLE_KEY:-}" \
    test \
    "$@"

"$SIDEY_REPO_ROOT/scripts/macos/tests/test_recording.sh"
