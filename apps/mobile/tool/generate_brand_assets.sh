#!/bin/sh
# Copyright 2026 ATLASHC Paweł Dolatowski
# SPDX-License-Identifier: Apache-2.0

# Regenerates (default) or verifies (--check) the launcher icons, launch logo and Android icon layers
# from the in-app WattByteMark. Run from anywhere; needs the Flutter SDK on PATH.
#
#   tool/generate_brand_assets.sh           write assets/branding/*, ios/.../Assets.xcassets/*, android/.../res/*
#   tool/generate_brand_assets.sh --check   fail if anything differs from what the renderer produces
#
# Details: assets/branding/README.md
set -eu
cd "$(dirname "$0")/.."
mode=write
if [ "${1:-}" = "--check" ]; then mode=check; fi
WB_BRAND_MODE="$mode" flutter test tool/brand/generate_brand_assets_test.dart
