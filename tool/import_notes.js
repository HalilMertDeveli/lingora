// Merges converted Notion notes into the app's assets.
//
//   node tool/import_notes.js <dir>
//
// <dir> holds words.json and any number of grammar topic files (every other
// *.json, each an array of topics). Writes assets/notes/words.json and
// assets/notes/grammar.json, dropping duplicate ids and empty entries.
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node tool/import_notes.js <dir>');
  process.exit(1);
}
const out = path.join(__dirname, '..', 'assets', 'notes');
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
const clean = (s) => (typeof s === 'string' ? s.trim() : s);

// Category order shown in the app.
const ORDER = [
  'Temeller', 'To be', 'Zamanlar', 'Modallar', 'İsimler ve Zamirler', 'Sıfat ve Zarflar', 'Edatlar',
  'Bağlaçlar', 'Cümle Yapısı', 'Yan Cümleler', 'Fiilimsiler', 'Edilgen Yapı', 'Dolaylı Anlatım',
  'Koşul ve Dilek', 'Kalıplar ve Deyimler', 'Phrasal Verbs', 'Çeviri Yöntemi', 'Günlük İngilizce',
];

// Words
const seenWords = new Set();
const words = [];
for (const w of read('words.json')) {
  const en = clean(w.en), tr = clean(w.tr);
  if (!en || !tr || seenWords.has(w.id)) continue;
  seenWords.add(w.id);
  words.push({ id: w.id, en, tr, topic: clean(w.topic) || 'Karışık', example: clean(w.example) || null, story: clean(w.story) || null });
}

// Grammar topics, in file order: English Book first, then the others.
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json') && f !== 'words.json').sort((a, b) => {
  const rank = (f) => (f.startsWith('eb') ? 0 : 1);
  return rank(a) - rank(b) || a.localeCompare(b);
});
const seenTopics = new Set();
const topics = [];
for (const f of files) {
  for (const t of read(f)) {
    if (!t.id || seenTopics.has(t.id) || !t.title) continue;
    const examples = (t.examples || [])
      .map((e) => ({ en: clean(e.en), tr: clean(e.tr) }))
      .filter((e) => e.en && e.tr);
    if (!clean(t.body) && examples.length === 0 && !(t.rules || []).length) continue;
    seenTopics.add(t.id);
    topics.push({
      id: t.id,
      title: clean(t.title),
      category: ORDER.includes(t.category) ? t.category : 'Temeller',
      source: clean(t.source),
      body: clean(t.body) || '',
      rules: (t.rules || []).map(clean).filter(Boolean),
      examples,
    });
  }
}
topics.sort((a, b) => ORDER.indexOf(a.category) - ORDER.indexOf(b.category));

fs.writeFileSync(path.join(out, 'words.json'), JSON.stringify(words, null, 1) + '\n');
fs.writeFileSync(path.join(out, 'grammar.json'), JSON.stringify(topics, null, 1) + '\n');
const ex = topics.reduce((n, t) => n + t.examples.length, 0);
console.log(`words: ${words.length}, topics: ${topics.length}, examples: ${ex}`);
