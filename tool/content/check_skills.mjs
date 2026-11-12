// Checks the general course's skill-unit extension files (assets/courses/tr_en/NNx_*.json)
// against docs/genel-mufredat.md: the same rules as test/course_content_test.dart and
// test/content_quality_test.dart, plus the skill-unit lesson recipe, the section skills
// test, repetition against the whole course and word counts for the PR description.
//
//   node tool/content/check_skills.mjs [file ...]     (default: every NNx_*.json)
//
// Exit code 1 when a problem is found. Fast enough to run after every edit.
//
// Sections 5+ (B1–B2) follow the "Faz 2b ders kalıbı": shadow, a listen-first
// story, one `write` per unit with its server rubric. Rubrics are read from
// functions/src/writing_tasks.json and, while content is being written, from
// every *.json in $RUBRIC_DIR (same shape, merged later).
import fs from 'node:fs';
import path from 'node:path';

const dir = 'assets/courses/tr_en';
const all = ['../tr_en.json', ...fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort()];
const targets = process.argv.slice(2).map((f) => path.basename(f));
const extFiles = targets.length ? targets : all.filter((f) => /^\d\dx_/.test(f));
const rubrics = JSON.parse(fs.readFileSync('functions/src/writing_tasks.json', 'utf8'));
if (process.env.RUBRIC_DIR) {
  for (const f of fs.readdirSync(process.env.RUBRIC_DIR).filter((f) => f.endsWith('.json'))) {
    Object.assign(rubrics, JSON.parse(fs.readFileSync(path.join(process.env.RUBRIC_DIR, f), 'utf8')));
  }
}
const focusTypes = new Set(['article', 'tense', 'preposition', 'word_order', 'be']);
const themes = new Set(
  [...fs.readFileSync('lib/data/topic_themes.dart', 'utf8').matchAll(/id: '([a-z_]+)'/g)].map((m) => m[1]),
);

const asciiTurkish = ['tesekkur', 'tesekkurler', 'gunaydin', 'nasilsin', 'nasilsiniz', 'ogrenci', 'ogretmen',
  'degil', 'degilim', 'guzel', 'icin', 'simdi', 'bugun', 'yarin', 'gorusuruz', 'lutfen', 'konusmak', 'calismak',
  'ogrenmek', 'sehir', 'kucuk', 'buyuk', 'universite', 'musteri', 'kahvalti', 'aksam', 'hosgeldiniz', 'tanistigima',
  'calisiyorum', 'ingilizce', 'turkce', 'turkiye', 'ogle', 'cumle', 'yapiyorum', 'odeme', 'gorusme', 'sirket'];

