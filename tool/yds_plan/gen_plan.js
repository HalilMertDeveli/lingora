// Generates the weekly table (markdown) and machine-readable plan JSON for the 52-week YDS program.
// Usage (repo root): node tool/yds_plan/gen_plan.js .
// Rewrites the table between the TABLO markers in docs/sinav/yds-1-yil.md and assets/plans/yds_1_yil.json.
const fs = require('fs');
const path = require('path');
const root = process.argv[2];

// Phases
const phases = [
  { id: 1, title: 'Sıfır → A2 temel', weeks: [1, 10], minutes: 'H1–4: 120–150 dk, H5–10: 180 dk' },
  { id: 2, title: 'A2 → B1 ve YDS temeli', weeks: [11, 20], minutes: '210 dk' },
  { id: 3, title: 'B1 → B2 akademik', weeks: [21, 34], minutes: '210–240 dk' },
  { id: 4, title: 'Sınav stratejisi', weeks: [35, 42], minutes: '210–240 dk' },
  { id: 5, title: 'Deneme kampı', weeks: [43, 52], minutes: '240 dk' },
];

// newWords per week, reading words per day, choice questions per day
function targets(w) {
  if (w <= 2) return { newWords: 100, readPerDay: 300, qPerDay: 0, intensive: 0 };
  if (w <= 4) return { newWords: 160, readPerDay: 300, qPerDay: 0, intensive: 0 };
  if (w <= 7) return { newWords: 160, readPerDay: 600, qPerDay: 0, intensive: 0 };
  if (w <= 10) return { newWords: 160, readPerDay: 600, qPerDay: 10, intensive: 0 };
  if (w <= 14) return { newWords: 150, readPerDay: 1000, qPerDay: 25, intensive: 0 };
  if (w <= 20) return { newWords: 150, readPerDay: 1000, qPerDay: 25, intensive: 1 };
  if (w <= 34) return { newWords: 145, readPerDay: 1500, qPerDay: 35, intensive: 1 };
  if (w <= 42) return { newWords: 125, readPerDay: 1800, qPerDay: 40, intensive: 2 };
  if (w <= 50) return { newWords: 75, readPerDay: 2000, qPerDay: 40, intensive: 2 };
  return { newWords: 0, readPerDay: 2000, qPerDay: 40, intensive: 2 };
}

