#!/usr/bin/env bash
# Convert illustrator source art (WebP, or PNG/JPEG) into the Copper Kit asset catalog, replacing
# the procedural ArtGen renders.
#
#   Tools/convert_webp_art.sh <source-folder>
#
# For every asset below it looks for <name>.webp (then .png, .jpg, .jpeg) in the
# source folder, converts it with `sips` to PNG (sprites, alpha kept) or JPEG
# (opaque onboarding backgrounds) at the exact catalog size, writes it into
# CopperKit/Assets.xcassets/<name>.imageset/ (overwriting) together with its
# Contents.json, validates the result and prints a summary.
# An optional AppIcon.webp/.png (1024x1024) is flattened to an opaque PNG and written to
# AppIcon.appiconset/AppIcon-1024.png (the appiconset's Contents.json is left untouched).
# Sprites should be transparent PNG/WebP with ~6-8 % margins; onboarding backgrounds must keep the
# bottom 40 % a calm deep-blue gradient for UI text (see Docs/AssetPrompts.md).
# Set CATALOG_DIR to write into a different .xcassets folder (e.g. for a dry run).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="${CATALOG_DIR:-$ROOT/CopperKit/Assets.xcassets}"
JPEG_QUALITY=90

# name:width:height:format
ASSETS=(
  "ck01_onboarding_catalogue:1290:2796:jpeg"
  "ck02_onboarding_prepare:1290:2796:jpeg"
  "ck03_onboarding_return:1290:2796:jpeg"
  "ck04_home_case:1232:1136:png"
  "ck05_copper_hammer:1024:1024:png"
  "ck06_tool_tag:800:1000:png"
  "ck07_blue_tray:1040:880:png"
  "ck08_tool_roll:1120:800:png"
  "ck09_glove_clipboard:800:880:png"
  "ck10_handover_case:960:800:png"
  "ck11_closed_case:1000:900:png"
  "ck12_service_tray:1000:900:png"
)

