// Checks ydm_ full cards (YDS Faz 2c) written from tool/yds/work/ydm_list.json.
// Usage: node tool/yds/check_ydm.js tool/yds/work/ydm_1.json [more…]
const l = require('./lex.js');
const list = l.J('tool/yds/work/ydm_list.json');
const bridge = new Map(list.filter((x) => x.bridge).map((x) => [x.id, x]));
const cardId = (w) => 'ydm_' + w.trim().toLowerCase().replace(/\s+/g, '_');
const yd = new Set(l.J('assets/vocab/yds.json').entries.filter((e) => e.id.startsWith('yd_')).map((e) => e.word.trim().toLowerCase()));
const problems = [];
const P = (ok, m) => { if (!ok) problems.push(m); };
const clean = (s) => typeof s === 'string' && s.length > 0 && s === s.trim() && !/[^\s] {2,}[^\s]/.test(s) && !/\*\*/.test(s);
const ids = new Set();
let n = 0, tips = 0;
for (const f of process.argv.slice(2)) {
  for (const c of JSON.parse(l.fs.readFileSync(f, 'utf8'))) {
    n++;
    const at = c.id || '(id yok)';
    P(typeof c.word === 'string' && c.id === cardId(c.word), `${at}: id = ydm_ + word`);
    P(!ids.has(c.id), `${at}: tekrar`);
    ids.add(c.id);
    P(!yd.has((c.word || '').toLowerCase()), `${at}: yd_ kartı zaten var`);
    const b = bridge.get(c.id);
    if (b) {
      P(c.word === b.word, `${at}: köprü kelimesi aynen kalmalı ("${b.word}")`);
      P(c.topic === b.topic, `${at}: topic ${b.topic}`);
      P(c.senses?.[0]?.tr === b.tr, `${at}: ilk anlam köprü karşılığı olmalı ("${b.tr}")`);
    }
    P(/^ys[1-4]u\d+$/.test(c.topic || ''), `${at}: topic ys1–ys4 ünitesi`);
    P(typeof c.pos === 'string', `${at}: pos`);
    P(Array.isArray(c.senses) && c.senses.length && c.senses.every((s) => clean(s.tr) && clean(s.def)), `${at}: senses`);
    P(Array.isArray(c.examples) && c.examples.length && c.examples.every((x) => clean(x.en) && clean(x.tr) && x.en.includes(x.target) && ['genel', 'akademik', 'haber'].includes(x.context)), `${at}: örnek`);
    P(Array.isArray(c.collocations) && c.collocations.length && c.collocations.every((x) => clean(x.phrase) && clean(x.tr) && x.phrase.includes(x.answer)), `${at}: eşdizim`);
    if (/verb|noun/.test(c.pos || '')) P(Array.isArray(c.family), `${at}: family`);
    if (c.tip) tips++;
  }
}
P(tips >= n / 2, `ipucu ${tips}/${n} (en az yarısı)`);
console.log(`${problems.length ? 'HATA ' + problems.length : 'TAMAM'}: ${n} kart, ${tips} ipucu`);
problems.slice(0, 40).forEach((p) => console.log('  ✗ ' + p));
process.exitCode = problems.length ? 1 : 0;
