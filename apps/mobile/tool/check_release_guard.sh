#!/usr/bin/env bash
# Release guard: proves that a WattByte build without a valid backend configuration is refused.
#
#   tool/check_release_guard.sh            the configuration matrix (seconds, no Gradle)
#   tool/check_release_guard.sh --builds   the matrix, then real release builds (Gradle, minutes; CI only)
#
# The matrix runs tool/check_backend_config.dart (the rules of lib/config/backend_config.dart, the same ones the app
# applies at start-up) for every combination that matters and fails when a verdict is not the expected one:
# "rejected" means exit code 1 plus the INVALID BUILD CONFIGURATION header, "accepted" means exit code 0 plus OK.
# Any other exit code (a crash, an argument error) fails the script, so a broken checker can never look like a rejection.
#
# --builds additionally proves the COMPILE-TIME half of the guard (kBuildConfigurationGuard in lib/config/app_config.dart):
#   flutter build apk --release                                          must fail with [WB-CONFIG-001]
#   flutter build apk --release (API_BASE_URL set, LOCAL_ONLY_DEV=true)  must fail with [WB-CONFIG-002]
#   flutter build apk --release (API_BASE_URL set)                       must SUCCEED (positive control), and its
#                                                                        libapp.so must not contain the development banner
# A build that fails for any other reason fails this script: the marker is what proves the right guard fired.
# The builds run with -v so that the compiler's message is always in the log (it is only shown on failure of this script).
# The release signing key is not needed (WATTBYTE_ALLOW_UNSIGNED_RELEASE=1 keeps a missing key from being the reason
# the build stops). The two refused builds produce no artifact, because the Dart compile is what fails; the positive control
# builds an UNSIGNED arm64 APK with a made-up address, inspects it and deletes it again (an app-release.apk that was already
# there is put aside and restored).
#
# Fixture hosts are made up (.test / .invalid), never an address of the product. Nothing here is a secret.
# Works from any directory; needs `dart` (and `flutter` with --builds) on PATH and `flutter pub get` done.
set -euo pipefail

builds=false
for arg in "$@"; do
  case "$arg" in
    --builds) builds=true ;;
    *)
      echo "usage: tool/check_release_guard.sh [--builds]" >&2
      exit 64
      ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # apps/mobile

command -v dart > /dev/null || { echo "dart is not on PATH" >&2; exit 69; }
if [ "$builds" = true ]; then
  command -v flutter > /dev/null || { echo "flutter is not on PATH (needed for --builds)" >&2; exit 69; }
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/wb-release-guard.XXXXXX")"
trap 'rm -rf "$work"' EXIT

HTTPS_API='https://api.ci-guard.test'
HTTP_API='http://api.ci-guard.test'
PLACEHOLDER_API='https://api.ci-guard.invalid'
LOCAL_API='http://127.0.0.1:8080'

checks=0
failures=0

fail_check() {
  echo "  FAIL      $1"
  failures=$((failures + 1))
}

# Runs the checker. Usage: check <reject|accept> <description> <checker arguments...>
# `dart run` may print "Running build hooks..." (without a newline) in front of the verdict, so nothing is anchored.
check() {
  local expect="$1" label="$2" output status=0
  shift 2
  checks=$((checks + 1))
  output="$(dart run tool/check_backend_config.dart "$@" 2>&1)" || status=$?
  if [ "$expect" = reject ] && [ "$status" -eq 1 ] && grep -q 'INVALID BUILD CONFIGURATION' <<< "$output"; then
    # The first error, without the address: the checker never prints a define's value.
    echo "  rejected  $label"
    echo "              -> $(sed -n 's/^  - //p' <<< "$output" | head -n 1)"
  elif [ "$expect" = accept ] && [ "$status" -eq 0 ] && grep -q 'OK: ' <<< "$output"; then
    echo "  accepted  $label ($(grep -o 'OK: .*' <<< "$output" | head -n 1))"
  else
    fail_check "$label: expected it to be ${expect}ed, the checker exited with $status"
    sed 's/^/              | /' <<< "$output"
  fi
}

echo "Backend configuration matrix (tool/check_backend_config.dart)"
echo
echo "Must be rejected:"
check reject "release, no API_BASE_URL" \
  --build-mode=release
check reject "release, LOCAL_ONLY_DEV=false, no API_BASE_URL" \
  --build-mode=release --dart-define=LOCAL_ONLY_DEV=false
