#!/usr/bin/env bash
# Build build/Murmur.app from the SwiftPM package and sign it.
#
# Usage: scripts/build-app.sh [--unsigned] [--skip-build] [--debug]
#   --unsigned    ad-hoc signature (CI). Ad-hoc builds lose macOS permission grants on every
#                 rebuild, so local installs use a stable identity (scripts/setup-signing.sh).
#   --skip-build  reuse the existing `swift build` output.
#   --debug       debug configuration.
set -euo pipefail
cd "$(dirname "$0")/.."

config=release
signing=identity
skip_build=0
for arg in "$@"; do
  case "$arg" in
    --unsigned) signing=adhoc ;;
    --skip-build) skip_build=1 ;;
    --debug) config=debug ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ "$skip_build" -eq 0 ]; then
  swift build -c "$config" --product Murmur
fi
bin_dir="$(swift build -c "$config" --show-bin-path)"
[ -x "$bin_dir/Murmur" ] || { echo "error: $bin_dir/Murmur not found; build first" >&2; exit 1; }

app=build/Murmur.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Murmur" "$app/Contents/MacOS/Murmur"

version="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.0.0)"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build_number/" Resources/Info.plist > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# SwiftPM resource bundles from dependencies.
shopt -s nullglob
for bundle in "$bin_dir"/*.bundle; do
  cp -R "$bundle" "$app/Contents/Resources/"
done

# Dynamic frameworks, if any dependency ships one, go in Contents/Frameworks. (No arrays here:
# macOS's bash 3.2 treats an empty array as unbound under `set -u`.)
has_frameworks=0
for framework in "$bin_dir"/*.framework; do
  mkdir -p "$app/Contents/Frameworks"
  cp -R "$framework" "$app/Contents/Frameworks/"
  has_frameworks=1
done
shopt -u nullglob
if [ "$has_frameworks" -eq 1 ]; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/Murmur" 2>/dev/null || true
fi

if [ "$signing" = adhoc ]; then
  identity="-"
else
  identity="${MURMUR_SIGNING_IDENTITY:-$(cat .signing-identity 2>/dev/null || true)}"
  if [ -z "$identity" ] || [ "$identity" = "-" ]; then
    echo "error: no stable signing identity. Run scripts/setup-signing.sh once (or pass --unsigned)." >&2
    exit 1
  fi
fi

if [ -d "$app/Contents/Frameworks" ]; then
  for framework in "$app/Contents/Frameworks"/*.framework; do
    codesign --force --sign "$identity" --options runtime --timestamp=none "$framework"
  done
fi
codesign --force --sign "$identity" --options runtime --timestamp=none \
  --entitlements Resources/Murmur.entitlements "$app"
codesign --verify --strict --verbose=1 "$app"

echo "Built $app ($version, build $build_number, signed with: $identity)"
