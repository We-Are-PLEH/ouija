#!/bin/sh
# Regenera los dos formatos de icono a partir de Resources/icon-source.png.
#
#   Resources/AppIcon.icns              — Finder, Dock y macOS anteriores a 26
#   Resources/Ouija.xcassets/…          — fuente del Assets.car que pide macOS 26
#
# macOS 26 (Tahoe) busca `CFBundleIconName` dentro de un Assets.car para el icono
# de las notificaciones; `CFBundleIconFile` + .icns sigue valiendo para Finder,
# pero la notificacion sale en blanco. Se mantienen los dos.
#
# El .car lo compila `actool`, que va con Xcode completo. Si no lo tienes, lo
# genera el workflow `assets` en un runner de GitHub (ver README).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/Resources/icon-source.png"
SET="$ROOT/build/AppIcon.iconset"
ASSET="$ROOT/Resources/Ouija.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "falta $SRC" >&2; exit 1; }

# --- .icns -------------------------------------------------------------------
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

# --- fuente del asset catalog ------------------------------------------------
mkdir -p "$ASSET"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$SRC" --out "$ASSET/icon_$size.png" >/dev/null
done

cat > "$ROOT/Resources/Ouija.xcassets/Contents.json" <<'JSON'
{
  "info" : { "author" : "ouija", "version" : 1 }
}
JSON

cat > "$ASSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "ouija", "version" : 1 }
}
JSON

echo "icns:    $ROOT/Resources/AppIcon.icns"
echo "xcassets: $ASSET"
echo "El Assets.car se compila aparte con actool (workflow 'assets')."
