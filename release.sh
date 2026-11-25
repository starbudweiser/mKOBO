#!/bin/zsh
# Publie une version de mKOBO : compile (arm64), notarise (Apple), zippe puis crée la release GitHub.
# Usage : VERSION=x.y.z ./release.sh [notes]   — VERSION par défaut : 0.1.0 s'il n'y a encore aucun tag.
set -euo pipefail
cd "$(dirname "$0")"
LAST="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1 | sed 's/^v//')"
VERSION="${VERSION:-${LAST:-0.1.0}}"
TAG="v$VERSION"
DIST="$PWD/dist"
NOTES="${1:-mKOBO $VERSION}"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Modifications non commitées : commiter avant la release." >&2; exit 1; }
! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "La version $TAG existe déjà (VERSION=x.y.z pour une autre)." >&2; exit 1; }

VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
rm -rf "$DIST"; mkdir -p "$DIST"
DIST="$DIST" /Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh mKOBO.app
ASSET="mKOBO-$VERSION-macOS-arm64.zip"
mv "$DIST/mKOBO.zip" "$DIST/$ASSET"
(cd "$DIST" && shasum -a 256 "$ASSET" > "$ASSET.sha256")

git tag "$TAG" && git push -q origin main "$TAG"
gh release create "$TAG" "$DIST/$ASSET" "$DIST/$ASSET.sha256" --title "mKOBO $VERSION" --notes "$NOTES"
