// Builds a reading section from tool/yds/work/: ys6 "Okuma evi 1" (06_okuma_evi_1.json) or
// ys8 "Okuma evi 2" (08_okuma_evi_2.json); the last unit gets the section's half mock (work/<sec>m.json).
// Usage: node tool/yds/build_reading.js ys6 | ys8
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const read = (f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8'));
const SECTIONS = {
  ys6: {
    file: '06_okuma_evi_1.json', index: 6, units: 6, title: 'Okuma evi 1', cefr: 'A2+–B1',
    description: 'Yoğun okuma: fen, sağlık ve sosyal konularda 48 özgün metin, her ünitede bir okuma stratejisi ve cümle çözümleme; sonunda 40 soruluk tanı denemesi',
    mock: { title: 'Yarım deneme 1 (tanı)', description: 'YDS dağılımında 40 soru, 90 dakika. Gerçek sınavdan bir basamak kolay (B1–B1+); sonucuna göre zayıf soru tiplerini gör.' },
  },
  ys8: {
    file: '08_okuma_evi_2.json', index: 8, units: 10, title: 'Okuma evi 2', cefr: 'B2',
    description: 'Akademik okuma: gerçek YDS uzunluğunda 80 özgün metin, her ünitede bir soru türü ya da metin yapısı stratejisi; sonunda 40 soruluk yarım deneme',
    mock: { title: 'Yarım deneme 2', description: 'YDS dağılımında 40 soru, 90 dakika, gerçek sınav düzeyinde (B2). Sonucunu Yarım deneme 1 ile karşılaştır.' },
  },
};
const sec = process.argv[2];
const s = SECTIONS[sec];
if (!s) throw new Error('kullanım: build_reading.js ys6|ys8');
const units = Array.from({ length: s.units }, (_, i) => read(`${sec}u${i + 1}.json`));
const mock = read(`${sec}m.json`);
units[s.units - 1].nodes.push({
  id: `${sec}u${s.units}m`, type: 'mock', title: s.mock.title, description: s.mock.description,
  examId: 'yds', size: 40, minutes: 90, exercises: mock.exercises,
});
const section = {
  section: {
    id: sec, index: s.index, title: s.title, cefr: s.cefr, parallel: true, description: s.description,
    grammar: units.map((u) => u.title.toLocaleLowerCase('tr')),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds', s.file), JSON.stringify(section, null, 2) + '\n');
console.log(`${sec}: ${units.length} ünite, deneme ${mock.exercises.length} soru`);
