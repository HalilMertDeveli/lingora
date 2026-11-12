// Checks a full YDS mock for assets/exam_packs/yds_full.json (YDS Faz 2c): tool/yds/work/<id>.json =
// {"id":"yds_m9","title":"Tam Deneme 9","minutes":180,"questions":[80]} — same layout as yds_m1–m8,
// qtype on every question, the content rules of rules.js, and new texts (no topic overlap with any
// passage already in the app: ys6, ys8, mocks m1–m8, extensive reading).
// Usage: node tool/yds/check_mock.js yds_m9
const l = require('./lex.js');
const id = process.argv[2];
const mock = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const { walk, exercise } = require('./rules.js')(P, problems);
walk(mock, id);

const LAYOUT = [['yds_vocab', 6, 'vocabulary'], ['yds_grammar', 10, 'grammar'], ['yds_cloze', 10, 'cloze'],
  ['yds_completion', 10, 'sentenceCompletion'], ['yds_translation', 6, 'translation'], ['yds_reading', 20, 'reading'],
  ['yds_dialogue', 6, 'dialogue'], ['yds_restatement', 3, 'restatement'], ['yds_paragraph', 4, 'paragraphCompletion'],
  ['yds_irrelevant', 5, 'irrelevantSentence']];
P(mock.id === id && /^Tam Deneme \d+$/.test(mock.title) && mock.minutes === 180, 'id/title/minutes');
const qs = mock.questions || [];
P(qs.length === 80, `soru sayısı ${qs.length} (80)`);
// Same order as the existing mocks: sections in layout order.
const expected = LAYOUT.flatMap(([s, n, t]) => Array.from({ length: n }, () => [s, t]));
qs.forEach((q, i) => {
  const at = q.id || `#${i}`;
  P(q.id === `${id}_q${String(i + 1).padStart(2, '0')}`, `${at}: id ${id}_q${String(i + 1).padStart(2, '0')} olmalı`);
  P(q.section === expected[i]?.[0], `${at}: section ${q.section} (${expected[i]?.[0]})`);
  P(q.qtype === expected[i]?.[1], `${at}: qtype ${q.qtype} (${expected[i]?.[1]})`);
  P((q.explanation || '').trim().length > 40, `${at}: açıklama kısa`);
  // Pack items use `text`; reuse the course-choice rules on the same fields.
  exercise({ type: 'choice', question: q.text, options: q.options, answer: q.answer, explanation: q.explanation, qtype: q.qtype, ...(q.passage === undefined ? {} : { passage: q.passage }) }, at);
});

// Passages: 2 cloze texts × 5, 5 reading texts × 4, reading 250–330 words.
const groups = (sec) => [...new Set(qs.filter((q) => q.section === sec).map((q) => q.passage))];
const cloze = groups('yds_cloze');
P(cloze.length === 2 && cloze.every(Boolean), `cloze 2 metin olmalı (${cloze.length})`);
for (const p of cloze.filter(Boolean)) P(qs.filter((q) => q.passage === p).length === 5, 'her cloze metninde 5 soru');
const reading = groups('yds_reading');
P(reading.length === 5 && reading.every(Boolean), `okuma 5 metin olmalı (${reading.length})`);
for (const p of reading.filter(Boolean)) {
  const w = (p.match(/\p{L}+/gu) || []).length;
  P(w >= 230 && w <= 340, `okuma metni ${w} kelime (250–330): ${p.slice(0, 50)}…`);
  P(qs.filter((q) => q.passage === p).length === 4, 'her okuma metninde 4 soru');
}

// Topic overlap with every passage already in the app.
const stop = new Set('the a an and of to in is are was were that this it for on with as by be from at or which who have has had their they its not but can more than been also into about such these those many most some may other one two when there would could after over so if what how our we you he she his her them'.split(' '));
const bag = (t) => new Set((t.toLowerCase().match(/[a-z]{5,}/g) || []).filter((w) => !stop.has(w)));
const existing = [];
const fromSection = (f) => {
  if (!l.fs.existsSync(l.path.join(l.ROOT, f))) return;
  for (const u of l.J(f).units) for (const n of u.nodes) for (const e of n.exercises || []) if (e.passage && e.passage.split(/\s+/).length > 120) existing.push([n.id, e.passage]);
};
fromSection('assets/courses/exam_yds/06_okuma_evi_1.json');
fromSection('assets/courses/exam_yds/08_okuma_evi_2.json');
for (const m of l.J('assets/exam_packs/yds_full.json').mocks) if (m.id !== id) for (const q of m.questions) if (q.passage) existing.push([m.id, q.passage]);
for (const f of l.fs.readdirSync(l.path.join(l.ROOT, 'assets/reading'))) for (const s of l.J(`assets/reading/${f}`)) existing.push([s.id, s.text]);
// Other new full mocks being written alongside this one.
for (const other of l.fs.readdirSync(l.path.join(__dirname, 'work')).filter((f) => /^yds_m\d+\.json$/.test(f)).map((f) => f.slice(0, -5)).filter((x) => x !== id && !l.J('assets/exam_packs/yds_full.json').mocks.some((m) => m.id === x))) {
  const f = l.path.join(__dirname, 'work', `${other}.json`);
  if (l.fs.existsSync(f)) for (const q of JSON.parse(l.fs.readFileSync(f, 'utf8')).questions || []) if (q.passage) existing.push([other, q.passage]);
}
const seen = new Set();
for (const p of [...cloze, ...reading].filter(Boolean)) {
  const a = bag(p);
  for (const [src, t] of existing) {
    const b = bag(t);
    let c = 0;
    for (const w of a) if (b.has(w)) c++;
    const jac = c / (a.size + b.size - c);
    const key = `${src}|${p.slice(0, 30)}`;
    if (jac > 0.18 && !seen.has(key)) { seen.add(key); problems.push(`konu örtüşmesi ${jac.toFixed(2)} (${src}): ${p.slice(0, 60)}…`); }
  }
}
const dist = [0, 0, 0, 0, 0];
qs.forEach((q) => Number.isInteger(q.answer) && dist[q.answer]++);
P(Math.max(...dist) < 80 * 0.3 && Math.min(...dist) > 80 * 0.12, `doğru şık dağılımı ${dist}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (doğru şık ${dist})`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
