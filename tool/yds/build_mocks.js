// Appends (or replaces) new full mocks in assets/exam_packs/yds_full.json from tool/yds/work/<id>.json:
// YDS mocks (yds_mN, Faz 2c–4c) and YÖKDİL-format mocks (yokdil_mN, Faz 4c). Other mocks are left untouched.
// YÖKDİL mocks bring their own section ids (yokdil_*), added to the pack's section list once.
// Usage: node tool/yds/build_mocks.js yds_m15 … yokdil_m1 …
const l = require('./lex.js');
const packPath = l.path.join(l.ROOT, 'assets/exam_packs/yds_full.json');
const pack = JSON.parse(l.fs.readFileSync(packPath, 'utf8').replace(/^﻿/, ''));
const YOKDIL_SECTIONS = [
  { id: 'yokdil_vocab', title: 'YÖKDİL · Kelime bilgisi' },
  { id: 'yokdil_grammar', title: 'YÖKDİL · Dil bilgisi' },
  { id: 'yokdil_cloze', title: 'YÖKDİL · Paragrafta boşluk (cloze)' },
  { id: 'yokdil_completion', title: 'YÖKDİL · Cümle tamamlama' },
  { id: 'yokdil_translation', title: 'YÖKDİL · Çeviri' },
  { id: 'yokdil_reading', title: 'YÖKDİL · Okuma' },
  { id: 'yokdil_paragraph', title: 'YÖKDİL · Paragraf tamamlama' },
  { id: 'yokdil_irrelevant', title: 'YÖKDİL · Anlam bütünlüğünü bozan cümle' },
];
for (const id of process.argv.slice(2)) {
  const m = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
  const keys = ['id', 'section', 'qtype', 'passage', 'text', 'options', 'answer', 'explanation'];
  const mock = {
    id: m.id, title: m.title, minutes: m.minutes,
    questions: m.questions.map((q) => Object.fromEntries(keys.filter((k) => q[k] !== undefined).map((k) => [k, q[k]]))),
  };
  const i = pack.mocks.findIndex((x) => x.id === id);
  if (i >= 0) pack.mocks[i] = mock; else pack.mocks.push(mock);
  if (id.startsWith('yokdil_')) {
    for (const s of YOKDIL_SECTIONS) if (!pack.sections.some((x) => x.id === s.id)) pack.sections.push(s);
  }
}
const yds = pack.mocks.filter((m) => m.id.startsWith('yds_')).length;
const yokdil = pack.mocks.filter((m) => m.id.startsWith('yokdil_')).length;
pack.description = pack.description.replace(/\d+(?: YDS \+ \d+ YÖKDİL)? özgün tam deneme/,
  `${yokdil ? `${yds} YDS + ${yokdil} YÖKDİL` : yds} özgün tam deneme`);
l.fs.writeFileSync(packPath, JSON.stringify(pack, null, 1) + '\n');
console.log(`yds_full: ${pack.mocks.length} deneme (${yds} YDS, ${yokdil} YÖKDİL)`);
