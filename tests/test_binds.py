"""binds.py: al cerrarse el plugin solo se suelta una tecla que es solo nuestra."""
import sys; sys.dont_write_bytecode = True
import importlib.util, json, os
spec = importlib.util.spec_from_file_location("binds", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "binds.py"))
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)

D = b.DESC
text = json.dumps([
    {"modmask": 69, "key": "L", "description": D, "submap": ""},          # nuestra, sola
    {"modmask": 65, "key": "L", "description": D, "submap": ""},          # nuestra, pero comparte
    {"modmask": 65, "key": "L", "description": "otra cosa", "submap": ""},
    {"modmask": 68, "key": "L", "description": "Lock system", "submap": ""},
    {"modmask": 64, "key": "K", "description": "", "submap": "swl-locked"},  # submap propio: no cuenta
    {"modmask": 73, "key": "R", "description": D, "submap": ""},          # nuestra en el principal...
    {"modmask": 73, "key": "R", "description": "Resize", "submap": "resize"},  # ...y ajena en otro submap
])
own = b.owners(text)
assert own["SUPER + CTRL + SHIFT + L"] == {"own": 1, "foreign": 0}
assert own["SUPER + SHIFT + L"] == {"own": 1, "foreign": 1}
assert "SUPER + K" not in own
assert own["SUPER + ALT + SHIFT + R"] == {"own": 1, "foreign": 1}
assert b.releasable(own, ["SUPER + CTRL + SHIFT + L", "SUPER + SHIFT + L", "SUPER + CTRL + L", "SUPER + ALT + Z", "SUPER + ALT + SHIFT + R"]) == ["SUPER + CTRL + SHIFT + L"]
assert b.owners("") is None and b.owners("{}") is None
assert b.lua_str("a]]b") == "[=[a]]b]=]"
print("binds ok")
