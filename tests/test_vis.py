"""vis.py: el original nunca se pisa con un 0, show restaura solo lo que está en ese workspace."""
import sys; sys.dont_write_bytecode = True
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("vis", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vis.py"))
vis = importlib.util.module_from_spec(spec); spec.loader.exec_module(vis)

orig = {"opacity": "1", "opacity_inactive": "0.96", "opacity_fullscreen": "1"}
wins = [{"address": "0xa", "ws": 3, "props": orig}, {"address": "0xb", "ws": 4, "props": orig}]

data, targets = vis.plan_hide({}, wins, {3})
assert targets == ["0xa"] and data["0xa"]["opacity_inactive"] == "0.96" and "0xb" not in data

# ocultar otra vez (ya está a 0): el original guardado NO cambia
zero = [{"address": "0xa", "ws": 3, "props": {"opacity": "0", "opacity_inactive": "0", "opacity_fullscreen": "0"}}]
data2, _ = vis.plan_hide(data, zero, {3})
assert data2["0xa"]["opacity_inactive"] == "0.96"

# show del 4 no toca el 3; show del 3 lo restaura con sus valores y lo saca del estado
left, restore = vis.plan_show(data2, [{"address": "0xa", "ws": 3}], {4})
assert restore == [] and "0xa" in left
left, restore = vis.plan_show(data2, [{"address": "0xa", "ws": 3}], {3})
assert restore == [("0xa", orig)] and left == {}

# una ventana que se movió de workspace se restaura donde esté ahora; una cerrada se olvida
left, restore = vis.plan_show(data2, [{"address": "0xa", "ws": 5}], {5})
assert restore[0][0] == "0xa"
left, restore = vis.plan_show(data2, [], {3})
assert left == {} and restore == []

assert vis.number("0.96") == "0.96" and vis.number("garbage") == "1"
# sync: lo guardado en un workspace que ya no está bloqueado se devuelve
left, restore = vis.plan_show(data, [{"address": "0xa", "ws": 3}], {3, 4} - {4})
assert restore and left == {}
# restauración comprobada: lo que Hyprland rechaza se queda guardado para reintentar
saved = {"opacity": "1", "opacity_inactive": "0.96", "opacity_fullscreen": "1"}
state = {"0xa": {"opacity": "0", "opacity_inactive": "0", "opacity_fullscreen": "0"},
         "0xb": {"opacity": "0", "opacity_inactive": "0", "opacity_fullscreen": "0"}}
def write_ok_only_b(values):
    for addr, props in values:
        if addr == "0xb": state[addr].update(props)       # 0xa: Hyprland lo rechaza
failed = vis.apply_restore([("0xa", saved), ("0xb", saved)], read=lambda a: state.get(a), write=write_ok_only_b, pause=0)
assert failed == [("0xa", saved)], failed
kept = vis.plan_keep({}, failed, [{"address": "0xa", "ws": 3}, {"address": "0xb", "ws": 3}])
assert kept == {"0xa": dict({"ws": 3}, **saved)}
# una ventana que se cerró mientras tanto no se queda en el estado
assert vis.apply_restore([("0xz", saved)], read=lambda a: None, write=lambda v: None, pause=0) == []
assert vis.plan_keep({}, [("0xz", saved)], []) == {}
# reintento al segundo intento
calls = []
def flaky(values):
    calls.append(1)
    if len(calls) >= 2:
        for addr, props in values: state[addr].update(props)
state["0xa"] = {"opacity": "0", "opacity_inactive": "0", "opacity_fullscreen": "0"}
assert vis.apply_restore([("0xa", saved)], read=lambda a: state.get(a), write=flaky, pause=0) == [] and len(calls) == 2
assert vis.same("1", "1.000000") and not vis.same("0", "1") and not vis.same("garbage", "1")
# vigía: ocultas fuera de un bloqueado = a reintentar
assert vis.strays({"0xa": {}, "0xb": {}}, [{"address": "0xa", "ws": 3}, {"address": "0xb", "ws": 4}], {3}) == {4}
# lista de ventanas ilegible: NO se olvida nada (antes: [] y se borraba todo)
import tempfile, json as _json
tmp = tempfile.mkdtemp()
os.environ["SWL_HIDDEN"] = os.path.join(tmp, "hidden.json")
saved_state = {"0xa": dict({"ws": 3}, **saved)}
vis.save(saved_state)
real_clients, real_set = vis.clients, vis.set_props
vis.clients = lambda: None
vis.set_props = lambda v: (_ for _ in ()).throw(AssertionError("no debe tocar Hyprland"))
assert vis.window_list() is None
vis.cmd_show({3}); vis.cmd_sync(set()); vis.cmd_restore_all()
assert vis.load() == saved_state, vis.load()
vis.clients, vis.set_props = real_clients, real_set
print("vis ok")
