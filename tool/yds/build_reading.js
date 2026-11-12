// Builds a reading section from tool/yds/work/: ys6 "Okuma evi 1" (06_okuma_evi_1.json), ys8 "Okuma evi 2"
// (08_okuma_evi_2.json) or ys10 "Okuma evi 3" (10_okuma_evi_3.json).
// ys6/ys8: the last unit gets the section's half mock (work/<sec>m.json).
// ys10 (Faz 3b): half mocks 6–8 after the chests of u3/u5/u7 (work/ys10u3m.json …), and the last unit ends
// with a section mock drawn from the section (size 30, 45 minutes).
// Usage: node tool/yds/build_reading.js ys6 | ys8 | ys10
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const read = (f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8'));
const halfMock = (n, week) => ({
  title: `Yarım deneme ${n}`,
  description: `Plandaki ${week} denemesi: YDS dağılımında 40 soru, 90 dakika, gerçek sınav düzeyinde (B2). Sonucunu önceki yarım denemelerle karşılaştır.`,
});
const SECTIONS = {
  ys6: {
    file: '06_okuma_evi_1.json', index: 6, units: 6, title: 'Okuma evi 1', cefr: 'A2+–B1',
    description: 'Yoğun okuma: fen, sağlık ve sosyal konularda 48 özgün metin, her ünitede bir okuma stratejisi ve cümle çözümleme; sonunda 40 soruluk tanı denemesi',
    mocks: { 6: { title: 'Yarım deneme 1 (tanı)', description: 'YDS dağılımında 40 soru, 90 dakika. Gerçek sınavdan bir basamak kolay (B1–B1+); sonucuna göre zayıf soru tiplerini gör.', file: 'ys6m.json' } },
  },
  ys8: {
    file: '08_okuma_evi_2.json', index: 8, units: 10, title: 'Okuma evi 2', cefr: 'B2',
    description: 'Akademik okuma: gerçek YDS uzunluğunda 80 özgün metin, her ünitede bir soru türü ya da metin yapısı stratejisi; sonunda 40 soruluk yarım deneme',
    mocks: { 10: { title: 'Yarım deneme 5', description: 'YDS dağılımında 40 soru, 90 dakika, gerçek sınav düzeyinde (B2). Sonucunu önceki yarım denemelerle karşılaştır.', file: 'ys8m.json' } },
  },
  ys10: {
    file: '10_okuma_evi_3.json', index: 10, units: 8, title: 'Okuma evi 3', cefr: 'B2',
    description: 'YÖKDİL alan okuması: fen, sağlık ve sosyal bilimlerde 64 özgün metin, terim yoğun uzun cümleler ve paragraf soruları; arada yarım denemeler 6–8',
    mocks: {
      3: { ...halfMock(6, 'H37'), file: 'ys10u3m.json' },
      5: { ...halfMock(7, 'H39'), file: 'ys10u5m.json' },
      7: { ...halfMock(8, 'H41'), file: 'ys10u7m.json' },
    },
    sectionMock: { title: 'Okuma evi 3 denemesi', description: 'Bölümün alan metinlerinden 30 soru, 45 dakika', size: 30, minutes: 45 },
  },
};
const sec = process.argv[2];
const s = SECTIONS[sec];
if (!s) throw new Error('kullanım: build_reading.js ys6|ys8|ys10');
const units = Array.from({ length: s.units }, (_, i) => read(`${sec}u${i + 1}.json`));
const counts = [];
for (const [u, m] of Object.entries(s.mocks)) {
  const ex = read(m.file).exercises;
  units[u - 1].nodes.push({
    id: `${sec}u${u}m`, type: 'mock', title: m.title, description: m.description, examId: 'yds', size: 40, minutes: 90, exercises: ex,
  });
  counts.push(`${sec}u${u}m ${ex.length}`);
}
if (s.sectionMock) {
  const m = s.sectionMock;
  units[s.units - 1].nodes.push({
    id: `${sec}u${s.units}m`, type: 'mock', title: m.title, description: m.description, examId: 'yds', size: m.size, minutes: m.minutes,
  });
  counts.push(`${sec}u${s.units}m bölümden ${m.size}`);
}
const section = {
  section: {
    id: sec, index: s.index, title: s.title, cefr: s.cefr, parallel: true, description: s.description,
    grammar: units.map((u) => u.title.toLocaleLowerCase('tr')),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds', s.file), JSON.stringify(section, null, 2) + '\n');
console.log(`${sec}: ${units.length} ünite; denemeler: ${counts.join(', ')}`);
