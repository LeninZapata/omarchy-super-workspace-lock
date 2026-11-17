.pragma library

// Lo que se le pide a Hyprland mientras se ve la capa: blur fuerte y un submap
// que solo deja pasar los atajos permitidos, cada uno con su acción original.
// Los atajos de Omarchy son funciones Lua (hyprctl binds dice "__lua N"), así
// que la acción se toma del caché del menú de atajos de Omarchy
// (~/.cache/omarchy/keybindings-*.records: "TECLAS → desc\tkind\targ").
// Puro (ES5): solo arma texto Lua; quien lo ejecuta es Service.qml.

var SUBMAP = "swl-locked"
var NAMESPACE = "super-workspace-lock"
var BLUR = { size: 12, passes: 4 }
var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MOD_ALIAS = { CONTROL: "CTRL", META: "SUPER", WIN: "SUPER", MOD4: "SUPER" }

// "super ctrl + l", "SUPER + CTRL + L" → "SUPER + CTRL + L"; null si no es válido.
function normChord(s) {
  if (typeof s !== "string") return null
  var tokens = s.toUpperCase().split(/[\s+]+/).filter(function(t) { return t.length > 0 })
  if (tokens.length === 0) return null
  for (var i = 0; i < tokens.length; i++) {
    if (!/^[A-Z0-9_]+$/.test(tokens[i])) return null
    if (MOD_ALIAS[tokens[i]]) tokens[i] = MOD_ALIAS[tokens[i]]
  }
  var key = tokens[tokens.length - 1]
  var mods = []
  for (var j = 0; j < tokens.length - 1; j++)
    if (MOD_ORDER.indexOf(tokens[j]) !== -1 && mods.indexOf(tokens[j]) === -1) mods.push(tokens[j])
    else if (MOD_ORDER.indexOf(tokens[j]) === -1) return null
  mods.sort(function(a, b) { return MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b) })
  return mods.concat([key]).join(" + ")
}

// Caché de Omarchy → { "SUPER + TAB": { kind: "lua", arg: "hl.dsp.focus(...)" }, ... }
function parseRecords(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var cols = lines[i].split("\t")
    if (cols.length < 3) continue
    var kind = cols[1], arg = cols.slice(2).join("\t")
    if ((kind !== "lua" && kind !== "exec") || arg.length === 0) continue
    var keys = cols[0].split("→")[0]
    var alts = keys.split(" / ")
    for (var j = 0; j < alts.length; j++) {
      var c = normChord(alts[j])
      if (c && !map[c]) map[c] = { kind: kind, arg: arg }
    }
  }
  return map
}

// Texto como cadena larga de Lua, con un nivel de = que no aparezca dentro.
function luaStr(s) {
  var eq = ""
  while (String(s).indexOf("]" + eq + "]") !== -1) eq += "="
  return "[" + eq + "[" + s + "]" + eq + "]"
}

function actionLua(rec) {
  return rec.kind === "exec" ? "hl.dsp.exec_cmd(" + luaStr(rec.arg) + ")" : rec.arg
}

// Una vez (y tras cada recarga de Hyprland): blur sin animación para la capa.
function layerRuleLua() {
  return 'hl.layer_rule({ match = { namespace = "^' + NAMESPACE + '$" }, blur = true, ignore_alpha = 0, no_anim = true })'
}

// Al mostrar la capa. Devuelve { lua, missing } (missing = permitidos sin acción en el caché).
function enterLua(allowed, records) {
  var binds = [], missing = []
  for (var i = 0; i < allowed.length; i++) {
    var c = normChord(allowed[i])
    if (!c) continue
    var rec = records[c]
    if (!rec) { missing.push(c); continue }
    binds.push("pcall(function() hl.bind(" + luaStr(c) + ", " + actionLua(rec) + ") end)")
  }
  var lua = "hl.config({ decoration = { blur = { enabled = true, size = " + BLUR.size + ", passes = " + BLUR.passes + " } } }); "
    + "hl.define_submap(" + luaStr(SUBMAP) + ", function() " + binds.join("; ") + " end); "
    + "hl.dispatch(hl.dsp.submap(" + luaStr(SUBMAP) + "))"
  return { lua: lua, missing: missing }
}

// Al quitar la capa: fuera del submap y el blur como estaba antes.
function exitLua(prev) {
  var p = prev || { enabled: false, size: 8, passes: 1 }
  return "hl.dispatch(hl.dsp.submap(\"reset\")); "
    + "hl.config({ decoration = { blur = { enabled = " + (p.enabled ? "true" : "false")
    + ", size = " + Math.round(Number(p.size) || 8) + ", passes = " + Math.round(Number(p.passes) || 1) + " } } })"
}

// Salida de `hyprctl getoption decoration:blur:{enabled,size,passes} -j` seguidas.
function parseBlurOptions(text) {
  var out = { enabled: false, size: 8, passes: 1 }
  var objs = String(text || "").match(/\{[^{}]*\}/g) || []
  for (var i = 0; i < objs.length; i++) {
    try {
      var o = JSON.parse(objs[i])
      if (o.option === "decoration:blur:enabled") out.enabled = o.bool === true || o.int === 1
      else if (o.option === "decoration:blur:size") out.size = o.int
      else if (o.option === "decoration:blur:passes") out.passes = o.int
    } catch (e) {}
  }
  return out
}

var LOCK_CMD = "omarchy-shell leninzapata.super-workspace-lock lockCurrent"

// Registra el atajo de bloqueo (y suelta los anteriores). Nunca toca bindings.lua:
// vive en Hyprland hasta la próxima recarga, tras la que Service.qml lo repone.
// Devuelve { lua, applied } con los atajos que quedan puestos.
function shortcutLua(chord, previous) {
  var lines = []
  var prev = previous || []
  for (var i = 0; i < prev.length; i++) {
    var p = normChord(prev[i])
    if (p) lines.push("pcall(function() hl.unbind(" + luaStr(p) + ") end)")
  }
  var c = normChord(chord)
  var applied = []
  if (c) {
    lines.push("pcall(function() hl.unbind(" + luaStr(c) + ") end)")
    lines.push("hl.bind(" + luaStr(c) + ", hl.dsp.exec_cmd(" + luaStr(LOCK_CMD) + "), { description = \"Super Workspace Lock: lock this workspace\" })")
    applied.push(c)
  }
  return { lua: lines.join("; "), applied: applied }
}

// Devuelve a Lenin su Hyprland: `reload` repone blur, atajos y reglas, pero NO
// saca del submap (comprobado), así que además se hace submap reset.
var RECOVER_SH = "hyprctl reload >/dev/null; hyprctl dispatch 'hl.dsp.submap(\"reset\")' >/dev/null"

function recoverCmd() { return ["sh", "-c", RECOVER_SH] }

// Vigía para que ninguna capa encierre: si el proceso del shell muere mientras
// Hyprland sigue en el submap, recupera la config de Lenin. Se lanza desacoplado
// al entrar en el submap.
function watchdogCmd(shellPid) {
  var pid = Math.round(Number(shellPid) || 0)
  if (!(pid > 1)) return null
  return ["sh", "-c",
    'pid="$1"; while kill -0 "$pid" 2>/dev/null && [ "$(hyprctl submap)" = "' + SUBMAP + '" ]; do sleep 1; done; '
    + 'if ! kill -0 "$pid" 2>/dev/null && [ "$(hyprctl submap)" = "' + SUBMAP + '" ]; then ' + RECOVER_SH + '; fi',
    "swl-watchdog", String(pid)]
}
