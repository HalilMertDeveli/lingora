// Checks one ys5 word-bank unit and its cards before it is merged into 05_kelime_bankasi_1.json.
// Usage: node tool/yds/check_unit.js ys5u3   (reads tool/yds/work/ys5u3.json and ys5u3.cards.json)
// Mirrors test/course_content_test.dart + content_quality_test.dart and the Phase 1 spec (§2.3–2.4).
const l = require('./lex.js');
const ctx = require('./context.js');
const id = process.argv[2];
const dir = l.path.join(__dirname, 'work');
const unit = JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.json`), 'utf8'));
const cards = JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.cards.json`), 'utf8'));
// ys5 (F1) and ys7 (F2) word banks share this checker; the section decides list, level and exclusions.
const sec = id.slice(0, 3);
const words = require(sec === 'ys7' ? './work/words_ys7.json' : './work/words.json');
const mine = words[id];
const earlier = Object.keys(words).filter((k) => +k.slice(4) < +id.slice(4)).flatMap((k) => words[k]);
const lastUnit = sec === 'ys7' ? 'ys7u15' : 'ys5u10';
const [pMin, pMax, pLabel] = sec === 'ys7' ? [110, 170, '120–160'] : [70, 135, '80–120'];
const problems = [];
const warn = [];
const P = (ok, m) => { if (!ok) problems.push(m); };

const { walk, exercise } = require('./rules.js')(P, problems);
walk(unit, id);
walk(cards, `${id}.cards`);
// Unit shape.
P(unit.id === id, 'unit id');
P(typeof unit.theme === 'string' && typeof unit.color === 'string' && /^0xFF[0-9A-F]{6}$/.test(unit.color), 'theme/color');
P(typeof unit.guide === 'string' && unit.guide.length > 200, 'guide kısa');
const gw = (unit.guide || '').split(/\s+/).length;
P(gw <= 330, `guide ${gw} kelime (≤ ~250 hedef)`);
const types = unit.nodes.map((n) => n.type).join(',');
const last = id === lastUnit;
P(types === (last ? 'lesson,lesson,lesson,lesson,test,chest,mock' : 'lesson,lesson,lesson,lesson,test,chest'), `düğüm deseni ${types}`);
const ids = [`${id}l1`, `${id}l2`, `${id}l3`, `${id}l4`, `${id}t`, `${id}c`, ...(last ? [`${id}m`] : [])];
P(unit.nodes.map((n) => n.id).join() === ids.join(), `düğüm id'leri ${unit.nodes.map((n) => n.id)}`);
const answers = [];
for (const [i, n] of unit.nodes.entries()) {
  P(typeof n.title === 'string' && typeof n.description === 'string', `${n.id}: title/description`);
  const ex = n.exercises || [];
  ex.forEach((e, k) => exercise(e, `${n.id}#${k}`));
  ex.filter((e) => e.type === 'choice').forEach((e) => answers.push(e.answer));
  const count = (t) => ex.filter((e) => e.type === t).length;
  if (i < 3) {
    P(n.vocab === true, `${n.id}: vocab:true`);
    P(ex.length >= 10 && ex.length <= 12, `${n.id}: ${ex.length} alıştırma (10–12)`);
    P(count('match') >= 2 && ex.filter((e) => e.type === 'match').every((e) => e.pairs.length === 5), `${n.id}: en az 2 match, 5'er çift`);
    P(count('fillBlank') >= 3, `${n.id}: en az 3 fillBlank`);
    P(count('choice') >= 4, `${n.id}: en az 4 choice`);
    P(count('translate') >= 1 && count('translate') <= 2, `${n.id}: 1–2 translate`);
  } else if (i === 3) {
    P(ex.length >= 10 && ex.length <= 12, `${n.id}: ${ex.length} alıştırma (10–12)`);
    const passages = new Set(ex.filter((e) => e.passage).map((e) => e.passage));
    P(passages.size >= 2, `${n.id}: en az 2 cloze paragrafı`);
    for (const p of passages) {
      const w = p.split(/\s+/).length;
      P(w >= pMin && w <= pMax, `${n.id}: paragraf ${w} kelime (${pLabel})`);
      const qs = ex.filter((e) => e.passage === p).length;
      P(qs >= 3 && qs <= 4, `${n.id}: paragraf başına 3–4 soru (${qs})`);
      const used = mine.filter((m) => ctx.uses(p, m));
      if (used.length < 8) warn.push(`${n.id}: paragraf ünite kelimesi ${used.length}`);
    }
    const all = [...passages].join(' ');
    const reused = mine.filter((m) => ctx.uses(all, m));
    P(reused.length >= 15, `${n.id}: paragraflar ünite kelimelerinden ${reused.length} kullanıyor (≥15)`);
  } else if (n.type === 'test') {
    P(ex.length === 15 && ex.every((e) => e.type === 'choice'), `${n.id}: 15 choice`);
    P(n.rewardXp === 25, `${n.id}: rewardXp 25`);
    if (earlier.length) {
      const mixed = ex.filter((e) => earlier.some((w) => ctx.uses(`${e.question} ${e.passage || ''}`, w) || e.options[e.answer].toLowerCase() === w));
      P(mixed.length >= 4, `${n.id}: önceki ünitelerden kelime kullanan soru ${mixed.length} (≥4)`);
    }
  } else if (n.type === 'chest') {
    P(n.rewardXp === 20, `${n.id}: rewardXp 20`);
  } else if (n.type === 'mock') {
    P(n.examId === 'yds' && n.size === 30 && n.minutes === 35, `${n.id}: mock yds/30/35`);
  }
}
// Answer letters spread.
const dist = [0, 0, 0, 0, 0];
answers.forEach((a) => dist[a]++);
P(Math.max(...dist) <= answers.length * 0.3, `doğru şık dağılımı dengesiz ${dist}`);

