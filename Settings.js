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

var PASSWORD_MODES = ["system", "own"]

function defaults() {
  return {
    schemaVersion: SCHEMA_VERSION,
    lockShortcut: "SUPER + CTRL + SHIFT + L",
    lockedAllowedShortcuts: DEFAULT_ALLOWED.slice(),
    defaults: { passwordMode: "system" },
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
              lockedAllowedShortcuts: d.lockedAllowedShortcuts,
              defaults: { passwordMode: d.defaults.passwordMode }, workspaces: {} }

  var sd = (src.defaults && typeof src.defaults === "object" && !Array.isArray(src.defaults)) ? src.defaults : {}
  if (PASSWORD_MODES.indexOf(sd.passwordMode) !== -1) out.defaults.passwordMode = sd.passwordMode

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
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    // Un campo ausente es «heredar» de defaults; solo se guarda lo que difiere.
    var clean = {}
    if (entry.private === true) clean.private = true
    if (PASSWORD_MODES.indexOf(entry.passwordMode) !== -1) clean.passwordMode = entry.passwordMode
    for (var k in clean) { out.workspaces[String(id)] = clean; break }
  }
  return out
}

function privateIds(settings) {
  var ids = []
  for (var key in settings.workspaces)
    if (settings.workspaces[key].private) ids.push(parseInt(key, 10))
  return ids.sort(function(a, b) { return a - b })
}

// Devuelve un objeto de ajustes NUEVO con un campo del workspace cambiado.
// value null/undefined = «heredar» (se borra el campo).
function withWorkspaceField(settings, id, field, value) {
  var out = normalize(settings)
  var key = String(id)
  var entry = {}
  var cur = out.workspaces[key] || {}
  for (var k in cur) entry[k] = cur[k]
  if (value === null || value === undefined || value === false) delete entry[field]
  else entry[field] = value
  out.workspaces[key] = entry
  out = normalize(out)
  return out
}

function withPrivate(settings, id, value) {
  return withWorkspaceField(settings, id, "private", value ? true : null)
}

// Configuración efectiva de un workspace: lo suyo o, si falta, lo de defaults.
function effective(settings, id) {
  var s = normalize(settings)
  var w = s.workspaces[String(id)] || {}
  return {
    private: w.private === true,
    passwordMode: w.passwordMode || s.defaults.passwordMode
  }
}
