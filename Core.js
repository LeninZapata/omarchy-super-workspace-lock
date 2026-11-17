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

// Copia del estado con algunos campos cambiados. `pending` = { id: msLímite } de
// los privados en modo retardo que se dejaron y aún no se bloquean.
function make(state, changes) {
  var out = { privateIds: state.privateIds, lockedIds: state.lockedIds,
              previousWorkspaceId: state.previousWorkspaceId, pending: state.pending || {} }
  for (var k in changes) out[k] = changes[k]
  return out
}

function pendingWithout(pending, ids) {
  var out = {}
  for (var k in (pending || {})) if (ids.indexOf(Number(k)) === -1) out[k] = pending[k]
  return out
}

// Al arrancar, todo privado empieza bloqueado: un reinicio no deja nada abierto.
function start(privateIds) {
  var p = uniq(privateIds || [])
  return { privateIds: p, lockedIds: p.slice(), previousWorkspaceId: -1, pending: {} }
}

function isPrivate(state, id) { return state.privateIds.indexOf(Number(id)) !== -1 }
function isLocked(state, id) { return state.lockedIds.indexOf(Number(id)) !== -1 }

// El workspace activo pasó de `fromId` a `toId`: el que se deja, si es privado, se
// bloquea; si tiene retardo (`delays[id]` en segundos), queda pendiente hasta
// nowMs + retardo. Volver a uno pendiente lo deja abierto.
function focusChanged(state, fromId, toId, nowMs, delays) {
  var from = Number(fromId), to = Number(toId)
  var locked = state.lockedIds
  var pending = pendingWithout(state.pending, [to])
  if (from > 0 && from !== to && isPrivate(state, from) && !isLocked(state, from)) {
    var d = delays ? Number(delays[from]) || 0 : 0
    if (d > 0) pending[String(from)] = (Number(nowMs) || 0) + d * 1000
    else locked = uniq(locked.concat([from]))
  }
  return make(state, { lockedIds: locked, previousWorkspaceId: to, pending: pending })
}

// Pasa el tiempo: los pendientes vencidos se bloquean.
function tick(state, nowMs) {
  var due = [], pending = {}
  for (var k in (state.pending || {})) {
    if (state.pending[k] <= nowMs) due.push(Number(k))
    else pending[k] = state.pending[k]
  }
  if (due.length === 0) return state
  return make(state, { lockedIds: uniq(state.lockedIds.concat(due)), pending: pending })
}

function hasPending(state) {
  for (var k in (state.pending || {})) return true
  return false
}

// Marcar o desmarcar privado. No bloquea al marcar: el bloqueo llega al salir.
function setPrivate(state, id, value) {
  var n = Number(id)
  var p = value ? uniq(state.privateIds.concat([n])) : without(state.privateIds, n)
  return make(state, { privateIds: p, pending: value ? state.pending : pendingWithout(state.pending, [n]) })
}

// La clave correcta quita el bloqueo de ese workspace (sigue siendo privado).
function unlockOk(state, id) {
  return make(state, { lockedIds: without(state.lockedIds, Number(id)), pending: pendingWithout(state.pending, [Number(id)]) })
}

// Los privados cambiaron fuera (settings.json recargado). Lo ya bloqueado sigue
// bloqueado aunque deje de ser privado: solo la clave lo abre.
function syncPrivate(state, ids) {
  var p = uniq(ids || [])
  var gone = []
  for (var k in (state.pending || {})) if (p.indexOf(Number(k)) === -1) gone.push(Number(k))
  return make(state, { privateIds: p, pending: pendingWithout(state.pending, gone) })
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

// Bloquear a mano el workspace actual (atajo o IPC). Si es público es un bloqueo
// puntual: no se toca privateIds, así que al desbloquearlo sigue público.
function lockNow(state, id) {
  var n = Number(id)
  if (!(n > 0)) return state
  return make(state, { lockedIds: uniq(state.lockedIds.concat([n])), pending: pendingWithout(state.pending, [n]) })
}

// Se bloqueó la sesión entera: todo privado vuelve a quedar bloqueado.
function sessionLocked(state) {
  return make(state, { lockedIds: uniq(state.lockedIds.concat(state.privateIds)), pending: {} })
}

// ¿Hay algún privado abierto? Solo entonces vale la pena vigilar el lock de sesión.
function hasUnlockedPrivate(state) {
  for (var i = 0; i < state.privateIds.length; i++)
    if (state.lockedIds.indexOf(state.privateIds[i]) === -1) return true
  return false
}
