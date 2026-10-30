#!/bin/bash
# The WattByteWidget extension must link system libraries only (audit H-07): a WidgetKit process has a small memory budget and
# must not load Flutter or any plugin framework. Fails when `otool -L` of the built extension lists anything outside
# /System/ and /usr/lib/ (a Flutter plugin appears as @rpath/<plugin>.framework/<plugin>).
#
#   bash tool/check_widget_links.sh [path/to/WattByteWidget.appex]      (default: the simulator build of this checkout)
#
# Exit codes: 0 clean, 1 foreign libraries linked, 2 the extension binary was not found.
set -eu
appex="${1:-build/ios/iphonesimulator/Runner.app/PlugIns/WattByteWidget.appex}"
binary="$appex/WattByteWidget"
if [ ! -f "$binary" ]; then
  echo "check_widget_links: $binary does not exist (run: flutter build ios --simulator --debug)" >&2
  exit 2
fi
foreign="$(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v '^/System/' | grep -v '^/usr/lib/' || true)"
if [ -n "$foreign" ]; then
  echo "check_widget_links: WattByteWidget links libraries that are not part of the system:" >&2
  echo "$foreign" | sed 's/^/  /' >&2
  echo "Its base xcconfig must not include the CocoaPods Pods-Runner xcconfig (ios/Flutter/Widget-*.xcconfig)." >&2
  exit 1
fi
echo "check_widget_links: $(basename "$appex") links system libraries only ($(otool -L "$binary" | tail -n +2 | wc -l | tr -d ' ') entries)"
