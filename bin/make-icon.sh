#!/bin/sh
# Regenera Resources/AppIcon.icns a partir de Resources/icon-source.png.
#
# El icono del bundle es lo que macOS pone en cada notificacion junto al nombre
# de la app: es la identidad del emisor. Se versiona el .icns ya montado para que
# compilar no dependa de tener el original a mano.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/Resources/icon-source.png"
SET="$ROOT/build/AppIcon.iconset"

[ -f "$SRC" ] || { echo "falta $SRC" >&2; exit 1; }

rm -rf "$SET"
mkdir -p "$SET"
# Los nombres son los que exige iconutil; cualquier otro se ignora en silencio.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$SET"
echo "icono: $ROOT/Resources/AppIcon.icns"
