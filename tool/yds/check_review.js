// Checks a ys11 "Ara denemeler" mixed-review unit (YDS Faz 3d) from tool/yds/work/ys11uN.json:
// 4 lessons of 10–12 choice (1 grammar+cloze, 2 sentenceCompletion+translation, 3 reading,
// 4 dialogue/restatement/paragraph), a 15-question mixed test, a chest; the half mock is added at build.
// Usage: node tool/yds/check_review.js ys11u1
const l = require('./lex.js');
const ov = require('./overlap.js');
const id = process.argv[2];
const unit = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const { walk, exercise } = require('./rules.js')(P, problems);
walk(unit, id);

const LESSONS = [
  ['grammar', 'cloze'],
  ['sentenceCompletion', 'translation'],
  ['reading'],
  ['dialogue', 'restatement', 'paragraphCompletion', 'irrelevantSentence'],
];
P(unit.id === id && typeof unit.theme === 'string' && /^0xFF[0-9A-F]{6}$/.test(unit.color || ''), 'id/theme/color');
P(typeof unit.guide === 'string' && unit.guide.length > 200 && unit.guide.split(/\s+/).length <= 330, 'guide 200 karakter – ~250 kelime');
const ids = [`${id}l1`, `${id}l2`, `${id}l3`, `${id}l4`, `${id}t`, `${id}c`];
P(unit.nodes.map((n) => n.id).join() === ids.join(), `düğümler ${unit.nodes.map((n) => n.id)} (${ids})`);
const dist = [0, 0, 0, 0, 0];
const passages = [];
for (const [i, n] of unit.nodes.entries()) {
  const ex = n.exercises || [];
  P(typeof n.title === 'string' && typeof n.description === 'string', `${n.id}: title/description`);
  ex.forEach((e, k) => exercise(e, `${n.id}#${k}`));
  ex.forEach((e) => { if (Number.isInteger(e.answer)) dist[e.answer]++; if (e.passage && e.passage.split(/\s+/).length > 120) passages.push(e.passage); });
  if (i < 4) {
    P(n.type === 'lesson' && ex.length >= 10 && ex.length <= 12 && ex.every((e) => e.type === 'choice'), `${n.id}: 10–12 choice`);
    P(ex.every((e) => LESSONS[i].includes(e.qtype)), `${n.id}: qtype ${LESSONS[i].join('/')} olmalı`);
    for (const t of LESSONS[i].slice(0, i === 3 ? 4 : 2)) P(ex.some((e) => e.qtype === t), `${n.id}: ${t} sorusu yok`);
  } else if (n.type === 'test') {
    P(n.rewardXp === 25 && ex.length === 15 && ex.every((e) => e.type === 'choice'), `${n.id}: 15 choice, rewardXp 25`);
    P(new Set(ex.map((e) => e.qtype)).size >= 7, `${n.id}: en az 7 farklı soru tipi (karışık)`);
  } else if (n.type === 'chest') {
    P(n.rewardXp === 20, `${n.id}: rewardXp 20`);
  }
}
P(Math.max(...dist) <= dist.reduce((a, b) => a + b, 0) * 0.3, `doğru şık dağılımı ${dist}`);
const others = l.fs.readdirSync(l.path.join(__dirname, 'work')).filter((f) => /^ys11u\d+m?\.json$/.test(f) && f !== `${id}.json`)
  .flatMap((f) => {
    const d = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', f), 'utf8'));
    return (d.exercises || (d.nodes || []).flatMap((n) => n.exercises || [])).filter((e) => e.passage).map((e) => [f, e.passage]);
  });
problems.push(...ov.overlaps([...new Set(passages)], [...ov.existingPassages(), ...others]));

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (doğru şık ${dist})`);
problems.slice(0, 50).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
