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
  ys9: {
    file: '09_kelime_bankasi_3.json', index: 9, units: 12, title: 'Kelime bankası 3', cefr: 'B2',
    description: 'Orta sıklık bandı ve YÖKDİL alan terimleri: 12 temada 1.300 yeni kelime, her biri kart, eşdizim ve B2 bağlam cümlesiyle',
    emoji: ['🔬', '🧬', '⚗️', '💊', '🥗', '👪', '🌐', '🏦', '📰', '🎭', '🧵', '🔀'],
  },
  // Faz 4a: appended after every existing card (ranks 4087–4986); earlier ranks never change.
  ys12: {
    file: '12_kelime_bankasi_4.json', index: 12, units: 8, title: 'Kelime bankası 4', cefr: 'B2–C1', append: true,
    description: 'Deneme kampı kelimesi: 8 temada 900 yeni orta–ileri sıklık kelime, sınavda karışan aileler ve ileri eşdizimler; her biri kart ve bağlam cümlesiyle',
    emoji: ['⚡', '🧐', '📉', '🛰️', '🫀', '⚖️', '🧩', '🪞'],
  },
};
const sec = process.argv[2];
const b = BANKS[sec];
if (!b) throw new Error('kullanım: build_bank.js ys5|ys7|ys9|ys12');
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
const kept = vocab.entries.filter((e) => !e.topic.startsWith(`${sec}u`));
const myTopics = units.map((u, i) => ({ name: u.id, emoji: b.emoji[i], description: `${u.title}: ${u.description}` }));
let entries, topics;
if (b.append) {
  // Append mode (F4+): existing cards keep their order and ranks; this bank follows them.
  entries = [...kept.sort((x, y) => x.rank - y.rank), ...mine];
  entries.forEach((e, i) => { e.rank = i + 1; });
  topics = [...vocab.topics.filter((t) => !t.name.startsWith(`${sec}u`)), ...myTopics];
} else {
  // F1–F3 banks first (ys5, ys7, ys9), then the old path's ydm_ cards (topics ys1–ys4) in path order; stable within a topic.
  const order = (t) => {
    const s = t.match(/^ys\d+/)[0];
    const b = Object.keys(BANKS).indexOf(s);
    // Append-mode banks (ys12 …) stay after the ydm_ topics.
    return (BANKS[s]?.append ? 90 + b : b >= 0 ? b : 10 + +t[2]) * 1000 + +t.split('u')[1];
  };
  entries = [...kept.filter((e) => e.id.startsWith('yd_') && !BANKS[e.topic.match(/^ys\d+/)[0]]?.append), ...mine]
    .sort((x, y) => order(x.topic) - order(y.topic) || 0)
    .concat(kept.filter((e) => !e.id.startsWith('yd_')), kept.filter((e) => BANKS[e.topic.match(/^ys\d+/)[0]]?.append));
  entries.forEach((e, i) => { e.rank = i + 1; });
  topics = [...vocab.topics.filter((t) => !t.name.startsWith(`${sec}u`)), ...myTopics].sort((x, y) => order(x.name) - order(y.name));
}
l.fs.writeFileSync(vocabPath, JSON.stringify({ version: 1, topics, entries }, null, 2) + '\n');
console.log(`${sec}: ${units.length} ünite, ${mine.length} kart; yds.json toplam ${entries.length}`);
