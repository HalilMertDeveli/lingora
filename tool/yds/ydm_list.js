// Lists the old YDS path's vocabulary for F2c full cards (ids ydm_<word>, yds-yontem's wordCardId):
// 1) bridge words: match pairs of `vocab` lessons, path order, first occurrence wins — exactly the bridge
//    cards lib/study/review_queue.dart courseWordCards makes; their ids must stay identical;
// 2) the rest of those lessons' vocabulary: fillBlank answers and correct choice options, as base forms
//    (farmers → farmer, explained → explain); inflected forms of covered words, general-course vocabulary
//    and function words are skipped.
// Words that already have a yd_ card (ys5/ys7) are skipped. Writes tool/yds/work/ydm_list.json.
// Usage: NGSL=<NGSL 1.2 csv> node tool/yds/ydm_list.js
const l = require('./lex.js');
const cardId = (en) => 'ydm_' + en.trim().toLowerCase().replace(/\s+/g, '_');
const yd = new Set(l.J('assets/vocab/yds.json').entries.filter((e) => e.id.startsWith('yd_')).map((e) => e.word.trim().toLowerCase()));
const seen = new Set();
const out = [];
const units = l.YDS_OLD.flatMap((f) => l.J(f).units);

for (const u of units) for (const n of u.nodes) {
  if (n.type !== 'lesson' || !n.vocab) continue;
  for (const e of n.exercises || []) if (e.type === 'match') for (const [tr, en] of e.pairs) {
    const k = en.trim().toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    if (!yd.has(k)) out.push({ id: cardId(en), word: en.trim(), tr, topic: u.id, bridge: true });
  }
}

const ngsl = process.env.NGSL
  ? new Set(l.fs.readFileSync(process.env.NGSL, 'utf8').split(/\r?\n/).slice(1).map((r) => r.split(',')[0].toLowerCase()))
  : new Set();
const lexicon = new Set([...l.seen(l.GENERAL_ALL), ...ngsl]);
const generalTaught = l.taught(l.GENERAL_ALL);
const fn = new Set(l.fs.readFileSync(l.path.join(__dirname, 'function_words.txt'), 'utf8').split(/\s+/).filter(Boolean));
const base = (k) => {
  if (k.includes(' ')) return k;
  const c = l.lemmas(k).filter((x) => x !== k && !(k.endsWith('ly') && !k.endsWith('ily')));
  const known = c.filter((x) => lexicon.has(x) || seen.has(x) || yd.has(x)).sort((a, b) => b.length - a.length);
  return known[0] ?? k;
};
for (const u of units) for (const n of u.nodes) {
  if (n.type !== 'lesson' || !n.vocab) continue;
  for (const e of n.exercises || []) {
    const ans = e.type === 'fillBlank' ? e.answer : e.type === 'choice' ? e.options[e.answer] : null;
    if (typeof ans !== 'string') continue;
    const raw = ans.trim().toLowerCase();
    if (!/^[a-z][a-z' -]*$/.test(raw) || raw.split(' ').length > 4) continue;
    const k = base(raw);
    if (seen.has(k) || seen.has(raw) || yd.has(k) || fn.has(k) || generalTaught.has(k) || generalTaught.has(raw)) continue;
    seen.add(k);
    seen.add(raw);
    out.push({ id: cardId(k), word: k, tr: null, topic: u.id, bridge: false });
  }
}
l.fs.writeFileSync(l.path.join(__dirname, 'work', 'ydm_list.json'), JSON.stringify(out, null, 1));
const b = out.filter((x) => x.bridge).length;
console.log(`ydm: ${out.length} kelime (${b} köprü, ${out.length - b} yeni)`);