// [week, path units / lessons, grammar focus, question-type work, mock]
const W = [
  [1, 'Genel s1 u1–u5', 'to be, isim çoğulu, a/an, this/that', '—', ''],
  [2, 'Genel s1 u6–u12', 'present simple, there is/are, can, past simple giriş', '—', ''],
  [3, 'Genel s2 u1–u6', 'present simple 3. tekil, sıklık zarfları, iyelik', '—', ''],
  [4, 'Genel s2 u7–u12', 'edatlar (yer/zaman), emir, can/can\'t', '—', ''],
  [5, 'Genel s3 u1–u6', 'past simple, past continuous', '—', ''],
  [6, 'Genel s3 u7–u12', 'nesne zamirleri, karşılaştırma, much/many, going to/will', '—', ''],
  [7, 'Genel s4 u1–u4', 'present perfect (ever/never, just/already/yet)', '—', ''],
  [8, 'Genel s4 u5–u8', 'should/must/have to, too/enough, first conditional, -ing/to', 'Tadım: 5 şıklı dilbilgisi (A2)', ''],
  [9, 'Genel s4 u9–u12', 'who/which/that (giriş), resmî e-posta dili', 'Tadım: kelime ve dilbilgisi (A2)', ''],
  [10, 'Tekrar haftası: s1–s4 ünite testleri', 'A1–A2 karışık', 'Tadım: kısa paragraf (A2)', 'Seviye kontrolü (genel kurs s4 sonu)'],
  [11, 'Genel s5 u1–u4', 'present perfect continuous, used to, edilgen (giriş)', 'Dilbilgisi (B1)', ''],
  [12, 'Genel s5 u5–u8', 'edilgen, second conditional, reported speech, phrasal verbs', 'Dilbilgisi, kelime', ''],
  [13, 'YDS ys1u11 Cümlenin iskeleti, ys1u12 İsim öbeği ve gönderim', 'özne–yüklem, isim öbeği, gönderim', 'Dilbilgisi, kelime', ''],
  [14, 'YDS ys1u13 Temel zamanlar, Genel s5 u9–u12', 'zaman çekirdeği, modal of deduction', 'Dilbilgisi, cümle tamamlama (giriş)', ''],
  [15, 'YDS ys1u14 Sözcük türetme, Genel s6 u1–u3', 'ek ile türetme, past perfect', 'Kelime, cloze (giriş)', ''],
  [16, 'YDS ys1u15 Temel bağlaçlar, ys1u16 Uzun cümle', 'bağlaç ve edat çekirdeği, sıfat cümleciği', 'Cümle tamamlama, çeviri (giriş)', ''],
  [17, 'YDS ys1u1 Zamanlar, Genel s6 u4–u6', 'zaman uyumu, so/such…that, wish', 'Dilbilgisi, cloze', ''],
  [18, 'YDS ys1u2 Kipler, Genel s6 u7–u9', 'kipler, question tags', 'Dilbilgisi, cümle tamamlama', ''],
  [19, 'YDS ys1u3 Edilgen ve ettirgen, Genel s6 u10–u12', 'edilgen, ettirgen, karşıtlık (yine de)', 'Dilbilgisi, çeviri', ''],
  [20, 'YDS ys1u4 Koşul ve wish', 'koşul türleri, wish/if only', 'Karışık set (H11–20)', 'Yarım deneme 1 (tanı, 40 soru / 90 dk)'],
  [21, 'YDS ys1u5 Sıfat cümlecikleri', 'relative clause, kısaltma', 'Dilbilgisi, çeviri', ''],
  [22, 'YDS ys1u6 İsim cümlecikleri, Genel s7 u1–u2', 'noun clause, mixed conditionals', 'Dilbilgisi, cümle tamamlama', 'Yarım deneme 2'],
  [23, 'YDS ys1u7 Gerund ve infinitive, Genel s7 u3', 'gerund/infinitive, should have', 'Dilbilgisi, cloze', ''],
  [24, 'YDS ys1u8 Bağlaçlar ve geçişler, Genel s7 u4', 'bağlaç ve geçiş ifadeleri, haber dili', 'Cümle tamamlama, paragraf tamamlama (giriş)', 'Yarım deneme 3'],
  [25, 'YDS ys1u9 Edatlar, Genel s7 u7', 'edat + eşdizim, causative', 'Kelime, cloze', ''],
  [26, 'YDS ys1u10 Miktar ve karşılaştırma, Genel s7 u8', 'quantifier, karşılaştırma, inversion', 'Karışık set (ys1)', 'Bölüm 1 denemesi (ys1 sonu)'],
  [27, 'YDS ys2u1 Akademik fiiller, ys2u2 Sıfatlar ve zarflar', 'akademik fiil kalıpları', 'Kelime, cümle tamamlama', 'Yarım deneme 4'],
  [28, 'YDS ys2u3 Phrasal verbs, ys2u4 İsim kalıpları', 'phrasal verb, eşdizim', 'Kelime, cloze', ''],
  [29, 'YDS ys2u5 Eş anlamlılar, ys2u6 Karıştırılanlar, Genel s8 u2', 'eş anlam, bağlamdan anlam, yazıda bağlantı', 'Kelime, restatement (giriş)', ''],
  [30, 'YDS ys2u7–u9 YÖKDİL alan kelimeleri (hedef alana ağırlık)', 'alan terimleri', 'Okuma (alan metinleri)', 'Tam deneme 1 (yeni: yds_m9)'],
  [31, 'YDS ys2u10–u11 Kelime setleri 1–2, Genel s8 u8', 'ince anlam farkları', 'Kelime, cloze', ''],
  [32, 'YDS ys2u12–u13 Kelime setleri 3–4, Genel s8 u10', 'akademik ses', 'Kelime, okuma', 'Yarım deneme 5'],
  [33, 'YDS ys2u14–u15 Kelime setleri 5–6', 'zarf ve kalıplar', 'Karışık set (ys2)', 'Bölüm 2 denemesi (ys2 sonu)'],
  [34, 'Tekrar haftası: ys1–ys2 zayıf üniteler (analize göre)', 'zayıf konular', 'Karışık set (ys1–ys2)', 'Tam deneme 2 (yeni: yds_m10)'],
  [35, 'YDS ys3u1 Cloze, ys3u2 Cümle tamamlama', '—', 'Cloze, cümle tamamlama (strateji)', ''],
  [36, 'YDS ys3u3 Çeviri İng→Tr, ys3u4 Çeviri Tr→İng', '—', 'Çeviri (iki yön)', 'Tam deneme 3 (yeni: yds_m11)'],
  [37, 'YDS ys3u5 Ana fikir, ys3u6 Paragraf soruları', '—', 'Okuma (strateji)', 'Yarım deneme 6'],
  [38, 'YDS ys3u7 Diyalog, ys3u8 Restatement (YÖKDİL: çeviri tekrarı)', '—', 'Diyalog, restatement', 'Tam deneme 4 (yeni: yds_m12)'],
  [39, 'YDS ys3u9 Paragraf tamamlama, ys3u10 Anlam bütünlüğü', '—', 'Paragraf tamamlama, anlam bütünlüğü', 'Yarım deneme 7'],
  [40, 'YDS ys3u11 Okuma kampı: fen, ys3u12 sağlık', '—', 'Okuma (zamanlı)', 'Tam deneme 5 (yeni: yds_m13) + Bölüm 3 denemesi'],
  [41, 'YDS ys3u13 Okuma kampı: sosyal, ys3u14 tarih/kültür', '—', 'Okuma (zamanlı)', 'Yarım deneme 8 + okuma kampı denemesi'],
  [42, 'Tekrar haftası: ys3 zayıf soru tipleri', 'zayıf konular', 'Karışık set (tüm tipler)', 'Tam deneme 6 (yeni: yds_m14)'],
  [43, 'YDS ys4u1 Karışık set 1', '—', 'Karışık (tam dağılım)', 'Tam deneme 7 (yeni: yds_m15)'],
  [44, 'YDS ys4u2 Karışık set 2', '—', 'Karışık (tam dağılım)', 'Tam deneme 8 (yds_m1, ys4u2)'],
  [45, 'YDS ys4u3 Süre stratejisi', '—', 'Bölüm süre çalışması', 'Tam deneme 9 (yds_m2, ys4u3)'],
  [46, 'YDS ys4u4 Hata analizi', '—', 'Hata defteri yoğun', 'Tam deneme 10 (yds_m3, ys4u4)'],
  [47, 'YDS ys4u5 Deneme haftası 1: dilbilgisi', '—', 'Zayıf tip (analize göre)', 'Tam deneme 11 (yds_m4, ys4u5)'],
  [48, 'YDS ys4u6 Deneme haftası 2: kelime', '—', 'Zayıf tip', 'Tam deneme 12 (yds_m5, ys4u6) ve 13 (yeni: yds_m16)'],
  [49, 'YDS ys4u7 Deneme haftası 3: çeviri', '—', 'Zayıf tip', 'Tam deneme 14 (yds_m6, ys4u7) ve 15 (yeni: yds_m17)'],
  [50, 'YDS ys4u8 Deneme haftası 4: okuma', '—', 'Zayıf tip', 'Tam deneme 16 (yds_m7, ys4u8) ve 17 (yeni: yds_m18)'],
  [51, 'YDS ys4u9 Deneme haftası 5: son prova', '—', 'Zayıf tip', 'Tam deneme 18 (yds_m8, ys4u9) ve 19 (yeni: yds_m19)'],
  [52, 'Son hafta: yalnızca tekrar ve hata defteri', '—', 'Hafif karışık set', 'Tam deneme 20 (yeni: yds_m20, sınavdan 4–5 gün önce)'],
];