check reject "release, LOCAL_ONLY_DEV=true, no API_BASE_URL" \
  --build-mode=release --dart-define=LOCAL_ONLY_DEV=true
check reject "release, LOCAL_ONLY_DEV=true, https API_BASE_URL" \
  --build-mode=release --dart-define=API_BASE_URL="$HTTPS_API" --dart-define=LOCAL_ONLY_DEV=true
check reject "profile, no API_BASE_URL" \
  --build-mode=profile
check reject "profile, LOCAL_ONLY_DEV=true, https API_BASE_URL" \
  --build-mode=profile --dart-define=API_BASE_URL="$HTTPS_API" --dart-define=LOCAL_ONLY_DEV=true
check reject "release, http API_BASE_URL, APP_ENV=production" \
  --build-mode=release --dart-define=APP_ENV=production --dart-define=API_BASE_URL="$HTTP_API"
check reject "release, .invalid placeholder API_BASE_URL, APP_ENV=production" \
  --build-mode=release --dart-define=APP_ENV=production --dart-define=API_BASE_URL="$PLACEHOLDER_API"
check reject "release, http API_BASE_URL without APP_ENV (a build that ships is checked as production)" \
  --build-mode=release --dart-define=API_BASE_URL="$HTTP_API"
check reject "release, .invalid placeholder API_BASE_URL without APP_ENV" \
  --build-mode=release --dart-define=API_BASE_URL="$PLACEHOLDER_API"
check reject "release, a dart.vm.* define would override the build mode" \
  --build-mode=release --dart-define=API_BASE_URL="$HTTPS_API" --dart-define=dart.vm.product=false
check reject "profile, dart.vm.profile=false with LOCAL_ONLY_DEV=true and no API_BASE_URL (spoofed debug)" \
  --build-mode=profile --dart-define=dart.vm.profile=false --dart-define=LOCAL_ONLY_DEV=true
check reject "release, the unedited config/production.example.json (placeholder hosts)" \
  --build-mode=release --dart-define-from-file=config/production.example.json
check reject "debug, no API_BASE_URL, LOCAL_ONLY_DEV not set" \
  --build-mode=debug
check reject "debug, no API_BASE_URL, LOCAL_ONLY_DEV=false" \
  --build-mode=debug --dart-define=LOCAL_ONLY_DEV=false
check reject "debug, LOCAL_ONLY_DEV=true with APP_ENV=production" \
  --build-mode=debug --dart-define=APP_ENV=production --dart-define=LOCAL_ONLY_DEV=true
check reject "release, config/local-only-dev.example.json (the debug-only template)" \
  --build-mode=release --dart-define-from-file=config/local-only-dev.example.json
check reject "debug, a malformed API_BASE_URL does not degrade to local-only (LOCAL_ONLY_DEV=true)" \
  --build-mode=debug --dart-define=API_BASE_URL=not-a-url --dart-define=LOCAL_ONLY_DEV=true

echo
echo "Must be accepted:"
check accept "release, https API_BASE_URL (the defines of the release workflow)" \
  --build-mode=release --dart-define=API_BASE_URL="$HTTPS_API"
check accept "release, https API_BASE_URL, APP_ENV=production" \
  --build-mode=release --dart-define=APP_ENV=production --dart-define=API_BASE_URL="$HTTPS_API"
check accept "release, https API_BASE_URL, LOCAL_ONLY_DEV=false" \
  --build-mode=release --dart-define=API_BASE_URL="$HTTPS_API" --dart-define=LOCAL_ONLY_DEV=false
check accept "profile, https API_BASE_URL" \
  --build-mode=profile --dart-define=API_BASE_URL="$HTTPS_API"
check accept "debug, LOCAL_ONLY_DEV=true (explicit local-only development)" \
  --build-mode=debug --dart-define=LOCAL_ONLY_DEV=true
check accept "debug, config/local-only-dev.example.json" \
  --build-mode=debug --dart-define-from-file=config/local-only-dev.example.json
check accept "debug, http://127.0.0.1:8080 (development against a local API)" \
  --build-mode=debug --dart-define=API_BASE_URL="$LOCAL_API"
check accept "debug, config/development.example.json" \
  --build-mode=debug --dart-define-from-file=config/development.example.json

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures of $checks configuration checks FAILED"
  exit 1
fi
echo "All $checks configuration checks behaved as expected"

[ "$builds" = true ] || exit 0

# ------------------------------------------------------------------------------------------ compile-time guard
builds_run=0

