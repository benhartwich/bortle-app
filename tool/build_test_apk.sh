#!/usr/bin/env bash
# A test APK for the maintainer's phone, built in the Flutter Docker image.
#
# Android installs an update only over the same signature. The debug key Flutter
# makes lives in ~/.android of whatever builds, so a fresh container signed every
# build with a new one and every "update" had to be a reinstall (2026-10-28). This
# build always signs with the one test key given here, kept outside the repository.
#
#   BORTLE_APP_TEST_KEYSTORE=/root/.bortle/bortle-app-test.keystore tool/build_test_apk.sh
#
# The keystore is a plain debug keystore (store and key password "android", alias
# androiddebugkey): a test build is never a store build, which Codemagic signs.
set -euo pipefail
cd "$(dirname "$0")/.."
keystore="${BORTLE_APP_TEST_KEYSTORE:?set BORTLE_APP_TEST_KEYSTORE to the test keystore}"
[ -f "$keystore" ] || { echo "no keystore at $keystore" >&2; exit 1; }
docker run --rm \
  -v bortle-app-pubcache:/root/.pub-cache \
  -v bortle-app-gradle:/root/.gradle \
  -v "$keystore:/root/.android/debug.keystore:ro" \
  -v "$PWD:/app" -w /app \
  ghcr.io/cirruslabs/flutter:stable \
  bash -c 'flutter pub get >/dev/null && flutter build apk --release'
ls -la build/app/outputs/flutter-apk/app-release.apk
