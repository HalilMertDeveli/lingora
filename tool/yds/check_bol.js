// Checks extensive-reading stories (ReadingStory format, assets/reading/*.json) for YDS Faz 2b:
// id yb_*, level B1/B1+, 400–700 words, ≤ 2% unknown words once glosses are counted, 2 questions.
// Usage: node tool/yds/check_bol.js tool/yds/work/bol_1.json [more files…]   (NGSL=<csv> adds its top 1000)
// Set 2 (Faz 3b, files tool/yds/work/bol2_*.json → yds_bol_okuma_2.json): level B1+ or B2, 500–800 words, and
// everything taught through ys9 counts as known.
const l = require('./lex.js');
const ctx = require('./context.js');
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };

// Set 3 (Faz 4b, files tool/yds/work/bol3_*.json → yds_bol_okuma_3.json): level B2, 600–900 words, everything
// taught through ys12 counts as known (ys12 from tool/yds/work/words_ys12.json until its cards ship), and each
// text recycles ≥ 8 ys9 + ys12 words.
const cards = l.J('assets/vocab/yds.json').entries;
const args = process.argv.slice(2);
const set = args.some((f) => /bol3_/.test(f)) ? 3 : args.some((f) => /bol2_/.test(f)) ? 2 : 1;
const ys12List = () => {
  const f = l.path.join(__dirname, 'work', 'words_ys12.json');
  return l.fs.existsSync(f) ? Object.values(JSON.parse(l.fs.readFileSync(f, 'utf8'))).flat() : cards.filter((e) => /^ys12u/.test(e.topic)).map((e) => e.word);
};
const SET = {
  1: { levels: ['B1', 'B1+'], words: [400, 700], banks: /^ys[57]u/, files: ['05_kelime_bankasi_1', '06_okuma_evi_1', '07_kelime_bankasi_2'] },
  2: { levels: ['B1+', 'B2'], words: [500, 800], banks: /^ys[579]u/, files: ['05_kelime_bankasi_1', '06_okuma_evi_1', '07_kelime_bankasi_2', '08_okuma_evi_2', '09_kelime_bankasi_3'] },
  3: { levels: ['B2'], words: [600, 900], banks: /^ys(5|7|9|12)u/, recycle: 8,
    files: ['05_kelime_bankasi_1', '06_okuma_evi_1', '07_kelime_bankasi_2', '08_okuma_evi_2', '09_kelime_bankasi_3', '10_okuma_evi_3', '11_ara_denemeler'] },
}[set];
const bank = [...cards.filter((e) => SET.banks.test(e.topic)).map((e) => e.word), ...(set === 3 ? ys12List() : [])]
  .filter((w) => !w.includes(' '));
// Recycling list for set 3: ys9 cards and the ys12 list (single words and phrases).
const recycleWords = set === 3 ? [...cards.filter((e) => /^ys9u/.test(e.topic)).map((e) => e.word), ...ys12List()] : [];
const known = l.seen([...l.GENERAL_ALL, ...l.YDS_OLD, ...SET.files.map((f) => `assets/courses/exam_yds/${f}.json`)]);
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
    P(SET.levels.includes(s.level), `${at}: level ${SET.levels.join(' ya da ')}`);
    for (const k of ['emoji', 'title', 'titleTr', 'text']) P(clean(s[k]) && s[k].length > 0, `${at}: ${k}`);
    P(TR.test(s.titleTr) || !/[a-z]{3,}/.test(s.titleTr) || s.titleTr !== s.title, `${at}: titleTr Türkçe olmalı`);
    const text = s.text || '';
    P(text.includes('\n\n'), `${at}: paragraflar boş satırla ayrılmalı`);
    const words = text.match(/\p{L}+(?:[-'’]\p{L}+)*/gu) || [];
    P(words.length >= SET.words[0] && words.length <= SET.words[1], `${at}: ${words.length} kelime (${SET.words.join('–')})`);
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
    let recycled = '';
    if (SET.recycle) {
      const used = recycleWords.filter((w) => ctx.uses(text, w));
      P(used.length >= SET.recycle, `${at}: ys9 + ys12 kelimesi ${used.length} (≥ ${SET.recycle})`);
      recycled = `, ys9+ys12 ${used.length}`;
    }
    rows.push([s.id, s.level, words.length, pct, Object.keys(g).length, recycled]);
  }
}
console.log(`${problems.length ? 'HATA ' + problems.length : 'TAMAM'}: ${rows.length} metin, doğru şık ${answers}`);
for (const [id, lv, w, pct, g, r] of rows) console.log(`  ${id} ${lv}: ${w} kelime, bilinmeyen %${pct.toFixed(1)}, ${g} gloss${r}`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
