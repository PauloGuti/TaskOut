#!/bin/bash
# Publica una versión nueva. Uso:  ./release.sh 1.1.0 "Qué cambió"
# Compila, comprime, firma la actualización (llave privada = tu Llavero), crea el
# appcast.xml y lo sube todo a GitHub Releases. Las apps instaladas se actualizan solas.
set -e
cd "$(dirname "$0")"
VER="$1"; NOTES="${2:-Mejoras y correcciones.}"
[ -z "$VER" ] && { echo "Uso: ./release.sh 1.1.0 \"notas\""; exit 1; }
[ -n "$(git status --porcelain)" ] && { echo "Hay cambios sin commitear. Haz commit primero."; exit 1; }
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

echo "$VER" > VERSION
./build.sh
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent build/TaskOut.app "$OUT/TaskOut-$VER.zip"
SPARKLE=.build-arm64/artifacts/sparkle/Sparkle/bin
"$SPARKLE/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VER/" "$OUT"

git add VERSION && git commit -m "Versión $VER" || true
git tag "v$VER"
git push origin HEAD "v$VER"
gh release create "v$VER" "$OUT/TaskOut-$VER.zip" "$OUT/appcast.xml" --title "TaskOut $VER" --notes "$NOTES"
echo "✓ Publicada v$VER"
