// Builds assets/reading/yds_bol_okuma_1.json (ReadingStory array) from tool/yds/work/bol_*.json:
// B1 texts first, then B1+, each group in the writers' order.
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const files = l.fs.readdirSync(work).filter((f) => /^bol_\d+\.json$/.test(f)).sort();
const all = files.flatMap((f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8')));
const keys = ['id', 'level', 'emoji', 'title', 'titleTr', 'text', 'glosses', 'questions'];
const out = [...all.filter((s) => s.level === 'B1'), ...all.filter((s) => s.level === 'B1+')]
  .map((s) => Object.fromEntries(keys.map((k) => [k, s[k]])));
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/reading/yds_bol_okuma_1.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`yds_bol_okuma_1: ${out.length} metin (${files.join(', ')})`);
