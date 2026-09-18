#!/bin/sh
# Compila Ouija.app en build/.
#
# Sin Makefile a proposito: el make de macOS es 3.81, sin .RECIPEPREFIX, y un
# script se lee mejor que una receta con tabuladores invisibles.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/Ouija.app"

command -v swiftc >/dev/null || { echo "falta swiftc: instala las Command Line Tools" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -swift-version 5: la concurrencia estricta de Swift 6 no aporta nada a un
# agente de un solo hilo y si mucho ruido de compilacion.
swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/Ouija" "$ROOT"/Sources/Ouija/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# PkgInfo: lo pone Xcode siempre y algunos servicios del sistema lo esperan.
printf "APPL????" > "$APP/Contents/PkgInfo"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# macOS 26 saca de aqui el icono de las notificaciones; el .icns solo cubre Finder.
cp "$ROOT/Resources/Assets.car" "$APP/Contents/Resources/Assets.car"
# El script de foco viaja dentro del bundle: la app es autocontenida y no
# depende de que el repo siga en su sitio.
cp "$ROOT/bin/ouija-focus" "$APP/Contents/Resources/ouija-focus"
chmod +x "$APP/Contents/Resources/ouija-focus"

# Firma ad-hoc: UNUserNotificationCenter exige un bundle firmado.
codesign --force --sign - "$APP"

echo "build: $APP"