const phaseOf = (w) => phases.find((p) => w >= p.weeks[0] && w <= p.weeks[1]);

// Structured mocks of a week, so the app never has to parse the Turkish `mock` text.
// kind: full (80/180, pack yds_full), half (40/90), section (a path mock node), check (level check, no mock).
// nodeId: the path node that runs it, when it exists; id: the pack mock id.
const sectionMocks = {
  20: [{ kind: 'half', nodeId: 'ys6u6m', size: 40, minutes: 90 }],
  26: [{ kind: 'section', nodeId: 'ys1u10m', size: 20, minutes: 45 }],
  33: [{ kind: 'section', nodeId: 'ys2u15m', size: 30, minutes: 60 }],
  32: [{ kind: 'half', nodeId: 'ys8u10m', size: 40, minutes: 90 }],
  40: [{ kind: 'section', nodeId: 'ys3u10m', size: 40, minutes: 90 }],
  41: [{ kind: 'section', nodeId: 'ys3u14m', size: 32, minutes: 80 }],
};
function mocksFor(week, text) {
  if (!text) return [];
  const out = [];
  for (const m of text.matchAll(/yds_m(\d+)/g)) out.push({ kind: 'full', id: `yds_m${m[1]}`, size: 80, minutes: 180 });
  const listed = sectionMocks[week] ?? [];
  out.push(...listed);
  if (/Yarım deneme/.test(text) && !listed.some((m) => m.kind === 'half')) {
    out.push({ kind: 'half', nodeId: null, size: 40, minutes: 90 });
  }
  if (/Seviye kontrolü/.test(text)) out.push({ kind: 'check', size: 0, minutes: 0 });
  return out;
}

