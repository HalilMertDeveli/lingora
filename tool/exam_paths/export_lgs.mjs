// Writes a readable review copy of the LGS path (docs/sinav/lgs-plan.md): every question with its
// answer and explanation. Usage: node tool/exam_paths/export_lgs.mjs . <out.md>
import fs from 'node:fs';
import path from 'node:path';

const [repo, out] = process.argv.slice(2);
const read = (p) => JSON.parse(fs.readFileSync(path.join(repo, p), 'utf8'));
const top = read('assets/courses/exam_lgs.json');
const dir = path.join(repo, 'assets/courses/exam_lgs');
const sections = [
  { section: top.section, units: top.units },
  ...fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort().map((f) => read(`assets/courses/exam_lgs/${f}`)),
];
const L = ['A', 'B', 'C', 'D', 'E'];
const lines = [];
const w = (s = '') => lines.push(s);
const quote = (s) => s.split('\n').map((l) => `> ${l}`).join('\n');

w('# LGS İngilizce çalışma yolu — inceleme kopyası');
w();
w('Bu dosya uygulamadaki içeriğin okunur kopyasıdır (cevaplar ve açıklamalar dahil). Kaynak: `assets/courses/exam_lgs*`. Plan: `docs/sinav/lgs-plan.md`.');
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
        w(`### ${n.title} (\`${n.id}\`) — ${n.size} soru, ${n.minutes} dk; sorular bölümün mini testlerinden seçilir`);
        w();
        continue;
      }
      w(`### ${n.title} (\`${n.id}\`)`);
      w();
      let lastPassage = null;
      (n.exercises ?? []).forEach((e, i) => {
        const no = `**${i + 1}.**`;
        switch (e.type) {
          case 'choice':
            if (e.passage && e.passage !== lastPassage) {
              w(quote(e.passage));
              w();
            }
            lastPassage = e.passage ?? null;
            w(`${no} ${e.question.replace(/\n/g, '  \n')}`);
            w();
            e.options.forEach((o, k) => w(`- ${L[k]}) ${o}${k === e.answer ? ' ✅' : ''}`));
            w();
            w(`  _Açıklama:_ ${e.explanation}`);
            break;
          case 'select':
            w(`${no} Kart: "${e.prompt}" → **${e.answer}** (seçenekler: ${e.choices.map((c) => `${c.emoji} ${c.text}`).join(', ')})`);
            break;
          case 'match':
            w(`${no} Eşleştir: ${e.pairs.map(([tr, en]) => `${tr} = ${en}`).join(' · ')}`);
            break;
          case 'fillBlank':
            w(`${no} Boşluk: ${e.text} → **${e.answer}** (${e.choices.join(' / ')}) — _${e.translation}_`);
            break;
          case 'translate':
            w(`${no} Çeviri: "${e.text}" → **${e.answers.join(' | ')}** (kelimeler: ${e.tokens.join(' ')})`);
            break;
          default:
            w(`${no} ${e.type}`);
        }
        w();
      });
    }
  }
}
fs.writeFileSync(out, lines.join('\n'));
console.log(`${out}: ${lines.length} satır`);
