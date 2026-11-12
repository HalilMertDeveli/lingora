// Independent answer-key check.
//   node tool/yds/blind.js export <section.json> <out.json>   → choice questions without answers
//   node tool/yds/blind.js compare <section.json> <answers.json> → mismatches between key and blind solution
// answers.json: {"<nodeId>#<i>": <option index>, ...}
const fs = require('fs');
const [, , cmd, file, other] = process.argv;
const sec = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
const items = [];
for (const u of sec.units) for (const n of u.nodes) (n.exercises || []).forEach((e, i) => {
  if (e.type === 'choice') items.push({ id: `${n.id}#${i}`, e });
});
if (cmd === 'export') {
  fs.writeFileSync(other, JSON.stringify(items.map(({ id, e }) => ({ id, passage: e.passage, question: e.question, options: e.options })), null, 1));
  console.log(`${items.length} soru → ${other}`);
} else {
  const got = JSON.parse(fs.readFileSync(other, 'utf8'));
  const bad = items.filter(({ id, e }) => got[id] !== e.answer);
  console.log(`${items.length} soru, çözülen ${Object.keys(got).length}, uyuşmazlık ${bad.length}`);
  for (const { id, e } of bad) console.log(`  ${id}: anahtar ‘${e.options[e.answer]}’, bağımsız çözüm ‘${e.options[got[id]]}’ — ${e.question.slice(0, 90)}`);
  process.exitCode = bad.length ? 1 : 0;
}
