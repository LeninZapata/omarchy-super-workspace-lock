#!/usr/bin/env python3
"""Suelta el atajo de bloqueo SOLO donde es nuestro.

  binds.py release "SUPER + CTRL + SHIFT + L" [...]

`hl.unbind(tecla)` quita TODO lo que haya en esa tecla, así que antes se lee
`hyprctl binds -j` y solo se suelta una tecla del mapa principal en la que todo lo que hay
lleva nuestra descripción. Si la lista no se puede leer, no se toca nada (sale con 1).
Lo usa Service.qml al cerrarse el plugin, cuando ya no puede esperar una lectura async.
"""
import json, subprocess, sys

DESC = "Super Workspace Lock: lock this workspace"     # = Gate.LOCK_DESC
MODS = ((64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"))


def chord(b):
    mods = [name for bit, name in MODS if int(b.get("modmask") or 0) & bit]
    return " + ".join(mods + [str(b.get("key") or "").upper()])


def owners(text):
    """{ "SUPER + CTRL + L": {"own": n, "foreign": n} } del mapa principal; None si no se lee."""
    try:
        binds = json.loads(text)
    except (TypeError, ValueError):
        return None
    if not isinstance(binds, list):
        return None
    out = {}
    for b in binds:
        if not isinstance(b, dict) or (b.get("submap") or "") != "" or b.get("mouse"):
            continue
        e = out.setdefault(chord(b), {"own": 0, "foreign": 0})
        e["own" if b.get("description") == DESC else "foreign"] += 1
    return out


def releasable(own, chords):
    return [c for c in chords if c in own and own[c]["own"] > 0 and own[c]["foreign"] == 0]


def lua_str(s):
    eq = ""
    while ("]" + eq + "]") in s:
        eq += "="
    return "[" + eq + "[" + s + "]" + eq + "]"


def main(argv):
    if len(argv) < 3 or argv[1] != "release":
        print(__doc__)
        return 64
    r = subprocess.run(["hyprctl", "binds", "-j"], capture_output=True, text=True)
    own = owners(r.stdout) if r.returncode == 0 else None
    if own is None:
        return 1
    chords = releasable(own, argv[2:])
    if chords:
        subprocess.run(["hyprctl", "eval", "; ".join(
            "pcall(function() hl.unbind(%s) end)" % lua_str(c) for c in chords)], capture_output=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
