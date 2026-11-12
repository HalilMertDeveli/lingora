// Checks the general course's reading library (docs/genel-mufredat.md §2 "Faz 6"):
// assets/reading/genel_okuma_*.json, ReadingStory format, ids go_*.
//
//   NGSL=<ngsl_1.2.csv> node tool/content/check_reading.mjs [file ...]   (default: every genel_okuma_*.json)
//
// Per story: level A1/A2/B1/B2 and its length, 3 questions with 4 options and a Turkish explanation
// that quotes the right option, glosses (lower-case, found in the text), and at most 2% unknown words
// once glosses are counted. "Known" depends on the level: the words used in the general course up to
// that level (tool/yds/lex.js), function words and the first N lemmas of NGSL (A1 800, A2 1200,
// B1 2000, B2 all). NGSL itself is not shipped (docs/kaynaklar.md); pass its CSV with NGSL=.
// Also: unique ids, balanced answer positions, a third of each file dialogue-heavy, genre mix.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const l = require('../yds/lex.js');

const dir = 'assets/reading';
const files = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs.readdirSync(dir).filter((f) => /^genel_okuma_.*\.json$/.test(f)).map((f) => path.join(dir, f));

const sec = (n) => `assets/courses/tr_en/${n}.json`;
const ext = (i) => fs.readdirSync('assets/courses/tr_en').filter((f) => f.startsWith(`0${i}x_`)).map((f) => `assets/courses/tr_en/${f}`);
const upTo = {
  A1: ['assets/courses/tr_en.json', ...ext(1), sec('02_gunluk_hayat'), ...ext(2)],
  A2: [sec('03_kendini_anlatmak'), ...ext(3), sec('04_sehirde_ve_iste'), ...ext(4)],
  B1: [sec('05_deneyimler'), ...ext(5), sec('06_fikirler_ve_hikayeler'), ...ext(6)],
  B2: [sec('07_is_ve_tartisma'), ...ext(7), sec('08_akicilik'), ...ext(8)],
};
const levels = ['A1', 'A2', 'B1', 'B2'];
const ngslTop = { A1: 800, A2: 1200, B1: 2000, B2: 100000 };
const lengths = { A1: [100, 180], A2: [150, 250], B1: [250, 400], B2: [400, 650] };

const ngsl = process.env.NGSL
  ? fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1).map((r) => r.split(',')[0].toLowerCase()).filter(Boolean)
  : [];
if (!ngsl.length) console.warn('NGSL= verilmedi: bilinen kelime yalnızca kurs kelimeleri, sonuç katı olur.');
const functionWords = fs.readFileSync('tool/yds/function_words.txt', 'utf8').split(/\s+/).filter(Boolean);
const knownAt = {};
{
  const acc = new Set(functionWords);
  for (const lv of levels) {
    for (const w of l.seen(upTo[lv].map((f) => f.replace(/\\/g, '/')))) acc.add(w);
    knownAt[lv] = new Set([...acc, ...ngsl.slice(0, ngslTop[lv])]);
  }
}

