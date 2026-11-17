#!/usr/bin/env bash
# Cambia al workspace N (Hyprland 0.56: dispatch en Lua) y espera a que sea el activo.
# Uso: tests/ws.sh N   · sale con 1 si no llegó.
set -euo pipefail
n="$1"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$n\" })" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(hyprctl activeworkspace -j | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["id"])')" = "$n" ] && exit 0
  sleep 0.1
done
echo "no se llegó al workspace $n" >&2; exit 1
