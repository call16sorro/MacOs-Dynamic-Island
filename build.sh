#!/bin/bash
# Compile et empaquette DynamicIsland.app (pas besoin de Xcode).
# Usage : ./build.sh        -> build
#         ./build.sh run    -> build + (re)lance l'app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/DynamicIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DynamicIsland "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Adaptateur MediaRemote (Deezer, navigateurs…) chargé par /usr/bin/perl.
clang -dynamiclib -fobjc-arc -framework Foundation -arch arm64 -arch x86_64 \
    -o "$APP/Contents/Resources/MediaRemoteAdapter.dylib" Helper/MediaRemoteAdapter.m
cp Helper/mediaremote.pl "$APP/Contents/Resources/"
# Signature stable (certificat local « Dynamic Island Dev ») : macOS garde alors les
# autorisations (Accessibilité, Accès complet au disque…) d'une compilation à l'autre.
# Sans ce certificat, signature ad hoc : les autorisations sont à redonner à chaque build.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Dynamic Island Dev"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP/Contents/Resources/MediaRemoteAdapter.dylib"
codesign --force --sign "${IDENTITY:--}" "$APP"
[[ -z "$IDENTITY" ]] && echo "⚠️  Signature ad hoc : certificat « Dynamic Island Dev » introuvable"
echo "✅ $APP"

if [[ "${1:-}" == "run" ]]; then
    pkill -x DynamicIsland 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi
