# Brief: ys9 "Kelime bankası 3" unit writer (YDS Faz 3a)

Read `tool/yds/work/BRIEF_ys5.md` and `tool/yds/work/BRIEF_ys7.md` first: ys9 follows them (card format,
exercise rules, qtype, ≥ 3 wrong options named in every explanation, guide sections, self-check) with the
differences below. Spec: `docs/sinav/yds-faz3-icerik.md` § F3a.

## Differences
- Level B2, YDS/YÖKDİL register. Word list: `tool/yds/work/words_ys9.json` (108–109 per unit).
- **Four vocab lessons** (vocab:true) instead of three: l1 words 1–27, l2 28–54, l3 55–81, l4 82–end, each
  10–12 exercises (≥ 2 match × 5 pairs, ≥ 3 fillBlank, ≥ 4 choice, 1–2 translate).
- **l5 "Bağlamda"**: two cloze paragraphs of **140–180 words** (B2, YÖKDİL-like), 3–4 blanks each, using
  ≥ 15 unit words; the rest mixed choice/fillBlank (10–12 exercises).
- Node ids: `<unit>l1` … `<unit>l5`, `<unit>t`, `<unit>c` (+ `ys9u12m` after the chest of ys9u12:
  `{"id":"ys9u12m","type":"mock","title":"Kelime bankası 3 denemesi","description":"Bölümün 1.300 kelimesinden 30 soru, 35 dakika","examId":"yds","size":30,"minutes":35}`).
- Test: 15 choice (10 vocabulary, 3 sentenceCompletion, 2 reading); ≥ 3 vocabulary items at real YDS
  difficulty; ≥ 4 items use words from earlier ys9 units (ys9u1 uses ys7 words instead).
- Coverage: every unit word appears in English context at least twice inside the unit.
- Guide (≤ 250 words): the "next layer" line says these follow Kelime bankası 1–2. Theme notes:
  u10 (attitude adjectives) explains how such words signal the author's attitude in reading questions;
  u11 (transitions II) shows how they drive paragraph-completion and irrelevant-sentence items;
  u12 (confusable pairs) contrasts each pair with one example each and a memory tip.
- Cards: id `yd_<word>` (spaces → `_`), topic = unit id; examples 12–22 words, "akademik"/"haber";
  family for verbs and nouns where real.

## Self-check
`node tool/yds/check_unit.js <unitId>` until TAMAM; re-solve every choice without looking at `answer`.
Write only `tool/yds/work/<unitId>.json` and `<unitId>.cards.json`; helper scripts in your scratchpad subfolder.
