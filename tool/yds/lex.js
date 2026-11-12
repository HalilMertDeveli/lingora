// Shared helpers for YDS phase content checks (node tool/yds/*.js).
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const J = (f) => JSON.parse(fs.readFileSync(path.join(ROOT, f), 'utf8').replace(/^﻿/, ''));
const GENERAL = ['assets/courses/tr_en.json', ...['02_gunluk_hayat', '03_kendini_anlatmak', '04_sehirde_ve_iste',
  '05_deneyimler', '06_fikirler_ve_hikayeler'].map((x) => `assets/courses/tr_en/${x}.json`)];
const YDS_OLD = ['assets/courses/exam_yds.json', 'assets/courses/exam_yds/02_kelime_ve_kaliplar.json',
  'assets/courses/exam_yds/03_soru_tipleri.json', 'assets/courses/exam_yds/04_deneme_ve_zaman.json'];

function* exercises(file) {
  for (const u of J(file).units) for (const n of u.nodes) for (const e of n.exercises || []) yield [u, n, e];
}

/// Words a learner has been taught: English side of match pairs, fillBlank answers and
/// single-word correct choice options (lowercase, as written).
function taught(files) {
  const s = new Set();
  const add = (w) => { w = w.trim().toLowerCase(); if (/^[a-z][a-z' -]*$/.test(w) && w.split(' ').length <= 3) s.add(w); };
  for (const f of files) for (const [, , e] of exercises(f)) {
    if (e.type === 'match') e.pairs.forEach((p) => add(p[1]));
    if (e.type === 'fillBlank') add(e.answer);
    if (e.type === 'choice') add(e.options[e.answer]);
  }
  return s;
}

/// Every English word form that appears anywhere in [files].
function seen(files) {
  const s = new Set();
  for (const f of files) for (const [, , e] of exercises(f)) {
    const t = [e.text, e.question, e.passage, ...(e.options || []), ...(e.answers || []), ...(e.choices || []),
      ...((e.pairs || []).map((p) => p[1]))].filter((x) => typeof x === 'string' && e.lang !== 'tr').join(' ');
    tokens(t).forEach((w) => s.add(w));
  }
  return s;
}

const tokens = (t) => (t.toLowerCase().match(/[a-z]+(?:'[a-z]+)?/g) || []);

/// Rough lemma candidates for an inflected form.
function lemmas(w) {
  const out = new Set([w]);
  const add = (x) => x.length > 1 && out.add(x);
  if (w.endsWith("'s")) add(w.slice(0, -2));
  if (w.endsWith('ies')) add(w.slice(0, -3) + 'y');
  if (w.endsWith('es')) add(w.slice(0, -2));
  if (w.endsWith('s')) add(w.slice(0, -1));
  if (w.endsWith('ied')) add(w.slice(0, -3) + 'y');
  if (w.endsWith('ed')) { add(w.slice(0, -2)); add(w.slice(0, -1)); if (w[w.length - 3] === w[w.length - 4]) add(w.slice(0, -3)); }
  if (w.endsWith('ing')) { add(w.slice(0, -3)); add(w.slice(0, -3) + 'e'); if (w[w.length - 4] === w[w.length - 5]) add(w.slice(0, -4)); }
  if (w.endsWith('ly')) { add(w.slice(0, -2)); if (w.endsWith('ily')) add(w.slice(0, -3) + 'y'); if (w.endsWith('ally')) add(w.slice(0, -4)); }
  if (w.endsWith('er')) { add(w.slice(0, -2)); add(w.slice(0, -1)); }
  if (w.endsWith('est')) { add(w.slice(0, -3)); add(w.slice(0, -2)); }
  if (w.endsWith('ier')) add(w.slice(0, -3) + 'y');
  return [...out];
}

module.exports = { ROOT, J, GENERAL, YDS_OLD, exercises, taught, seen, tokens, lemmas, fs, path };