usage() {
  echo "usage: $(basename "$0") <source-folder>" >&2
  echo "       expects ck01_onboarding_catalogue.webp, ck04_home_case.webp, ... (.png/.jpg also accepted)" >&2
  echo "       optional: AppIcon.webp (1024x1024)" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
SRC="$1"
if [[ ! -d "$SRC" ]]; then
  echo "error: source folder not found: $SRC" >&2
  exit 1
fi
if ! command -v sips >/dev/null 2>&1; then
  echo "error: sips not found (macOS only)" >&2
  exit 1
fi
if [[ ! -d "$CATALOG" ]]; then
  echo "error: asset catalog not found: $CATALOG" >&2
  exit 1
fi

prop() { # prop <file> <key>
  sips -g "$2" "$1" 2>/dev/null | awk -v k="$2" '$1 == k":" { print $2 }'
}

find_src() { # find_src <name> -> path or empty
  local ext
  for ext in webp WEBP png PNG jpg JPG jpeg JPEG; do
    if [[ -f "$SRC/$1.$ext" ]]; then echo "$SRC/$1.$ext"; return; fi
  done
}

aspect_note() { # aspect_note <sw> <sh> <width> <height>
  local sw=$1 sh=$2 width=$3 height=$4
  # warn when the aspect ratio differs by more than 1 % (resampling would distort)
  if (( sw * height * 100 > sh * width * 101 || sh * width * 100 > sw * height * 101 )); then
    echo " [warning: source ${sw}x${sh} has a different aspect ratio, stretched]"
  elif [[ "$sw" != "$width" || "$sh" != "$height" ]]; then
    echo " [resampled from ${sw}x${sh}]"
  fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ckart.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok=0; failed=0
summary=()

for entry in "${ASSETS[@]}"; do
  IFS=: read -r name width height format <<<"$entry"
  src="$(find_src "$name")"
  if [[ -z "$src" ]]; then
    summary+=("MISSING  $name (no $name.webp/.png/.jpg in $SRC)")
    failed=$((failed + 1)); continue
  fi

  sw="$(prop "$src" pixelWidth)"; sh="$(prop "$src" pixelHeight)"
  if [[ -z "$sw" || -z "$sh" ]]; then
    summary+=("FAILED   $name (sips cannot read $(basename "$src"))")
    failed=$((failed + 1)); continue
  fi
  note="$(aspect_note "$sw" "$sh" "$width" "$height")"

  if [[ "$format" == "jpeg" ]]; then ext="jpg"; else ext="png"; fi
  out="$TMP/$name.$ext"
  if [[ "$format" == "jpeg" ]]; then
    sips -s format jpeg -s formatOptions "$JPEG_QUALITY" -z "$height" "$width" "$src" --out "$out" >/dev/null
  else
    sips -s format png -z "$height" "$width" "$src" --out "$out" >/dev/null
  fi

  ow="$(prop "$out" pixelWidth)"; oh="$(prop "$out" pixelHeight)"; alpha="$(prop "$out" hasAlpha)"
  if [[ "$ow" != "$width" || "$oh" != "$height" ]]; then
    summary+=("FAILED   $name (got ${ow}x${oh}, expected ${width}x${height})")
    failed=$((failed + 1)); continue
  fi
  if [[ "$format" == "png" && "$alpha" != "yes" ]]; then
    note="$note [warning: no alpha channel in source]"
  fi
  if [[ "$format" == "jpeg" && "$alpha" == "yes" ]]; then
    summary+=("FAILED   $name (JPEG output unexpectedly has alpha)")
    failed=$((failed + 1)); continue
  fi

  dir="$CATALOG/$name.imageset"
  mkdir -p "$dir"
  # drop stale images (e.g. an old .png when switching formats)
  find "$dir" -maxdepth 1 -type f ! -name Contents.json ! -name "$name.$ext" -delete
  mv -f "$out" "$dir/$name.$ext"
  cat >"$dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$name.$ext",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  bytes="$(stat -f %z "$dir/$name.$ext")"
  summary+=("OK       $name.$ext  ${width}x${height}  alpha=${alpha}  $((bytes / 1024)) KB$note")
  ok=$((ok + 1))
done

# Optional app icon: opaque 1024x1024 PNG (alpha is flattened away by a JPEG round trip).
icon_src="$(find_src AppIcon)"
if [[ -n "$icon_src" ]]; then
  iw="$(prop "$icon_src" pixelWidth)"; ih="$(prop "$icon_src" pixelHeight)"
  if [[ -z "$iw" || -z "$ih" ]]; then
    summary+=("FAILED   AppIcon (sips cannot read $(basename "$icon_src"))")
    failed=$((failed + 1))
  else
    note="$(aspect_note "$iw" "$ih" 1024 1024)"
    sips -s format jpeg -s formatOptions 100 -z 1024 1024 "$icon_src" --out "$TMP/icon.jpg" >/dev/null
    sips -s format png "$TMP/icon.jpg" --out "$TMP/AppIcon-1024.png" >/dev/null
    ia="$(prop "$TMP/AppIcon-1024.png" hasAlpha)"
    idir="$CATALOG/AppIcon.appiconset"
    if [[ ! -f "$idir/Contents.json" ]]; then
      summary+=("FAILED   AppIcon (no $idir/Contents.json; run Tools/ArtGen/run.sh --only AppIcon once)")
      failed=$((failed + 1))
    else
      mv -f "$TMP/AppIcon-1024.png" "$idir/AppIcon-1024.png"
      if ! grep -q '"AppIcon-1024.png"' "$idir/Contents.json"; then
        note="$note [warning: Contents.json does not reference AppIcon-1024.png; run Tools/ArtGen/run.sh --only AppIcon]"
      fi
      summary+=("OK       AppIcon-1024.png  1024x1024  alpha=${ia}$note")
    fi
  fi
fi

echo "Copper Kit art conversion  ($SRC -> $CATALOG)"
for line in "${summary[@]}"; do echo "  $line"; done
echo "Converted $ok of ${#ASSETS[@]} images, failed/missing $failed."
[[ $failed -eq 0 ]]
