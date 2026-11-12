// Checks one ys6 "Okuma evi 1" unit (tool/yds/work/ys6uN.json) or the diagnostic half mock
// (tool/yds/work/ys6m.json = {"exercises":[40 choice]}) against the Phase 1 spec (§3, §4).
// Usage: node tool/yds/check_reading.js ys6u3 | ys6m | --text "…"      (optional NGSL=<NGSL 1.2 csv> adds its top 1000)
const l = require('./lex.js');
const ctx = require('./context.js');
const id = process.argv[2];
const dir = l.path.join(__dirname, 'work');
const data = id === '--text' ? {} : JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.json`), 'utf8'));
const problems = [];
const warn = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const { walk, exercise } = require('./rules.js')(P, problems);
walk(data, id);

// ---- vocabulary: what the learner knows by now ----
const BANK = 'assets/courses/exam_yds/05_kelime_bankasi_1.json';
const bankWords = l.J('assets/vocab/yds.json').entries.filter((e) => e.topic.startsWith('ys5u')).map((e) => e.word);
const known = new Set([...l.seen(l.GENERAL), ...l.seen(l.YDS_OLD), ...l.seen([BANK])]);
l.fs.readFileSync(l.path.join(__dirname, 'function_words.txt'), 'utf8').split(/\s+/).filter(Boolean).forEach((w) => known.add(w));
if (process.env.NGSL) {
  l.fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1, 1001).forEach((r) => known.add(r.split(',')[0].toLowerCase()));
}
const isKnown = (w) => known.has(w) || l.lemmas(w).some((x) => known.has(x)) || bankWords.some((b) => !b.includes(' ') && ctx.uses(w, b));

function analyse(text) {
  const words = text.match(/[A-Za-z]+(?:[-'][A-Za-z]+)*/g) || [];
  const sentences = text.split(/(?<=[.!?])\s+/).filter((s) => s.trim());
  // Proper nouns: capitalised and not sentence-initial.
  const initial = new Set(sentences.map((s) => (s.match(/[A-Za-z]+/) || [''])[0]));
  const unknown = [];
  for (const w of words) {
    if (/^[A-Z]/.test(w) && !initial.has(w)) continue;
    const parts = w.toLowerCase().split(/[-']/).filter((p) => p.length > 1);
    if (parts.some((p) => !isKnown(p))) unknown.push(w.toLowerCase());
  }
  const passive = (text.match(/\b(is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?(\w+ed|known|shown|given|taken|made|found|seen|built|written|done|grown|held|kept|led|paid|sold|told|thought|brought|caught|chosen|drawn|driven|eaten|fallen|forgotten|hidden|spoken|stolen|worn|won|understood|taught|spent|sent|set|put|cut|read|run|begun|broken|born|spread|felt|lost|meant|left)\b/gi) || []).length;
  const relative = (text.match(/\b(which|who|whom|whose)\b|, where\b|, when\b/gi) || []).length;
  const used = bankWords.filter((b) => ctx.uses(text, b));
  return { words: words.length, avg: words.length / sentences.length, unknown, pct: (100 * unknown.length) / words.length, passive, relative, used };
}

function passageRules(p, at, [min, max], strict = true) {
  const a = analyse(p);
  P(a.words >= min - 5 && a.words <= max + 10, `${at}: metin ${a.words} kelime (${min}–${max})`);
  if (!strict) return a;
  P(a.pct <= 5, `${at}: bilinmeyen kelime %${a.pct.toFixed(1)} (≤%5): ${[...new Set(a.unknown)].join(', ')}`);
  P(a.used.length >= 8, `${at}: ys5 kelimesi ${a.used.length} (≥8)`);
  P(a.avg >= 13 && a.avg <= 24, `${at}: ortalama cümle ${a.avg.toFixed(1)} kelime (15–22)`);
  P(a.passive >= 2, `${at}: edilgen yapı ${a.passive} (≥2)`);
  P(a.relative >= 2, `${at}: yan cümle (which/who/whose…) ${a.relative} (≥2)`);
  return a;
}

if (id === '--text') {
  // node tool/yds/check_reading.js --text "passage" → quick numbers while writing
  const a = analyse(process.argv[3]);
  console.log(JSON.stringify({ ...a, unknown: [...new Set(a.unknown)], used: a.used }, null, 1));
  process.exit(0);
}
const dist = [0, 0, 0, 0, 0];
const countAnswers = (ex) => ex.filter((e) => e.type === 'choice').forEach((e) => dist[e.answer]++);
const report = [];

if (id === 'ys6m') {
  const ex = data.exercises;
  P(Array.isArray(ex) && ex.length === 40 && ex.every((e) => e.type === 'choice'), 'deneme: 40 choice olmalı');
  ex.forEach((e, k) => exercise(e, `ys6m#${k}`));
  const want = { vocabulary: 3, grammar: 5, cloze: 5, sentenceCompletion: 5, translation: 3, reading: 8, dialogue: 3, restatement: 2, paragraphCompletion: 2, irrelevantSentence: 4 };
  const got = {};
  ex.forEach((e) => { got[e.qtype] = (got[e.qtype] || 0) + 1; });
  for (const [k, v] of Object.entries(want)) P(got[k] === v, `deneme: ${k} ${got[k] || 0} (${v})`);
  const readP = [...new Set(ex.filter((e) => e.qtype === 'reading').map((e) => e.passage))];
  P(readP.length === 2 && readP.every(Boolean), `deneme: okuma 2 metin olmalı (${readP.length})`);
  const clozeP = [...new Set(ex.filter((e) => e.qtype === 'cloze').map((e) => e.passage))];
  P(clozeP.length === 1 && clozeP[0], `deneme: cloze 1 metin olmalı (${clozeP.length})`);
  readP.filter(Boolean).forEach((p, i) => report.push(['okuma ' + (i + 1), passageRules(p, `ys6m okuma ${i + 1}`, [180, 320], false)]));
  countAnswers(ex);
} else {
  const unit = data;
  const n = +id.slice(4);
  const range = n <= 2 ? [150, 220] : [200, 350];
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
      P(ex.length === 10, `${node.id}: 10 alıştırma (2 metin × 4 + 2)`);
      const ps = [...new Set(ex.filter((e) => e.passage).map((e) => e.passage))];
      P(ps.length === 2, `${node.id}: 2 metin olmalı (${ps.length})`);
      let total = 0;
      ps.forEach((p, k) => {
        P(ex.filter((e) => e.passage === p && e.qtype === 'reading').length === 4, `${node.id}: metin ${k + 1} için 4 reading sorusu`);
        const a = passageRules(p, `${node.id} metin ${k + 1}`, range);
        total += a.words;
        report.push([`${node.id}/${k + 1}`, a]);
      });
      P(Math.abs((r.words || 0) - total) <= 10, `${node.id}: reading.words ${r.words}, metinler ${total}`);
      P(ex.filter((e) => e.type === 'match' || e.type === 'fillBlank').length === 2, `${node.id}: 2 ek match/fillBlank`);
      P(/ys5 kelimeleri:/.test(node.description), `${node.id}: description "ys5 kelimeleri: …" listesini içermeli`);
    } else if (i === 3) {
      P(ex.length >= 8 && ex.length <= 10 && ex.every((e) => e.type === 'choice'), `${node.id}: 8–10 choice (cümle çözümleme)`);
      P(ex.every((e) => ['grammar', 'translation'].includes(e.qtype)), `${node.id}: qtype grammar/translation`);
      P(ex.filter((e) => e.qtype === 'translation').length >= 3, `${node.id}: en az 3 çeviri sorusu`);
    } else if (node.type === 'test') {
      P(node.rewardXp === 25 && ex.length === 15 && ex.every((e) => e.type === 'choice'), `${node.id}: 15 choice, rewardXp 25`);
      const ps = [...new Set(ex.filter((e) => e.qtype === 'reading').map((e) => e.passage))];
      P(ps.length === 2 && ps.every(Boolean), `${node.id}: 2 yeni metin (${ps.length})`);
      ps.filter(Boolean).forEach((p, k) => {
        P(ex.filter((e) => e.passage === p).length === 4, `${node.id}: metin ${k + 1} için 4 soru`);
        report.push([`${node.id}/${k + 1}`, passageRules(p, `${node.id} metin ${k + 1}`, range)]);
      });
      P(ex.filter((e) => ['translation', 'sentenceCompletion'].includes(e.qtype)).length === 7, `${node.id}: 7 cümle düzeyi soru (translation/sentenceCompletion)`);
    } else if (node.type === 'chest') {
      P(node.rewardXp === 20, `${node.id}: rewardXp 20`);
    }
  }
}
P(Math.max(...dist) <= dist.reduce((a, b) => a + b, 0) * 0.3, `doğru şık dağılımı dengesiz ${dist}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (doğru şık ${dist})`);
for (const [k, a] of report) console.log(`  ${k}: ${a.words} kelime, ort. cümle ${a.avg.toFixed(1)}, bilinmeyen %${a.pct.toFixed(1)}, ys5 ${a.used.length}, edilgen ${a.passive}, yan cümle ${a.relative}`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
warn.forEach((p) => console.log('  ! ' + p));
process.exitCode = problems.length ? 1 : 0;
