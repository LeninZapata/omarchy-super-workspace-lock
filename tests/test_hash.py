"""hash.py: set/verify/remove/has, permisos 600 y la clave nunca en claro."""
import json
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HASH = os.path.join(HERE, "..", "hash.py")


def run(cmd, wid, stdin=""):
    return subprocess.run([sys.executable, "-I", HASH, cmd, str(wid)], input=stdin, text=True,
                          capture_output=True, env={**os.environ, "SWL_PASSWORDS": FILE}).returncode


with tempfile.TemporaryDirectory() as d:
    FILE = os.path.join(d, "swl", "passwords.json")
    assert run("has", 4) == 2
    assert run("verify", 4, "x\n") == 2, "sin clave propia"
    assert run("set", 4, "test-swl-clave\n") == 0
    raw = open(FILE).read()
    assert "test-swl-clave" not in raw, "la clave no se guarda en claro"
    entry = json.loads(raw)["entries"]["4"]
    assert entry["algo"] == "scrypt" and entry["salt"] and entry["hash"]
    assert stat.S_IMODE(os.stat(FILE).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(os.path.dirname(FILE)).st_mode) == 0o700
    assert run("has", 4) == 0
    assert run("verify", 4, "test-swl-clave\n") == 0
    assert run("verify", 4, "test-swl-clavE\n") == 1
    assert run("verify", 4, "\n") == 1
    assert run("set", 4, "\n") == 65, "clave vacía rechazada"
    # misma clave, otra sal: hashes distintos
    run("set", 5, "test-swl-clave\n")
    e = json.load(open(FILE))["entries"]
    assert e["4"]["hash"] != e["5"]["hash"]
    assert run("remove", 4) == 0 and run("has", 4) == 2 and run("has", 5) == 0
    assert run("verify", 0, "x\n") == 64 and run("set", "abc", "x\n") == 64
    # archivo roto: se trata como vacío, no rompe
    open(FILE, "w").write("{roto")
    assert run("verify", 5, "x\n") == 2

print("hash ok")
