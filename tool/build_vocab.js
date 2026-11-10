// Builds assets/vocab/software.json (Yazılımcı İngilizcesi) from content parts.
//
// Usage: node tool/build_vocab.js <part.json> [<part.json> ...]
//
// Each part is a JSON array of entries with a per-topic `localRank`
// (1 = most important in that topic). Duplicate words keep the copy with the
// better relative rank. The global `rank` interleaves topics by relative
// rank, so every rank band on the knowledge map mixes topics.
const fs = require('fs');
const path = require('path');

const TOPICS = [
  { name: 'Temeller', emoji: '🧱', description: 'Değişken, fonksiyon, bellek: her yazılımcının temel kelimeleri' },
  { name: 'Git ve sürüm kontrolü', emoji: '🌿', description: 'Commit, branch, merge, rebase ve arkadaşları' },
  { name: 'Hata ayıklama', emoji: '🐞', description: 'Hatayı bul, tekrar et, kök nedeni anlat' },
  { name: 'Test', emoji: '🧪', description: 'Birim testi, mock, kapsama, QA' },
  { name: 'Mimari ve tasarım', emoji: '🏛️', description: 'Katmanlar, desenler, bağımlılıklar, teknik borç' },
  { name: 'Web', emoji: '🌐', description: 'İstek, yanıt, uç nokta, tarayıcı, bileşen' },
  { name: 'Mobil (Flutter/Android/Kotlin)', emoji: '📱', description: 'Widget, yaşam döngüsü, izinler, mağaza' },
  { name: 'Veri ve yapay zekâ', emoji: '📊', description: 'Sorgu, şema, veri hattı, model, tahmin' },
  { name: 'DevOps ve bulut', emoji: '☁️', description: 'Canlıya alma, ortamlar, konteyner, izleme' },
  { name: 'Güvenlik', emoji: '🔐', description: 'Kimlik doğrulama, yetki, açık, şifreleme' },
  { name: 'Proje yönetimi ve Agile', emoji: '🗂️', description: 'Sprint, backlog, tahmin, öncelik, teslim' },
  { name: 'Toplantı ve iletişim', emoji: '🗣️', description: 'Stand-up, Slack, e-posta: işte doğal İngilizce' },
  { name: 'Mülakat', emoji: '🎤', description: 'Teknik mülakatta kendini ve çözümünü anlat' },
];
const topicIndex = Object.fromEntries(TOPICS.map((t, i) => [t.name, i]));

const parts = process.argv.slice(2);
if (!parts.length) throw new Error('usage: node tool/build_vocab.js <part.json>...');
const raw = parts.flatMap((p) => JSON.parse(fs.readFileSync(p, 'utf8')));

const topicSize = {};
for (const e of raw) topicSize[e.topic] = Math.max(topicSize[e.topic] || 0, e.localRank);
const rel = (e) => e.localRank / topicSize[e.topic];

const byWord = new Map();
for (const e of raw) {
  if (!(e.topic in topicIndex)) throw new Error(`unknown topic ${e.topic}`);
  const key = e.word.trim().toLowerCase();
  const prev = byWord.get(key);
  if (!prev || rel(e) < rel(prev)) byWord.set(key, e);
}

const entries = [...byWord.values()].sort(
  (a, b) => rel(a) - rel(b) || topicIndex[a.topic] - topicIndex[b.topic] || a.word.localeCompare(b.word),
);

const slug = (w) =>
  'sw_' +
  w
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
const ids = new Set();
const out = entries.map((e, i) => {
  let id = slug(e.word);
  for (let n = 2; ids.has(id); n++) id = `${slug(e.word)}_${n}`;
  ids.add(id);
  const o = {
    id,
    word: e.word,
    pos: e.pos,
    rank: i + 1,
    topic: e.topic,
    senses: e.senses,
    examples: e.examples,
    collocations: e.collocations,
  };
  if (e.synonym) o.synonym = e.synonym;
  if (e.tip) o.tip = e.tip;
  if (e.fromNotes) {
    o.fromNotes = true;
    o.notesWord = e.notesWord;
  }
  return o;
});

const file = path.join(__dirname, '..', 'assets', 'vocab', 'software.json');
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify({ version: 1, topics: TOPICS, entries: out }, null, 1) + '\n');
const counts = {};
for (const e of out) counts[e.topic] = (counts[e.topic] || 0) + 1;
console.log(`${out.length} entries (${raw.length - out.length} duplicates dropped)`, counts);
console.log('fromNotes:', out.filter((e) => e.fromNotes).length);
