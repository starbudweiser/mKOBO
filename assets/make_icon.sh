#!/bin/zsh
# Fabrique mKOBO_1024.png puis mKOBO.icns (iconutil).
set -euo pipefail
cd "$(dirname "$0")"
swiftc -o /tmp/mkobo_make_icon make_icon.swift
/tmp/mkobo_make_icon mKOBO_1024.png
SET="$(mktemp -d)/mKOBO.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s mKOBO_1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) mKOBO_1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o mKOBO.icns
echo "OK : mKOBO.icns"
