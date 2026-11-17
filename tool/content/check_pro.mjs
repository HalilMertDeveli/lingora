// Checks the units of the professional courses (pro_*.json) and their
// "Notlarım" lessons. Rules: docs in the header of each check below.
//
//   node tool/content/check_pro.mjs                 # shipped courses
//   node tool/content/check_pro.mjs draft.json ...  # drafts {course, units, notes}
//
// A draft holds new units and, in the same order, one note lesson per unit
// (assets/notes/lessons.json format). Shipped units with a `listening` node
// (the leveled units) get the full check; older units only the basic one.
import fs from 'node:fs';

const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const problems = [];
const bad = (where, msg) => problems.push(`${where}: ${msg}`);

const asciiTurkish = [
  'tesekkur', 'tesekkurler', 'gunaydin', 'nasilsin', 'nasilsiniz', 'ogrenci', 'ogretmen', 'degil',
  'guzel', 'icin', 'simdi', 'bugun', 'yarin', 'gorusuruz', 'lutfen', 'konusmak', 'calismak', 'ogrenmek',
  'sehir', 'kucuk', 'buyuk', 'universite', 'musteri', 'kahvalti', 'aksam', 'hosgeldiniz', 'calisiyorum',
  'ingilizce', 'turkce', 'turkiye', 'ogle', 'cumle', 'yapiyorum', 'odeme', 'gorusme', 'sirket',
];

