// Rough vocabulary statistics for the skill units (curriculum §5.8): per extension unit,
// how many content-word lemmas are new to the course so far and how many are reused from
// the same section's earlier units. Lemmas are approximate: lowercase, plural/-ed/-ing/'s
// stripped, a small irregular table; function words are ignored.
//
//   node tool/content/lemma_stats.mjs
import fs from 'node:fs';
import path from 'node:path';

const dir = 'assets/courses/tr_en';
const files = ['../tr_en.json', ...fs.readdirSync(dir).filter((f) => f.endsWith('.json'))].sort((a, b) => {
  const n = (f) => (f === '../tr_en.json' ? '01' : f.slice(0, 3));
  return n(a).localeCompare(n(b));
});

const stop = new Set(`a an the and or but so if of to in on at for with from by up down out off about into over
after before than then too very not no yes i you he she it we they me him her us them my your his its our their
mine yours this that these those there here what who whom which whose when where why how is are am was were be
been being do does did done have has had will would can could should must may might shall let 's 're 've 'd 'll
n't s t d ll m re ve all some any one two three four five six seven eight nine ten just also only oh ok okay hi
hello please thanks thank`.split(/\s+/));
const irregular = { went: 'go', gone: 'go', saw: 'see', seen: 'see', took: 'take', taken: 'take', got: 'get',
  made: 'make', came: 'come', ate: 'eat', eaten: 'eat', drank: 'drink', bought: 'buy', thought: 'think',
  told: 'tell', said: 'say', left: 'leave', felt: 'feel', met: 'meet', wrote: 'write', written: 'write',
  spoke: 'speak', spoken: 'speak', knew: 'know', known: 'know', gave: 'give', given: 'give', found: 'find',
  sent: 'send', spent: 'spend', paid: 'pay', lost: 'lose', slept: 'sleep', heard: 'hear', began: 'begin',
  children: 'child', people: 'person', men: 'man', women: 'woman', better: 'good', best: 'good', worse: 'bad',
  feet: 'foot', teeth: 'tooth', ran: 'run', sat: 'sit', stood: 'stand', brought: 'bring', taught: 'teach',
  caught: 'catch', forgot: 'forget', broke: 'break', broken: 'break', woke: 'wake', swam: 'swim', flew: 'fly' };
const lemma = (w) => {
  w = w.toLowerCase().replace(/’/g, "'").replace(/'s$|'$/, '');
  if (irregular[w]) return irregular[w];
  if (w.length > 4 && w.endsWith('ies')) return w.slice(0, -3) + 'y';
  if (w.length > 4 && /(ches|shes|sses|xes)$/.test(w)) return w.slice(0, -2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
  if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3);
  if (w.length > 4 && w.endsWith('ied')) return w.slice(0, -3) + 'y';
  if (w.length > 4 && w.endsWith('ed')) return w.slice(0, -2);
  return w;
};
const english = (u) => {
  const out = [];
  const add = (s) => s && out.push(s);
  for (const n of u.nodes) {
    for (const e of n.exercises ?? []) {
      if (['listen', 'speak', 'fillBlank'].includes(e.type)) add(e.text?.replace('___', e.answer));
      if (e.type === 'translate') add(e.lang === 'en' ? e.text : e.answers[0]);
      // select answers and choice options may be Turkish: not counted
      if (e.type === 'match') for (const p of e.pairs) add(p[1]);
      if (e.type === 'choice') add(e.passage);
    }
    for (const s of n.steps ?? []) if (s.kind === 'line') add(s.text);
  }
  return out.join(' ');
};
// English words only (not parts of Turkish words); a capitalised word inside a sentence
// is a name or place and is skipped, one at a sentence start is an ordinary word.
const lemmas = (text) => {
  const out = new Set();
  for (const m of text.matchAll(/(?<![\p{L}'’])[A-Za-z][A-Za-z'’-]*(?![\p{L}])/gu)) {
    const w = m[0];
    const before = text.slice(0, m.index).trimEnd();
    const sentenceStart = before === '' || /[.!?:\n"]$/.test(before);
    if (/^[A-Z]/.test(w) && !sentenceStart && w !== 'I') continue;
    const l = lemma(w);
    if (l.length > 1 && !stop.has(l)) out.add(l);
  }
  return out;
};

const known = new Set();
const rows = [];
for (const f of files) {
  const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  const section = j.section?.id ?? j.extends;
  const ext = /x_/.test(f);
  const sectionWords = new Set();
  if (ext) {
    // Words of the section's own (base) units.
    const base = f.startsWith('01') ? '../tr_en.json' : files.find((x) => x.startsWith(f.slice(0, 2) + '_'));
    for (const u of JSON.parse(fs.readFileSync(path.join(dir, base), 'utf8')).units) for (const w of lemmas(english(u))) sectionWords.add(w);
  }
  for (const u of j.units) {
    const ws = lemmas(english(u));
    if (ext) {
      const fresh = [...ws].filter((w) => !known.has(w));
      const reused = [...ws].filter((w) => sectionWords.has(w));
      rows.push({ section, unit: u.id, title: u.title, lemmas: ws.size, new: fresh.length, reusedFromSection: reused.length, sampleNew: fresh.slice(0, process.env.ALL ? 99 : 12).join(' ') });
      for (const w of ws) sectionWords.add(w);
    }
    for (const w of ws) known.add(w);
  }
}
console.table(rows);
