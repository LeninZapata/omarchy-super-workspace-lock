"""vis.py: el original nunca se pisa con un 0, show restaura solo lo que está en ese workspace."""
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
print("vis ok")
