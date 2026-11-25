#!/bin/zsh
# Construit mKOBO.app : signée par le certificat local stable puis installée dans ~/Applications/Applications Personnelles.
#   DEV=1       : édition de développement « mKOBO DEV.app » (bundle id …dev, données à part), dans le dossier du projet, non installée.
#   NO_INSTALL=1 : ne pas installer.   UNIVERSAL=1 : arm64 + x86_64 (publication).   VERSION=x.y.z : version.
set -euo pipefail
cd "$(dirname "$0")"
TOOLS=/Volumes/SKYRIM/TOOLS
VERSION="${VERSION:-$( (git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null || true) | head -1 | sed 's/^v//')}"
VERSION="${VERSION:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
if [ -n "${DEV:-}" ]; then APP="mKOBO DEV.app"; ID="fr.stephan.mkobo.dev"; NAME="mKOBO DEV"; OPT=(-Onone -g); else APP="mKOBO.app"; ID="fr.stephan.mkobo"; NAME="mKOBO"; OPT=(-O); fi
DEST="${MKOBO_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"

# fichiers communs : Socle et mise à jour automatique, recopiés à chaque build
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/Socle.swift
[ -f "$TOOLS/DESIGN/Socle/swift/FlatRoundSheet.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/FlatRoundSheet.swift" Sources/FlatRoundSheet.swift
for f in Updater.swift UpdaterView.swift; do [ -f "$TOOLS/MAC/_tools/shared/$f" ] && cp "$TOOLS/MAC/_tools/shared/$f" Sources/$f; done
[ -f assets/mKOBO.icns ] || ./assets/make_icon.sh

rm -rf "${APP:?}" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
ARCHS=(arm64); [ -n "${UNIVERSAL:-}" ] && ARCHS=(arm64 x86_64)
for arch in $ARCHS; do
  swiftc $OPT -swift-version 5 -parse-as-library -target $arch-apple-macos14.0 -o build/mKOBO-$arch Sources/*.swift
done
if [ ${#ARCHS[@]} -gt 1 ]; then lipo -create build/mKOBO-arm64 build/mKOBO-x86_64 -output "$APP/Contents/MacOS/mKOBO"; else cp build/mKOBO-arm64 "$APP/Contents/MacOS/mKOBO"; fi

sed -e "s/__ID__/$ID/g" -e "s/__NAME__/$NAME/g" -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp assets/mKOBO.icns "$APP/Contents/Resources/AppIcon.icns"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
[ -f Resources/kepubify ] && cp Resources/kepubify "$APP/Contents/Resources/kepubify"
rm -rf build

SIGN="$TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi
echo "OK : $APP"

if [ -z "${DEV:-}" ] && [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  osascript -e "tell application id \"$ID\" to quit" 2>/dev/null || true
  rm -rf "${DEST:?}/${APP:?}"
  cp -R "$APP" "$DEST/"
  echo "Installée : $DEST/$APP"
fi
