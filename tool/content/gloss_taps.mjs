// Lists glosses the reading screen cannot tap: the same tokenizer as
// lib/models/reading.dart tokenizeStory (whitespace split, edge punctuation
// stripped, longest phrase of up to 6 words first). Run with --fix to replace an
// unmatched key by the form that appears in the text ("mayor" → "mayor's")
// when exactly one such form exists.
//
//   node tool/content/gloss_taps.mjs [--fix] assets/reading/genel_okuma_a.json …
import fs from 'node:fs';

const fix = process.argv.includes('--fix');
const files = process.argv.slice(2).filter((a) => a !== '--fix');
const norm = (w) => w.replaceAll('’', "'").replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, '').toLowerCase();
let bad = 0;
for (const f of files) {
  const stories = JSON.parse(fs.readFileSync(f, 'utf8'));
  for (const s of stories) {
    const tapped = new Set();
    const words = [];
    for (const p of s.text.split(/\n\s*\n/).filter((x) => x.trim())) {
      const n = p.trim().split(/\s+/).map(norm);
      words.push(...n);
      for (let i = 0; i < n.length; ) {
        let len = 1;
        for (let k = 6; k >= 1; k--) {
          if (i + k > n.length) continue;
          const key = n.slice(i, i + k).join(' ');
          if (key in s.glosses) { tapped.add(key); len = k; break; }
        }
        i += len;
      }
    }
    for (const key of Object.keys(s.glosses)) {
      if (tapped.has(key)) continue;
      // Single-word keys: inflected or possessive forms in the text.
      const forms = key.includes(' ') ? [] : [...new Set(words.filter((w) => w.startsWith(key) && w !== key))];
      if (fix && forms.length === 1) {
        s.glosses[forms[0]] = s.glosses[key];
        delete s.glosses[key];
        console.log(`${s.id}: "${key}" → "${forms[0]}"`);
      } else {
        bad++;
        console.log(`${s.id}: "${key}" cannot be tapped${forms.length ? ` (forms: ${forms.join(', ')})` : ''}`);
      }
    }
  }
  if (fix) fs.writeFileSync(f, JSON.stringify(stories, null, 2) + '\n');
}
console.log(bad ? `${bad} gloss(es) cannot be tapped` : 'OK');
process.exit(bad ? 1 : 0);
