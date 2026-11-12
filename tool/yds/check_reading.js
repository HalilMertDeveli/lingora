// Checks one reading unit — ys6 "Okuma evi 1" (Faz 1 §3) or ys8 "Okuma evi 2" (Faz 2b) — from
// tool/yds/work/<unitId>.json, or a half mock {"exercises":[40 choice]} (tool/yds/work/ys6m.json, ys8m.json).
// Usage: node tool/yds/check_reading.js ys6u3 | ys8u4 | ys6m | ys8m | --text "…" [--sec ys8]
// Optional NGSL=<NGSL 1.2 csv> adds its top 1000 words to the known set.
const l = require('./lex.js');
const ctx = require('./context.js');
const id = process.argv[2];
const secArg = process.argv.indexOf('--sec');
// Section of the id; half mocks of the review section ys11 (ys11u1m …) are checked like ys8's (B2).
const secOf = (x) => { const s = x.match(/^ys\d+/)[0]; return s === 'ys11' ? 'ys8' : s; };
const sec = id === '--text' ? (secArg > 0 ? process.argv[secArg + 1] : 'ys6') : secOf(id);
const dir = l.path.join(__dirname, 'work');
const data = id === '--text' ? {} : JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.json`), 'utf8'));
const problems = [];
const warn = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const { walk, exercise } = require('./rules.js')(P, problems);
walk(data, id);

// ---- per section: what the learner knows by now and what the texts must look like ----
const BANK1 = 'assets/courses/exam_yds/05_kelime_bankasi_1.json';
const BANK2 = 'assets/courses/exam_yds/07_kelime_bankasi_2.json';
const cards = l.J('assets/vocab/yds.json').entries;
const bankOf = (s) => cards.filter((e) => e.topic.startsWith(`${s}u`)).map((e) => e.word);
const CFG = {
  ys6: {
    knownFiles: [...l.GENERAL, ...l.YDS_OLD, BANK1], banks: { ys5: 8 }, range: (n) => (n <= 2 ? [150, 220] : [200, 350]),
    avg: [13, 24], passive: 2, relative: 2, nominal: 0, testSentences: 7, mockRange: [180, 320], cefr: null,
  },
  ys8: {
    knownFiles: [...l.GENERAL_ALL, ...l.YDS_OLD, BANK1, BANK2], banks: { ys7: 10, ys5: 3 }, range: () => [250, 320],
    avg: [17, 27], passive: 3, relative: 2, nominal: 2, testSentences: 7, mockRange: [250, 330], cefr: 'B2',
  },
}[sec];
const known = l.seen(CFG.knownFiles);
l.fs.readFileSync(l.path.join(__dirname, 'function_words.txt'), 'utf8').split(/\s+/).filter(Boolean).forEach((w) => known.add(w));
if (process.env.NGSL) {
  l.fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1, 1001).forEach((r) => known.add(r.split(',')[0].toLowerCase()));
}
const bankWords = Object.fromEntries(Object.keys(CFG.banks).map((b) => [b, bankOf(b)]));
const allBank = Object.values(bankWords).flat();
const isKnown = (w) => known.has(w) || l.lemmas(w).some((x) => known.has(x)) || allBank.some((b) => !b.includes(' ') && ctx.uses(w, b));

function analyse(text) {
  const words = text.match(/\p{L}+(?:[-'’]\p{L}+)*/gu) || [];
  const sentences = text.split(/(?<=[.!?])\s+/).filter((s) => s.trim());
  // Proper nouns: capitalised and not sentence-initial.
  const initial = new Set(sentences.map((s) => (s.match(/\p{L}+/u) || [''])[0]));
  const unknown = [];
  for (const w of words) {
    if (/^\p{Lu}/u.test(w) && !initial.has(w)) continue;
    const parts = w.toLowerCase().split(/[-'’]/).filter((p) => p.length > 1);
    if (parts.some((p) => !isKnown(p))) unknown.push(w.toLowerCase());
  }
  const passive = (text.match(/\b(is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?(\w+ed|known|shown|given|taken|made|found|seen|built|written|done|grown|held|kept|led|paid|sold|told|thought|brought|caught|chosen|drawn|driven|eaten|fallen|forgotten|hidden|spoken|stolen|worn|won|understood|taught|spent|sent|set|put|cut|read|run|begun|broken|born|spread|felt|lost|meant|left)\b/gi) || []).length;
  const relative = (text.match(/\b(which|who|whom|whose)\b|, where\b|, when\b/gi) || []).length;
  // Nominalisations: distinct -tion/-sion/-ment/-ity/-ance/-ence nouns of 8+ letters.
  const nominal = new Set((text.toLowerCase().match(/\b[a-z]{4,}(?:tion|sion|ment|ity|ance|ence)s?\b/g) || [])).size;
  const used = Object.fromEntries(Object.entries(bankWords).map(([b, ws]) => [b, ws.filter((w) => ctx.uses(text, w))]));
  return { words: words.length, avg: words.length / sentences.length, unknown, pct: (100 * unknown.length) / words.length, passive, relative, nominal, used };
}

function passageRules(p, at, [min, max], strict = true) {
  const a = analyse(p);
  P(a.words >= min - 5 && a.words <= max + 10, `${at}: metin ${a.words} kelime (${min}–${max})`);
  if (!strict) return a;
  P(a.pct <= 5, `${at}: bilinmeyen kelime %${a.pct.toFixed(1)} (≤%5): ${[...new Set(a.unknown)].join(', ')}`);
  for (const [b, need] of Object.entries(CFG.banks)) P(a.used[b].length >= need, `${at}: ${b} kelimesi ${a.used[b].length} (≥${need})`);
  P(a.avg >= CFG.avg[0] && a.avg <= CFG.avg[1], `${at}: ortalama cümle ${a.avg.toFixed(1)} kelime (${CFG.avg[0] + 2}–${CFG.avg[1] - 2})`);
  P(a.passive >= CFG.passive, `${at}: edilgen yapı ${a.passive} (≥${CFG.passive})`);
  P(a.relative >= CFG.relative, `${at}: yan cümle (which/who/whose…) ${a.relative} (≥${CFG.relative})`);
  P(a.nominal >= CFG.nominal, `${at}: isimleştirme ${a.nominal} (≥${CFG.nominal})`);
  return a;
}
// At least one inference or attitude/purpose question per text (Faz 2b).
const deep = /infer|impl(y|ied)|attitude|purpose|conclude|suggest|tone|most likely|assume|why does the author/i;

if (id === '--text') {
  // node tool/yds/check_reading.js --text "passage" [--sec ys8] → quick numbers while writing
  const a = analyse(process.argv[3]);
  console.log(JSON.stringify({ ...a, unknown: [...new Set(a.unknown)] }, null, 1));
  process.exit(0);
}
const dist = [0, 0, 0, 0, 0];
const countAnswers = (ex) => ex.filter((e) => e.type === 'choice').forEach((e) => dist[e.answer]++);
const report = [];

// Half mocks: the section's own (ys6m, ys8m) and extra ones placed in a unit (ys8u1h …).
if (/^ys\d+(m|u\d+[hm])$/.test(id)) {
  const ex = data.exercises;
  P(Array.isArray(ex) && ex.length === 40 && ex.every((e) => e.type === 'choice'), 'deneme: 40 choice olmalı');
  ex.forEach((e, k) => exercise(e, `${id}#${k}`));
  const want = { vocabulary: 3, grammar: 5, cloze: 5, sentenceCompletion: 5, translation: 3, reading: 8, dialogue: 3, restatement: 2, paragraphCompletion: 2, irrelevantSentence: 4 };
  const got = {};
  ex.forEach((e) => { got[e.qtype] = (got[e.qtype] || 0) + 1; });
  for (const [k, v] of Object.entries(want)) P(got[k] === v, `deneme: ${k} ${got[k] || 0} (${v})`);
  const readP = [...new Set(ex.filter((e) => e.qtype === 'reading').map((e) => e.passage))];
  P(readP.length === 2 && readP.every(Boolean), `deneme: okuma 2 metin olmalı (${readP.length})`);
  const clozeP = [...new Set(ex.filter((e) => e.qtype === 'cloze').map((e) => e.passage))];
  P(clozeP.length === 1 && clozeP[0], `deneme: cloze 1 metin olmalı (${clozeP.length})`);
  readP.filter(Boolean).forEach((p, i) => report.push(['okuma ' + (i + 1), passageRules(p, `${id} okuma ${i + 1}`, CFG.mockRange, false)]));
  // New texts only: no topic overlap with anything already in the app or another new half mock.
  const ov = require('./overlap.js');
  const others = l.fs.readdirSync(dir).filter((f) => /^ys\d+(m|u\d+[hm])\.json$/.test(f) && f !== `${id}.json`)
    .flatMap((f) => JSON.parse(l.fs.readFileSync(l.path.join(dir, f), 'utf8')).exercises.filter((e) => e.passage).map((e) => [f, e.passage]));
  problems.push(...ov.overlaps([...readP, ...clozeP].filter(Boolean), [...ov.existingPassages(), ...others]));
  countAnswers(ex);
} else {
  const unit = data;
  const n = +id.slice(4);
  const range = CFG.range(n);
  P(unit.id === id, 'unit id');
  P(typeof unit.theme === 'string' && /^0xFF[0-9A-F]{6}$/.test(unit.color || ''), 'theme/color');
  P(typeof unit.guide === 'string' && unit.guide.length > 200 && unit.guide.split(/\s+/).length <= 330, 'guide 200 karakter – ~250 kelime');
  const ids = [`${id}l1`, `${id}l2`, `${id}l3`, `${id}l4`, `${id}t`, `${id}c`];
  P(unit.nodes.map((x) => x.id).join() === ids.join(), `düğümler ${unit.nodes.map((x) => x.id)} (${ids})`);
  for (const [i, node] of unit.nodes.entries()) {
    const ex = node.exercises || [];
    ex.forEach((e, k) => exercise(e, `${node.id}#${k}`));
    countAnswers(ex);
    P(typeof node.title === 'string' && typeof node.description === 'string', `${node.id}: title/description`);
    if (i < 3) {
      P(node.type === 'lesson', `${node.id}: lesson`);
      const r = node.reading || {};
      P(['fen', 'saglik', 'sosyal'].includes(r.field) && Number.isInteger(r.words) && typeof r.cefr === 'string', `${node.id}: reading {field, words, cefr}`);
      if (CFG.cefr) P(r.cefr === CFG.cefr, `${node.id}: reading.cefr ${CFG.cefr}`);
      for (const b of Object.keys(CFG.banks)) P(Array.isArray(r[b]) && r[b].length > 0, `${node.id}: reading.${b} listesi`);
      P(ex.length === 10, `${node.id}: 10 alıştırma (2 metin × 4 + 2)`);
      const ps = [...new Set(ex.filter((e) => e.passage).map((e) => e.passage))];
      P(ps.length === 2, `${node.id}: 2 metin olmalı (${ps.length})`);
      let total = 0;
      ps.forEach((p, k) => {
        const qs = ex.filter((e) => e.passage === p && e.qtype === 'reading');
        P(qs.length === 4, `${node.id}: metin ${k + 1} için 4 reading sorusu`);
        if (sec === 'ys8') P(qs.some((q) => deep.test(q.question)), `${node.id}: metin ${k + 1} için çıkarım ya da tutum sorusu yok`);
        const a = passageRules(p, `${node.id} metin ${k + 1}`, range);
        total += a.words;
        report.push([`${node.id}/${k + 1}`, a]);
      });
      P(Math.abs((r.words || 0) - total) <= 10, `${node.id}: reading.words ${r.words}, metinler ${total}`);
      P(ex.filter((e) => e.type === 'match' || e.type === 'fillBlank').length === 2, `${node.id}: 2 ek match/fillBlank`);
      P(/ys5 kelimeleri:|ys7 kelimeleri:/.test(node.description), `${node.id}: description kelime listesini ("ys5/ys7 kelimeleri: …") içermeli`);
    } else if (i === 3) {
      P(ex.length >= 8 && ex.length <= 10 && ex.every((e) => e.type === 'choice'), `${node.id}: 8–10 choice (cümle çözümleme)`);
      P(ex.every((e) => ['grammar', 'translation'].includes(e.qtype)), `${node.id}: qtype grammar/translation`);
      P(ex.filter((e) => e.qtype === 'translation').length >= 3, `${node.id}: en az 3 çeviri sorusu`);
      // F1 review: main-verb distractors are verb-like forms (relative-clause verb, participle, auxiliary).
      for (const [k, e] of ex.entries()) {
        if (sec === 'ys8' && /ana fiil/i.test(e.question)) {
          const verbish = e.options.filter((o) => /(ed|ing|en|s)$|^(is|are|was|were|has|have|had|can|could|may|might|must|will|would|should|do|does|did)\b/i.test(o.trim()));
          P(verbish.length >= 4, `${node.id}#${k}: ana fiil sorusunda şıkların en az 4'ü fiil biçimi olmalı (${e.options.join(' / ')})`);
        }
      }
    } else if (node.type === 'test') {
      P(node.rewardXp === 25 && ex.length === 15 && ex.every((e) => e.type === 'choice'), `${node.id}: 15 choice, rewardXp 25`);
      const ps = [...new Set(ex.filter((e) => e.qtype === 'reading').map((e) => e.passage))];
      P(ps.length === 2 && ps.every(Boolean), `${node.id}: 2 yeni metin (${ps.length})`);
      ps.filter(Boolean).forEach((p, k) => {
        P(ex.filter((e) => e.passage === p).length === 4, `${node.id}: metin ${k + 1} için 4 soru`);
        report.push([`${node.id}/${k + 1}`, passageRules(p, `${node.id} metin ${k + 1}`, range)]);
      });
      P(ex.filter((e) => ['translation', 'sentenceCompletion'].includes(e.qtype)).length === CFG.testSentences, `${node.id}: ${CFG.testSentences} cümle düzeyi soru (translation/sentenceCompletion)`);
    } else if (node.type === 'chest') {
      P(node.rewardXp === 20, `${node.id}: rewardXp 20`);
    }
  }
}
P(Math.max(...dist) <= dist.reduce((a, b) => a + b, 0) * 0.3, `doğru şık dağılımı dengesiz ${dist}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (doğru şık ${dist})`);
for (const [k, a] of report) {
  const banks = Object.entries(a.used).map(([b, ws]) => `${b} ${ws.length}`).join(', ');
  console.log(`  ${k}: ${a.words} kelime, ort. cümle ${a.avg.toFixed(1)}, bilinmeyen %${a.pct.toFixed(1)}, ${banks}, edilgen ${a.passive}, yan cümle ${a.relative}, isimleştirme ${a.nominal}`);
}
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
warn.forEach((p) => console.log('  ! ' + p));
process.exitCode = problems.length ? 1 : 0;
