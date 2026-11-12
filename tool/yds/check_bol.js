// Checks extensive-reading stories (ReadingStory format, assets/reading/*.json) for YDS Faz 2b:
// id yb_*, level B1/B1+, 400–700 words, ≤ 2% unknown words once glosses are counted, 2 questions.
// Usage: node tool/yds/check_bol.js tool/yds/work/bol_1.json [more files…]   (NGSL=<csv> adds its top 1000)
const l = require('./lex.js');
const ctx = require('./context.js');
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };

const cards = l.J('assets/vocab/yds.json').entries;
const bank = cards.filter((e) => /^ys[57]u/.test(e.topic)).map((e) => e.word).filter((w) => !w.includes(' '));
const known = l.seen([...l.GENERAL_ALL, ...l.YDS_OLD, 'assets/courses/exam_yds/05_kelime_bankasi_1.json',
  'assets/courses/exam_yds/06_okuma_evi_1.json', 'assets/courses/exam_yds/07_kelime_bankasi_2.json']);
l.fs.readFileSync(l.path.join(__dirname, 'function_words.txt'), 'utf8').split(/\s+/).filter(Boolean).forEach((w) => known.add(w));
if (process.env.NGSL) {
  l.fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1, 1001).forEach((r) => known.add(r.split(',')[0].toLowerCase()));
}
const isKnown = (w) => known.has(w) || l.lemmas(w).some((x) => known.has(x)) || bank.some((b) => ctx.uses(w, b));
const TR = /[çğıöşüÇĞİÖŞÜ]/;
const clean = (s) => typeof s === 'string' && s === s.trim() && !/[^\s] {2,}[^\s]/.test(s) && !/\*\*|<\/?[a-z]+>/.test(s);

const rows = [];
const ids = new Set();
const answers = [0, 0, 0, 0, 0];
for (const file of process.argv.slice(2)) {
  const stories = JSON.parse(l.fs.readFileSync(file, 'utf8'));
  P(Array.isArray(stories), `${file}: dizi olmalı`);
  for (const s of stories) {
    const at = s.id || '(id yok)';
    P(/^yb_[a-z0-9_]+$/.test(s.id || ''), `${at}: id yb_<slug>`);
    P(!ids.has(s.id), `${at}: id tekrar`);
    ids.add(s.id);
    P(['B1', 'B1+'].includes(s.level), `${at}: level B1 ya da B1+`);
    for (const k of ['emoji', 'title', 'titleTr', 'text']) P(clean(s[k]) && s[k].length > 0, `${at}: ${k}`);
    P(TR.test(s.titleTr) || !/[a-z]{3,}/.test(s.titleTr) || s.titleTr !== s.title, `${at}: titleTr Türkçe olmalı`);
    const text = s.text || '';
    P(text.includes('\n\n'), `${at}: paragraflar boş satırla ayrılmalı`);
    const words = text.match(/\p{L}+(?:[-'’]\p{L}+)*/gu) || [];
    P(words.length >= 400 && words.length <= 700, `${at}: ${words.length} kelime (400–700)`);
    // Glossed words and phrases count as known.
    const g = s.glosses || {};
    const glossed = new Set();
    for (const [k, v] of Object.entries(g)) {
      P(k === k.toLowerCase() && clean(k) && clean(v), `${at}: gloss "${k}" (küçük harf, temiz)`);
      P(text.toLowerCase().includes(k), `${at}: gloss "${k}" metinde yok`);
      k.split(/\s+/).forEach((w) => glossed.add(w));
    }
    const sentences = text.split(/(?<=[.!?…"”])\s+/);
    const initial = new Set(sentences.map((x) => (x.match(/\p{L}+/u) || [''])[0]));
    const unknown = [];
    for (const w of words) {
      if (/^\p{Lu}/u.test(w) && !initial.has(w)) continue;
      const lw = w.toLowerCase();
      if (glossed.has(lw)) continue;
      if (lw.split(/[-'’]/).filter((p) => p.length > 1).some((p) => !isKnown(p) && !glossed.has(p))) unknown.push(lw);
    }
    const pct = (100 * unknown.length) / Math.max(words.length, 1);
    P(pct <= 2, `${at}: bilinmeyen %${pct.toFixed(1)} (≤%2, gloss dışı): ${[...new Set(unknown)].join(', ')}`);
    const qs = s.questions || [];
    P(qs.length === 2, `${at}: 2 soru`);
    for (const [i, q] of qs.entries()) {
      P(clean(q.q) && Array.isArray(q.options) && q.options.length >= 4 && q.options.length <= 5, `${at}#q${i}: q ve 4–5 şık`);
      P(new Set((q.options || []).map((o) => o.toLowerCase())).size === (q.options || []).length, `${at}#q${i}: aynı şık`);
      P(Number.isInteger(q.answer) && q.answer >= 0 && q.answer < (q.options || []).length, `${at}#q${i}: answer`);
      P(clean(q.explain) && TR.test(q.explain), `${at}#q${i}: Türkçe explain`);
      P(!/(ilk|birinci|ikinci|üçüncü|dördüncü|beşinci|son) (seçene|şık)|\b[A-E] şık/i.test((q.explain || '').replace(/İ/g, 'i')), `${at}#q${i}: açıklama şıkkı konumla anıyor`);
      if (Number.isInteger(q.answer)) answers[q.answer]++;
    }
    rows.push([s.id, s.level, words.length, pct, Object.keys(g).length]);
  }
}
console.log(`${problems.length ? 'HATA ' + problems.length : 'TAMAM'}: ${rows.length} metin, doğru şık ${answers}`);
for (const [id, lv, w, pct, g] of rows) console.log(`  ${id} ${lv}: ${w} kelime, bilinmeyen %${pct.toFixed(1)}, ${g} gloss`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
