#!/usr/bin/env bash
# Compile and run the Copper Kit art generator. Extra arguments are passed through, e.g.
#   Tools/ArtGen/run.sh --only ck04_home_case,AppIcon
#   Tools/ArtGen/run.sh --out /tmp/art --scale 0.3 --ss 1 --preview
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/artgen.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
echo "Compiling ArtGen..."
xcrun swiftc -Ounchecked "$HERE/ArtGen.swift" -o "$BUILD/artgen"
"$BUILD/artgen" --root "$ROOT" "$@"
