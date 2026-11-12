// Checks a full mock for assets/exam_packs/yds_full.json: tool/yds/work/<id>.json =
// {"id":"yds_m9","title":"Tam Deneme 9","minutes":180,"questions":[80]} — same layout as yds_m1–m8 (YDS), or
// {"id":"yokdil_m1","title":"YÖKDİL Fen denemesi 1","field":"fen","minutes":180,"questions":[80]} in the YÖKDİL
// layout (YDS Faz 4c). Checks qtype on every question, the content rules of rules.js, and new texts (no topic
// overlap with any passage already in the app or another new mock).
// Usage: node tool/yds/check_mock.js yds_m15 | yokdil_m1
const l = require('./lex.js');
const ov = require('./overlap.js');
const id = process.argv[2];
const mock = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const { walk, exercise } = require('./rules.js')(P, problems);
walk(mock, id);

const yokdil = id.startsWith('yokdil_');
const n = +id.match(/\d+$/)[0];
// [section, count, qtype]
const LAYOUT = yokdil
  // Real YÖKDİL order (araştırma §1.3): no dialogue or restatement; translation 6 EN→TR + 6 TR→EN.
  ? [['yokdil_vocab', 6, 'vocabulary'], ['yokdil_grammar', 14, 'grammar'], ['yokdil_cloze', 10, 'cloze'],
    ['yokdil_completion', 11, 'sentenceCompletion'], ['yokdil_translation', 12, 'translation'], ['yokdil_reading', 15, 'reading'],
    ['yokdil_paragraph', 6, 'paragraphCompletion'], ['yokdil_irrelevant', 6, 'irrelevantSentence']]
  : [['yds_vocab', 6, 'vocabulary'], ['yds_grammar', 10, 'grammar'], ['yds_cloze', 10, 'cloze'],
    ['yds_completion', 10, 'sentenceCompletion'], ['yds_translation', 6, 'translation'], ['yds_reading', 20, 'reading'],
    ['yds_dialogue', 6, 'dialogue'], ['yds_restatement', 3, 'restatement'], ['yds_paragraph', 4, 'paragraphCompletion'],
    ['yds_irrelevant', 5, 'irrelevantSentence']];
const FIELD_TITLE = { fen: 'Fen', saglik: 'Sağlık', sosyal: 'Sosyal' };
if (yokdil) {
  P(FIELD_TITLE[mock.field], `field fen|saglik|sosyal (${mock.field})`);
  P(mock.id === id && mock.title === `YÖKDİL ${FIELD_TITLE[mock.field]} denemesi 1` && mock.minutes === 180, 'id/title/minutes');
} else {
  // m8 and m20 close a plan stage: "Tam Deneme N · Son prova".
  P(mock.id === id && new RegExp(`^Tam Deneme ${n}( · Son prova)?$`).test(mock.title) && mock.minutes === 180, 'id/title/minutes');
}
const qs = mock.questions || [];
P(qs.length === 80, `soru sayısı ${qs.length} (80)`);
const expected = LAYOUT.flatMap(([s, k, t]) => Array.from({ length: k }, () => [s, t]));
qs.forEach((q, i) => {
  const at = q.id || `#${i}`;
  P(q.id === `${id}_q${String(i + 1).padStart(2, '0')}`, `${at}: id ${id}_q${String(i + 1).padStart(2, '0')} olmalı`);
  P(q.section === expected[i]?.[0], `${at}: section ${q.section} (${expected[i]?.[0]})`);
  P(q.qtype === expected[i]?.[1], `${at}: qtype ${q.qtype} (${expected[i]?.[1]})`);
  P((q.explanation || '').trim().length > 40, `${at}: açıklama kısa`);
  // Pack items use `text`; reuse the course-choice rules on the same fields.
  exercise({ type: 'choice', question: q.text, options: q.options, answer: q.answer, explanation: q.explanation, qtype: q.qtype, ...(q.passage === undefined ? {} : { passage: q.passage }) }, at);
});

// Passages. YDS: 2 cloze × 5, 5 reading × 4 (250–330 words; m19–m20 "a notch above": 280–380).
// YÖKDİL: 2 cloze × 5, 5 reading × 3 (250–350 words).
const prefix = yokdil ? 'yokdil' : 'yds';
const groups = (sec) => [...new Set(qs.filter((q) => q.section === `${prefix}_${sec}`).map((q) => q.passage))];
const cloze = groups('cloze');
P(cloze.length === 2 && cloze.every(Boolean), `cloze 2 metin olmalı (${cloze.length})`);
for (const p of cloze.filter(Boolean)) P(qs.filter((q) => q.passage === p).length === 5, 'her cloze metninde 5 soru');
const reading = groups('reading');
const perText = yokdil ? 3 : 4;
const [rMin, rMax] = yokdil ? [250, 350] : n >= 19 ? [280, 380] : [250, 330];
P(reading.length === 5 && reading.every(Boolean), `okuma 5 metin olmalı (${reading.length})`);
for (const p of reading.filter(Boolean)) {
  const w = (p.match(/\p{L}+/gu) || []).length;
  P(w >= rMin - 20 && w <= rMax + 10, `okuma metni ${w} kelime (${rMin}–${rMax}): ${p.slice(0, 50)}…`);
  P(qs.filter((q) => q.passage === p).length === perText, `her okuma metninde ${perText} soru`);
}
// YÖKDİL field weighting: the mock lists the field of each cloze and reading text (≥ 70 % from its own field).
if (yokdil) {
  const tf = mock.textFields || [];
  P(tf.length === 7 && tf.every((f) => FIELD_TITLE[f]), `textFields: 7 alan (2 cloze + 5 okuma, sırayla) (${tf.length})`);
  P(tf.filter((f) => f === mock.field).length >= 5, `metinlerin ≥ %70'i ${mock.field} alanından olmalı (${tf.filter((f) => f === mock.field).length}/7)`);
}

// Topic overlap with every passage already in the app and the other new mocks being written alongside.
const shipped = new Set(l.J('assets/exam_packs/yds_full.json').mocks.map((m) => m.id));
const others = l.fs.readdirSync(l.path.join(__dirname, 'work')).filter((f) => /^(yds|yokdil)_m\d+\.json$/.test(f))
  .map((f) => f.slice(0, -5)).filter((x) => x !== id && !shipped.has(x))
  .flatMap((x) => (JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${x}.json`), 'utf8')).questions || [])
    .filter((q) => q.passage).map((q) => [x, q.passage]));
problems.push(...ov.overlaps([...cloze, ...reading].filter(Boolean), [...ov.existingPassages((s) => s === id), ...others]));

const dist = [0, 0, 0, 0, 0];
qs.forEach((q) => Number.isInteger(q.answer) && dist[q.answer]++);
P(Math.max(...dist) < 80 * 0.3 && Math.min(...dist) > 80 * 0.12, `doğru şık dağılımı ${dist}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (doğru şık ${dist})`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
