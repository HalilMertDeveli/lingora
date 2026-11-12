// Adds the old YDS path's full cards (ids ydm_<word>, YDS Faz 2c) to assets/vocab/yds.json, after the
// ys5/ys7 bank cards, in path order (tool/yds/work/ydm_list.json order). Bridge cards keep their exact id;
// for new words the id is derived from the headword the writers chose; duplicates (same id, or a word that
// already has a yd_ card) are dropped, first one wins. Topics ys1–ys4 units get topic entries.
// Usage: node tool/yds/build_ydm.js
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const cardId = (w) => 'ydm_' + w.trim().toLowerCase().replace(/\s+/g, '_');
const files = l.fs.readdirSync(work).filter((f) => /^ydm_\d+\.json$/.test(f)).sort((a, b) => +a.match(/\d+/)[0] - +b.match(/\d+/)[0]);
const cards = files.flatMap((f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8')));
const vocabPath = l.path.join(l.ROOT, 'assets/vocab/yds.json');
const vocab = JSON.parse(l.fs.readFileSync(vocabPath, 'utf8'));
const banks = vocab.entries.filter((e) => e.id.startsWith('yd_'));
const ydWords = new Set(banks.map((e) => e.word.trim().toLowerCase()));
const seen = new Set();
const ydm = [];
let dropped = 0;
for (const c of cards) {
  const id = cardId(c.word);
  if (c.id !== id || seen.has(id) || ydWords.has(c.word.trim().toLowerCase())) { dropped++; continue; }
  seen.add(id);
  const { id: _, word, pos, topic, ...rest } = c;
  ydm.push({ id, word, pos, rank: 0, topic, ...Object.fromEntries(Object.entries(rest).filter(([k]) => k !== 'rank')) });
}
const entries = [...banks, ...ydm];
entries.forEach((e, i) => { e.rank = i + 1; });

// Topic entries for the old path's units, titled from the course files.
const unitTitle = new Map(l.YDS_OLD.flatMap((f) => l.J(f).units).map((u) => [u.id, u.title]));
const used = [...new Set(ydm.map((e) => e.topic))];
const topics = [
  ...vocab.topics.filter((t) => !/^ys[1-4]u/.test(t.name)),
  ...used.map((t) => ({ name: t, emoji: '📘', description: `YDS yolu: ${unitTitle.get(t) ?? t}` })),
];
l.fs.writeFileSync(vocabPath, JSON.stringify({ version: 1, topics, entries }, null, 2) + '\n');
const bridges = l.J('tool/yds/work/ydm_list.json').filter((x) => x.bridge).map((x) => x.id);
const missing = bridges.filter((id) => !seen.has(id));
console.log(`ydm: ${ydm.length} kart (${bridges.length - missing.length}/${bridges.length} köprü), ${dropped} tekrar atıldı; yds.json toplam ${entries.length}`);
if (missing.length) { console.log('Eksik köprü kartı:', missing.join(', ')); process.exitCode = 1; }
