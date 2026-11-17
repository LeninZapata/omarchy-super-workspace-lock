// Los catálogos de i18n/ deben tener las mismas claves y los mismos %n que en.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'i18n');
const load = f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
const placeholders = v => JSON.stringify(v).match(/%\d+/g)?.sort().join(',') ?? '';
const base = load('en.json');
let fails = 0;
for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json') && f !== 'en.json')) {
  const cat = load(file);
  for (const k of Object.keys(base)) {
    if (!(k in cat)) { console.error(`${file}: falta "${k}"`); fails++; }
    else if (placeholders(base[k]) !== placeholders(cat[k])) { console.error(`${file}: "${k}" con otros %n`); fails++; }
  }
  for (const k of Object.keys(cat)) if (!(k in base)) { console.error(`${file}: "${k}" no está en en.json`); fails++; }
}
if (fails) process.exit(1);
console.log(`i18n ok (${Object.keys(base).length} claves)`);
