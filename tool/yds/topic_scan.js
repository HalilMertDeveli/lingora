// Topic-repeat scan for new mocks (YDS Faz 3): every item's text (short ones too) against everything in the
// app and the other new work files, by shared rare words (see overlap.js rareOverlaps).
// Usage: WORDFREQ=<tsv> node tool/yds/topic_scan.js yds_m11 yds_m12 … ys11u1m …
const l = require('./lex.js');
const ov = require('./overlap.js');
const ids = process.argv.slice(2);
const load = (id) => {
  const d = JSON.parse(l.fs.readFileSync(l.path.join(__dirname, 'work', `${id}.json`), 'utf8'));
  const items = d.questions || d.exercises || (d.nodes || []).flatMap((n) => n.exercises || []);
  return items.map((q, i) => [`${id}#${i + 1}`, [q.passage, q.text, q.question].filter(Boolean).join(' ')]);
};
const shipped = ov.allTexts();
let total = 0;
for (const id of ids) {
  const mine = load(id);
  const others = ids.filter((x) => x !== id).flatMap(load);
  // Words a passage shares with its own questions are not repeats: group by mock id prefix.
  const probs = ov.rareOverlaps(mine, [...shipped, ...others].filter(([src]) => !src.startsWith(id)), 2);
  const uniq = [...new Set(probs.map((p) => p.replace(/#\d+/, '')))];
  total += uniq.length;
  console.log(`${id}: ${uniq.length ? uniq.length + ' olası tekrar' : 'temiz'}`);
  uniq.slice(0, 15).forEach((p) => console.log('  ! ' + p));
}
process.exitCode = total ? 1 : 0;
