// Writes assets/themes/<theme>/<object>.svg for every object a theme in
// lib/data/topic_themes.dart names (a theme block's quoted strings that are
// object names), plus the software topic objects for `kod`.
//
//   node tool/themes/gen_theme_svgs.mjs
import fs from 'node:fs';
import path from 'node:path';
import { OBJECTS } from './objects.mjs';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '../..');
const dart = fs.readFileSync(path.join(root, 'lib/data/topic_themes.dart'), 'utf8');
const out = path.join(root, 'assets/themes');
fs.rmSync(out, { recursive: true, force: true });

const svg = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">${body}</svg>\n`;

const blocks = dart.split('TopicTheme(').slice(1);
let files = 0, bytes = 0;
const missing = [];
for (const b of blocks) {
  const id = /id: '([^']+)'/.exec(b)?.[1];
  if (!id) continue;
  const names = new Set([...b.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).filter((n) => n in OBJECTS || /_/.test(n) || false));
  const objs = [...b.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).filter((n) => n in OBJECTS);
  if (id === 'kod') {
    const soft = /softwareTopicObject[\s\S]*?const \[([^\]]+)\]/.exec(dart)[1];
    objs.push(...[...soft.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]));
  }
  for (const key of ['steps', 'reward', 'badge', 'decor', 'hat']) {
    const m = new RegExp(String.raw`${key}: (\[[^\]]*\]|'[^']*')`).exec(b);
    if (!m) continue;
    for (const [, n] of m[1].matchAll(/'([a-z_]+)'/g)) if (!(n in OBJECTS)) missing.push(`${id}/${n}`);
  }
  fs.mkdirSync(path.join(out, id), { recursive: true });
  for (const n of new Set(objs)) {
    const s = svg(OBJECTS[n]);
    fs.writeFileSync(path.join(out, id, `${n}.svg`), s);
    files++;
    bytes += s.length;
  }
}
// The style sheet for Figma: every object once, named.
fs.mkdirSync(path.join(root, 'build/theme_sheet'), { recursive: true });
for (const [n, body] of Object.entries(OBJECTS)) fs.writeFileSync(path.join(root, 'build/theme_sheet', `${n}.svg`), svg(body));
console.log(`${blocks.length} themes, ${files} files, ${(bytes / 1024).toFixed(1)} KB`);
if (missing.length) {
  console.error('missing objects:', missing.join(', '));
  process.exit(1);
}
