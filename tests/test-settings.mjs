// Settings.js: defectos, normalización y cambio de private.
import assert from 'node:assert/strict';
import { loadLib } from './harness.mjs';

const S = loadLib('Settings.js');
const plain = x => JSON.parse(JSON.stringify(x));

const d = plain(S.defaults());
assert.equal(d.lockShortcut, 'SUPER + CTRL + SHIFT + L');
assert.ok(d.lockedAllowedShortcuts.includes('SUPER + TAB'));
assert.ok(d.lockedAllowedShortcuts.includes('SUPER + SPACE'));

// basura → defectos, sin lanzar
for (const raw of [null, 7, 'x', [], { workspaces: [] }]) assert.deepEqual(plain(S.normalize(raw)), d);

// valores inválidos caen a su defecto; los válidos se quedan
let n = plain(S.normalize({ lockShortcut: 'rm -rf; x', lockedAllowedShortcuts: ['SUPER + 1', 'bad;', 'SUPER + 1', 3],
  workspaces: { '2': { private: true }, '3': { private: 'yes' }, 'x': { private: true }, '04': { private: true }, '-1': { private: true } } }));
assert.equal(n.lockShortcut, d.lockShortcut);
assert.deepEqual(n.lockedAllowedShortcuts, ['SUPER + 1']);
assert.deepEqual(n.workspaces, { '2': { private: true } });
assert.equal(plain(S.normalize({ lockShortcut: '' })).lockShortcut, '');

// private
let s = S.withPrivate(S.defaults(), 3, true);
s = S.withPrivate(s, 1, true);
assert.deepEqual(plain(S.privateIds(s)), [1, 3]);
s = S.withPrivate(s, 3, false);
assert.deepEqual(plain(S.privateIds(s)), [1]);

// passwordMode: por workspace y por defecto; «heredar» = campo ausente
let pm = S.normalize({ defaults: { passwordMode: 'own' }, workspaces: { '4': { passwordMode: 'system' }, '5': { passwordMode: 'raro', private: true } } });
assert.equal(pm.defaults.passwordMode, 'own');
assert.deepEqual(plain(pm.workspaces), { '4': { passwordMode: 'system' }, '5': { private: true } });
assert.equal(S.effective(pm, 4).passwordMode, 'system');
assert.equal(S.effective(pm, 5).passwordMode, 'own', 'hereda de defaults');
assert.equal(S.effective(pm, 9).private, false);
let w = S.withWorkspaceField(S.defaults(), 3, 'passwordMode', 'own');
assert.deepEqual(plain(w.workspaces), { '3': { passwordMode: 'own' } });
w = S.withPrivate(w, 3, true);
w = S.withWorkspaceField(w, 3, 'passwordMode', null);
assert.deepEqual(plain(w.workspaces), { '3': { private: true } });
assert.deepEqual(plain(S.withPrivate(w, 3, false).workspaces), {});
assert.equal(S.normalize({ defaults: { passwordMode: 'x' } }).defaults.passwordMode, 'system');

// retardo: rangos 5..3600 enteros; heredar de defaults; delays() solo de privados en delay
let dl = S.normalize({ defaults: { lockMode: 'delay', delaySeconds: 30 },
  workspaces: { '2': { private: true }, '3': { private: true, lockMode: 'immediate' }, '4': { private: true, delaySeconds: 10 },
                '5': { lockMode: 'delay', delaySeconds: 4 }, '6': { private: true, delaySeconds: 99999 } } });
assert.deepEqual(plain(dl.workspaces['5']), { lockMode: 'delay' }, 'delay fuera de rango se descarta');
assert.deepEqual(plain(S.delays(dl)), { '2': 30, '4': 10, '6': 30 });
assert.equal(S.effective(dl, 3).lockMode, 'immediate');
assert.equal(S.normalize({ defaults: { delaySeconds: 2.5 } }).defaults.delaySeconds, 60);

// atajos permitidos: añadir sin repetir, quitar, y nada inválido
let al = S.withAllowed(S.defaults(), 'SUPER + F', true);
assert.ok(al.lockedAllowedShortcuts.includes('SUPER + F'));
assert.equal(S.withAllowed(al, 'SUPER + F', true).lockedAllowedShortcuts.filter(c => c === 'SUPER + F').length, 1);
assert.ok(!S.withAllowed(al, 'SUPER + F', false).lockedAllowedShortcuts.includes('SUPER + F'));
assert.ok(!S.withAllowed(al, 'x; os.exit()', true).lockedAllowedShortcuts.includes('x; os.exit()'));

// inactividad: apagado de fábrica, 15 min, bloquea aunque suene audio; por workspace hereda
assert.equal(d.defaults.idleLock, 'off');
assert.equal(d.defaults.idleSeconds, 900);
assert.equal(d.defaults.idleAudio, 'lock');
let id = S.normalize({ defaults: { idleLock: 'on', idleSeconds: 600, idleAudio: 'wait' },
  workspaces: { '2': { private: true }, '3': { private: true, idleLock: 'off' }, '4': { private: true, idleSeconds: 120, idleAudio: 'lock' },
                '5': { idleLock: 'on' }, '6': { private: true, idleSeconds: 30, idleLock: true, idleAudio: 'x' } } });
assert.deepEqual(plain(id.workspaces['6']), { private: true }, 'fuera de rango o desconocido se descarta');
assert.deepEqual(plain(S.idleTargets(id)), { '2': { seconds: 600, audio: 'wait' }, '4': { seconds: 120, audio: 'lock' }, '6': { seconds: 600, audio: 'wait' } });
assert.deepEqual(plain(S.idleTargets(S.normalize({ workspaces: { '2': { private: true } } }))), {}, 'apagado por defecto');
assert.deepEqual(plain(S.idleTargets(S.normalize({ workspaces: { '2': { private: true, idleLock: 'on' } } }))), { '2': { seconds: 900, audio: 'lock' } }, 'encendido solo en un workspace');
assert.equal(S.normalize({ defaults: { idleSeconds: 59 } }).defaults.idleSeconds, 900);
assert.equal(S.normalize({ defaults: { idleSeconds: 7201 } }).defaults.idleSeconds, 900);
let iw = S.withWorkspaceField(S.withPrivate(S.defaults(), 3, true), 3, 'idleLock', 'off');
assert.equal(S.effective(iw, 3).idleLock, 'off');
assert.deepEqual(plain(S.withWorkspaceField(iw, 3, 'idleLock', null).workspaces), { '3': { private: true } });

console.log('settings ok');
