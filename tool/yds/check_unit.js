// Checks one ys5 word-bank unit and its cards before it is merged into 05_kelime_bankasi_1.json.
// Usage: node tool/yds/check_unit.js ys5u3   (reads tool/yds/work/ys5u3.json and ys5u3.cards.json)
// Mirrors test/course_content_test.dart + content_quality_test.dart and the Phase 1 spec (§2.3–2.4).
const l = require('./lex.js');
const ctx = require('./context.js');
const id = process.argv[2];
const dir = l.path.join(__dirname, 'work');
const unit = JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.json`), 'utf8'));
const cards = JSON.parse(l.fs.readFileSync(l.path.join(dir, `${id}.cards.json`), 'utf8'));
const words = require('./work/words.json');
const mine = words[id];
const earlier = Object.keys(words).filter((k) => +k.slice(4) < +id.slice(4)).flatMap((k) => words[k]);
const problems = [];
const warn = [];
const P = (ok, m) => { if (!ok) problems.push(m); };

const QTYPES = ['vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue',
  'restatement', 'paragraphCompletion', 'irrelevantSentence'];
const POS_RE = /(ilk|birinci|ikinci|üçüncü|dördüncü|beşinci|son) (seçene|şık)|\b[A-E] şık|\b[A-E]\) (seçene|şık)/i; // kalite-turu PR #38
const strCheck = (where, key, s) => {
  if (s !== s.trim()) problems.push(`${where}: baş/son boşluk`);
  if (/[^\s] {2,}[^\s]/.test(s)) problems.push(`${where}: çift boşluk`);
  if ((key === 'guide' ? /�|&nbsp;|<\/?[a-z]+>/ : /�|\*\*|&nbsp;|<\/?[a-z]+>/).test(s)) problems.push(`${where}: yasak işaret (** ya da html)`);
};
const walk = (v, where, key = '') => {
  if (typeof v === 'string') strCheck(where, key, v);
  else if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${where}[${i}]`, key));
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, `${where}.${k}`, k);
};
walk(unit, id);
walk(cards, `${id}.cards`);

