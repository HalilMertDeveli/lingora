// Band and overlap report for the ys9 word bank (YDS Faz 3a). Lists are read from outside the repo:
//   WORDFREQ=<word\tzipf tsv from wordfreq's large_en> NGSL=<NGSL 1.2 csv> NAWL=<NAWL 1.2 csv>
//   node tool/yds/bands9.js [tool/yds/work/words_ys9.json] [--pool out.tsv]
// Categories (each item counted once): phrase (multiword) · list (NAWL, or NGSL rank > 1000) ·
// mid (wordfreq Zipf 3.0–4.3) · field (everything else: rarer terms). Targets: mid ≥ 65 %,
// field + phrase ≤ 25 % (phrases ≤ 100), list ~5–10 %. Overlap with everything taught must be 0.
const fs = require('fs');
const l = require('./lex.js');
const zipf = new Map(fs.readFileSync(process.env.WORDFREQ, 'utf8').split('\n').map((r) => r.split('\t')).map(([w, z]) => [w, +z]));
const rows = (f) => fs.readFileSync(f, 'utf8').replace(/^﻿/, '').split(/\r?\n/).slice(1).filter(Boolean).map((r) => r.split(','));
const ngsl = new Map(rows(process.env.NGSL).map((r) => [r[0].toLowerCase(), +r[1]]));
const nawl = new Set(rows(process.env.NAWL).map((r) => r[0].toLowerCase()));
const am = (w) => [w, w.replace(/ise$/, 'ize').replace(/isation$/, 'ization').replace(/yse$/, 'yze').replace(/our$/, 'or')
  .replace(/ence$/, 'ense').replace(/tre$/, 'ter').replace(/ogue$/, 'og').replace(/ae/, 'e')];
const z = (w) => Math.max(...am(w).map((x) => zipf.get(x) ?? 0));

// Everything taught so far: general course, the whole YDS path, every card.
const files = [...l.YDS_OLD, ...l.fs.readdirSync(l.path.join(l.ROOT, 'assets/courses/exam_yds')).filter((f) => /^(0[5-9]|1\d)_/.test(f) && !f.startsWith('09_'))
  .map((f) => `assets/courses/exam_yds/${f}`)];
const taught = new Set([...l.taught(l.GENERAL_ALL), ...l.taught(files), ...l.J('assets/vocab/yds.json').entries.filter((e) => !e.topic.startsWith('ys9u')).map((e) => e.word.toLowerCase())]);
const isTaught = (w) => taught.has(w) || (!w.includes(' ') && l.lemmas(w).some((x) => taught.has(x)));
const category = (w) => {
  if (w.includes(' ')) return 'phrase';
  if (am(w).some((x) => nawl.has(x)) || am(w).some((x) => (ngsl.get(x) ?? 0) > 1000)) return 'list';
  const v = z(w);
  return v >= 3.0 && v <= 4.3 ? 'mid' : 'field';
};

const poolArg = process.argv.indexOf('--pool');
if (poolArg > 0) {
  // Candidate pool: untaught lowercase words in the mid band, 4+ letters, not in NGSL ≤ 1000.
  const out = [];
  for (const [w, v] of zipf) {
    if (v < 3.0 || v > 4.3 || !/^[a-z]{4,}$/.test(w)) continue;
    if ((ngsl.get(w) ?? 9999) <= 1000 || isTaught(w)) continue;
    out.push(`${w}\t${v}`);
  }
  fs.writeFileSync(process.argv[poolArg + 1], out.join('\n'));
  console.log(`havuz: ${out.length} kelime`);
  process.exit(0);
}

const words = JSON.parse(fs.readFileSync(process.argv[2] ?? l.path.join(__dirname, 'work/words_ys9.json'), 'utf8'));
const all = Object.values(words).flat();
const count = { mid: 0, field: 0, phrase: 0, list: 0 };
const problems = [];
const seen = new Set();
for (const [u, ws] of Object.entries(words)) {
  const per = { mid: 0, field: 0, phrase: 0, list: 0 };
  for (const w of ws) {
    if (w !== w.toLowerCase() || w !== w.trim()) problems.push(`${u}: "${w}" küçük harf ve kırpılmış olmalı`);
    if (seen.has(w)) problems.push(`${u}: "${w}" tekrar`);
    seen.add(w);
    if (isTaught(w)) problems.push(`${u}: "${w}" daha önce öğretildi`);
    per[category(w)]++;
  }
  for (const k in per) count[k] += per[k];
  console.log(u, ws.length, JSON.stringify(per));
}
const pc = (n) => ((100 * n) / all.length).toFixed(1);
console.log(`F3a: ${all.length} öğe — orta sıklık (Zipf 3.0–4.3) ${count.mid} (%${pc(count.mid)}), alan ${count.field} + öbek ${count.phrase} (%${pc(count.field + count.phrase)}), NAWL/NGSL kalanı ${count.list} (%${pc(count.list)})`);
if (count.mid < all.length * 0.65) problems.push(`orta sıklık %${pc(count.mid)} (≥ %65)`);
if (count.field + count.phrase > all.length * 0.25) problems.push(`alan + öbek %${pc(count.field + count.phrase)} (≤ %25)`);
if (count.phrase > 100) problems.push(`öbek ${count.phrase} (≤ 100)`);
console.log(problems.length ? `HATA ${problems.length}` : 'TAMAM');
problems.slice(0, 40).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
