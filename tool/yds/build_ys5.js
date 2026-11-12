// Builds assets/courses/exam_yds/05_kelime_bankasi_1.json and assets/vocab/yds.json from tool/yds/work/.
// Usage: node tool/yds/build_ys5.js
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const ids = Array.from({ length: 10 }, (_, i) => `ys5u${i + 1}`);
const units = ids.map((id) => JSON.parse(l.fs.readFileSync(l.path.join(work, `${id}.json`), 'utf8')));
const emoji = ['🔄', '👥', '💼', '🔬', '🩺', '🌿', '💬', '📏', '✨', '🔗'];

const section = {
  section: {
    id: 'ys5',
    index: 5,
    title: 'Kelime bankası 1',
    cefr: 'A2–B1',
    parallel: true,
    description: 'Sıfırdan başlayan için YDS kelime temeli: 10 temada 800 yeni kelime, her kelime kart, eşdizim ve bağlam cümlesiyle',
    grammar: units.map((u) => u.title.toLocaleLowerCase('tr')),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds/05_kelime_bankasi_1.json'), JSON.stringify(section, null, 2) + '\n');

let rank = 0;
const entries = [];
for (const id of ids) {
  for (const c of JSON.parse(l.fs.readFileSync(l.path.join(work, `${id}.cards.json`), 'utf8'))) {
    const { id: cid, word, pos, ...rest } = c;
    entries.push({ id: cid, word, pos, rank: ++rank, topic: id, ...Object.fromEntries(Object.entries(rest).filter(([k]) => k !== 'topic' && k !== 'rank')) });
  }
}
const vocab = {
  version: 1,
  topics: units.map((u, i) => ({ name: u.id, emoji: emoji[i], description: `${u.title}: ${u.description}` })),
  entries,
};
l.fs.mkdirSync(l.path.join(l.ROOT, 'assets/vocab'), { recursive: true });
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/vocab/yds.json'), JSON.stringify(vocab, null, 2) + '\n');
console.log(`ys5: ${units.length} ünite, yds.json: ${entries.length} kart`);
