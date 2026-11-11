// One-off: adds `"theme": "<id>"` after each unit's "color" line.
import fs from 'node:fs';
const map = {
  'assets/courses/tr_en.json': 'cay yemek aile zaman alisveris gunluk aile seyahat gecmis saglik hava hayaller',
  'assets/courses/tr_en/02_gunluk_hayat.json': 'gunluk is cay sanat aile cay sehir sehir spor yemek zaman seyahat',
  'assets/courses/tr_en/03_kendini_anlatmak.json': 'gecmis gecmis doga seyahat dedektif zaman duygular spor alisveris hayaller olasilik hayaller',
  'assets/courses/tr_en/04_sehirde_ve_iste.json': 'aile seyahat zaman is is alisveris hava spor cay yazisma teknoloji sehir',
  'assets/courses/tr_en/05_deneyimler.json': 'zaman tamir gecmis doga kutuphane olasilik haber gunluk dedektif seyahat mulakat duygular',
  'assets/courses/tr_en/06_fikirler_ve_hikayeler.json': 'gecmis kutuphane dedektif haber duygular hayaller duygular cay duygular toplanti toplanti sanat',
  'assets/courses/tr_en/07_is_ve_tartisma.json': 'olasilik olasilik dedektif haber toplanti yazisma tamir sahne is toplanti alisveris haber',
  'assets/courses/tr_en/08_akicilik.json': 'cay yazisma toplanti sahne sahne is toplanti dedektif yazisma kutuphane',
  'assets/courses/pro_interview.json': 'mulakat mulakat mulakat mulakat',
  'assets/courses/pro_tourism.json': 'otel otel yemek seyahat otel',
};
for (const [f, list] of Object.entries(map)) {
  const themes = list.split(' ');
  let s = fs.readFileSync(f, 'utf8');
  if (s.includes('"theme"')) continue;
  let i = 0;
  s = s.replace(/^([ \t]*)"color": "0x[0-9A-Fa-f]+",\r?\n/gm, (m, ind) => {
    const nl = m.endsWith('\r\n') ? '\r\n' : '\n';
    return `${m}${ind}"theme": "${themes[i++]}",${nl}`;
  });
  if (i !== themes.length) throw new Error(`${f}: ${i} units, ${themes.length} themes`);
  fs.writeFileSync(f, s);
}