const normalize = (s) => s.replaceAll('İ', 'i').toLowerCase().replaceAll('’', "'")
  .replace(/[.,!?;:¿¡"]/g, ' ').replace(/\s+/g, ' ').trim();
const words = (s) => s.trim().split(/\s+/).filter(Boolean).length;
const buildable = (answer, tokens) => {
  const bank = new Map();
  for (const t of tokens) for (const w of normalize(t).split(' ').filter(Boolean)) bank.set(w, (bank.get(w) ?? 0) + 1);
  for (const w of normalize(answer).split(' ').filter(Boolean)) {
    if (!bank.get(w)) return false;
    bank.set(w, bank.get(w) - 1);
  }
  return true;
};
const giveaway = (text, options) => {
  if (!/\b[Aa]n? (?:_{3,}|-{3,})/.test(text)) return false;
  return new Set(options.map((o) => /^[aeiou]/i.test(o.trim()))).size > 1;
};
const dupes = (xs, f = (x) => x.trim().toLowerCase()) => xs.filter((x, i) => xs.map(f).indexOf(f(x)) !== i);
const between = (n, lo, hi) => n >= lo && n <= hi;
// Connected-speech markers for listen sentences (curriculum §5.3).
const linking = /\b(want to|going to|got to|have to|has to|did you|do you|would you|could you|can you|what are you|a lot of|kind of|some of|out of|cup of|lots of|let me|give me|tell me|don't you|didn't you|won't|can't|I'd|I'll|you'll|we'll|it's|that's|there's|he's|she's|I've|we've|isn't|aren't|wasn't|doesn't|don't|didn't|haven't|at the|in the|on the|for a|to the|and a|an hour|an apple|first of|next to|look at|pick it up|turn it|get up|is it|was it|can I|have a|has a)\b/i;

const problems = [];
const say = (where, msg) => problems.push(`${where}: ${msg}`);

// Exercise keys of the base course, for the repetition check.
const baseKeys = new Map();
const keyOf = (e) => `${e.type}:${normalize(e.text ?? e.prompt ?? e.question ?? JSON.stringify(e.pairs ?? ''))}`;
for (const f of all.filter((f) => !/^\d\dx_/.test(f))) {
  const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  for (const u of j.units) for (const n of u.nodes) for (const e of n.exercises ?? []) baseKeys.set(keyOf(e), n.id);
}
const extKeys = new Map();

const report = [];
for (const f of extFiles) {
  const file = path.join(dir, f);
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  const m = f.match(/^(\d\d)x_[a-z0-9_]+\.json$/);
  if (!m) { say(f, 'name must be NNx_slug.json'); continue; }
  const index = Number(m[1]);
  const level = index <= 2 ? 'A1' : index <= 4 ? 'A2' : index <= 6 ? 'B1' : 'B2';
  const textRange = { A1: [60, 90], A2: [100, 150], B1: [200, 300], B2: [300, 450] }[level];
  if (j.extends !== `s${index}`) say(f, `extends must be s${index}`);
  if (Object.keys(j).some((k) => k !== 'extends' && k !== 'units')) say(f, 'only extends and units');
  const letters = new Map();
  let choices = 0;

  // Whitespace, artifacts and ASCII Turkish in every string.
  const walk = (v, where, key = '') => {
    if (typeof v === 'string') {
      if (key === 'id' || key === 'theme') return;
      if (v !== v.trim()) say(where, 'leading/trailing space');
      if (/[^\s] {2,}[^\s]/.test(v)) say(where, 'double space');
      if ((key === 'guide' ? /�|&nbsp;|<\/?[a-z]+>/ : /�|\*\*|&nbsp;|<\/?[a-z]+>/).test(v)) say(where, 'artifact (** only in guide)');
      for (const w of asciiTurkish) {
        const r = new RegExp(`(^|[^\\p{L}])(${w}|${w[0].toUpperCase()}${w.slice(1)})($|[^\\p{L}])`, 'u');
        if (r.test(v)) say(where, `"${w}" lacks Turkish characters`);
      }
    } else if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${where}[${i}]`, key));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, `${where}.${k}`, k);
  };
  walk(j, f);

  const checkExercise = (e, at, level) => {
    switch (e.type) {
      case 'select': {
        const texts = (e.choices ?? []).map((c) => c.text);
        if (!e.prompt || texts.length < 2 || texts.some((t) => !t)) say(at, 'select needs prompt and {text, emoji} choices');
        if (!texts.includes(e.answer)) say(at, `answer "${e.answer}" not in choices`);
        if (dupes(texts).length) say(at, 'duplicate choices');
        if (texts.some((t) => t.length > 35)) say(at, 'select choice longer than 35 chars');
        break;
      }
      case 'fillBlank':
        if ((e.text?.match(/___/g) ?? []).length !== 1) say(at, 'exactly one ___');
        if (!e.translation) say(at, 'translation missing');
        if (!(e.choices?.length >= 2) || !e.choices.includes(e.answer)) say(at, 'answer not in choices');
        if (dupes(e.choices ?? []).length) say(at, 'duplicate choices');
        if (giveaway(e.text ?? '', e.choices ?? [])) say(at, 'a/an giveaway');
        break;
      case 'translate':
        if (!e.text || !['tr', 'en'].includes(e.lang)) say(at, 'text/lang');
        if (!(e.answers?.length) || !(e.tokens?.length)) say(at, 'answers/tokens missing');
        else if (!e.answers.some((a) => buildable(a, e.tokens))) say(at, `no answer buildable from tokens: ${e.answers[0]}`);
        if (dupes(e.answers ?? [], normalize).length) say(at, 'duplicate answers');
        break;
      case 'listen':
        if (!e.text || !(e.answers?.length)) say(at, 'listen text/answers');
        if (dupes(e.answers ?? [], normalize).length) say(at, 'duplicate answers');
        if (e.answers && !e.answers.some((a) => normalize(a) === normalize(e.text))) say(at, 'listen text not among answers');
        break;
      case 'match': {
        const pairs = e.pairs ?? [];
        if (pairs.length < 3 || pairs.some((p) => p.length !== 2 || !p[0] || !p[1])) say(at, 'match needs ≥3 pairs');
        if (dupes(pairs.map((p) => p[0])).length || dupes(pairs.map((p) => p[1])).length) say(at, 'match pairs not unique');
        break;
      }
      case 'speak':
        if (!e.text) say(at, 'speak text');
        break;
      case 'shadow':
        if (!e.text || !e.translation) say(at, 'shadow text/translation');
        if (e.rate != null && !(e.rate >= 0.5 && e.rate <= 1.2)) say(at, 'shadow rate 0.5–1.2');
        break;
      case 'write': {
        const m = words(e.model ?? '');
        if (!e.prompt || !e.model) say(at, 'write prompt/model');
        if (!(e.minWords > 0) || !(e.maxWords >= e.minWords)) say(at, 'write min/maxWords');
        if (m < e.minWords || m > e.maxWords) say(at, `write model ${m} words (${e.minWords}–${e.maxWords})`);
        if (!between(e.checklist?.length ?? 0, 3, 5)) say(at, 'write checklist 3–5 items');
        if (!(e.focus?.length >= 1 && e.focus.length <= 3) || e.focus.some((x) => !focusTypes.has(x))) {
          say(at, 'write focus 1–3 of article/tense/preposition/word_order/be');
        }
        const r = rubrics[e.taskId];
        if (!r) say(at, `no server rubric for ${e.taskId}`);
        else {
          if (r.minWords !== e.minWords || r.maxWords !== e.maxWords) say(at, 'rubric length differs');
          if ([...r.focus].sort().join() !== [...(e.focus ?? [])].sort().join()) say(at, 'rubric focus differs');
          if (r.level !== level) say(at, `rubric level ${r.level} (${level})`);
          if (!r.rubric || r.rubric.length < 120 || !r.task || !(r.checklist?.length >= 3)) say(at, 'rubric task/checklist/rubric text too thin');
        }
        break;
      }
      case 'choice': {
        const o = e.options ?? [];
        if (o.length !== 4) say(at, 'tr_en choice needs 4 options');
        if (dupes(o).length) say(at, 'duplicate options');
        if (!Number.isInteger(e.answer) || e.answer < 0 || e.answer >= o.length) say(at, 'answer index');
        if (!e.question || !e.explanation) say(at, 'question/explanation');
        if (/(ilk|ikinci|üçüncü|dördüncü|beşinci|son) (seçenek|şık)/i.test(e.explanation ?? '')) say(at, 'explanation refers to option position');
        if (e.answer >= 0 && e.answer < o.length && !(e.explanation ?? '').toLowerCase().includes(o[e.answer].toLowerCase().slice(0, 12))) {
          say(at, 'explanation should quote the right option text');
        }
        if (giveaway(e.question ?? '', o)) say(at, 'a/an giveaway');
        if ('passage' in e && !e.passage) say(at, 'empty passage');
        choices++;
        letters.set(e.answer, (letters.get(e.answer) ?? 0) + 1);
        break;
      }
      default:
        say(at, `unknown type ${e.type}`);
    }
    const k = keyOf(e);
    if (baseKeys.has(k)) say(at, `repeats base exercise ${baseKeys.get(k)}`);
    else if (extKeys.has(k)) say(at, `repeats ${extKeys.get(k)}`);
    else extKeys.set(k, at);
  };

  const count = (xs, t) => xs.filter((e) => e.type === t).length;
  const b2b = index >= 5; // Faz 2b recipe (B1–B2)
  const baseFile = index === 1 ? '../tr_en.json' : all.find((x) => x.startsWith(`${f.slice(0, 2)}_`));
  const firstUnit = JSON.parse(fs.readFileSync(path.join(dir, baseFile), 'utf8')).units.length + 1;
  for (const [ui, u] of j.units.entries()) {
    const uid = `s${index}u${firstUnit + ui}`;
    const W = `${f}/${u.id}`;
    if (u.id !== uid) say(W, `id should be ${uid}`);
    if (!themes.has(u.theme)) say(W, `unknown theme ${u.theme}`);
    if (!/^0x[0-9A-Fa-f]{8}$/.test(u.color ?? '')) say(W, 'color');
    for (const h of ['Bu ünitede yapabileceklerin', 'Strateji', 'Model metin', 'Türklerin sık hatası']) {
      if (!(u.guide ?? '').includes(h)) say(W, `guide lacks "${h}"`);
    }
    const types = u.nodes.map((n) => n.type).join(',');
    if (types !== 'lesson,lesson,story,lesson,lesson,test,chest') say(W, `pattern ${types}`);
    const ids = ['l1', 'l2', 's', 'l3', 'l4', 't', 'c'].map((x) => uid + x);
    u.nodes.forEach((n, i) => n.id !== ids[i] && say(W, `node id ${n.id} should be ${ids[i]}`));
    const [l1, l2, s, l3, l4, t, c] = u.nodes;
    const row = { unit: u.id, title: u.title };
    for (const n of [l1, l2, l3, l4]) {
      const ex = n.exercises ?? [];
      if (!between(ex.length, 8, 10)) say(`${W}/${n.id}`, `${ex.length} exercises (8–10)`);
      ex.forEach((e, i) => checkExercise(e, `${n.id}#${i}`, level));
      if (!n.title || !n.description) say(n.id, 'title/description');
    }
    // Lesson recipes (curriculum §1, "Faz 2b ders kalıbı" for B1–B2).
    const e1 = l1.exercises, e2 = l2.exercises, e3 = l3.exercises, e4 = l4.exercises;
    if (b2b) {
      const sig = (xs) =>
        ['listen', 'shadow', 'speak', 'fillBlank', 'select', 'match', 'translate', 'choice', 'write'].map((t) => count(xs, t)).join();
      if (sig(e1) !== '4,2,0,2,0,1,0,0,0') say(l1.id, 'B1–B2 listening: listen×4, shadow×2, fillBlank×2, match×1');
      const [lo, hi] = level === 'B1' ? [10, 16] : [12, 20];
      for (const e of e1.filter((e) => e.type === 'listen')) {
        if (!between(words(e.text), lo, hi)) say(l1.id, `listen "${e.text}" ${words(e.text)} words (${lo}–${hi})`);
      }
      if (!between(count(e2, 'choice'), 5, 6) || count(e2, 'match') !== 1 || count(e2, 'fillBlank') + count(e2, 'select') !== 2) {
        say(l2.id, 'B1–B2 reading: choice×5–6, match×1, fillBlank/select×2');
      }
      if (sig(e3) !== '0,2,4,0,2,0,1,0,0') say(l3.id, 'B1–B2 speaking: shadow×2, speak×4, select×2, translate×1');
      if (sig(e4) !== '0,0,0,3,1,1,3,0,1') say(l4.id, 'B1–B2 writing: write×1, translate×3, fillBlank×3, select×1, match×1');
      const w = e4.find((e) => e.type === 'write');
      if (w) {
        if (w.taskId !== `${l4.id}w`) say(l4.id, `taskId should be ${l4.id}w`);
        const model = normalize(w.model ?? '');
        for (const e of e4.filter((e) => e.type === 'translate' && e.lang === 'tr')) {
          if (!e.answers.some((a) => model.includes(normalize(a)))) say(l4.id, `translate "${e.answers[0]}" is not a sentence of the model text`);
        }
      }
    } else if (!between(count(e1, 'listen'), 5, 6) || count(e1, 'fillBlank') < 2 || count(e1, 'speak') < 1 || count(e1, 'match') < 1) {
      say(l1.id, 'listening recipe: listen×5–6, fillBlank×2, speak×1, match×1');
    }
    const listens = [...e1, ...(t.exercises ?? [])].filter((e) => e.type === 'listen');
    const linked = listens.filter((e) => linking.test(e.text)).length;
    row.linking = `${linked}/${listens.length}`;
    if (linked * 2 < listens.length) say(l1.id, `only ${linked}/${listens.length} listen sentences have connected speech`);
    if (!b2b && (!between(count(e2, 'choice'), 4, 5) || !between(count(e2, 'match'), 1, 2))) say(l2.id, 'reading recipe: choice×4–5, match×1–2, select/fillBlank×2');
    const passages = new Set(e2.filter((e) => e.type === 'choice').map((e) => e.passage));
    if (passages.size !== 1 || !passages.values().next().value) say(l2.id, 'reading choices share one passage');
    const passage = [...passages][0] ?? '';
    row.reading = words(passage);
    if (!between(words(passage), textRange[0], textRange[1])) say(l2.id, `passage ${words(passage)} words (${level} ${textRange.join('–')})`);
    if (!b2b && (!between(count(e3, 'speak'), 4, 5) || count(e3, 'select') < 2 || count(e3, 'translate') < 2 || count(e3, 'match') < 1)) say(l3.id, 'speaking recipe: speak×4–5, select×2, translate×2, match×1');
    if (!b2b && (count(e4, 'translate') < 4 || count(e4, 'fillBlank') < 3 || count(e4, 'select') < 1 || count(e4, 'match') < 1)) say(l4.id, 'writing recipe: translate×4, fillBlank×3, select×1, match×1');
    // Story: 14–20 lines, 4–5 questions.
    const lines = s.steps.filter((x) => x.kind === 'line'), qs = s.steps.filter((x) => x.kind === 'question');
    if (b2b) {
      const storyWords = lines.reduce((n, x) => n + words(x.text), 0);
      const [lo, hi] = level === 'B1' ? [250, 350] : [350, 500];
      row.story = storyWords;
      if (s.listenFirst !== true) say(s.id, 'B1–B2 story must be listenFirst');
      if (!between(storyWords, lo, hi) || qs.length !== 5) say(s.id, `story ${storyWords} words, ${qs.length} questions (${lo}–${hi}, 5)`);
    } else if (!between(lines.length, 14, 20) || !between(qs.length, 4, 5)) say(s.id, `story ${lines.length} lines, ${qs.length} questions (14–20, 4–5)`);
    for (const q of qs) {
      if (!q.choices.includes(q.answer)) say(s.id, `story answer "${q.answer}" not in choices`);
      if (dupes(q.choices).length) say(s.id, 'duplicate story choices');
    }
    for (const x of lines) if (!x.speaker || !x.text || !x.translation || !x.avatar) say(s.id, 'story line fields');
    if (s.rewardXp !== 15 || t.rewardXp !== 25 || c.rewardXp !== 20) say(W, 'xp: story 15, test 25, chest 20');
    // Unit test: empty, except the section skills test of the last unit.
    const te = t.exercises ?? [];
    if (ui === j.units.length - 1) {
      if (t.title !== `Bölüm ${index} beceri testi` || t.description !== 'Bu bölümün hedeflerini ölçer') say(t.id, 'skills test title/description');
      if (te.length !== 20) say(t.id, `${te.length} questions (20)`);
      const mix = [count(te, 'listen'), count(te, 'choice'), count(te, 'translate'), count(te, 'fillBlank') + count(te, 'select')];
      const want = b2b ? '6,8,4,2' : '6,6,5,3';
      if (mix.join() !== want) say(t.id, `mix listen/choice/translate/language ${mix} (${want})`);
      const tp = new Set(te.filter((e) => e.type === 'choice').map((e) => e.passage));
      if (tp.size !== 2) say(t.id, `skills test reading: 2 texts × ${b2b ? 4 : 3}`);
      const [plo, phi] = b2b ? [120, textRange[1]] : [textRange[0] - 20, textRange[1]];
      for (const p of tp) if (p && !between(words(p), plo, phi)) say(t.id, `test passage ${words(p)} words (${plo}–${phi})`);
      te.forEach((e, i) => checkExercise(e, `${t.id}#${i}`, level));
      // The writing part measures production: Turkish → English.
      te.forEach((e, i) => e.type === 'translate' && e.lang !== 'tr' && say(`${t.id}#${i}`, 'skills test translate must be tr→en'));
      if (!(u.guide ?? '').includes('Beceri testi')) say(W, 'guide should map the skills test to can-do (a "Beceri testi" part)');
    } else if (te.length) say(t.id, 'only the last unit test carries questions');
    report.push(row);
  }
  if (choices) {
    const most = Math.max(...letters.values());
    if (most >= choices * 0.4) say(f, `answer positions unbalanced ${JSON.stringify([...letters])}`);
  }
}

console.table(report);
console.log(problems.length ? `${problems.length} problem(s):\n${problems.join('\n')}` : 'OK');
process.exit(problems.length ? 1 : 0);
