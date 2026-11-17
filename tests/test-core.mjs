// Máquina de estado (Core.js): arranque, salir, marcar privado, desbloquear.
import assert from 'node:assert/strict';
import { loadLib } from './harness.mjs';

const C = loadLib('Core.js');
const plain = s => JSON.parse(JSON.stringify(s));

// arranque: privados bloqueados, ids saneados y ordenados
let s = C.start([3, '2', 2, 0, -1, 'x']);
assert.deepEqual(plain(s), { privateIds: [2, 3], lockedIds: [2, 3], previousWorkspaceId: -1 });

// marcar privado no bloquea; salir de él sí
s = C.start([]);
s = C.setPrivate(s, 2, true);
assert.deepEqual(plain(s.lockedIds), []);
s = C.focusChanged(s, 2, 1);
assert.deepEqual(plain(s.lockedIds), [2]);
assert.equal(s.previousWorkspaceId, 1);
assert.equal(C.isLocked(s, 2), true);

// salir de uno público no bloquea nada
s = C.focusChanged(s, 1, 2);
assert.deepEqual(plain(s.lockedIds), [2]);

// desbloquear lo saca de la lista pero sigue privado; volver a salir lo bloquea
s = C.unlockOk(s, 2);
assert.deepEqual(plain(s.lockedIds), []);
assert.equal(C.isPrivate(s, 2), true);
s = C.focusChanged(s, 2, 3);
assert.deepEqual(plain(s.lockedIds), [2]);

// el estado de entrada no se muta
const before = C.start([4]);
C.unlockOk(before, 4);
assert.deepEqual(plain(before.lockedIds), [4]);

// quitar private a uno bloqueado se rechaza; a uno abierto, no
let r = C.start([5]);
assert.equal(C.canSetPrivate(r, 5, false), false);
assert.equal(C.canSetPrivate(r, 5, true), true);
r = C.unlockOk(r, 5);
assert.equal(C.canSetPrivate(r, 5, false), true);

// recargar ajustes no abre lo bloqueado aunque ya no sea privado
r = C.syncPrivate(C.start([6]), [7]);
assert.deepEqual(plain(r.privateIds), [7]);
assert.deepEqual(plain(r.lockedIds), [6]);

// lista del panel: 1-5 + existentes por encima + privados; nada de especiales (id < 0)
assert.deepEqual(plain(C.panelIds([1, 3, 7, -98], [9], 5)), [1, 2, 3, 4, 5, 7, 9]);
assert.deepEqual(plain(C.panelIds([], [], 5)), [1, 2, 3, 4, 5]);

console.log('core ok');
