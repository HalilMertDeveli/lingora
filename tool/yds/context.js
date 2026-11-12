// Does a text use a word-bank item (any inflected form, phrasal verbs with irregular pasts)?
const IRR = {
  go: ['went', 'gone', 'goes', 'going'], take: ['took', 'taken', 'takes', 'taking'], give: ['gave', 'given', 'gives', 'giving'],
  run: ['ran', 'runs', 'running'], come: ['came', 'comes', 'coming'], get: ['got', 'gotten', 'gets', 'getting'],
  set: ['sets', 'setting'], put: ['puts', 'putting'], cut: ['cuts', 'cutting'], keep: ['kept', 'keeps', 'keeping'],
  break: ['broke', 'broken', 'breaks', 'breaking'], bring: ['brought', 'brings', 'bringing'], draw: ['drew', 'drawn', 'draws', 'drawing'],
  catch: ['caught', 'catches', 'catching'], lead: ['led', 'leads', 'leading'], make: ['made', 'makes', 'making'],
  stand: ['stood', 'stands', 'standing'], hand: ['handed', 'hands', 'handing'], turn: ['turned', 'turns', 'turning'],
  look: ['looked', 'looks', 'looking'], pick: ['picked', 'picks', 'picking'], fill: ['filled', 'fills', 'filling'],
  carry: ['carried', 'carries', 'carrying'], die: ['died', 'dies', 'dying'], wipe: ['wiped', 'wipes', 'wiping'],
  back: ['backed', 'backs', 'backing'], point: ['pointed', 'points', 'pointing'], focus: ['focused', 'focuses', 'focusing', 'focussed'],
  phase: ['phased', 'phases', 'phasing'], opt: ['opted', 'opts', 'opting'], pass: ['passed', 'passes', 'passing'],
  call: ['called', 'calls', 'calling'], work: ['worked', 'works', 'working'], sort: ['sorted', 'sorts', 'sorting'],
  end: ['ended', 'ends', 'ending'], cope: ['coped', 'copes', 'coping'], deal: ['dealt', 'deals', 'dealing'],
  seek: ['sought'], undergo: ['underwent', 'undergone', 'undergoes', 'undergoing'], foresee: ['foresaw', 'foreseen'],
  spread: ['spreads', 'spreading'], arise: ['arose', 'arisen'], withdraw: ['withdrew', 'withdrawn'], bleed: ['bled'],
  breed: ['bred'], forbid: ['forbade', 'forbidden'], overcome: ['overcame'], rise: ['rose', 'risen'], fall: ['fell', 'fallen'],
  grow: ['grew', 'grown'], drive: ['drove', 'driven'], begin: ['began', 'begun'], buy: ['bought'], sell: ['sold'],
  think: ['thought'], feel: ['felt'], make_: [],
};
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function forms(w) {
  const f = new Set([w, w + 's', w + 'es', w + 'ed', w + 'ing', w + 'ly', w + 'er', w + 'ers']);
  // "+d" only after a final e (use → used); otherwise kin → kind, ban → band match by mistake.
  if (w.endsWith('e')) { f.add(w + 'd'); f.add(w.slice(0, -1) + 'ing'); f.add(w.slice(0, -1) + 'ed'); }
  if (w.endsWith('y')) { f.add(w.slice(0, -1) + 'ies'); f.add(w.slice(0, -1) + 'ied'); f.add(w.slice(0, -1) + 'ily'); }
  if (/[^aeiou][aeiou][bdgmnprt]$/.test(w)) { const d = w + w.slice(-1); f.add(d + 'ed'); f.add(d + 'ing'); }
  if (w.endsWith('is')) f.add(w.slice(0, -2) + 'es'); // analysis → analyses
  if (w.endsWith('on')) f.add(w.slice(0, -2) + 'a'); // criterion → criteria
  if (w.endsWith('um')) f.add(w.slice(0, -2) + 'a');
  if (w.endsWith('us')) f.add(w.slice(0, -2) + 'i');
  if (w.endsWith('ise')) { f.add(w.slice(0, -3) + 'ize'); f.add(w.slice(0, -3) + 'ized'); f.add(w.slice(0, -3) + 'izing'); f.add(w.slice(0, -3) + 'izes'); }
  if (w.endsWith('le')) f.add(w.slice(0, -1) + 'y');
  if (w.endsWith('f')) f.add(w.slice(0, -1) + 'ves');
  for (const x of IRR[w] || []) f.add(x);
  return [...f];
}
const cache = new Map();
function regex(item) {
  if (cache.has(item)) return cache.get(item);
  const parts = item.toLowerCase().split(' ');
  const head = `(?:${forms(parts[0]).map(esc).join('|')})`;
  // Phrasal verbs may be split by a short object: "carry the test out".
  const tail = parts.slice(1).map(esc);
  const src = parts.length === 1
    ? `\\b${head}\\b`
    : `\\b${head}\\b(?:\\s+${tail.join('\\s+')}|(?:\\s+[a-z'-]+){1,3}\\s+${tail.join('\\s+')})\\b`;
  const r = new RegExp(src, 'i');
  cache.set(item, r);
  return r;
}
const uses = (text, item) => regex(item).test(text);

/// English sentences and passages of a unit (not options, not match pairs, not Turkish).
function unitContexts(unit) {
  const out = [];
  const filled = new Map(); // cloze passage → passage with its numbered blanks filled
  for (const n of unit.nodes) {
    for (const e of n.exercises || []) {
      if (e.type === 'choice') {
        // Fill the blank with the right option so the target counts as used in context.
        const q = (e.question || '').replace(/-{3,}/, e.options ? e.options[e.answer] : '');
        if (!/[çğıöşüÇĞİÖŞÜ]/.test(q)) out.push(q);
        if (e.passage) {
          let p = filled.get(e.passage) ?? e.passage;
          const k = /\((\d+)\)/.exec(e.question || '');
          if (k) p = p.replace(`(${k[1]})----`, e.options[e.answer]);
          filled.set(e.passage, p);
        }
      }
      if (e.type === 'fillBlank') out.push(e.text.replace('___', e.answer));
      if (e.type === 'translate') out.push(e.lang === 'tr' ? e.answers[0] : e.text);
    }
  }
  return [...new Set([...out, ...filled.values()])];
}

module.exports = { uses, forms, unitContexts };
