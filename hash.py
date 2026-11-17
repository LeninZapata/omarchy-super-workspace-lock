#!/usr/bin/env python3
"""Claves propias por workspace (passwords.json) con scrypt.

La clave llega SIEMPRE por stdin (una línea), nunca por argumento: un argumento
se ve en `ps`. Nunca se escribe en claro ni se imprime.

  hash.py set <id>     lee la clave de stdin y guarda salt + hash   (exit 0)
  hash.py verify <id>  lee la clave de stdin: 0 = coincide, 1 = no, 2 = sin clave propia
  hash.py remove <id>  quita la clave propia de ese workspace          (exit 0)
  hash.py has <id>     0 = tiene clave propia, 2 = no

Ruta: $SWL_PASSWORDS o ~/.config/omarchy/super-workspace-lock/passwords.json (600).
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import tempfile

N, R, P = 2 ** 15, 8, 1
MAXMEM = 64 * 1024 * 1024
SCHEMA_VERSION = 1


def path():
    return os.environ.get("SWL_PASSWORDS") or os.path.expanduser(
        "~/.config/omarchy/super-workspace-lock/passwords.json")


def load():
    try:
        with open(path(), encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("entries"), dict):
            return data
    except (OSError, ValueError):
        pass
    return {"schemaVersion": SCHEMA_VERSION, "entries": {}}


def save(data):
    # Escritura atómica y solo para el dueño: el temporal nace en 600 en la misma carpeta.
    target = path()
    folder = os.path.dirname(target)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    fd, tmp = tempfile.mkstemp(prefix=".passwords-", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, target)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def derive(password, salt, n=N, r=R, p=P):
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=n, r=r, p=p, maxmem=MAXMEM, dklen=32)


def read_password():
    line = sys.stdin.readline()
    return line[:-1] if line.endswith("\n") else line


def workspace_id(arg):
    n = int(arg)
    if n <= 0:
        raise ValueError
    return str(n)


def main(argv):
    if len(argv) != 3 or argv[1] not in ("set", "verify", "remove", "has"):
        sys.stderr.write("usage: hash.py set|verify|remove|has <workspace-id>\n")
        return 64
    try:
        wid = workspace_id(argv[2])
    except ValueError:
        sys.stderr.write("invalid workspace id\n")
        return 64
    os.umask(0o077)
    data = load()
    entries = data["entries"]
    cmd = argv[1]

    if cmd == "has":
        return 0 if wid in entries else 2
    if cmd == "remove":
        if entries.pop(wid, None) is not None:
            save(data)
        return 0
    if cmd == "set":
        password = read_password()
        if not password:
            sys.stderr.write("empty password\n")
            return 65
        salt = os.urandom(16)
        entries[wid] = {
            "algo": "scrypt", "n": N, "r": R, "p": P,
            "salt": base64.b64encode(salt).decode("ascii"),
            "hash": base64.b64encode(derive(password, salt)).decode("ascii"),
        }
        data["schemaVersion"] = SCHEMA_VERSION
        save(data)
        return 0
    # verify
    entry = entries.get(wid)
    password = read_password()
    if not isinstance(entry, dict) or entry.get("algo") != "scrypt":
        return 2
    try:
        salt = base64.b64decode(entry["salt"])
        expected = base64.b64decode(entry["hash"])
        got = derive(password, salt, int(entry.get("n", N)), int(entry.get("r", R)), int(entry.get("p", P)))
    except (KeyError, ValueError, TypeError):
        return 2
    return 0 if hmac.compare_digest(got, expected) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