const normalize = (s) =>
  s.replaceAll('İ', 'i').toLowerCase().replaceAll('’', "'").replace(/[.,!?;:¿¡"]/g, ' ').replace(/\s+/g, ' ').trim();
const lower = (s) => s.trim().toLowerCase();
const dupes = (items, norm = lower) => {
  const seen = new Set();
  return items.filter((i) => (seen.has(norm(i)) ? true : (seen.add(norm(i)), false)));
};
const englishWords = (t) => t.trim().split(/\s+/).filter((w) => /[A-Za-z0-9]/.test(w)).length;

const male = ['👨', '👦', '👴', '🧔', '👲', '🤵', '👮‍♂️', '👨‍'];
const female = ['👩', '👧', '👵', '🧕', '👱‍♀️', '👸', '🤰', '👩‍'];
const genderOf = (a) => (female.some((f) => a?.startsWith(f)) ? 'female' : male.some((m) => a?.startsWith(m)) ? 'male' : null);

const rules = {
  A2: { lines: [4, 6], words: [45, 75], qs: [2, 3], wps: 2, sec: 30 },
  B1: { lines: [6, 8], words: [90, 130], qs: [3, 4], wps: 2.4, sec: 45 },
  B2: { lines: [8, 12], words: [135, 190], qs: [3, 4], wps: 2.7, sec: 60, inference: true },
};

function strings(v, where, key = '') {
  if (typeof v === 'string') {
    if (key === 'id' || key === 'theme' || key.endsWith('Id') || key.endsWith('Ids')) return;
    if (v !== v.trim()) bad(where, 'leading/trailing space');
    if (/[^\s] {2,}[^\s]/.test(v)) bad(where, 'double space');
    if ((key === 'guide' ? /�|&nbsp;|<\/?[a-z]+>/ : /�|\*\*|&nbsp;|<\/?[a-z]+>/).test(v)) bad(where, 'artifact');
    for (const w of asciiTurkish) {
      for (const f of [w, w[0].toUpperCase() + w.slice(1)]) {
        if (new RegExp(`(^|[^\\p{L}])${f}($|[^\\p{L}])`, 'u').test(v)) bad(where, `"${f}" lacks Turkish characters`);
      }
    }
  } else if (Array.isArray(v)) v.forEach((x, i) => strings(x, `${where}[${i}]`, key));
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) strings(x, `${where}.${k}`, k);
}

function articleGiveaway(prompt, options) {
  if (!/\b([Aa]n?) (?:_{3,}|-{3,})/.test(prompt)) return false;
  return new Set(options.map((o) => /^[aeiouAEIOU]/.test(o.trim()))).size > 1;
}

function checkExercise(e, at) {
  switch (e.type) {
    case 'select': {
      const texts = (e.choices ?? []).map((c) => c.text);
      if (texts.length !== 4) bad(at, 'select needs 4 choices');
      if (!texts.includes(e.answer)) bad(at, 'select answer not in choices');
      if (dupes(texts).length) bad(at, 'select duplicate choices');
      for (const c of e.choices ?? []) {
        if (!c.emoji) bad(at, `select choice without emoji: ${c.text}`);
        if (/[✅❌✔✖✓✗☑❎]/.test(`${c.emoji} ${c.text}`)) bad(at, 'verdict mark on a card');
        if (c.text.length > 35) bad(at, `select choice too long: ${c.text}`);
      }
      if (!e.prompt) bad(at, 'select without prompt');
      break;
    }
    case 'translate': {
      if (!['tr', 'en'].includes(e.lang)) bad(at, 'translate lang must be tr or en');
      if (!e.text || !e.answers?.length) bad(at, 'translate needs text and answers');
      if (dupes(e.answers ?? [], normalize).length) bad(at, 'translate duplicate answers');
      const bank = (e.tokens ?? []).map(normalize);
      const words = normalize(e.answers?.[0] ?? '').split(' ');
      for (const w of words) {
        const i = bank.indexOf(w);
        if (i < 0) {
          bad(at, `token "${w}" missing for "${e.answers[0]}"`);
          break;
        }
        bank.splice(i, 1);
      }
      if (bank.length < 2) bad(at, 'translate needs at least 2 distractor tokens');
      if (e.lang === 'tr' && /[çğıöşüÇĞİÖŞÜ]/.test(e.answers?.[0] ?? '') && !/[A-Z]/.test(e.answers[0][0])) {
        bad(at, 'English answer with Turkish letters?');
      }
      break;
    }
    case 'fillBlank': {
      if ((e.text?.match(/___/g) ?? []).length !== 1 || /____/.test(e.text)) bad(at, 'fillBlank needs exactly one ___');
      if (!e.translation) bad(at, 'fillBlank without translation');
      if (e.choices?.length !== 3) bad(at, 'fillBlank needs 3 choices');
      if (!e.choices?.includes(e.answer)) bad(at, 'fillBlank answer not in choices');
      if (dupes(e.choices ?? []).length) bad(at, 'fillBlank duplicate choices');
      if (articleGiveaway(e.text ?? '', e.choices ?? [])) bad(at, 'a/an giveaway');
      break;
    }
    case 'listen':
      if (!e.text || e.answers?.[0] !== e.text) bad(at, 'listen: answers[0] must equal text');
      if (/[çğıöşüÇĞİÖŞÜ]/.test(e.text ?? '')) bad(at, 'listen text with Turkish letters');
      break;
    case 'match': {
      const pairs = e.pairs ?? [];
      if (pairs.length < 4 || pairs.length > 5) bad(at, 'match needs 4–5 pairs');
      if (dupes(pairs.map((p) => p[0])).length || dupes(pairs.map((p) => p[1])).length) bad(at, 'match duplicates');
      break;
    }
    case 'speak':
      if (!e.text || !e.translation) bad(at, 'speak needs text and translation');
      if (/[çğıöşüÇĞİÖŞÜ]/.test(e.text ?? '')) bad(at, 'speak text with Turkish letters');
      break;
    default:
      bad(at, `unknown exercise type ${e.type}`);
  }
}

function checkUnit(u, { full, cefr }) {
  const at = u.id;
  for (const k of ['id', 'title', 'description', 'color', 'theme']) if (!u[k]) bad(at, `missing ${k}`);
  if (!/^0xFF[0-9A-F]{6}$/.test(u.color ?? '')) bad(at, 'color must be 0xFFRRGGBB');
  const want = full ? ['l1', 'l2', 's', 'l3', 'd', 't', 'c'] : null;
  const types = u.nodes.map((n) => n.type);
  if (want) {
    const ids = u.nodes.map((n) => n.id);
    if (ids.join() !== want.map((s) => u.id + s).join()) bad(at, `node ids must be ${want.map((s) => u.id + s)}`);
    if (types.join() !== 'lesson,lesson,story,lesson,listening,test,chest') bad(at, 'node pattern');
  }
  const unitTypes = new Set();
  for (const n of u.nodes) {
    const nat = n.id;
    if (!n.title || !n.description) bad(nat, 'node needs title and description');
    if (n.type === 'lesson') {
      const ex = n.exercises ?? [];
      if (ex.length < 8 || ex.length > 10) bad(nat, `lesson has ${ex.length} exercises (8–10)`);
      const kinds = new Set(ex.map((e) => e.type));
      if (full && kinds.size < 5) bad(nat, 'lesson should mix at least 5 exercise types');
      ex.forEach((e, i) => {
        unitTypes.add(e.type);
        checkExercise(e, `${nat}#${i}`);
      });
      const firstTexts = ex.map((e) => e.text ?? e.prompt).filter(Boolean);
      if (full && dupes(firstTexts).length) bad(nat, `repeated exercise text: ${dupes(firstTexts)}`);
    } else if (n.type === 'story') {
      if (n.rewardXp !== 15) bad(nat, 'story rewardXp 15');
      const lines = n.steps.filter((s) => s.kind === 'line');
      const qs = n.steps.filter((s) => s.kind === 'question');
      if (full && (lines.length < 10 || qs.length < 3)) bad(nat, 'story needs ≥10 lines and ≥3 questions');
      const avatars = {};
      for (const s of lines) {
        if (!s.speaker || !s.avatar || !s.text || !s.translation) bad(nat, 'story line fields');
        if (full && !genderOf(s.avatar)) bad(nat, `avatar ${s.avatar} has no voice (use 👨/👩-based emoji)`);
        if (avatars[s.speaker] && avatars[s.speaker] !== s.avatar) bad(nat, `${s.speaker} changes avatar`);
        avatars[s.speaker] = s.avatar;
      }
      for (const q of qs) {
        if (!q.choices?.includes(q.answer)) bad(nat, `story question answer not in choices: ${q.prompt}`);
        if (dupes(q.choices ?? []).length) bad(nat, 'story question duplicate choices');
      }
      if (n.steps[0]?.kind !== 'line') bad(nat, 'story starts with a line');
    } else if (n.type === 'listening') {
      const r = rules[n.cefr];
      if (!r) {
        bad(nat, `listening cefr ${n.cefr} (A2/B1/B2)`);
        continue;
      }
      if (cefr && n.cefr !== cefr) bad(nat, `listening cefr ${n.cefr} != unit level ${cefr}`);
      if (n.rewardXp !== 15) bad(nat, 'listening rewardXp 15');
      const sp = n.speakers ?? [];
      if (sp.length !== 2 || new Set(sp.map((s) => s.gender)).size !== 2) bad(nat, 'two speakers, a woman and a man');
      for (const s of sp) if (genderOf(s.avatar) !== s.gender) bad(nat, `${s.name}: avatar ${s.avatar} ≠ ${s.gender}`);
      const lines = n.lines ?? [];
      if (lines.length < r.lines[0] || lines.length > r.lines[1]) bad(nat, `${lines.length} lines (${r.lines})`);
      const words = lines.reduce((a, l) => a + englishWords(l.text), 0);
      if (words < r.words[0] || words > r.words[1]) bad(nat, `${words} words (${r.words})`);
      const secs = Math.round(words / r.wps);
      if (secs < Math.round(r.sec * 0.7) || secs > Math.round(r.sec * 1.3)) bad(nat, `${secs}s`);
      lines.forEach((l, i) => {
        if (!sp.some((s) => s.name === l.speaker)) bad(nat, `line ${i} unknown speaker`);
        if (!l.translation) bad(nat, `line ${i} translation`);
        if (/[çğıöşüÇĞİÖŞÜ]/.test(l.text)) bad(nat, `line ${i} has Turkish letters (not recordable)`);
        if (i > 0 && l.speaker === lines[i - 1].speaker) bad(nat, `line ${i} same speaker twice`);
      });
      const qs = n.questions ?? [];
      if (qs.length < r.qs[0] || qs.length > r.qs[1]) bad(nat, `${qs.length} questions (${r.qs})`);
      if (new Set(qs.map((q) => q.kind)).size < 2) bad(nat, 'at least 2 question kinds');
      for (const q of qs) {
        if (q.kind === 'who') {
          const said = lines.filter((l) => l.text.includes(q.quote));
          if (said.length !== 1 || said[0].speaker !== q.answer) bad(nat, `who "${q.quote}"`);
        } else {
          if (q.kind === 'choice') {
            if (!q.choices?.includes(q.answer) || dupes(q.choices).length) bad(nat, `choice ${q.prompt}`);
          } else if (q.kind === 'trueFalse') {
            if (typeof q.answer !== 'boolean' || !q.statement) bad(nat, 'trueFalse needs statement and bool');
          } else bad(nat, `question kind ${q.kind}`);
          if (!(q.line >= 0 && q.line < lines.length) || !lines[q.line].text.toLowerCase().includes((q.key ?? '#').toLowerCase())) {
            bad(nat, `key "${q.key}" not in line ${q.line}`);
          }
          if (!['detail', 'inference', 'attitude'].includes(q.skill)) bad(nat, 'question skill');
        }
      }
      if (r.inference) {
        if (!qs.some((q) => q.skill === 'inference' || q.skill === 'attitude')) bad(nat, 'B2 needs an inference/attitude question');
        if (!n.idioms?.length) bad(nat, 'B2 needs idioms');
        for (const i of n.idioms ?? []) {
          if (!lines.some((l) => l.text.toLowerCase().includes(i.toLowerCase()))) bad(nat, `idiom "${i}" not in text`);
        }
      }
    } else if (n.type === 'test') {
      if (n.rewardXp !== 25) bad(nat, 'test rewardXp 25');
    } else if (n.type === 'chest') {
      if (n.rewardXp !== 20) bad(nat, 'chest rewardXp 20');
    }
  }
  if (full) {
    for (const t of ['select', 'translate', 'fillBlank', 'listen', 'match', 'speak']) {
      if (!unitTypes.has(t)) bad(at, `unit has no ${t} exercise`);
    }
  }
}

const roles = new Set(['s', 'v', 'o', 'aux', 'neg', 'q', 'x']);
function checkNote(l, at) {
  for (const k of ['id', 'unit', 'level', 'title', 'emoji', 'summary', 'compare', 'tip']) if (!l[k]) bad(at, `note missing ${k}`);
  if (!Array.isArray(l.noteIds)) bad(at, 'noteIds must be a list');
  if (!/^Meslek · /.test(l.unit ?? '')) bad(at, 'note unit must start with "Meslek · "');
  if ((l.compare ?? '').length < 150) bad(at, 'compare (Biz nasıl söylüyoruz?) too short');
  if (!(l.formulas?.length >= 2 && l.formulas.length <= 4)) bad(at, '2–4 formulas');
  for (const f of l.formulas ?? []) {
    if (!f.label || !f.example || !f.parts?.length) bad(at, 'formula fields');
    for (const p of f.parts ?? []) if (!roles.has(p[1])) bad(at, `formula role ${p[1]}`);
  }
  if (!(l.mistakes?.length >= 3)) bad(at, '≥3 mistakes');
  for (const m of l.mistakes ?? []) if (!m.wrong || !m.right || !m.why) bad(at, 'mistake fields');
  if (!(l.quiz?.length >= 4 && l.quiz.length <= 5)) bad(at, '4–5 quiz questions');
  for (const q of l.quiz ?? []) {
    if (q.options?.length !== 3 || dupes(q.options).length) bad(at, `quiz options: ${q.q}`);
    if (!(q.answer >= 0 && q.answer < (q.options?.length ?? 0))) bad(at, `quiz answer: ${q.q}`);
    if (!q.why) bad(at, `quiz why: ${q.q}`);
    if (articleGiveaway(q.q ?? '', q.options ?? [])) bad(at, `quiz a/an giveaway: ${q.q}`);
    if (/(ilk|birinci|ikinci|üçüncü|son) ?(seçene|şık)/i.test(q.why ?? '')) bad(at, 'quiz why names an option by position');
  }
  if (l.timeline !== null || l.timelineNote !== null) bad(at, 'timeline and timelineNote must be null');
}

const levelOf = (u) => u.nodes.find((n) => n.type === 'listening')?.cefr;
const args = process.argv.slice(2);
const allIds = new Map();
for (const f of fs.readdirSync('assets/courses').filter((f) => f.endsWith('.json'))) {
  for (const u of read(`assets/courses/${f}`).units ?? []) for (const n of u.nodes) allIds.set(n.id, f);
}

if (args.length) {
  for (const p of args) {
    const d = read(p);
    strings(d, p);
    if (d.units.length !== d.notes.length) bad(p, 'one note per unit');
    const ids = new Set();
    d.units.forEach((u, i) => {
      for (const n of u.nodes) {
        if (ids.has(n.id)) bad(n.id, 'duplicate id in draft');
        ids.add(n.id);
        const owner = allIds.get(n.id);
        if (owner && owner !== `${d.course}.json`) bad(n.id, `id already used in ${owner}`);
      }
      checkUnit(u, { full: true, cefr: d.notes[i]?.level });
      if (d.notes[i]) checkNote(d.notes[i], `${u.id} note ${d.notes[i].id}`);
    });
  }
} else {
  const lessons = read('assets/notes/lessons.json');
  for (const f of fs.readdirSync('assets/courses').filter((f) => /^pro_.*\.json$/.test(f))) {
    const d = read(`assets/courses/${f}`);
    strings(d, f);
    for (const u of d.units) checkUnit(u, { full: !!levelOf(u), cefr: levelOf(u) });
  }
  lessons.filter((l) => l.unit?.startsWith('Meslek')).forEach((l) => checkNote(l, l.id));
}

if (problems.length) {
  console.log(problems.join('\n'));
  console.log(`\n${problems.length} problem(s)`);
  process.exit(1);
}
console.log('ok');
