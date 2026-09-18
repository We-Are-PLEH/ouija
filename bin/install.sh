#!/bin/sh
# Instala Ouija.app y su LaunchAgent.
#
# La app se copia a ~/Library/Application Support/Ouija/ y NO se ejecuta desde el
# repo: launchd no puede leer segun que rutas (CloudStorage, volumenes externos)
# y el repo puede moverse de sitio.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX="$HOME/Library/Application Support/Ouija"
LABEL=com.wearepleh.ouija
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[ -d "$ROOT/build/Ouija.app" ] || "$ROOT/bin/build.sh"

mkdir -p "$PREFIX" "$HOME/Library/Logs/Ouija" "$HOME/Library/LaunchAgents"

# Parar antes de sustituir el binario: si no, launchd reinicia el viejo.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

rm -rf "$PREFIX/Ouija.app"
cp -R "$ROOT/build/Ouija.app" "$PREFIX/Ouija.app"

sed -e "s|__PREFIX__|$PREFIX|g" -e "s|__HOME__|$HOME|g" \
  "$ROOT/launchd/$LABEL.plist.in" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

# Registrar en LaunchServices: sin esto, `open ouija://…` no sabe quien atiende
# el esquema, porque la app no vive en /Applications.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$PREFIX/Ouija.app" || true

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "instalado: $PREFIX/Ouija.app"
echo "log:       $HOME/Library/Logs/Ouija/ouija.log"
