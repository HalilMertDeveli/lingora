// Checks the C1 sections of the general course (docs/genel-mufredat.md §2 "Faz 4–5"):
// assets/courses/tr_en/09_*.json and 10_*.json, normal section files.
//
//   node tool/content/check_c1.mjs [file ...]        (RUBRIC_DIR=<dir> adds draft rubrics)
//
// Per unit: lesson,lesson,story,lesson,lesson,test,chest; l1/l2 language lessons (8–10);
// odd units l3 listening (listen×4 of 15–25 words, shadow×2 at rate 1.0, fillBlank×2, match×1)
// and l4 speaking (shadow×2, speak×4, select×2, translate×1); even units l3 reading (one
// 500–800-word text, choice×6) and l4 writing (write×1 of 220–300 words, translate×3 from the
// model, fillBlank×3, select×1, match×1). Story listenFirst, 450–650 words, 5 questions.
// The last unit's test is the C1 skills test (6 listen, 8 choice on 2 texts, 4 tr→en, 2
// language). Guide headings, themes, rubric match, answer balance, repeats across the course.
// The general exercise rules (answers in choices, buildable tokens…) are in course_content_test.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const lex = require('../yds/lex.js');

const dir = 'assets/courses/tr_en';
const files = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs.readdirSync(dir).filter((f) => /^(09|10)_[a-z0-9_]+\.json$/.test(f)).map((f) => path.join(dir, f));
const themes = new Set([...fs.readFileSync('lib/data/topic_themes.dart', 'utf8').matchAll(/id: '([a-z_]+)'/g)].map((m) => m[1]));
const rubrics = JSON.parse(fs.readFileSync('functions/src/writing_tasks.json', 'utf8'));
if (process.env.RUBRIC_DIR) {
  for (const f of fs.readdirSync(process.env.RUBRIC_DIR).filter((f) => f.endsWith('.json'))) {
    Object.assign(rubrics, JSON.parse(fs.readFileSync(path.join(process.env.RUBRIC_DIR, f), 'utf8')));
  }
}
const focusTypes = new Set(['article', 'tense', 'preposition', 'word_order', 'be']);
const normalize = (s) => s.replaceAll('İ', 'i').toLowerCase().replaceAll('’', "'").replace(/[.,!?;:¿¡"]/g, ' ').replace(/\s+/g, ' ').trim();
const words = (s) => (s ?? '').trim().split(/\s+/).filter(Boolean).length;
const between = (n, lo, hi) => n >= lo && n <= hi;
const count = (xs, t) => xs.filter((e) => e.type === t).length;
const sig = (xs) => ['listen', 'shadow', 'speak', 'fillBlank', 'select', 'match', 'translate', 'choice', 'write'].map((t) => count(xs, t)).join();
const linking = /\b(want to|going to|got to|have to|did you|do you|would you|could you|a lot of|kind of|sort of|out of|let me|I'd|I'll|you'll|we'll|it's|that's|there's|he's|she's|I've|we've|you've|isn't|aren't|wasn't|doesn't|don't|didn't|haven't|hasn't|wouldn't|couldn't|shouldn't|won't|can't|must've|might've|should've|would've|could've|at the|in the|on the|of the|to the|and a|as a|it is|what I|that I)\b/i;

// Exercise texts already in the course, for repeats.
// A reading question is the same question only on the same text ("Metnin ana fikri ne?" recurs).
const keyOf = (e) =>
  `${e.type}:${normalize(e.text ?? e.prompt ?? e.question ?? JSON.stringify(e.pairs ?? ''))}${e.type === 'choice' ? `:${normalize(e.passage ?? '').slice(0, 60)}` : ''}`;
const seen = new Map();
for (const f of ['../tr_en.json', ...fs.readdirSync(dir).filter((f) => f.endsWith('.json'))]) {
  if (files.some((x) => path.basename(x) === f)) continue;
  for (const u of JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')).units) {
    for (const n of u.nodes) for (const e of n.exercises ?? []) seen.set(keyOf(e), n.id);
  }
}

// Reading texts (curriculum, C1 rule): at most 5% unknown words, where "known" is every word
// used in S1–S8 (tool/yds/lex.js), function words and NGSL (NGSL=<csv>, not shipped).
const known = new Set(fs.readFileSync('tool/yds/function_words.txt', 'utf8').split(/\s+/).filter(Boolean));
const courseFiles = ['assets/courses/tr_en.json', ...fs.readdirSync(dir).filter((f) => /^0[1-8]/.test(f)).map((f) => `${dir}/${f}`)];
for (const w of lex.seen(courseFiles)) known.add(w);
if (process.env.NGSL) {
  for (const r of fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1)) known.add(r.split(',')[0].toLowerCase());
} else console.warn('NGSL= verilmedi: okuma metni bilinmeyen oranı katı hesaplanır.');
// A later C1 section also knows the words of the C1 sections before it (S10 knows S9).
const knownBefore = new Map();
for (const f of fs.readdirSync(dir).filter((f) => /^(09|10)_[a-z0-9_]+\.json$/.test(f)).sort()) {
  knownBefore.set(f, new Set(knownBefore.size ? lex.seen([...knownBefore.keys()].map((x) => `${dir}/${x}`)) : []));
}
let sectionKnown = new Set();
const isKnown = (w) => known.has(w) || sectionKnown.has(w) || lex.lemmas(w).some((x) => known.has(x) || sectionKnown.has(x));

// YDS banks ys7 and later: their card words may appear in text but may not be taught as targets
// (match pairs, fillBlank answers, the right option of a choice), as test/yds_kelime_bankasi_test.dart checks.
const bankWords = new Set(
  JSON.parse(fs.readFileSync('assets/vocab/yds.json', 'utf8'))
    .entries.filter((e) => Number((/^ys(\d+)u/.exec(e.topic) ?? [])[1]) >= 7)
    .map((e) => e.word.toLowerCase()),
);
const taughtWords = (e) =>
  e.type === 'match'
    ? e.pairs.map((p) => p[1])
    : e.type === 'fillBlank'
      ? [e.answer]
      : e.type === 'choice'
        ? [e.options?.[e.answer]]
        : [];
const contraction = (w) => {
  const m = w.match(/^(\p{L}+)['’](t|s|re|ll|ve|d|m)$/u);
  if (!m) return null;
  return m[2] === 't' ? ({ won: 'will', can: 'can' }[m[1]] ?? m[1].replace(/n$/, '')) : m[1];
};
/** Share of unknown words in an English text (names inside a sentence skipped), 0–100. */
function unknownPct(text) {
  const ws = text.match(/\p{L}+(?:[-'’]\p{L}+)*/gu) ?? [];
  const initial = new Set(text.split(/(?<=[.!?…"”:])\s+/).map((x) => (x.match(/\p{L}+/u) ?? [''])[0]));
  let unknown = 0;
  for (const w of ws) {
    if (/^\p{Lu}/u.test(w) && !initial.has(w)) continue;
    const lw = w.toLowerCase();
    const b = contraction(lw);
    if (b && isKnown(b)) continue;
    if (lw.split(/[-'’]/).filter((x) => x.length > 1).some((x) => !isKnown(x))) unknown++;
  }
  return (100 * unknown) / Math.max(ws.length, 1);
}
/** Target words a unit teaches: English sides of l1/l2 match pairs, select and fillBlank answers. */
function targets(u) {
  const out = new Set();
  for (const n of u.nodes.slice(0, 2)) {
    for (const e of n.exercises ?? []) {
      if (e.type === 'match') e.pairs.forEach((x) => out.add(x[1].toLowerCase()));
      if (e.type === 'fillBlank' || e.type === 'select') out.add(String(e.answer).toLowerCase());
    }
  }
  return out;
}

const problems = [];
const say = (at, m) => problems.push(`${at}: ${m}`);
const rows = [];
for (const file of files) {
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  const s = j.section ?? {};
  const index = s.index;
  if (s.cefr !== 'C1') say(file, 'section.cefr C1');
  // A draft file outside assets is checked as the section its index names.
  const own = [...knownBefore.keys()].find((f) => f.startsWith(String(index).padStart(2, '0')));
  sectionKnown = own ? knownBefore.get(own) : index === 10 ? lex.seen([...knownBefore.keys()].filter((f) => f.startsWith('09')).map((x) => `${dir}/${x}`)) : new Set();
  for (const u of j.units ?? []) {
    for (const n of u.nodes) {
      for (const [i, e] of (n.exercises ?? []).entries()) {
        for (const w of taughtWords(e)) if (bankWords.has(String(w).trim().toLowerCase())) say(`${n.id}#${i}`, `"${w}" is a YDS ys7+ bank word: not as a target`);
      }
    }
  }
  const letters = [0, 0, 0, 0];
  for (const [ui, u] of (j.units ?? []).entries()) {
    const no = ui + 1;
    const uid = `s${index}u${no}`;
    const odd = no % 2 === 1;
    const last = ui === j.units.length - 1;
    if (u.id !== uid) say(u.id, `id should be ${uid}`);
    if (!themes.has(u.theme)) say(uid, `theme ${u.theme}`);
    const headings = ['Yapı', 'Bu ünitede yapabileceklerin', 'Strateji', 'Türklerin sık hatası', ...(odd ? [] : ['Model metin']), ...(last ? ['Beceri testi'] : [])];
    for (const h of headings) if (!(u.guide ?? '').includes(`## ${h}`)) say(uid, `guide lacks "## ${h}"`);
    const types = u.nodes.map((n) => n.type).join(',');
    if (types !== 'lesson,lesson,story,lesson,lesson,test,chest') { say(uid, `pattern ${types}`); continue; }
    const [l1, l2, st, l3, l4, t, c] = u.nodes;
    ['l1', 'l2', 's', 'l3', 'l4', 't', 'c'].forEach((x, i) => u.nodes[i].id !== uid + x && say(uid, `node id ${u.nodes[i].id}`));
    for (const n of [l1, l2, l3, l4]) {
      if (!between((n.exercises ?? []).length, 8, 10)) say(n.id, `${n.exercises?.length} exercises (8–10)`);
      for (const [i, e] of (n.exercises ?? []).entries()) {
        const k = keyOf(e);
        if (seen.has(k)) say(`${n.id}#${i}`, `repeats ${seen.get(k)}`);
        else seen.set(k, `${n.id}#${i}`);
        if (e.type === 'choice') {
          letters[e.answer]++;
          if (!(e.explanation ?? '').toLowerCase().includes(String(e.options?.[e.answer]).toLowerCase().slice(0, 12))) say(`${n.id}#${i}`, 'explanation should quote the right option');
          if (e.options?.length !== 4) say(`${n.id}#${i}`, '4 options');
        }
      }
    }
    for (const n of [l1, l2]) if ((n.exercises ?? []).some((e) => ['write', 'shadow', 'choice'].includes(e.type))) say(n.id, 'language lesson: no write/shadow/choice');
    const row = { unit: uid, title: u.title, kind: odd ? 'dinleme/konuşma' : 'okuma/yazma', targets: targets(u).size };
    if (row.targets > 60) say(uid, `${row.targets} target words (≤60)`);
    if (odd) {
      if (sig(l3.exercises) !== '4,2,0,2,0,1,0,0,0') say(l3.id, 'C1 listening: listen×4, shadow×2, fillBlank×2, match×1');
      for (const e of l3.exercises.filter((e) => e.type === 'listen')) {
        if (!between(words(e.text), 15, 25)) say(l3.id, `listen ${words(e.text)} words (15–25): ${e.text}`);
        if (!e.answers?.some((a) => normalize(a) === normalize(e.text))) say(l3.id, 'listen text not among answers');
      }
      for (const e of [...l3.exercises, ...l4.exercises].filter((e) => e.type === 'shadow')) if (e.rate !== 1) say(u.id, 'C1 shadow rate 1.0');
      if (sig(l4.exercises) !== '0,2,4,0,2,0,1,0,0') say(l4.id, 'C1 speaking: shadow×2, speak×4, select×2, translate×1');
      const listens = l3.exercises.filter((e) => e.type === 'listen');
      const linked = listens.filter((e) => linking.test(e.text)).length;
      row.linking = `${linked}/${listens.length}`;
      if (linked * 2 < listens.length) say(l3.id, `only ${linked}/${listens.length} listen sentences with connected speech`);
    } else {
      const ch = l3.exercises.filter((e) => e.type === 'choice');
      const passages = new Set(ch.map((e) => e.passage));
      if (ch.length !== 6 || passages.size !== 1) say(l3.id, 'C1 reading: one text, choice×6');
      row.reading = words([...passages][0]);
      const pct = unknownPct([...passages][0] ?? '');
      row.unknown = `${pct.toFixed(1)}%`;
      if (pct > 5) say(l3.id, `reading text ${pct.toFixed(1)}% unknown words (≤5%)`);
      if (!between(row.reading, 500, 800)) say(l3.id, `reading ${row.reading} words (500–800)`);
      if (sig(l4.exercises) !== '0,0,0,3,1,1,3,0,1') say(l4.id, 'C1 writing: write×1, translate×3, fillBlank×3, select×1, match×1');
      const w = l4.exercises.find((e) => e.type === 'write');
      if (w) {
        row.write = `${w.minWords}–${w.maxWords} / ${words(w.model)}`;
        if (w.taskId !== `${l4.id}w`) say(l4.id, `taskId ${l4.id}w`);
        if (!(w.minWords >= 220 && w.maxWords <= 300 && w.maxWords > w.minWords)) say(l4.id, 'C1 write 220–300 words');
        if (!between(words(w.model), w.minWords, w.maxWords)) say(l4.id, `model ${words(w.model)} words`);
        if (!between(w.checklist?.length ?? 0, 3, 5)) say(l4.id, 'checklist 3–5');
        if (!(w.focus?.length >= 1 && w.focus.length <= 3 && w.focus.every((x) => focusTypes.has(x)))) say(l4.id, 'focus 1–3 known types');
        const model = normalize(w.model ?? '');
        for (const e of l4.exercises.filter((e) => e.type === 'translate' && e.lang === 'tr')) {
          if (!e.answers.some((a) => model.includes(normalize(a)))) say(l4.id, `translate "${e.answers[0]}" not in the model`);
        }
        if (!(u.guide ?? '').includes(w.model.split('\n')[0].slice(0, 40))) say(uid, 'guide model text differs from the write model');
        const r = rubrics[w.taskId];
        if (!r) say(l4.id, `no rubric ${w.taskId}`);
        else {
          if (r.level !== 'C1' || r.minWords !== w.minWords || r.maxWords !== w.maxWords) say(l4.id, 'rubric level/length');
          if ([...r.focus].sort().join() !== [...w.focus].sort().join()) say(l4.id, 'rubric focus');
          if (!/^Can-do:/.test(r.rubric ?? '') || r.rubric.length < 150) say(l4.id, 'rubric must start "Can-do:" and say what success looks like');
        }
      }
    }
    // Listen-first story.
    const lines = st.steps.filter((x) => x.kind === 'line');
    const qs = st.steps.filter((x) => x.kind === 'question');
    row.story = lines.reduce((a, x) => a + words(x.text), 0);
    if (st.listenFirst !== true) say(st.id, 'listenFirst');
    if (!between(row.story, 450, 650) || qs.length !== 5) say(st.id, `story ${row.story} words, ${qs.length} questions (450–650, 5)`);
    for (const q of qs) if (!q.choices.includes(q.answer)) say(st.id, `answer not in choices: ${q.prompt}`);
    if (st.rewardXp !== 15 || t.rewardXp !== 25 || c.rewardXp !== 20) say(uid, 'xp 15/25/20');
    // Skills test.
    const te = t.exercises ?? [];
    if (last) {
      if (t.title !== `Bölüm ${index} beceri testi` || t.description !== 'Bu bölümün hedeflerini ölçer') say(t.id, 'skills test title/description');
      const mix = [count(te, 'listen'), count(te, 'choice'), count(te, 'translate'), count(te, 'fillBlank') + count(te, 'select')].join();
      if (mix !== '6,8,4,2') say(t.id, `mix ${mix} (6,8,4,2)`);
      const tp = new Set(te.filter((e) => e.type === 'choice').map((e) => e.passage));
      if (tp.size !== 2) say(t.id, '2 reading texts × 4');
      if (te.some((e) => e.type === 'translate' && e.lang !== 'tr')) say(t.id, 'translate tr→en');
      for (const [i, e] of te.entries()) {
        if (e.type === 'choice') letters[e.answer]++;
        const k = keyOf(e);
        if (seen.has(k)) say(`${t.id}#${i}`, `repeats ${seen.get(k)}`);
        else seen.set(k, `${t.id}#${i}`);
      }
    } else if (te.length) say(t.id, 'only the last unit test has questions');
    rows.push(row);
  }
  const total = letters.reduce((a, b) => a + b, 0);
  if (total && Math.max(...letters) >= total * 0.4) say(file, `answer positions ${letters}`);
}
console.table(rows);
console.log(problems.length ? `${problems.length} problem(s):\n${problems.join('\n')}` : 'OK');
process.exit(problems.length ? 1 : 0);
