#!/usr/bin/env bash
# Build Murmur with the stable signing identity and install it to /Applications/Murmur.app.
#
# Launch the installed app from Spotlight or Finder, not from this terminal: macOS attributes
# permissions to the process that launched an app, and a terminal launch makes the grants
# land on the terminal instead of on Murmur.
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id="com.zedan.murmur"
target=/Applications/Murmur.app

scripts/build-app.sh

# Refuse to replace some other app that happens to be called Murmur.
if [ -d "$target" ]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$existing_id" ] && [ "$existing_id" != "$bundle_id" ]; then
    echo "error: $target belongs to $existing_id, not $bundle_id. Move it away first." >&2
    exit 1
  fi
fi

# Match the installed binary's full path, so another app that is also named Murmur is left alone.
binary="$target/Contents/MacOS/Murmur"
if pgrep -f "$binary" >/dev/null 2>&1; then
  echo "Quitting the running Murmur…"
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$binary" >/dev/null 2>&1 || break
    sleep 0.3
  done
  pkill -f "$binary" 2>/dev/null || true
fi

rm -rf "$target"
ditto build/Murmur.app "$target"
echo "Installed $target."
echo "Now open Murmur from Spotlight (⌘Space, type Murmur) or from Finder ▸ Applications."
