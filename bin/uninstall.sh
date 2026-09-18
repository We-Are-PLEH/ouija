#!/bin/sh
# Retira el LaunchAgent y la app instalada. No toca la configuracion del usuario.
set -eu
LABEL=com.wearepleh.ouija
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/Ouija/Ouija.app"
echo "retirado $LABEL"
