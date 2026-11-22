// Máquina de estado (Core.js): arranque, salir, marcar privado, desbloquear.
import assert from 'node:assert/strict';
import { loadLib } from './harness.mjs';

const C = loadLib('Core.js');
const plain = s => JSON.parse(JSON.stringify(s));

// arranque: privados bloqueados, ids saneados y ordenados
let s = C.start([3, '2', 2, 0, -1, 'x']);
assert.deepEqual(plain(s), { privateIds: [2, 3], lockedIds: [2, 3], previousWorkspaceId: -1, pending: {} });

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

// faillock: 10 fallos válidos → espera hasta último + 120 s
const fl = n => ['leninzapata:', 'When                Type  Source                                           Valid']
  .concat(Array.from({ length: n }, (_, i) => `2026-11-17 14:30:${String(i).padStart(2, '0')} RHOST                                                 V`)).join('\n');
const last = new Date(2026, 10, 17, 14, 30, 9).getTime();
assert.equal(C.faillockWait(fl(9), last, 10, 120), 0);
assert.equal(C.faillockWait(fl(10), last + 20000, 10, 120), 100);
assert.equal(C.faillockWait(fl(10), last + 121000, 10, 120), 0);
assert.equal(C.faillockWait(fl(10).replace(/ V$/gm, ' I'), last, 10, 120), 0);
assert.equal(C.faillockWait('', last, 10, 120), 0);

// bloqueo puntual: un público se bloquea ya y al desbloquear sigue público
let q = C.start([]);
q = C.lockNow(q, 4);
assert.deepEqual(plain(q.lockedIds), [4]);
assert.equal(C.isPrivate(q, 4), false);
q = C.unlockOk(q, 4);
assert.deepEqual(plain(q.lockedIds), []);
assert.equal(C.isPrivate(q, 4), false);
assert.deepEqual(plain(C.lockNow(q, -1)), plain(q));

// lock de sesión: vuelven a bloquearse todos los privados; los puntuales siguen
let z = C.unlockOk(C.unlockOk(C.start([2, 3]), 2), 3);
z = C.lockNow(z, 5);
assert.equal(C.hasUnlockedPrivate(z), true);
z = C.sessionLocked(z);
assert.deepEqual(plain(z.lockedIds), [2, 3, 5]);
assert.equal(C.hasUnlockedPrivate(z), false);
assert.equal(C.hasUnlockedPrivate(C.start([])), false);

// retardo: salir deja pendiente; volver antes lo limpia; vencido → bloqueado
let d = C.setPrivate(C.start([]), 4, true);
d = C.focusChanged(d, 4, 1, 1000, { 4: 10 });
assert.deepEqual(plain(d.lockedIds), []);
assert.deepEqual(plain(d.pending), { '4': 11000 });
assert.equal(C.hasPending(d), true);
assert.equal(C.tick(d, 5000), d, 'sin vencidos no cambia');
let back = C.focusChanged(d, 1, 4, 6000, { 4: 10 });
assert.deepEqual(plain(back.pending), {}, 'volver antes de tiempo lo deja abierto');
assert.deepEqual(plain(back.lockedIds), []);
d = C.tick(d, 11000);
assert.deepEqual(plain(d.lockedIds), [4]);
assert.deepEqual(plain(d.pending), {});
// sin retardo sigue siendo inmediato
assert.deepEqual(plain(C.focusChanged(C.setPrivate(C.start([]), 4, true), 4, 1, 0, {}).lockedIds), [4]);
// el lock de sesión vacía los pendientes y bloquea
let sp = C.focusChanged(C.setPrivate(C.start([]), 4, true), 4, 1, 0, { 4: 30 });
sp = C.sessionLocked(sp);
assert.deepEqual(plain(sp.lockedIds), [4]);
assert.deepEqual(plain(sp.pending), {});
// dejar de ser privado quita su pendiente
assert.deepEqual(plain(C.syncPrivate(C.focusChanged(C.setPrivate(C.start([]), 4, true), 4, 1, 0, { 4: 30 }), []).pending), {});

// inactividad: solo privados abiertos con plazo cumplido; "wait" aparte (depende del audio)
let ist = C.setPrivate(C.setPrivate(C.setPrivate(C.start([]), 2, true), 3, true), 4, true);
ist = C.unlockOk(C.unlockOk(C.unlockOk(ist, 2), 3), 4);
ist = C.lockNow(ist, 4);
const targets = { 2: { seconds: 60, audio: 'lock' }, 3: { seconds: 300, audio: 'wait' }, 4: { seconds: 60, audio: 'lock' } };
assert.deepEqual(plain(C.idleDue(ist, targets, 59000)), { lock: [], wait: [] });
assert.deepEqual(plain(C.idleDue(ist, targets, 60000)), { lock: [2], wait: [] }, '4 ya está bloqueado');
assert.deepEqual(plain(C.idleDue(ist, targets, 300000)), { lock: [2], wait: [3] });
assert.deepEqual(plain(C.idleDue(ist, {}, 999999)), { lock: [], wait: [] });
assert.deepEqual(plain(C.idleDue(ist, targets, 0)), { lock: [], wait: [] });
assert.deepEqual(plain(C.lockMany(ist, [2, 3]).lockedIds).sort(), [2, 3, 4]);

console.log('core ok');
