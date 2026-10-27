#!/bin/bash
# Compila e monta "build/Mouse Fix Pro.app", com o Helper dentro.
#
#   ./scripts/build-app.sh             compila para este Mac
#   ./scripts/build-app.sh --install   compila, copia para /Applications e abre
#
# Variáveis opcionais:
#   UNIVERSAL=1                 binário único para Apple Silicon e Intel (precisa do Xcode completo)
#   SIGN_IDENTITY="Meu Cert"    assina com um certificado seu; sem isso a assinatura é ad-hoc
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)"
fi

APP="build/Mouse Fix Pro.app"
HELPER="$APP/Contents/Library/LoginItems/Mouse Fix Pro Helper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"

# Ícone: gera o .icns a partir do PNG de 1024 px.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

cp "$BIN/MouseFixPro" "$APP/Contents/MacOS/MouseFixPro"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/MouseFixProHelper" "$HELPER/Contents/MacOS/MouseFixProHelper"
cp Resources/Helper-Info.plist "$HELPER/Contents/Info.plist"
cp build/AppIcon.icns "$HELPER/Contents/Resources/AppIcon.icns"

strip -x "$APP/Contents/MacOS/MouseFixPro" "$HELPER/Contents/MacOS/MouseFixProHelper" 2>/dev/null || true

# Assina de dentro para fora: primeiro o Helper, depois o app.
SIGN="${SIGN_IDENTITY:--}"
codesign --force --options runtime --sign "$SIGN" "$HELPER"
codesign --force --options runtime --sign "$SIGN" "$APP"

echo "Pronto: $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MouseFixProHelper 2>/dev/null || true
    pkill -x MouseFixPro 2>/dev/null || true
    rm -rf "/Applications/Mouse Fix Pro.app"
    cp -R "$APP" /Applications/
    open "/Applications/Mouse Fix Pro.app"
    echo "Instalado em /Applications."
fi
