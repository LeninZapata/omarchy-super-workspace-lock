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

// atajo de bloqueo: lee los atajos de Hyprland y solo toca lo suyo
const bind = (modmask, key, description, submap = '') => ({ modmask, key, description, submap, mouse: false, dispatcher: '__lua', arg: '1' });
const binds = JSON.stringify([
  bind(65, 'L', 'Super Workspace Lock: lock this workspace'),     // SUPER+SHIFT+L: nuestro (anterior)
  bind(68, 'L', 'Lock system'),                                    // SUPER+CTRL+L: de Omarchy
  bind(64, 'L', 'something', 'swl-locked'),                        // en otro submap: no cuenta
]);
const owners = G.bindOwners(binds);
assert.deepEqual(JSON.parse(JSON.stringify(owners)), { 'SUPER + SHIFT + L': { own: 1, foreign: 0 }, 'SUPER + CTRL + L': { own: 0, foreign: 1 } });
assert.equal(G.bindOwners('not json'), null);

// tecla libre: suelta el anterior (nuestro) y pone el nuevo
const sc = G.shortcutLua('super ctrl shift + l', ['SUPER + SHIFT + L'], owners);
assert.deepEqual([...sc.applied], ['SUPER + CTRL + SHIFT + L']);
assert.equal(sc.conflict, '');
assert.ok(sc.lua.startsWith('pcall(function() hl.unbind([[SUPER + SHIFT + L]]) end)'));
assert.ok(sc.lua.includes('hl.bind([[SUPER + CTRL + SHIFT + L]], hl.dsp.exec_cmd([[omarchy-shell leninzapata.super-workspace-lock lockCurrent]])'));
assert.ok(!sc.lua.includes('hl.unbind([[SUPER + CTRL + SHIFT + L]])'), 'tecla libre: no hay nada que soltar');

// tecla ocupada por otro: NO se suelta ni se pisa, vuelve como conflicto
const taken = G.shortcutLua('SUPER + CTRL + L', [], owners);
assert.deepEqual([...taken.applied], []);
assert.equal(taken.conflict, 'SUPER + CTRL + L');
assert.ok(!taken.lua.includes('SUPER + CTRL + L'), 'nada sobre un atajo ajeno');

// un anterior que ahora comparte tecla con otro no se suelta
const shared = G.bindOwners(JSON.stringify([bind(65, 'L', 'Super Workspace Lock: lock this workspace'), bind(65, 'L', 'mine')]));
assert.ok(!G.shortcutLua('SUPER + ALT + K', ['SUPER + SHIFT + L'], shared).lua.includes('unbind([[SUPER + SHIFT + L]])'));

// re-aplicar sobre el nuestro: se suelta y se pone de nuevo (sin duplicar)
const again = G.shortcutLua('SUPER + SHIFT + L', [], owners);
assert.ok(again.lua.startsWith('pcall(function() hl.unbind([[SUPER + SHIFT + L]]) end)') && again.applied.length === 1);

// sin poder leer los atajos: no se suelta NI se pone nada; los anteriores siguen y se reintenta
const blind = G.shortcutLua('SUPER + ALT + K', ['super shift + l'], null);
assert.equal(blind.lua, '');
assert.deepEqual([...blind.applied], ['SUPER + SHIFT + L']);
assert.equal(blind.retry, true);
assert.equal(G.shortcutLua('SUPER + ALT + K', [], owners).retry, false);

// vacío = sin atajo: suelta el anterior solo si sigue siendo solo nuestro
const none = G.shortcutLua('', ['SUPER + SHIFT + L'], owners);
assert.deepEqual([...none.applied], []);
assert.ok(none.lua.includes('hl.unbind([[SUPER + SHIFT + L]])'));
assert.ok(!none.lua.includes('hl.bind('));
assert.equal(G.shortcutLua('', ['SUPER + CTRL + L'], owners).lua, '', 'una tecla ajena nunca se suelta');

// al cerrarse el plugin: binds.py comprueba antes de soltar
assert.deepEqual([...G.releaseCmd('/p/binds.py', ['super ctrl shift + l'])], ['python3', '-I', '/p/binds.py', 'release', 'SUPER + CTRL + SHIFT + L']);
assert.equal(G.releaseCmd('/p/binds.py', []), null);

// vigía: solo con un pid válido, y vigila el submap propio
assert.equal(G.watchdogCmd(0), null);
const w = G.watchdogCmd(4242);
assert.equal(w[0], 'sh');
assert.equal(w[w.length - 1], '4242');
assert.ok(w[2].includes('swl-locked') && w[2].includes('hyprctl reload'));
assert.ok(w[2].includes('hl.dsp.submap(') && w[2].includes('reset'), 'reload no saca del submap: hace falta reset');
assert.ok(G.recoverCmd()[2].includes('submap'));

// regla propia de la ventana de ajustes + foco
assert.ok(G.focusSettingsLua().includes('hl.dsp.window.resize('));
assert.ok(G.focusSettingsLua().includes('hl.get_windows()') && G.focusSettingsLua().includes('hl.dsp.focus('));

// duración de la animación de workspaces
assert.equal(G.workspaceAnimMs('[[{"name":"workspaces","enabled":true,"speed":3.0}]]'), 300);
assert.equal(G.workspaceAnimMs('[[{"name":"workspaces","enabled":false,"speed":3.0}]]'), 0);
assert.equal(G.workspaceAnimMs('basura'), 300);

console.log('gate ok');
