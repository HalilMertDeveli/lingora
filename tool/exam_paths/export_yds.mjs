// Writes a readable review copy of the YDS path (plan: docs/sinav/yds-plan.md): every question with its
// answer and explanation, plus the full mocks of the yds_full pack. Usage:
//   node tool/exam_paths/export_yds.mjs . <out.md> [--mocks]
import fs from 'node:fs';
import path from 'node:path';

const [repo, out] = process.argv.slice(2);
const withMocks = process.argv.includes('--mocks');
const read = (p) => JSON.parse(fs.readFileSync(path.join(repo, p), 'utf8'));
const top = read('assets/courses/exam_yds.json');
const dir = path.join(repo, 'assets/courses/exam_yds');
const sections = [
  { section: top.section, units: top.units },
  ...fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort().map((f) => read(`assets/courses/exam_yds/${f}`)),
];
const L = ['A', 'B', 'C', 'D', 'E'];
const lines = [];
const w = (s = '') => lines.push(s);
const quote = (s) => s.split('\n').map((l) => `> ${l}`).join('\n');

function choice(e, no, last) {
  if (e.passage && e.passage !== last) {
    w(quote(e.passage));
    w();
  }
  w(`${no} ${(e.question ?? e.text).replace(/\n/g, '  \n')}`);
  w();
  e.options.forEach((o, k) => w(`- ${L[k]}) ${o}${k === e.answer ? ' ✅' : ''}`));
  w();
  w(`  _Açıklama:_ ${e.explanation}`);
  return e.passage ?? null;
}

w('# YDS / YÖKDİL çalışma yolu — inceleme kopyası');
w();
w('Uygulamadaki içeriğin okunur kopyası (cevaplar ✅ ve açıklamalar dahil). Kaynak: `assets/courses/exam_yds*`' + (withMocks ? ' ve `assets/exam_packs/yds_full.json`' : '') + '. Plan: `docs/sinav/yds-plan.md`.');
w();
let unitNo = 0;
for (const { section, units } of sections) {
  w(`# Bölüm ${section.index} · ${section.title}`);
  w();
  for (const u of units) {
    unitNo++;
    w(`## Ünite ${unitNo} — ${u.title} (\`${u.id}\`)`);
    w();
    w(`_${u.description}_`);
    w();
    w('### Rehber');
    w();
    w(u.guide.replace(/^## /gm, '#### '));
    w();
    for (const n of u.nodes) {
      if (n.type === 'chest') continue;
      if (n.type === 'mock') {
        const src = n.packId ? `\`${n.packId}\` paketindeki \`${n.mockId}\`` : 'bölümün ünite testlerinden ve derslerinden seçilir';
        w(`### ${n.title} (\`${n.id}\`) — ${n.size} soru, ${n.minutes} dk; ${src}`);
        w();
        continue;
      }
      w(`### ${n.title}${n.vocab ? ' · kelime dersi' : ''} (\`${n.id}\`)`);
      w();
      let last = null;
      (n.exercises ?? []).forEach((e, i) => {
        const no = `**${i + 1}.**`;
        switch (e.type) {
          case 'choice':
            last = choice(e, no, last);
            break;
          case 'match':
            w(`${no} Eşleştir: ${e.pairs.map(([tr, en]) => `${tr} = ${en}`).join(' · ')}`);
            break;
          case 'fillBlank':
            w(`${no} Boşluk: ${e.text} → **${e.answer}** (${e.choices.join(' / ')}) — _${e.translation}_`);
            break;
          default:
            w(`${no} ${e.type}`);
        }
        w();
      });
    }
  }
}
if (withMocks) {
  const pack = read('assets/exam_packs/yds_full.json');
  w('# Tam denemeler (`yds_full`)');
  w();
  for (const m of pack.mocks) {
    w(`## ${m.title} (\`${m.id}\`) — ${m.questions.length} soru, ${m.minutes} dk`);
    w();
    let last = null;
    m.questions.forEach((q, i) => {
      last = choice(q, `**${i + 1}.** _(${q.section})_`, last);
      w();
    });
  }
}
fs.writeFileSync(out, lines.join('\n'));
console.log(`${out}: ${lines.length} satır`);