// Path unit ids named in a week's text: "Genel s2 u1–u6" → s2u1..s2u6 (section 1 ids are u1..u12),
// "ys2u7–u9" → ys2u7..ys2u9, "ys1u11" → ys1u11. Review weeks name no units.
function unitIds(text) {
  const ids = [];
  const range = (prefix, a, b) => {
    for (let i = +a; i <= +(b ?? a); i++) ids.push(`${prefix}${i}`);
  };
  for (const m of text.matchAll(/Genel s(\d+) u(\d+)(?:–u(\d+))?/g)) range(m[1] === '1' ? 'u' : `s${m[1]}u`, m[2], m[3]);
  for (const m of text.matchAll(/ys(\d+)u(\d+)(?:–u(\d+))?/g)) range(`ys${m[1]}u`, m[2], m[3]);
  return ids;
}

// Parallel tracks (sections with "parallel": true): Kelime bankası / Okuma evi units per week.
// F1 covers weeks 11–20; later phases extend this map when their sections ship.
const parallel = {};
for (let w = 11; w <= 20; w++) parallel[w] = [`ys5u${w - 10}`];
const okuma = { 12: 'ys6u1', 13: 'ys6u2', 15: 'ys6u3', 16: 'ys6u4', 18: 'ys6u5', 20: 'ys6u6' };
for (const [w, id] of Object.entries(okuma)) parallel[w].push(id);
// F2 (docs/sinav/yds-faz2-icerik.md): ys7 one unit a week (two in week 34), ys8 in weeks 22–32 (its end mock is half mock 5, week 32).
for (let w = 21; w <= 34; w++) parallel[w] = [`ys7u${w - 20}`];
parallel[34].push('ys7u15');
[22, 23, 24, 26, 27, 28, 29, 30, 31, 32].forEach((w, i) => parallel[w].push(`ys8u${i + 1}`));
let total = 0;
let readTotal = 0;
const weeks = W.map(([week, units, grammar, qtype, mock]) => {
  const t = targets(week);
  total += t.newWords;
  readTotal += t.readPerDay * 6;
  return {
    week,
    phase: phaseOf(week).id,
    units,
    unitIds: unitIds(units),
    parallelUnitIds: parallel[week] ?? [],
    grammar,
    questionWork: qtype,
    mock: mock || null,
    mocks: mocksFor(week, mock),
    newWords: t.newWords,
    wordsTotal: total,
    readingWordsPerDay: t.readPerDay,
    intensiveTextsPerDay: t.intensive,
    choicePerDay: t.qPerDay,
  };
});

