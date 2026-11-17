// Merges professional-course drafts (see check_pro.mjs) into the app:
// units go to assets/courses/<course>.json (a unit with the same id is
// replaced), each with a topic guide ("Rehber") built from its note: patterns,
// "Biz nasıl söylüyoruz?", common mistakes and a tip. The grammar path
// (assets/notes/lessons.json) is left alone.
//
//   node tool/content/check_pro.mjs draft.json && node tool/content/merge_pro.mjs draft.json
//   dart run tool/build_course_index.dart
import fs from 'node:fs';

const titles = {
  pro_dev: ['Yazılımcı Dersleri', 'Standup, code review, teknik mülakat'],
};

const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n'));
const cell = (s) => s.replaceAll('|', '/');

/// Turkish topic guide (markdown) of a unit, from its note lesson.
export function guideOf(note) {
  const md = [
    '## Bu ünitede ne öğreneceğiz?',
    note.summary,
    '',
    '## Kalıplar',
    '| Ne için? | Kalıp |',
    '|---|---|',
    ...note.formulas.map((f) => `| ${cell(f.label)} | **${cell(f.example)}** |`),
    '',
    '## Biz nasıl söylüyoruz?',
    note.compare,
    '',
    '## Sık yapılan hatalar',
    '| Yanlış | Doğru | Neden? |',
    '|---|---|---|',
    ...note.mistakes.map((m) => `| ${cell(m.wrong)} | **${cell(m.right)}** | ${cell(m.why)} |`),
    '',
    '## İpucu',
    note.tip,
  ];
  return md.join('\n');
}

for (const p of process.argv.slice(2)) {
  const d = read(p);
  const coursePath = `assets/courses/${d.course}.json`;
  const course = fs.existsSync(coursePath)
    ? read(coursePath)
    : { id: d.course, title: titles[d.course][0], fromLang: 'tr', learningLang: 'en', units: [] };
  const units = d.units.map((u, i) => {
    const { nodes, ...head } = u;
    return { ...head, guide: guideOf(d.notes[i]), nodes };
  });
  const ids = new Set(units.map((u) => u.id));
  course.units = [...course.units.filter((u) => !ids.has(u.id)), ...units];
  fs.writeFileSync(coursePath, `${JSON.stringify(course, null, 2)}\n`);

  console.log(`${p}: ${units.length} units → ${coursePath}`);
}
