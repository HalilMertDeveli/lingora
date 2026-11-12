// Appends (or replaces) the new full mocks yds_m9 / yds_m10 (YDS Faz 2c) in assets/exam_packs/yds_full.json
// from tool/yds/work/<id>.json. Other mocks are left untouched.
// Usage: node tool/yds/build_mocks.js yds_m9 yds_m10
const l = require('./lex.js');
const packPath = l.path.join(l.ROOT, 'assets/exam_packs/yds_full.json');
const pack = JSON.parse(l.fs.readFileSync(packPath, 'utf8').replace(/^﻿/, ''));
for (const id of process.argv.slice(2)) {
  const m = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
  const keys = ['id', 'section', 'qtype', 'passage', 'text', 'options', 'answer', 'explanation'];
  const mock = {
    id: m.id, title: m.title, minutes: m.minutes,
    questions: m.questions.map((q) => Object.fromEntries(keys.filter((k) => q[k] !== undefined).map((k) => [k, q[k]]))),
  };
  const i = pack.mocks.findIndex((x) => x.id === id);
  if (i >= 0) pack.mocks[i] = mock; else pack.mocks.push(mock);
}
pack.description = pack.description.replace(/\d+ özgün tam deneme/, `${pack.mocks.length} özgün tam deneme`);
l.fs.writeFileSync(packPath, JSON.stringify(pack, null, 1) + '\n');
console.log(`yds_full: ${pack.mocks.length} deneme`);
