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

console.log('settings ok');
