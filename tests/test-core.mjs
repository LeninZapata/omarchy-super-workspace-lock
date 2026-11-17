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

console.log('core ok');
