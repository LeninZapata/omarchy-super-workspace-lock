#!/usr/bin/env bash
# Captura la capa de bloqueo, recortada a su geometría (namespace propio).
# Uso: tests/shot.sh [salida.png]  · sale con 2 si la capa no está visible.
set -euo pipefail
out="${1:-/tmp/swl-shot.png}"
geom=$(hyprctl layers -j | python3 -I -c '
import json, sys
for mon in json.load(sys.stdin).values():
    for level in mon.get("levels", {}).values():
        for l in level:
            if l.get("namespace") == "super-workspace-lock":
                print("%d,%d %dx%d" % (l["x"], l["y"], l["w"], l["h"])); sys.exit()
')
if [ -z "$geom" ]; then echo "no hay capa visible (namespace super-workspace-lock)"; exit 2; fi
grim -g "$geom" "$out"
echo "$out ($geom)"
