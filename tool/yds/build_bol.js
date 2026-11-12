// Builds the YDS extensive-reading files (ReadingStory arrays) from tool/yds/work/:
//   node tool/yds/build_bol.js      → assets/reading/yds_bol_okuma_1.json from bol_*.json  (B1 first, then B1+)
//   node tool/yds/build_bol.js 2    → assets/reading/yds_bol_okuma_2.json from bol2_*.json (B1+ first, then B2)
// Each level group keeps the writers' order.
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const set = process.argv[2] === '2'
  ? { pattern: /^bol2_(\d+)\.json$/, levels: ['B1+', 'B2'], out: 'yds_bol_okuma_2' }
  : { pattern: /^bol_(\d+)\.json$/, levels: ['B1', 'B1+'], out: 'yds_bol_okuma_1' };
const files = l.fs.readdirSync(work).filter((f) => set.pattern.test(f))
  .sort((a, b) => +a.match(set.pattern)[1] - +b.match(set.pattern)[1]);
const all = files.flatMap((f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8')));
const keys = ['id', 'level', 'emoji', 'title', 'titleTr', 'text', 'glosses', 'questions'];
const out = set.levels.flatMap((lv) => all.filter((s) => s.level === lv))
  .map((s) => Object.fromEntries(keys.map((k) => [k, s[k]])));
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/reading', `${set.out}.json`), JSON.stringify(out, null, 2) + '\n');
console.log(`${set.out}: ${out.length} metin (${files.join(', ')})`);