const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const clean = (s) => typeof s === 'string' && s.length > 0 && s === s.trim() && !/[^\s] {2,}[^\s]/.test(s) && !/\*\*|<\/?[a-z]+>/.test(s);
const ids = new Set();
const rows = [];
for (const file of files) {
  const stories = JSON.parse(fs.readFileSync(file, 'utf8'));
  P(Array.isArray(stories), `${file}: dizi olmalı`);
  const answers = [0, 0, 0, 0];
  let dialogue = 0;
  const genres = {};
  for (const s of stories) {
    const at = s.id || '(id yok)';
    P(/^go_[a-z0-9_]+$/.test(s.id || ''), `${at}: id go_<slug>`);
    P(!ids.has(s.id), `${at}: id tekrar`);
    ids.add(s.id);
    P(levels.includes(s.level), `${at}: level A1/A2/B1/B2`);
    P(Object.keys(s).every((k) => ['id', 'level', 'emoji', 'title', 'titleTr', 'text', 'glosses', 'questions', 'genre'].includes(k)), `${at}: bilinmeyen alan`);
    for (const k of ['emoji', 'title', 'titleTr', 'text']) P(clean(s[k]), `${at}: ${k}`);
    const text = s.text || '';
    P(text.includes('\n\n'), `${at}: paragraflar boş satırla ayrılmalı`);
    const words = text.match(/\p{L}+(?:[-'’]\p{L}+)*/gu) || [];
    const [lo, hi] = lengths[s.level] || [0, 0];
    P(words.length >= lo && words.length <= hi, `${at}: ${words.length} kelime (${lo}–${hi})`);
    // Glosses: lower-case, found in the text, Turkish meaning.
    const glossed = new Set();
    for (const [k, v] of Object.entries(s.glosses || {})) {
      P(k === k.toLowerCase() && clean(k) && clean(v), `${at}: gloss "${k}"`);
      P(new RegExp(`(^|[^\\p{L}])${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^\\p{L}])`, 'u').test(text.toLowerCase()), `${at}: gloss "${k}" metinde kelime olarak yok`);
      k.split(/\s+/).forEach((w) => glossed.add(w));
    }
    // Unknown words after glosses (proper nouns inside a sentence are skipped).
    const known = knownAt[s.level] || new Set();
    const isKnown = (w) => known.has(w) || l.lemmas(w).some((x) => known.has(x));
    // Contractions: the base word counts ("didn't" → did, "won't" → will, "she'll" → she).
    const base = (w) => {
      const m = w.match(/^(\p{L}+)['’](t|s|re|ll|ve|d|m)$/u);
      if (!m) return null;
      if (m[2] !== 't') return m[1];
      return { won: 'will', can: 'can', shan: 'shall', ain: 'be' }[m[1]] ?? m[1].replace(/n$/, '');
    };
    // Speaker labels of interviews and scripts ("Mia: …") are names, not words.
    const labels = new Set([...text.matchAll(/(?:^|\n)(\p{Lu}\p{L}+):/gu)].map((m) => m[1]));
    const initial = new Set(text.split(/(?<=[.!?…"”:])\s+/).map((x) => (x.match(/\p{L}+/u) || [''])[0]));
    const unknown = [];
    for (const w of words) {
      if (labels.has(w) || (/^\p{Lu}/u.test(w) && !initial.has(w))) continue;
      const lw = w.toLowerCase();
      if (glossed.has(lw)) continue;
      const b = base(lw);
      if (b && (isKnown(b) || glossed.has(b))) continue;
      if (lw.split(/[-'’]/).filter((x) => x.length > 1).some((x) => !isKnown(x) && !glossed.has(x))) unknown.push(lw);
    }
    const pct = (100 * unknown.length) / Math.max(words.length, 1);
    P(pct <= 2, `${at}: bilinmeyen %${pct.toFixed(1)} (≤%2): ${[...new Set(unknown)].join(', ')}`);
    // Questions.
    const qs = s.questions || [];
    P(qs.length === 3, `${at}: 3 soru`);
    for (const [i, q] of qs.entries()) {
      P(clean(q.q) && Array.isArray(q.options) && q.options.length === 4 && q.options.every(clean), `${at}#${i}: soru/şıklar (4)`);
      P(new Set((q.options || []).map((o) => o.toLowerCase())).size === 4, `${at}#${i}: şıklar aynı`);
      P(Number.isInteger(q.answer) && q.answer >= 0 && q.answer < 4, `${at}#${i}: answer`);
      P(clean(q.explain) && q.explain.toLowerCase().includes(String(q.options?.[q.answer]).toLowerCase().slice(0, 12)), `${at}#${i}: explain doğru şıkkı metniyle anmalı`);
      P(!/(ilk|ikinci|üçüncü|dördüncü|son) (şık|seçenek)|\b[A-D]\)/i.test(q.explain || ''), `${at}#${i}: explain konumla anıyor`);
      if (Number.isInteger(q.answer)) answers[q.answer]++;
    }
    // Dialogue-heavy: at least a third of the sentences are inside quotes.
    const sentences = text.split(/(?<=[.!?…])\s+/).filter(Boolean);
    const quoted = sentences.filter((x) => /["“”]/.test(x) || /(?:^|\n)\p{Lu}\p{L}+:/u.test(x)).length;
    const isDialogue = quoted / Math.max(sentences.length, 1) >= 0.33;
    if (isDialogue) dialogue++;
    genres[s.genre] = (genres[s.genre] ?? 0) + 1;
    P(typeof s.genre === 'string' && s.genre.length > 0, `${at}: genre (öykü, anlatı, e-posta, röportaj, haber, nasıl yapılır, görüş, popüler bilim)`);
    rows.push({ id: s.id, level: s.level, words: words.length, unknown: `${pct.toFixed(1)}%`, dialogue: isDialogue ? 'yes' : '', genre: s.genre, title: s.title });
  }
  const total = answers.reduce((a, b) => a + b, 0);
  P(Math.max(...answers) < total * 0.4, `${file}: cevap konumları dengesiz ${answers}`);
  P(dialogue * 3 >= stories.length, `${file}: diyalog ağırlıklı ${dialogue}/${stories.length} (en az ⅓)`);
  console.log(`${file}: ${stories.length} metin, diyalog ${dialogue}, türler ${JSON.stringify(genres)}, cevaplar ${answers}`);
}
console.table(rows);
console.log(problems.length ? `${problems.length} sorun:\n${problems.join('\n')}` : 'TAMAM');
process.exit(problems.length ? 1 : 0);
