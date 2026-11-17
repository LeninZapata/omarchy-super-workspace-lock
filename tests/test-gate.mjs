// Gate.js: atajos normalizados, caché de Omarchy y el Lua del submap/blur.
import assert from 'node:assert/strict';
import { loadLib } from './harness.mjs';

const G = loadLib('Gate.js');

assert.equal(G.normChord('super ctrl + l'), 'SUPER + CTRL + L');
assert.equal(G.normChord('CTRL + SUPER + L'), 'SUPER + CTRL + L');
assert.equal(G.normChord('SHIFT CTRL + SPACE'), 'CTRL + SHIFT + SPACE');
assert.equal(G.normChord('SUPER + "); os.exit()'), null);
assert.equal(G.normChord('FOO + L'), null);

const records = [
  'SUPER + TAB                         → Next workspace\tlua\thl.dsp.focus({ workspace = "m+1" })',
  'SUPER CTRL + L                      → Lock system\texec\tomarchy-system-lock',
  'SUPER + W / SUPER + Q               → Close window\tlua\thl.dsp.window.close()',
  'SUPER + C                           → Universal copy\t\t',
  'basura sin tabs',
].join('\n');
const map = G.parseRecords(records);
assert.equal(map['SUPER + TAB'].arg, 'hl.dsp.focus({ workspace = "m+1" })');
assert.equal(map['SUPER + CTRL + L'].kind, 'exec');
assert.equal(map['SUPER + Q'].arg, 'hl.dsp.window.close()');
assert.equal(map['SUPER + C'], undefined);

const { lua, missing } = G.enterLua(['SUPER + TAB', 'super ctrl + l', 'SUPER + 9'], map);
assert.deepEqual([...missing], ['SUPER + 9']);
assert.ok(lua.includes('hl.bind([[SUPER + TAB]], hl.dsp.focus({ workspace = "m+1" }))'));
assert.ok(lua.includes('hl.dsp.exec_cmd([[omarchy-system-lock]])'));
assert.ok(lua.includes('hl.define_submap([[swl-locked]]'));
assert.ok(!lua.includes('window.close'), 'un atajo no permitido no entra al submap');
assert.ok(lua.indexOf('blur = { enabled = true') < lua.indexOf('hl.dsp.submap('), 'blur antes de entrar al submap');

assert.equal(G.luaStr('a]]b'), '[=[a]]b]=]');
const prev = G.parseBlurOptions('{"option": "decoration:blur:enabled", "bool": false, "set": true }\n{"option": "decoration:blur:size", "int": 8, "set": false }\n{"option": "decoration:blur:passes", "int": 1, "set": false }');
assert.deepEqual(JSON.parse(JSON.stringify(prev)), { enabled: false, size: 8, passes: 1 });
assert.ok(G.exitLua(prev).includes('enabled = false, size = 8, passes = 1'));
assert.ok(G.exitLua(prev).startsWith('hl.dispatch(hl.dsp.submap("reset"))'));

// atajo de bloqueo: suelta los anteriores y pone el nuevo, normalizado
const sc = G.shortcutLua('super ctrl shift + l', ['SUPER + ALT + L']);
assert.deepEqual([...sc.applied], ['SUPER + CTRL + SHIFT + L']);
assert.ok(sc.lua.startsWith('pcall(function() hl.unbind([[SUPER + ALT + L]]) end)'));
assert.ok(sc.lua.includes('hl.bind([[SUPER + CTRL + SHIFT + L]], hl.dsp.exec_cmd([[omarchy-shell leninzapata.super-workspace-lock lockCurrent]])'));
// vacío = sin atajo, solo suelta
const none = G.shortcutLua('', ['SUPER + CTRL + SHIFT + L']);
assert.deepEqual([...none.applied], []);
assert.ok(!none.lua.includes('hl.bind('));

// vigía: solo con un pid válido, y vigila el submap propio
assert.equal(G.watchdogCmd(0), null);
const w = G.watchdogCmd(4242);
assert.equal(w[0], 'sh');
assert.equal(w[w.length - 1], '4242');
assert.ok(w[2].includes('swl-locked') && w[2].includes('hyprctl reload'));
assert.ok(w[2].includes('hl.dsp.submap(') && w[2].includes('reset'), 'reload no saca del submap: hace falta reset');
assert.ok(G.recoverCmd()[2].includes('submap'));

console.log('gate ok');
