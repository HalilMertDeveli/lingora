// Builds build/figma/*.svg: the style guide and one sheet per theme, for
// uploading to the Figma file named in docs/tasarim/temalar.md.
import fs from 'node:fs';
import { OBJECTS, PALETTE } from './objects.mjs';
const dart = fs.readFileSync('lib/data/topic_themes.dart', 'utf8');
fs.mkdirSync('build/figma', { recursive: true });
const font = 'font-family="Inter, Arial, sans-serif"';
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
// Style guide.
let g = `<rect width="1000" height="360" rx="24" fill="#FFF8EE"/>`;
g += `<text x="32" y="56" ${font} font-size="32" font-weight="700" fill="${PALETTE.ink}">Dilbaz konu temaları · stil rehberi</text>`;
g += `<text x="32" y="92" ${font} font-size="16" fill="${PALETTE.ink}">64×64 ızgara · tek mürekkep çizgisi 2.5 px, yuvarlak uçlar · düz dolgu, gradyan yok · tek beyaz parlama · zeminde %12 gölge</text>`;
Object.entries(PALETTE).forEach(([n, c], i) => {
  const x = 32 + (i % 9) * 106, y = 120 + Math.floor(i / 9) * 104;
  g += `<rect x="${x}" y="${y}" width="90" height="56" rx="10" fill="${c}" stroke="${PALETTE.ink}" stroke-width="2"/>`;
  g += `<text x="${x}" y="${y + 74}" ${font} font-size="13" fill="${PALETTE.ink}">${n} ${c}</text>`;
});
fs.writeFileSync('build/figma/00_stil_rehberi.svg', `<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="360" viewBox="0 0 1000 360">${g}</svg>`);
// Theme sheets.
for (const b of dart.split('TopicTheme(').slice(2)) {
  const id = /id: '([^']+)'/.exec(b)[1];
  const name = /name: '([^']+)'/.exec(b)[1];
  const accent = /Color\(0xFF([0-9A-F]{6})\)/.exec(b)[1];
  const pick = (k) => [...(new RegExp(String.raw`${k}: (\[[^\]]*\]|'[^']*')`).exec(b)?.[1] ?? '').matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  const items = [
    ...pick('steps').map((o, i) => [o, `adım ${i + 1}`]),
    [pick('reward')[0], 'ödül'],
    [pick('badge')[0], 'rozet'],
    ...pick('decor').map((o) => [o, 'süs']),
    ...pick('hat').map((o) => [o, 'kostüm']),
  ];
  const lines = ['lessonInvite', 'testInvite', 'chestInvite'].map((k) => new RegExp(`${k}: '([^']+)'`).exec(b)?.[1] ?? '');
  const w = 40 + items.length * 112;
  let s = `<rect width="${w}" height="250" rx="20" fill="#FFFFFF" stroke="#${accent}" stroke-width="4"/>`;
  s += `<rect width="${w}" height="56" rx="20" fill="#${accent}"/><rect y="36" width="${w}" height="20" fill="#${accent}"/>`;
  s += `<text x="24" y="38" ${font} font-size="22" font-weight="700" fill="#FFFFFF">${esc(name)} · ${id}</text>`;
  items.forEach(([o, label], i) => {
    if (!OBJECTS[o]) return;
    s += `<g transform="translate(${24 + i * 112} 72) scale(1.4)">${OBJECTS[o]}</g>`;
    s += `<text x="${24 + i * 112 + 45}" y="186" ${font} font-size="12" text-anchor="middle" fill="${PALETTE.ink}">${o}</text>`;
    s += `<text x="${24 + i * 112 + 45}" y="202" ${font} font-size="11" text-anchor="middle" fill="#888">${label}</text>`;
  });
  s += `<text x="24" y="234" ${font} font-size="13" fill="${PALETTE.ink}">“${esc(lines.join('” · “'))}”</text>`;
  fs.writeFileSync(`build/figma/${id}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="250" viewBox="0 0 ${w} 250">${s}</svg>`);
}
console.log(fs.readdirSync('build/figma').length);