const fmt = (n) => n.toLocaleString('tr-TR');
let md = '| Hafta | Evre | Yol / ders | Dilbilgisi odağı | Kelime yeni / toplam | Okuma (kelime/gün; yoğun metin/gün) | Soru çalışması (soru/gün) | Deneme |\n';
md += '|---|---|---|---|---|---|---|---|\n';
for (const w of weeks) {
  md += `| ${w.week} | ${w.phase} | ${w.units} | ${w.grammar} | ${w.newWords} / ${fmt(w.wordsTotal)} | ${fmt(w.readingWordsPerDay)}; ${w.intensiveTextsPerDay} | ${w.questionWork}${w.choicePerDay ? ` (${w.choicePerDay})` : ''} | ${w.mock ?? ''} |\n`;
}
md += `\n**Toplam:** ${fmt(total)} yeni kelime ailesi (genel kurs + YDS yolu + kelime bankası), yaklaşık ${fmt(readTotal)} kelime okuma (haftada 6 gün).\n`;

const json = {
  id: 'yds_1_yil',
  title: 'YDS 1 yıllık program',
  doc: 'docs/sinav/yds-1-yil.md',
  daysPerWeek: 6,
  // Standard day (210 min incl. a 10 min break): share of study time per block. docs/sinav/yds-1-yil.md §3.
  blocks: [
    { id: 'review', title: 'Tekrar kartları', share: 0.15 },
    { id: 'lesson', title: 'Yeni ders', share: 0.3 },
    { id: 'reading', title: 'Okuma', share: 0.225 },
    { id: 'questions', title: 'Soru', share: 0.225 },
    { id: 'mistakes', title: 'Hata defteri', share: 0.1 },
  ],
  // Target seconds per question in a real YDS (180 min / 80 questions, ~15 min spare).
  // Reading includes reading the passage. docs/sinav/yds-arastirma.md §2.8.
  targetSeconds: {
    vocabulary: 45,
    grammar: 45,
    cloze: 70,
    sentenceCompletion: 90,
    translation: 120,
    reading: 180,
    dialogue: 100,
    restatement: 100,
    paragraphCompletion: 135,
    irrelevantSentence: 135,
  },
  phases,
  weeks,
  totals: { newWords: total, readingWords: readTotal, fullMocks: 20, halfMocks: 8 },
};

const docPath = path.join(root, 'docs/sinav/yds-1-yil.md');
const doc = fs.readFileSync(docPath, 'utf8');
const a = doc.indexOf('<!-- TABLO:BAŞ -->');
const b = doc.indexOf('<!-- TABLO:SON -->');
if (a < 0 || b < a) throw new Error('TABLO markers missing in ' + docPath);
fs.writeFileSync(docPath, doc.slice(0, a) + '<!-- TABLO:BAŞ -->\n' + md + doc.slice(b));
fs.mkdirSync(path.join(root, 'assets/plans'), { recursive: true });
fs.writeFileSync(path.join(root, 'assets/plans/yds_1_yil.json'), JSON.stringify(json, null, 2) + '\n');
console.log('words', total, 'reading', readTotal);
