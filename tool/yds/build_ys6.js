// Builds assets/courses/exam_yds/06_okuma_evi_1.json from tool/yds/work/ys6u1..6.json + ys6m.json.
// Usage: node tool/yds/build_ys6.js
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const read = (f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8'));
const units = Array.from({ length: 6 }, (_, i) => read(`ys6u${i + 1}.json`));
const mock = read('ys6m.json');
units[5].nodes.push({
  id: 'ys6u6m',
  type: 'mock',
  title: 'Yarım deneme 1 (tanı)',
  description: 'YDS dağılımında 40 soru, 90 dakika. Gerçek sınavdan bir basamak kolay (B1–B1+); sonucuna göre zayıf soru tiplerini gör.',
  examId: 'yds',
  size: 40,
  minutes: 90,
  exercises: mock.exercises,
});
const section = {
  section: {
    id: 'ys6',
    index: 6,
    title: 'Okuma evi 1',
    cefr: 'A2+–B1',
    parallel: true,
    description: 'Yoğun okuma: fen, sağlık ve sosyal konularda 48 özgün metin, her ünitede bir okuma stratejisi ve cümle çözümleme; sonunda 40 soruluk tanı denemesi',
    grammar: units.map((u) => u.title.toLowerCase()),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds/06_okuma_evi_1.json'), JSON.stringify(section, null, 2) + '\n');
console.log(`ys6: ${units.length} ünite, deneme ${mock.exercises.length} soru`);