# A build that must not compile. Usage: build_must_fail <marker> <description> <flutter build arguments...>
build_must_fail() {
  local marker="$1" label="$2" log status=0
  shift 2
  builds_run=$((builds_run + 1))
  log="$work/build-$builds_run.log"
  echo "  running   $label"
  echo "              flutter build apk --release -v${*:+ $*}"
  WATTBYTE_ALLOW_UNSIGNED_RELEASE=1 flutter build apk --release -v "$@" > "$log" 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    fail_check "$label: the build SUCCEEDED, it must not compile"
  elif ! grep -qF -- "$marker" "$log"; then
    fail_check "$label: the build failed (exit $status) but not with $marker, so the guard did not do it. Errors in its output, then its last lines:"
    { grep -E 'Error:|What went wrong|BLOCKED|FAILURE' "$log" | cut -c1-300 | head -n 20 || true
      echo '...'
      tail -n 25 "$log" | cut -c1-300 || true
    } | sed 's/^/              | /'
  else
    echo "  refused   $label"
    echo "              -> exit $status, output contains $marker"
  fi
}

echo
echo "Compile-time guard (real release builds, no signing key needed)"
echo
build_must_fail '[WB-CONFIG-001]' "release build without API_BASE_URL"
build_must_fail '[WB-CONFIG-002]' "release build with API_BASE_URL and LOCAL_ONLY_DEV=true" \
  --dart-define=API_BASE_URL="$HTTPS_API" --dart-define=LOCAL_ONLY_DEV=true

# The positive control: a valid configuration must still compile (a guard that refuses everything would pass the two
# builds above), and the development banner must not be in the shipped binary. The banner text can only be found by
# `grep -a` if the same grep finds a string that IS in the release binary (the title of the configuration error screen),
# otherwise "0 hits" would prove nothing.
build_must_succeed_without_banner() {
  local label="$1" log status=0 apk="build/app/outputs/flutter-apk/app-release.apk" so="$work/libapp.so" hits control
  shift
  builds_run=$((builds_run + 1))
  log="$work/build-$builds_run.log"
  echo "  running   $label"
  echo "              flutter build apk --release --target-platform android-arm64 -v $*"
  # A release APK that was already there (a developer's own build) is put aside and restored afterwards.
  local kept="$work/previous-app-release.apk"
  if [ -f "$apk" ]; then mv "$apk" "$kept"; fi
  WATTBYTE_ALLOW_UNSIGNED_RELEASE=1 flutter build apk --release --target-platform android-arm64 -v "$@" > "$log" 2>&1 || status=$?
  if [ "$status" -ne 0 ] || [ ! -f "$apk" ]; then
    fail_check "$label: the build must succeed, it exited with $status. Errors in its output, then its last lines:"
    { grep -E 'Error:|What went wrong|BLOCKED|FAILURE|WB-CONFIG' "$log" | cut -c1-300 | head -n 20 || true
      echo '...'
      tail -n 25 "$log" | cut -c1-300 || true
    } | sed 's/^/              | /'
    rm -f "$apk"
    if [ -f "$kept" ]; then mv "$kept" "$apk"; fi
    return
  fi
  if ! unzip -p "$apk" lib/arm64-v8a/libapp.so > "$so" 2> /dev/null || [ ! -s "$so" ]; then
    fail_check "$label: lib/arm64-v8a/libapp.so is not in the APK, nothing to inspect"
  else
    control="$(LC_ALL=C grep -a -c 'Invalid build configuration' "$so" || true)"
    hits="$(LC_ALL=C grep -a -c 'LOCAL ONLY DEVELOPMENT MODE' "$so" || true)"
    if [ "${control:-0}" -eq 0 ]; then
      fail_check "$label: the control string of the release binary was not found, so the banner check proves nothing"
    elif [ "${hits:-0}" -ne 0 ]; then
      fail_check "$label: the release binary contains the development banner text ($hits hit(s))"
    else
      echo "  built     $label"
      echo "              -> control string found, development banner text absent"
    fi
  fi
  rm -f "$apk" "$so"   # an unsigned artifact with a made-up address must not stay around as "the release APK"
  if [ -f "$kept" ]; then mv "$kept" "$apk"; fi
}

build_must_succeed_without_banner "release build with a valid API_BASE_URL (positive control)" \
  --dart-define=API_BASE_URL="$HTTPS_API"

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures of $((checks + builds_run)) checks FAILED"
  exit 1
fi
echo "Both invalid release configurations were refused by the compile-time guard, the valid one built and carries no development banner"
