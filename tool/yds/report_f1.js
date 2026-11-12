// Phase 1 reports for the PR: overlap, counts, word coverage (ys5 + ys6), unknown-word rate per ys6 text.
// Usage: node tool/yds/report_f1.js [--md out.md]
const l = require('./lex.js');
const ctx = require('./context.js');
const BANK = 'assets/courses/exam_yds/05_kelime_bankasi_1.json';
const READ = 'assets/courses/exam_yds/06_okuma_evi_1.json';
const has = (f) => l.fs.existsSync(l.path.join(l.ROOT, f));
const lines = [];
const out = (s = '') => { lines.push(s); console.log(s); };

const vocab = l.J('assets/vocab/yds.json');
const words = vocab.entries.filter((e) => e.topic.startsWith('ys5u')).map((e) => e.word);
const taught = new Set([...l.taught(l.GENERAL), ...l.taught(l.YDS_OLD)]);
const clash = words.filter((w) => taught.has(w.toLowerCase()));
out(`## Kelime çakışması\n\n${words.length} kelime, ${clash.length} çakışma${clash.length ? ': ' + clash.join(', ') : ''} (genel kurs s1–s6 + YDS ys1–ys4).`);

// Counts.
const count = (file) => {
  const c = { units: 0, lessons: 0, lessonEx: 0, lessonChoice: 0, testQ: 0, passages: new Set(), mockQ: 0 };
  for (const u of l.J(file).units) {
    c.units++;
    for (const n of u.nodes) {
      const ex = n.exercises || [];
      if (n.type === 'lesson') { c.lessons++; c.lessonEx += ex.length; c.lessonChoice += ex.filter((e) => e.type === 'choice').length; }
      if (n.type === 'test') c.testQ += ex.length;
      if (n.type === 'mock') c.mockQ += ex.length;
      ex.forEach((e) => e.passage && c.passages.add(e.passage));
    }
  }
  return c;
};
const cb = count(BANK);
out(`\n## Sayılar: ys5\n\n| | Hedef | Gerçek |\n|---|---|---|\n| Ünite | 10 | ${cb.units} |\n| Ders | 40 | ${cb.lessons} |\n| Ders alıştırması | ~440 | ${cb.lessonEx} |\n| Ders choice | ~200 | ${cb.lessonChoice} |\n| Test sorusu | 150 | ${cb.testQ} |\n| Kelime kartı | 800 | ${words.length} |\n| Paragraf (cloze + test) | 20 | ${cb.passages.size} |`);

// Coverage: every word in context ≥2 times across ys5 (+ys6).
const contexts = [];
for (const f of [BANK, ...(has(READ) ? [READ] : [])]) for (const u of l.J(f).units) contexts.push(...ctx.unitContexts(u));
const freq = Object.fromEntries(words.map((w) => [w, contexts.filter((t) => ctx.uses(t, w)).length]));
const low = words.filter((w) => freq[w] < 2);
const buckets = [0, 1, 2, 3, 5, 10].map((b, i, a) => [b, a[i + 1] ?? Infinity]);
out(`\n## Geri dönüşüm (bağlamda geçiş, ys5${has(READ) ? ' + ys6' : ''})\n\n${words.length - low.length}/${words.length} kelime en az 2 kez bağlamda geçiyor.${low.length ? ' Eksik: ' + low.join(', ') : ''}\n\n| Geçiş | Kelime |\n|---|---|\n` +
  buckets.map(([a, b]) => `| ${b === Infinity ? a + '+' : a === b - 1 ? a : `${a}–${b - 1}`} | ${words.filter((w) => freq[w] >= a && freq[w] < b).length} |`).join('\n'));

if (has(READ)) {
  // Unknown words per reading text: tokens − (general course + ys1–ys5 words + function words), proper nouns excluded.
  const known = new Set([...l.seen(l.GENERAL), ...l.seen(l.YDS_OLD), ...l.seen([BANK])]);
  const func = new Set(l.fs.readFileSync(l.path.join(__dirname, 'function_words.txt'), 'utf8').split(/\s+/).filter(Boolean));
  const bankRe = words;
  out('\n## Okuma metinleri: bilinmeyen kelime ve ys5 kelimeleri\n\n| Metin | Kelime | Bilinmeyen % | ys5 kelimesi | Bilinmeyenler |\n|---|---|---|---|---|');
  const seenP = new Set();
  let worst = 0;
  for (const u of l.J(READ).units) for (const n of u.nodes) for (const e of n.exercises || []) {
    if (!e.passage || seenP.has(e.passage) || /\(\d\)----/.test(e.passage)) continue;
    seenP.add(e.passage);
    const raw = e.passage.match(/[A-Za-z]+(?:'[a-z]+)?/g) || [];
    const toks = raw.filter((w, i) => !(/^[A-Z]/.test(w) && i > 0 && !/[.!?]\s*$/.test(e.passage.split(w)[0].slice(-3)))).map((w) => w.toLowerCase());
    const unk = [...new Set(toks.filter((w) => !func.has(w) && !l.lemmas(w).some((x) => known.has(x) || func.has(x)) && !bankRe.some((b) => ctx.uses(w, b))))];
    const unkCount = toks.filter((w) => unk.includes(w)).length;
    const pct = (100 * unkCount) / raw.length;
    worst = Math.max(worst, pct);
    const used = words.filter((w) => ctx.uses(e.passage, w));
    out(`| ${n.id} | ${raw.length} | ${pct.toFixed(1)} | ${used.length} | ${unk.slice(0, 8).join(', ')} |`);
  }
  out(`\nEn yüksek bilinmeyen oranı: %${worst.toFixed(1)} (sınır %5).`);
}
const md = process.argv.indexOf('--md');
if (md > 0) l.fs.writeFileSync(process.argv[md + 1], lines.join('\n') + '\n');
