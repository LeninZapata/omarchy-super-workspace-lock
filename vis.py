#!/usr/bin/env python3
"""Ventanas invisibles mientras su workspace está bloqueado.

Hyprland anima el cambio de workspace antes de que el plugin se entere: durante esa
transición se veía un instante lo que había detrás. Con las ventanas a opacidad 0 no
hay nada que ver. La opacidad original se guarda y se devuelve tal cual.

  vis.py hide N [N…]   guarda la opacidad de las ventanas de esos workspaces y la pone a 0
  vis.py show N [N…]   devuelve su opacidad a las ventanas que ahora estén en esos workspaces
  vis.py sync [N…]     al arrancar: oculta esos (los bloqueados) y devuelve el resto
  vis.py restore-all   devuelve la opacidad a todas las ventanas guardadas
  vis.py watch         vigía: si el plugin deja de responder con ventanas ocultas, restore-all

Estado: $SWL_HIDDEN o ~/.local/state/omarchy/super-workspace-lock/hidden.json (700/600):
{ "0xADDR": { "ws": 3, "opacity": "1", "opacity_inactive": "0.96", "opacity_fullscreen": "1" } }
"""
import json, os, subprocess, sys, tempfile, time

PROPS = ("opacity", "opacity_inactive", "opacity_fullscreen")
PLUGIN = "leninzapata.super-workspace-lock"


def path():
    return os.environ.get("SWL_HIDDEN") or os.path.expanduser("~/.local/state/omarchy/super-workspace-lock/hidden.json")


def load():
    try:
        data = json.load(open(path(), encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data):
    target = path()
    folder = os.path.dirname(target)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    fd, tmp = tempfile.mkstemp(prefix=".hidden-", dir=folder)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, target)


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def clients():
    try:
        return json.loads(hyprctl("clients", "-j"))
    except ValueError:
        return []


def number(text, fallback="1"):
    text = (text or "").strip()
    try:
        float(text)
        return text
    except ValueError:
        return fallback


def set_props(values):
    """values: [(address, {prop: value})] → un solo hyprctl eval."""
    lines = []
    for addr, props in values:
        for prop, value in props.items():
            lines.append('hl.dispatch(hl.dsp.window.set_prop({ prop = "%s", value = "%s", window = "address:%s" }))'
                         % (prop, value, addr))
    if lines:
        hyprctl("eval", "; ".join(lines))


def plan_hide(data, wins, ids):
    """Lo que hay que guardar y ocultar. Pura: no toca Hyprland. wins: [{address, ws, props}]"""
    data = dict(data)
    targets = []
    for w in wins:
        if w["ws"] not in ids:
            continue
        if w["address"] not in data:          # nunca pisar el original con un 0 ya puesto
            data[w["address"]] = dict({"ws": w["ws"]}, **w["props"])
        else:
            data[w["address"]]["ws"] = w["ws"]
        targets.append(w["address"])
    return data, targets


def plan_show(data, wins, ids):
    """Qué restaurar: las guardadas que ahora estén en esos workspaces; fuera las que ya no existen."""
    alive = {w["address"]: w["ws"] for w in wins}
    data = {a: v for a, v in data.items() if a in alive}
    restore = []
    for addr, saved in list(data.items()):
        if alive[addr] in ids:
            restore.append((addr, {p: saved.get(p, "1") for p in PROPS}))
            del data[addr]
    return data, restore


def window_list(ids=None):
    out = []
    for c in clients():
        ws = c.get("workspace", {}).get("id", 0)
        if ids is not None and ws not in ids:
            continue
        out.append({"address": c["address"], "ws": ws, "props": {}})
    return out


def cmd_hide(ids):
    data = load()
    wins = window_list(ids)
    for w in wins:
        if w["address"] not in data:
            w["props"] = {p: number(hyprctl("getprop", "address:" + w["address"], p)) for p in PROPS}
    data, targets = plan_hide(data, wins, ids)
    save(data)
    set_props([(a, {p: "0" for p in PROPS}) for a in targets])
    if data:
        # El vigía se lanza aquí, con el estado ya guardado (lanzado en paralelo lo
        # encontraba vacío y salía). Si ya hay uno, el flock hace que este salga solo.
        subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "watch"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)


def cmd_show(ids):
    data, restore = plan_show(load(), window_list(), ids)
    set_props(restore)
    save(data)


def cmd_sync(ids):
    wins = window_list()
    data, restore = plan_show(load(), wins, set(w["ws"] for w in wins) - set(ids))
    set_props(restore)
    save(data)
    if ids:
        cmd_hide(ids)


def cmd_restore_all():
    data, restore = plan_show(load(), window_list(), set(w["ws"] for w in window_list()))
    set_props(restore)
    save({})


def plugin_alive():
    r = subprocess.run(["omarchy-shell", PLUGIN, "state"], capture_output=True, text=True, timeout=10)
    return r.returncode == 0 and r.stdout.strip().startswith("{")


def cmd_watch():
    # Uno solo a la vez (flock sobre el propio archivo de estado).
    import fcntl
    os.makedirs(os.path.dirname(path()), mode=0o700, exist_ok=True)
    lock = open(path() + ".watch", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    misses = 0
    while load():
        try:
            misses = 0 if plugin_alive() else misses + 1
        except (OSError, subprocess.SubprocessError):
            misses += 1
        if misses >= 3:                       # ~15 s sin plugin con ventanas ocultas
            with locked_state():
                cmd_restore_all()
            return
        time.sleep(5)


def locked_state():
    """Cerrojo exclusivo para hide/show/restore-all: dos órdenes seguidas no se pisan el estado."""
    import fcntl
    os.makedirs(os.path.dirname(path()), mode=0o700, exist_ok=True)
    f = open(path() + ".lock", "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def main(argv):
    if len(argv) < 2:
        print(__doc__); return 64
    cmd, rest = argv[1], argv[2:]
    os.umask(0o077)
    if cmd == "sync":
        try:
            ids = {int(x) for x in rest if int(x) > 0}
        except ValueError:
            return 64
        with locked_state():
            cmd_sync(ids)
    elif cmd in ("hide", "show"):
        try:
            ids = {int(x) for x in rest if int(x) > 0}
        except ValueError:
            return 64
        with locked_state():
            (cmd_hide if cmd == "hide" else cmd_show)(ids)
    elif cmd == "restore-all":
        with locked_state():
            cmd_restore_all()
    elif cmd == "watch":
        cmd_watch()
    else:
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
