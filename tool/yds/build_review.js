// Builds assets/courses/exam_yds/11_ara_denemeler.json (ys11 "Ara denemeler", YDS Faz 3d) from
// tool/yds/work/ys11u1..3.json and the half mocks ys11u1m..3m.json (added after each unit's chest).
// Usage: node tool/yds/build_review.js
const l = require('./lex.js');
const work = l.path.join(__dirname, 'work');
const read = (f) => JSON.parse(l.fs.readFileSync(l.path.join(work, f), 'utf8'));
const MOCKS = [
  { title: 'Yarım deneme 2', week: 22 },
  { title: 'Yarım deneme 3', week: 24 },
  { title: 'Yarım deneme 4', week: 27 },
];
const units = MOCKS.map((m, i) => {
  const u = read(`ys11u${i + 1}.json`);
  u.nodes.push({
    id: `ys11u${i + 1}m`, type: 'mock', title: m.title,
    description: `YDS dağılımında 40 soru, 90 dakika (B1+–B2). Planın ${m.week}. haftasındaki yarım deneme; sonucunu önceki denemelerle karşılaştır.`,
    examId: 'yds', size: 40, minutes: 90, exercises: read(`ys11u${i + 1}m.json`).exercises,
  });
  return u;
});
const section = {
  section: {
    id: 'ys11', index: 11, title: 'Ara denemeler', cefr: 'B1+–B2', parallel: true,
    description: 'Planın 22., 24. ve 27. haftaları: o ana kadarki konulardan karışık tekrar, ardından 40 soruluk yarım deneme',
    grammar: units.map((u) => u.title.toLocaleLowerCase('tr')),
  },
  units,
};
l.fs.writeFileSync(l.path.join(l.ROOT, 'assets/courses/exam_yds/11_ara_denemeler.json'), JSON.stringify(section, null, 2) + '\n');
console.log(`ys11: ${units.length} ünite, ${units.reduce((n, u) => n + u.nodes.length, 0)} düğüm`);
