// Builds a word-bank section and its cards in assets/vocab/yds.json from tool/yds/work/.
// Usage: node tool/yds/build_bank.js ys5 | ys7
// Cards of other sections already in yds.json are kept; ranks run in section order (ys5 1–800, ys7 801–2000).
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const BANKS = {
  ys5: {
    file: '05_kelime_bankasi_1.json', index: 5, units: 10, title: 'Kelime bankası 1', cefr: 'A2–B1',
    description: 'Sıfırdan başlayan için YDS kelime temeli: 10 temada 800 yeni kelime, her kelime kart, eşdizim ve bağlam cümlesiyle',
    emoji: ['🔄', '👥', '💼', '🔬', '🩺', '🌿', '💬', '📏', '✨', '🔗'],
  },
  ys7: {
    file: '07_kelime_bankasi_2.json', index: 7, units: 15, title: 'Kelime bankası 2', cefr: 'B1+–B2',
    description: 'Akademik kelime: 15 temada 1.200 yeni kelime (NAWL ve sık genel kelimeler), her biri kart, eşdizim ve B2 bağlam cümlesiyle',
    emoji: ['🧪', '⚖️', '🔗', '📈', '🏛️', '💹', '🤖', '🩺', '⚡', '🏺', '🧠', '📜', '🧩', '🤔', '🧷'],
  },
};
const sec = process.argv[2];
const b = BANKS[sec];
if (!b) throw new Error('kullanım: build_bank.js ys5|ys7');
const ids = Array.from({ length: b.units }, (_, i) => `${sec}u${i + 1}`);
const units = ids.map((id) => JSON.parse(l.fs.readFileSync(l.path.join(work, `${id}.json`), 'utf8')));
const section = {
  section: {
    id: sec, index: b.index, title: b.title, cefr: b.cefr, parallel: true, description: b.description,
    grammar: units.map((u) => u.title.toLocaleLowerCase('tr')),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds', b.file), JSON.stringify(section, null, 2) + '\n');

const vocabPath = l.path.join(l.ROOT, 'assets/vocab/yds.json');
const vocab = l.fs.existsSync(vocabPath) ? JSON.parse(l.fs.readFileSync(vocabPath, 'utf8')) : { version: 1, topics: [], entries: [] };
const mine = [];
for (const id of ids) {
  for (const c of JSON.parse(l.fs.readFileSync(l.path.join(work, `${id}.cards.json`), 'utf8'))) {
    const { id: cid, word, pos, ...rest } = c;
    mine.push({ id: cid, word, pos, rank: 0, topic: id, ...Object.fromEntries(Object.entries(rest).filter(([k]) => k !== 'topic' && k !== 'rank')) });
  }
}
// Banks first (ys5, ys7), then the old path's ydm_ cards (topics ys1–ys4) in path order; stable within a topic.
const order = (t) => {
  const b = Object.keys(BANKS).indexOf(t.slice(0, 3));
  return (b >= 0 ? b : 10 + +t[2]) * 1000 + +t.split('u')[1];
};
const kept = vocab.entries.filter((e) => !e.topic.startsWith(`${sec}u`));
const entries = [...kept.filter((e) => e.id.startsWith('yd_')), ...mine].sort((x, y) => order(x.topic) - order(y.topic) || 0)
  .concat(kept.filter((e) => !e.id.startsWith('yd_')));
entries.forEach((e, i) => { e.rank = i + 1; });
const topics = [
  ...vocab.topics.filter((t) => !t.name.startsWith(`${sec}u`)),
  ...units.map((u, i) => ({ name: u.id, emoji: b.emoji[i], description: `${u.title}: ${u.description}` })),
].sort((x, y) => order(x.name) - order(y.name));
l.fs.writeFileSync(vocabPath, JSON.stringify({ version: 1, topics, entries }, null, 2) + '\n');
console.log(`${sec}: ${units.length} ünite, ${mine.length} kart; yds.json toplam ${entries.length}`);