const article = (q, opts) => {
  const m = /\b([Aa]n?) (?:_{3,}|-{3,})/.exec(q);
  if (!m) return false;
  return new Set(opts.map((o) => /^[aeiouAEIOU]/.test(o.trim()))).size > 1;
};
const norm = (s) => s.replace(/İ/g, 'i').toLowerCase().replace(/’/g, "'").replace(/[.,!?;:¿¡"]/g, ' ').replace(/\s+/g, ' ').trim();
const buildable = (a, toks) => {
  const bank = {};
  toks.forEach((t) => norm(t).split(' ').filter(Boolean).forEach((w) => { bank[w] = (bank[w] || 0) + 1; }));
  for (const w of norm(a).split(' ').filter(Boolean)) { if (!bank[w]) return false; bank[w]--; }
  return true;
};

function exercise(e, at) {
  const str = (v) => typeof v === 'string' && v.trim();
  switch (e.type) {
    case 'choice': {
      P(str(e.question), `${at}: question yok`);
      P(Array.isArray(e.options) && e.options.length === 5, `${at}: 5 şık olmalı`);
      P(new Set((e.options || []).map((o) => o.trim().toLowerCase())).size === (e.options || []).length, `${at}: aynı şık`);
      P(Number.isInteger(e.answer) && e.answer >= 0 && e.answer < 5, `${at}: answer 0–4`);
      P(str(e.explanation) && /[çğıöşüÇĞİÖŞÜ]/.test(e.explanation), `${at}: Türkçe açıklama yok`);
      P(!POS_RE.test((e.explanation || '').replace(/İ/g, 'i')),`${at}: açıklama şıkkı konumla anıyor`);
      P(!/\b[A-E]\)|şık [A-E]\b|\([A-E]\)/.test(e.explanation || ''), `${at}: açıklama harf ile anıyor`);
      P(!article(e.question || '', e.options || []), `${at}: a/an ipucu`);
      P(!('passage' in e) || str(e.passage), `${at}: passage boş`);
      P(QTYPES.includes(e.qtype), `${at}: qtype yok ya da geçersiz (${e.qtype})`);
      if (/\(\d\)-{4}/.test(e.passage || '')) P(e.qtype === 'cloze', `${at}: numaralı boşluklu paragraf → qtype cloze`);
      if (e.explanation && e.options) {
        P(e.explanation.toLowerCase().includes(e.options[e.answer].toLowerCase().slice(0, 40)) || /[“‘'"]/.test(e.explanation),
          `${at}: açıklama doğru şıkkı metniyle anmıyor`);
      }
      break;
    }
    case 'match': {
      P(Array.isArray(e.pairs) && e.pairs.length >= 3 && e.pairs.every((p) => p.length === 2 && str(p[0]) && str(p[1])), `${at}: pairs`);
      const L = new Set(e.pairs.map((p) => norm(p[0]))), R = new Set(e.pairs.map((p) => norm(p[1])));
      P(L.size === e.pairs.length && R.size === e.pairs.length, `${at}: çiftler benzersiz değil`);
      // Match tiles are one line high (lib/exercises/match_exercise.dart, height 28): longer text is cut off.
      for (const p of e.pairs) P(p[0].length <= 18 && p[1].length <= 18, `${at}: eşleştirme metni 18 karakteri aşıyor: ${p.join(' / ')}`);
      break;
    }
    case 'fillBlank': {
      P(str(e.text) && (e.text.match(/___/g) || []).length === 1, `${at}: tek ___ olmalı`);
      P(str(e.translation), `${at}: translation yok`);
      P(Array.isArray(e.choices) && e.choices.length >= 2 && e.choices.includes(e.answer), `${at}: choices/answer`);
      P(new Set((e.choices || []).map((c) => c.toLowerCase())).size === (e.choices || []).length, `${at}: aynı seçenek`);
      P(!article(e.text || '', e.choices || []), `${at}: a/an ipucu`);
      break;
    }
    case 'translate': {
      P(str(e.text) && (e.lang === 'tr' || e.lang === 'en'), `${at}: text/lang`);
      P(Array.isArray(e.answers) && e.answers.length && Array.isArray(e.tokens), `${at}: answers/tokens`);
      P((e.answers || []).some((a) => buildable(a, e.tokens || [])), `${at}: cevap token'larla kurulamıyor`);
      P(new Set((e.answers || []).map(norm)).size === (e.answers || []).length, `${at}: aynı cevap iki kez`);
      break;
    }
    default:
      problems.push(`${at}: beklenmeyen tür ${e.type}`);
  }
}

// Unit shape.
P(unit.id === id, 'unit id');
P(typeof unit.theme === 'string' && typeof unit.color === 'string' && /^0xFF[0-9A-F]{6}$/.test(unit.color), 'theme/color');
P(typeof unit.guide === 'string' && unit.guide.length > 200, 'guide kısa');
const gw = (unit.guide || '').split(/\s+/).length;
P(gw <= 330, `guide ${gw} kelime (≤ ~250 hedef)`);
const types = unit.nodes.map((n) => n.type).join(',');
const last = id === 'ys5u10';
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
      P(w >= 70 && w <= 135, `${n.id}: paragraf ${w} kelime (80–120)`);
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
const ex = new Set([...l.taught(l.GENERAL), ...l.taught(l.YDS_OLD)]);
const clash = mine.filter((w) => ex.has(w));
P(!clash.length, `daha önce öğretilmiş: ${clash.join(', ')}`);

console.log(`${id}: ${problems.length ? 'HATA ' + problems.length : 'TAMAM'}  (choice dağılımı ${dist}, uyarı ${warn.length})`);
problems.slice(0, 60).forEach((p) => console.log('  ✗ ' + p));
warn.slice(0, 20).forEach((p) => console.log('  ! ' + p));
process.exitCode = problems.length ? 1 : 0;
