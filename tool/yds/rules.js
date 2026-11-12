// Shared exercise rules for the YDS content checkers (check_unit.js, check_reading.js).
// Mirrors test/course_content_test.dart + content_quality_test.dart.
module.exports = (P, problems) => {
  const QTYPES = ['vocabulary', 'grammar', 'cloze', 'sentenceCompletion', 'translation', 'reading', 'dialogue',
    'restatement', 'paragraphCompletion', 'irrelevantSentence'];
  const POS_RE = /(ilk|birinci|ikinci|üçüncü|dördüncü|beşinci|son) (seçene|şık)|\b[A-E] şık|\b[A-E]\) (seçene|şık)/i; // kalite-turu PR #38
  const strCheck = (where, key, s) => {
    if (s !== s.trim()) problems.push(`${where}: baş/son boşluk`);
    if (/[^\s] {2,}[^\s]/.test(s)) problems.push(`${where}: çift boşluk`);
    if ((key === 'guide' ? /�|&nbsp;|<\/?[a-z]+>/ : /�|\*\*|&nbsp;|<\/?[a-z]+>/).test(s)) problems.push(`${where}: yasak işaret (** ya da html)`);
  };
  const walk = (v, where, key = '') => {
    if (typeof v === 'string') strCheck(where, key, v);
    else if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${where}[${i}]`, key));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, `${where}.${k}`, k);
  };

  const article = (q, opts) => {
    const m = /\b([Aa]n?) (?:_{3,}|-{3,})/.exec(q);
    if (!m) return false;
    return new Set(opts.map((o) => /^[aeiouAEIOU]/.test(o.trim()))).size > 1;
  };
  const norm = (s) => s.replace(/İ/g, 'i').toLowerCase().replace(/’/g, "'").replace(/[.,!?;:¿¡"]/g, ' ').replace(/\s+/g, ' ').trim();
  const buildable = (a, toks) => {
    const bank = {};
    toks.forEach((t) => norm(t).split(' ').filter(Boolean).forEach((w) => { bank[w] = (bank[w] || 0) + 1; }));
    for (const w of norm(a).split(' ').filter(Boolean)) { if (!bank[w]) return false; bank[w]--; }
    return true;
  };

  function exercise(e, at) {
    const str = (v) => typeof v === 'string' && v.trim();
    switch (e.type) {
      case 'choice': {
        P(str(e.question), `${at}: question yok`);
        P(Array.isArray(e.options) && e.options.length === 5, `${at}: 5 şık olmalı`);
        P(new Set((e.options || []).map((o) => o.trim().toLowerCase())).size === (e.options || []).length, `${at}: aynı şık`);
        P(Number.isInteger(e.answer) && e.answer >= 0 && e.answer < 5, `${at}: answer 0–4`);
        P(str(e.explanation) && /[çğıöşüÇĞİÖŞÜ]/.test(e.explanation), `${at}: Türkçe açıklama yok`);
        P(!POS_RE.test((e.explanation || '').replace(/İ/g, 'i')),`${at}: açıklama şıkkı konumla anıyor`);
        P(!/\b[A-E]\)|şık [A-E]\b|\([A-E]\)/.test(e.explanation || ''), `${at}: açıklama harf ile anıyor`);
        P(!article(e.question || '', e.options || []), `${at}: a/an ipucu`);
        P(!('passage' in e) || str(e.passage), `${at}: passage boş`);
        P(QTYPES.includes(e.qtype), `${at}: qtype yok ya da geçersiz (${e.qtype})`);
        if (/\(\d\)-{4}/.test(e.passage || '')) P(e.qtype === 'cloze', `${at}: numaralı boşluklu paragraf → qtype cloze`);
        if (e.explanation && e.options) {
          P(e.explanation.toLowerCase().includes(e.options[e.answer].toLowerCase().slice(0, 40)) || /[“‘'"]/.test(e.explanation),
            `${at}: açıklama doğru şıkkı metniyle anmıyor`);
        }
        break;
      }
      case 'match': {
        P(Array.isArray(e.pairs) && e.pairs.length >= 3 && e.pairs.every((p) => p.length === 2 && str(p[0]) && str(p[1])), `${at}: pairs`);
        const L = new Set(e.pairs.map((p) => norm(p[0]))), R = new Set(e.pairs.map((p) => norm(p[1])));
        P(L.size === e.pairs.length && R.size === e.pairs.length, `${at}: çiftler benzersiz değil`);
        // Match tiles are one line high (lib/exercises/match_exercise.dart, height 28): longer text is cut off.
        for (const p of e.pairs) P(p[0].length <= 18 && p[1].length <= 18, `${at}: eşleştirme metni 18 karakteri aşıyor: ${p.join(' / ')}`);
        break;
      }
      case 'fillBlank': {
        P(str(e.text) && (e.text.match(/___/g) || []).length === 1, `${at}: tek ___ olmalı`);
        P(str(e.translation), `${at}: translation yok`);
        P(Array.isArray(e.choices) && e.choices.length >= 2 && e.choices.includes(e.answer), `${at}: choices/answer`);
        P(new Set((e.choices || []).map((c) => c.toLowerCase())).size === (e.choices || []).length, `${at}: aynı seçenek`);
        P(!article(e.text || '', e.choices || []), `${at}: a/an ipucu`);
        break;
      }
      case 'translate': {
        P(str(e.text) && (e.lang === 'tr' || e.lang === 'en'), `${at}: text/lang`);
        P(Array.isArray(e.answers) && e.answers.length && Array.isArray(e.tokens), `${at}: answers/tokens`);
        P((e.answers || []).some((a) => buildable(a, e.tokens || [])), `${at}: cevap token'larla kurulamıyor`);
        P(new Set((e.answers || []).map(norm)).size === (e.answers || []).length, `${at}: aynı cevap iki kez`);
        break;
      }
      default:
        problems.push(`${at}: beklenmeyen tür ${e.type}`);
    }
  }

  return { QTYPES, walk, exercise, article, norm, buildable };
};
