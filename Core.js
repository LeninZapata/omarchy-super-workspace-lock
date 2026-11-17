.pragma library

// Máquina de estado del bloqueo: qué workspaces son privados y cuáles están
// bloqueados. Pura (ES5, sin QML): corre en QML y en node (tests/test-core.mjs).
// Cada transición devuelve un estado NUEVO; nunca muta el que recibe.

function uniq(ids) {
  var out = []
  for (var i = 0; i < ids.length; i++) {
    var id = Number(ids[i])
    if (isFinite(id) && id > 0 && out.indexOf(id) === -1) out.push(id)
  }
  return out.sort(function(a, b) { return a - b })
}

function without(ids, id) {
  return ids.filter(function(x) { return x !== id })
}

// Al arrancar, todo privado empieza bloqueado: un reinicio no deja nada abierto.
function start(privateIds) {
  var p = uniq(privateIds || [])
  return { privateIds: p, lockedIds: p.slice(), previousWorkspaceId: -1 }
}

function isPrivate(state, id) { return state.privateIds.indexOf(Number(id)) !== -1 }
function isLocked(state, id) { return state.lockedIds.indexOf(Number(id)) !== -1 }

// El workspace activo pasó de `fromId` a `toId`: el que se deja, si es privado, se bloquea.
function focusChanged(state, fromId, toId) {
  var from = Number(fromId)
  var locked = state.lockedIds
  if (from > 0 && from !== Number(toId) && isPrivate(state, from) && !isLocked(state, from))
    locked = uniq(locked.concat([from]))
  return { privateIds: state.privateIds, lockedIds: locked, previousWorkspaceId: Number(toId) }
}

// Marcar o desmarcar privado. No bloquea al marcar: el bloqueo llega al salir.
function setPrivate(state, id, value) {
  var n = Number(id)
  var p = value ? uniq(state.privateIds.concat([n])) : without(state.privateIds, n)
  return { privateIds: p, lockedIds: state.lockedIds, previousWorkspaceId: state.previousWorkspaceId }
}

// La clave correcta quita el bloqueo de ese workspace (sigue siendo privado).
function unlockOk(state, id) {
  return { privateIds: state.privateIds, lockedIds: without(state.lockedIds, Number(id)), previousWorkspaceId: state.previousWorkspaceId }
}

// Los privados cambiaron fuera (settings.json recargado). Lo ya bloqueado sigue
// bloqueado aunque deje de ser privado: solo la clave lo abre.
function syncPrivate(state, ids) {
  return { privateIds: uniq(ids || []), lockedIds: state.lockedIds, previousWorkspaceId: state.previousWorkspaceId }
}

// Quitar `private` a un workspace bloqueado se rechaza: sería abrirlo sin clave.
function canSetPrivate(state, id, value) {
  return !!value || !isLocked(state, id)
}

// Workspaces que lista el panel: 1..base siempre, más los que existen por encima
// y los privados (aunque hoy no existan). Ordenados, sin repetir.
function panelIds(existingIds, privateIds, base) {
  var n = base > 0 ? base : 5
  var ids = []
  for (var i = 1; i <= n; i++) ids.push(i)
  return uniq(ids.concat(existingIds || [], privateIds || []))
}

// Segundos que faltan para que faillock deje volver a intentar, a partir de la
// salida de `faillock --user <u>` (líneas "AAAA-MM-DD HH:MM:SS TIPO ORIGEN V|I").
// 0 si no hay bloqueo. deny/unlockSec son los de /etc/pam.d/omarchy-lock-password.
function faillockWait(text, nowMs, deny, unlockSec) {
  var times = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\s+\S+\s+.*\s(V)\s*$/)
    if (!m) continue
    times.push(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime())
  }
  if (times.length < deny) return 0
  times.sort(function(a, b) { return a - b })
  var last = times[times.length - 1]
  var left = Math.ceil((last + unlockSec * 1000 - nowMs) / 1000)
  return left > 0 ? left : 0
}
