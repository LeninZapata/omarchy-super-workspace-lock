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
