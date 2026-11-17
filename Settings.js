.pragma library

// Ajustes de settings.json: valores por defecto y normalización. Pura (ES5):
// corre en QML y en node (tests/test-settings.mjs). Un valor desconocido o fuera
// de rango cae a su defecto; nunca lanza. Claves y valores: DATOS.md.

var SCHEMA_VERSION = 1

var DEFAULT_ALLOWED = [
  "SUPER + 1", "SUPER + 2", "SUPER + 3", "SUPER + 4", "SUPER + 5",
  "SUPER + 6", "SUPER + 7", "SUPER + 8", "SUPER + 9", "SUPER + 0",
  "SUPER + TAB", "SUPER + SPACE", "SUPER + CTRL + L"
]

function defaults() {
  return {
    schemaVersion: SCHEMA_VERSION,
    lockShortcut: "SUPER + CTRL + SHIFT + L",
    lockedAllowedShortcuts: DEFAULT_ALLOWED.slice(),
    workspaces: {}
  }
}

// Un atajo es MODS + TECLA en mayúsculas, solo letras, números y _ (va dentro de Lua).
function isChord(s) {
  return typeof s === "string" && /^\s*[A-Za-z0-9_]+(\s*\+\s*[A-Za-z0-9_]+)*\s*$/.test(s)
}

function normalize(raw) {
  var d = defaults()
  var src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {}
  var out = { schemaVersion: SCHEMA_VERSION, lockShortcut: d.lockShortcut,
              lockedAllowedShortcuts: d.lockedAllowedShortcuts, workspaces: {} }

  if (src.lockShortcut === "" || isChord(src.lockShortcut)) out.lockShortcut = src.lockShortcut

  if (Array.isArray(src.lockedAllowedShortcuts)) {
    var list = []
    for (var i = 0; i < src.lockedAllowedShortcuts.length; i++) {
      var c = src.lockedAllowedShortcuts[i]
      if (isChord(c) && list.indexOf(c) === -1) list.push(c)
    }
    out.lockedAllowedShortcuts = list
  }

  var ws = (src.workspaces && typeof src.workspaces === "object" && !Array.isArray(src.workspaces)) ? src.workspaces : {}
  for (var key in ws) {
    var id = parseInt(key, 10)
    if (!(id > 0) || String(id) !== String(key)) continue
    var entry = ws[key]
    if (entry && typeof entry === "object" && entry.private === true) out.workspaces[String(id)] = { private: true }
  }
  return out
}

function privateIds(settings) {
  var ids = []
  for (var key in settings.workspaces)
    if (settings.workspaces[key].private) ids.push(parseInt(key, 10))
  return ids.sort(function(a, b) { return a - b })
}

// Devuelve un objeto de ajustes NUEVO con el cambio de `private`.
function withPrivate(settings, id, value) {
  var out = normalize(settings)
  if (value) out.workspaces[String(id)] = { private: true }
  else delete out.workspaces[String(id)]
  return out
}
