// Band and overlap report for the ys12 word bank (YDS Faz 4a, docs/sinav/yds-faz4-icerik.md § F4a). Lists are
// read from outside the repo:
//   WORDFREQ=<word\tzipf tsv from wordfreq's large_en> NGSL=<NGSL 1.2 csv>
//   node tool/yds/bands12.js [tool/yds/work/words_ys12.json] [--pool out.tsv]
// Categories (each item counted once):
//   mid    single word, wordfreq Zipf 2.8–4.0                                  target ≥ 60 %
//   family exam-confusable families and advanced collocations: every item of
//          ys12u7 (collocations) and ys12u8 (confusable families) not in mid  target ≤ 20 %
//   field  field terms (single words outside the band) and phrases elsewhere  target ≤ 20 %, phrases ≤ 120 in all
// Overlap with everything taught (general course, YDS path through ys11, every card) must be 0.
const fs = require('fs');
const l = require('./lex.js');
const zipf = new Map(fs.readFileSync(process.env.WORDFREQ, 'utf8').split('\n').map((r) => r.split('\t')).map(([w, z]) => [w, +z]));
const rows = (f) => fs.readFileSync(f, 'utf8').replace(/^﻿/, '').split(/\r?\n/).slice(1).filter(Boolean).map((r) => r.split(','));
const ngsl = new Map(rows(process.env.NGSL).map((r) => [r[0].toLowerCase(), +r[1]]));
const am = (w) => [w, w.replace(/ise$/, 'ize').replace(/isation$/, 'ization').replace(/yse$/, 'yze').replace(/our$/, 'or')
  .replace(/ence$/, 'ense').replace(/tre$/, 'ter').replace(/ogue$/, 'og').replace(/ae/, 'e')];
const z = (w) => Math.max(...am(w).map((x) => zipf.get(x) ?? 0));

// Everything taught so far: general course, the YDS path through ys11, every card outside ys12.
const files = [...l.YDS_OLD, ...l.fs.readdirSync(l.path.join(l.ROOT, 'assets/courses/exam_yds'))
  .filter((f) => /^(0[5-9]|1[01])_/.test(f)).map((f) => `assets/courses/exam_yds/${f}`)];
const taught = new Set([...l.taught(l.GENERAL_ALL), ...l.taught(files),
  ...l.J('assets/vocab/yds.json').entries.filter((e) => !e.topic.startsWith('ys12u')).map((e) => e.word.toLowerCase())]);
const isTaught = (w) => taught.has(w) || (!w.includes(' ') && l.lemmas(w).some((x) => taught.has(x)));
const inBand = (w) => !w.includes(' ') && z(w) >= 2.8 && z(w) <= 4.0;
const category = (w, unit) => {
  if (inBand(w)) return 'mid';
  if (unit === 'ys12u7' || unit === 'ys12u8') return 'family';
  return 'field';
};

const poolArg = process.argv.indexOf('--pool');
if (poolArg > 0) {
  // Candidate pool: untaught lowercase words in the band, 4+ letters, not NGSL ≤ 1000.
  const out = [];
  for (const [w, v] of zipf) {
    if (v < 2.8 || v > 4.0 || !/^[a-z]{4,}$/.test(w)) continue;
    if ((ngsl.get(w) ?? 9999) <= 1000 || isTaught(w)) continue;
    out.push(`${w}\t${v}`);
  }
  fs.writeFileSync(process.argv[poolArg + 1], out.join('\n'));
  console.log(`havuz: ${out.length} kelime`);
  process.exit(0);
}

const words = JSON.parse(fs.readFileSync(process.argv[2] ?? l.path.join(__dirname, 'work/words_ys12.json'), 'utf8'));
const all = Object.values(words).flat();
const count = { mid: 0, family: 0, field: 0 };
let phrases = 0;
const problems = [];
const seen = new Set();
for (const [u, ws] of Object.entries(words)) {
  const per = { mid: 0, family: 0, field: 0 };
  for (const w of ws) {
    if (w !== w.toLowerCase() || w !== w.trim()) problems.push(`${u}: "${w}" küçük harf ve kırpılmış olmalı`);
    if (seen.has(w)) problems.push(`${u}: "${w}" tekrar`);
    seen.add(w);
    if (isTaught(w)) problems.push(`${u}: "${w}" daha önce öğretildi`);
    if (w.includes(' ')) phrases++;
    per[category(w, u)]++;
  }
  for (const k in per) count[k] += per[k];
  console.log(u, ws.length, JSON.stringify(per));
}
const pc = (n) => ((100 * n) / all.length).toFixed(1);
console.log(`F4a: ${all.length} öğe — orta–ileri sıklık (Zipf 2.8–4.0) ${count.mid} (%${pc(count.mid)}), ` +
  `çeldirici aile + eşdizim ${count.family} (%${pc(count.family)}), alan + öbek ${count.field} (%${pc(count.field)}), öbek toplam ${phrases}`);
if (all.length !== 900) problems.push(`toplam ${all.length} (900)`);
if (count.mid < all.length * 0.6) problems.push(`orta–ileri sıklık %${pc(count.mid)} (≥ %60)`);
if (count.family > all.length * 0.2) problems.push(`aile + eşdizim %${pc(count.family)} (≤ %20)`);
if (count.field > all.length * 0.2) problems.push(`alan + öbek %${pc(count.field)} (≤ %20)`);
if (phrases > 120) problems.push(`öbek ${phrases} (≤ 120)`);
console.log(problems.length ? `HATA ${problems.length}` : 'TAMAM');
problems.slice(0, 40).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
