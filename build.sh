#!/bin/bash
# Compila TaskOut (Apple Silicon + Intel) y arma build/TaskOut.app
#   ./build.sh            -> solo compila
#   ./build.sh install    -> además copia a /Applications y la abre
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
# Binario universal (Apple Silicon + Intel) sin necesitar Xcode: una carpeta de compilación por
# arquitectura + lipo
BIN_ARM=.build-arm64/release
BIN_X86=.build-x86_64/release
swift build -c release --scratch-path .build-arm64 --triple arm64-apple-macosx
swift build -c release --scratch-path .build-x86_64 --triple x86_64-apple-macosx
BIN="$BIN_ARM"
APP=build/TaskOut.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "$BIN_ARM/TaskOut" "$BIN_X86/TaskOut" -output "$APP/Contents/MacOS/TaskOut"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
# Firma ad-hoc (sin cuenta de desarrollador). Primero Sparkle por dentro, al final la app.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "✓ $APP  (v$VERSION)"
if [ "$1" = "install" ]; then
  pkill -x TaskOut 2>/dev/null || true
  sleep 1
  rm -rf /Applications/TaskOut.app
  cp -R "$APP" /Applications/TaskOut.app
  open /Applications/TaskOut.app
  echo "✓ instalada en /Applications"
fi