// Word coverage: each unit word in context (sentences/passages, not options) at least twice in the unit.
const texts = ctx.unitContexts(unit);
const thin = mine.filter((w) => texts.filter((t) => ctx.uses(t, w)).length < 2);
P(thin.length <= 4, `bağlamda 2 kez geçmeyen kelime ${thin.length}: ${thin.join(', ')}`);
if (thin.length) warn.push(`bağlamda <2: ${thin.join(', ')}`);

// Cards.
P(Array.isArray(cards) && cards.length === mine.length, `kart sayısı ${cards.length} (${mine.length})`);
const cw = new Set(cards.map((c) => c.word));
const missing = mine.filter((w) => !cw.has(w));
P(!missing.length, `kartı olmayan kelime: ${missing.join(', ')}`);
const extra = cards.map((c) => c.word).filter((w) => !mine.includes(w));
P(!extra.length, `listede olmayan kart: ${extra.join(', ')}`);
for (const c of cards) {
  const at = `kart ${c.word}`;
  P(c.id === `yd_${String(c.word).replace(/ /g, '_')}`, `${at}: id`);
  P(c.topic === id, `${at}: topic`);
  P(typeof c.pos === 'string', `${at}: pos`);
  P(Array.isArray(c.senses) && c.senses.length && c.senses.every((s) => s.tr && s.def), `${at}: senses tr/def`);
  P(Array.isArray(c.examples) && c.examples.length >= 1 && c.examples.every((x) => x.en && x.tr && x.target && x.en.includes(x.target)), `${at}: örnek (en/tr/target, target cümlede)`);
  P(Array.isArray(c.collocations) && c.collocations.length >= 1 && c.collocations.every((x) => x.phrase && x.answer && x.tr && x.phrase.includes(x.answer)), `${at}: eşdizim`);
  if (/verb|noun/.test(c.pos)) P(Array.isArray(c.family), `${at}: family`);
}

// Overlap with taught words.
const ex = sec === 'ys7'
  ? new Set([...l.taught(l.GENERAL_ALL), ...l.taught([...l.YDS_OLD, 'assets/courses/exam_yds/05_kelime_bankasi_1.json']),
    ...l.J('assets/vocab/yds.json').entries.filter((e) => e.topic.startsWith('ys5u')).map((e) => e.word.toLowerCase())])
  : new Set([...l.taught(l.GENERAL), ...l.taught(l.YDS_OLD)]);
const clash = mine.filter((w) => ex.has(w));
P(!clash.length, `daha önce öğretilmiş: ${clash.join(', ')}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (choice dağılımı ${dist}, uyarı ${warn.length})`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
warn.slice(0, 20).forEach((p) => console.log('  ! ' + p));
process.exitCode = problems.length ? 1 : 0;
