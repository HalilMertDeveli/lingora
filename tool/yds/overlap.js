// Topic-overlap scan: compares new passages with every passage already in the app (reading sections,
// half mocks, full mocks, extensive reading) by shared content words (Jaccard on words of 5+ letters).
const l = require('./lex.js');

const STOP = new Set(('the a an and of to in is are was were that this it for on with as by be from at or which who have has had ' +
  'their they its not but can more than been also into about such these those many most some may other one two when there ' +
  'would could after over so if what how our we you he she his her them').split(' '));
const bag = (t) => new Set((t.toLowerCase().match(/[a-z]{5,}/g) || []).filter((w) => !STOP.has(w)));

/// [source id, passage] for every long passage shipped in the app, minus the sources [skip] names.
function existingPassages(skip = () => false) {
  const out = [];
  const exam = l.path.join(l.ROOT, 'assets/courses/exam_yds');
  for (const f of l.fs.readdirSync(exam).filter((x) => x.endsWith('.json'))) {
    for (const u of l.J(`assets/courses/exam_yds/${f}`).units) for (const n of u.nodes) {
      if (skip(n.id)) continue;
      for (const e of n.exercises || []) if (e.passage && e.passage.split(/\s+/).length > 120) out.push([n.id, e.passage]);
    }
  }
  for (const m of l.J('assets/exam_packs/yds_full.json').mocks) {
    if (skip(m.id)) continue;
    for (const q of m.questions) if (q.passage && q.passage.split(/\s+/).length > 120) out.push([m.id, q.passage]);
  }
  for (const f of l.fs.readdirSync(l.path.join(l.ROOT, 'assets/reading'))) for (const s of l.J(`assets/reading/${f}`)) out.push([s.id, s.text]);
  return [...new Map(out.map((x) => [x[1], x])).values()];
}

/// Problems for passages of [mine] that share too many content words with [existing].
function overlaps(mine, existing, limit = 0.18) {
  const problems = [];
  const seen = new Set();
  for (const p of mine) {
    const a = bag(p);
    for (const [src, t] of existing) {
      if (t === p) continue;
      const b = bag(t);
      let c = 0;
      for (const w of a) if (b.has(w)) c++;
      const jac = c / (a.size + b.size - c);
      const key = `${src}|${p.slice(0, 30)}`;
      if (jac > limit && !seen.has(key)) {
        seen.add(key);
        problems.push(`konu örtüşmesi ${jac.toFixed(2)} (${src}): ${p.slice(0, 60)}…`);
      }
    }
  }
  return problems;
}

/// Second check for short texts (dialogues, paragraph items): shared RARE words reveal a repeated topic
/// ("waggle", "tardigrade", "placebo"). Rare = wordfreq Zipf < 3.3 (WORDFREQ=<tsv>) and 6+ letters.
/// [mine]: [id, text] pairs; [all]: [id, text] of everything else (short texts included).
let zipf = null;
const QUESTION_WORDS = new Set(["inferred", "inference", "paragraph", "passage", "restatement", "dialogue"]);
function rareOverlaps(mine, all, minShared = 1) {
  if (!process.env.WORDFREQ) return [];
  zipf ??= new Map(l.fs.readFileSync(process.env.WORDFREQ, 'utf8').split('\n').map((r) => r.split('\t')).map(([w, z]) => [w, +z]));
  // English words only (in wordfreq at all, Zipf ≥ 1.5 — Turkish stems are not), and rare (< 3.3).
  const rare = (t) => new Set((t.toLowerCase().match(/[a-z]{6,}/g) || []).filter((w) => {
    const z = Math.max(zipf.get(w) ?? 0, zipf.get(w.replace(/s$/, '')) ?? 0);
    return z >= 1.5 && z < 3.0 && !QUESTION_WORDS.has(w);
  }));
  const index = new Map();
  for (const [src, t] of all) for (const w of rare(t)) (index.get(w) ?? index.set(w, new Set()).get(w)).add(src);
  const problems = [];
  for (const [id, t] of mine) {
    const hits = new Map();
    for (const w of rare(t)) for (const src of index.get(w) ?? []) if (src !== id) (hits.get(src) ?? hits.set(src, []).get(src)).push(w);
    for (const [src, ws] of hits) if (ws.length >= minShared) problems.push(`nadir kelime tekrarı (${src}): ${id} → ${ws.slice(0, 5).join(', ')}`);
  }
  return problems;
}

/// Every text shipped in the app, short ones included (questions, passages, stories), as [id, text].
function allTexts() {
  const out = [];
  const exam = l.path.join(l.ROOT, 'assets/courses/exam_yds');
  for (const f of l.fs.readdirSync(exam).filter((x) => x.endsWith('.json'))) {
    for (const u of l.J(`assets/courses/exam_yds/${f}`).units) for (const n of u.nodes) for (const e of n.exercises || []) {
      out.push([n.id, [e.passage, e.question, e.text].filter(Boolean).join(' ')]);
    }
  }
  for (const m of l.J('assets/exam_packs/yds_full.json').mocks) for (const q of m.questions) out.push([m.id, [q.passage, q.text].filter(Boolean).join(' ')]);
  for (const f of l.fs.readdirSync(l.path.join(l.ROOT, 'assets/reading'))) for (const s of l.J(`assets/reading/${f}`)) out.push([s.id, s.text]);
  return out;
}

module.exports = { existingPassages, overlaps, rareOverlaps, allTexts };
