// NGSL band report for the ys5 word bank. The NGSL list itself is NOT kept in the repo (CC BY-SA, used as
// reference only): download NGSL 1.2 stats CSV and pass its path.
// Usage: NGSL=/path/NGSL_12_stats.csv node tool/yds/bands.js [words.json]
const fs = require('fs');
const l = require('./lex.js');
const rows = fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1).filter(Boolean).map((r) => r.split(','));
const rank = new Map(rows.map((r) => [r[0].toLowerCase(), +r[1]]));
// British → American spelling, NGSL uses American.
const am = (w) => [w, w.replace(/ise$/, 'ize').replace(/isation$/, 'ization').replace(/yse$/, 'yze').replace(/our$/, 'or')
  .replace(/ence$/, 'ense').replace(/tre$/, 'ter').replace(/ogue$/, 'og').replace(/lled$/, 'led').replace(/ae/, 'e')];
const r = (w) => am(w).map((x) => rank.get(x)).find((x) => x) ?? null;
const src = process.argv[2] ?? l.path.join(__dirname, 'work/words.json');
const words = src.endsWith('yds.json')
  ? JSON.parse(fs.readFileSync(src, 'utf8')).entries.reduce((m, e) => ((m[e.topic] ??= []).push(e.word), m), {})
  : JSON.parse(fs.readFileSync(src, 'utf8'));
const tot = { le1000: 0, b1000_2000: 0, b2000_3000: 0, outside: 0, phrase: 0 };
const outside = [];
for (const [u, ws] of Object.entries(words)) {
  const per = { le1000: 0, b1000_2000: 0, b2000_3000: 0, outside: 0, phrase: 0 };
  for (const w of ws) {
    if (w.includes(' ')) { per.phrase++; continue; }
    const x = r(w);
    const k = !x ? 'outside' : x <= 1000 ? 'le1000' : x <= 2000 ? 'b1000_2000' : 'b2000_3000';
    per[k]++;
    if (k === 'outside') outside.push(w);
  }
  for (const k in per) tot[k] += per[k];
  console.log(u, JSON.stringify(per));
}
const single = tot.le1000 + tot.b1000_2000 + tot.b2000_3000 + tot.outside;
const band = tot.b1000_2000 + tot.b2000_3000;
console.log('TOPLAM', JSON.stringify(tot));
console.log(`Tek kelime ${single}: 1000–3000 bandında ${band} (%${((100 * band) / single).toFixed(1)}), ≤1000 ${tot.le1000}, NGSL dışı ${tot.outside}; öbek ${tot.phrase}`);
console.log('NGSL dışı:', outside.join(', '));

// F2 (NAWL=<NAWL 1.2 csv>): academic share of the whole list — NAWL / NGSL 1001–2809 / other (+ phrases).
if (process.env.NAWL) {
  const nawl = new Set(fs.readFileSync(process.env.NAWL, 'utf8').replace(/^﻿/, '').split(/\r?\n/).slice(1)
    .filter(Boolean).map((x) => x.split(',')[0].toLowerCase()));
  const inNawl = (w) => am(w).some((x) => nawl.has(x));
  const all = Object.values(words).flat();
  const n = all.filter((w) => !w.includes(' ') && inNawl(w));
  const g = all.filter((w) => !w.includes(' ') && !inNawl(w) && (r(w) ?? 0) > 1000);
  const p = all.filter((w) => w.includes(' '));
  const o = all.filter((w) => !w.includes(' ') && !inNawl(w) && !((r(w) ?? 0) > 1000));
  const pc = (x) => ((100 * x.length) / all.length).toFixed(1);
  console.log(`F2: ${all.length} öğe — NAWL ${n.length} (%${pc(n)}), NGSL 1001–2809 ${g.length} (%${pc(g)}), diğer ${o.length + p.length} (%${pc([...o, ...p])}: tek kelime ${o.length}, öbek ${p.length})`);
  console.log('Diğer tek kelimeler:', o.join(', '));
}
