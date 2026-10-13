#!/bin/bash
# Publica una versión de Windows. Uso:  ./windows/release.sh 1.1.0
# Sube el tag win-vX.Y.Z; GitHub Actions compila el instalador y lo publica.
set -e
cd "$(dirname "$0")/.."
VER="$1"
[ -z "$VER" ] && { echo "Uso: ./windows/release.sh 1.1.0"; exit 1; }
[ -n "$(git status --porcelain)" ] && { echo "Hay cambios sin commitear. Haz commit primero."; exit 1; }
(cd windows && npm version "$VER" --no-git-tag-version)
git add windows/package.json windows/package-lock.json
git commit -m "TaskOut Windows $VER"
git tag "win-v$VER"
git push origin HEAD "win-v$VER"
echo "✓ Subido win-v$VER — sigue la compilación en la pestaña Actions de GitHub"
