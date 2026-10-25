#!/bin/bash
# Compila e monta "build/MouseFix Lite.app".
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

APP="build/MouseFix Lite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MouseFixLite" "$APP/Contents/MacOS/MouseFixLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/MouseFixLite" 2>/dev/null || true
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Pronto: $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MouseFixLite 2>/dev/null || true
    rm -rf "/Applications/MouseFix Lite.app"
    cp -R "$APP" /Applications/
    open "/Applications/MouseFix Lite.app"
    echo "Instalado em /Applications."
fi
