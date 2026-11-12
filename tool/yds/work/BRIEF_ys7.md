# Brief: ys7 "Kelime bankası 2" unit writer (YDS Faz 2a)

Read `tool/yds/work/BRIEF_ys5.md` first: ys7 follows it exactly (unit shape, card format, exercise rules,
qtype, guide sections, self-check) with the differences below. Spec: `docs/sinav/yds-faz2-icerik.md` §F2a.

## Differences from ys5
- Learner level B1+ → B2 (academic). Sentences are longer and more academic than ys5 but stay clear;
  use science, health, society, economy, law, history topics, as in YDS texts.
- Word list: `tool/yds/work/words_ys7.json` (80 per unit). Earlier units for the test's mixed questions are the
  earlier ys7 units; ys7u1 mixes in ys5 words instead (`tool/yds/work/words.json`, any unit).
- Lesson 4 "Bağlamda": two cloze paragraphs of **120–160 words**, B2, 3–4 blanks each, using ≥ 15 unit words.
- Test (15 choice): 10 vocabulary + 3 sentenceCompletion + 2 reading as in ys5, and **at least 3 of the
  vocabulary items are real-exam YDS vocabulary questions**: one academic sentence, 5 academic options of the
  same part of speech, real YDS difficulty (put `"qtype":"vocabulary"`; these are the hardest of the unit).
- Every choice explanation names the right option AND why ≥ 3 of the 4 wrong options are wrong, each by its
  text in ‘…’ (checker rule). One short phrase per wrong option.
- Match pairs: keep glosses short (one meaning).
- Guide: the "next layer" line says these are the academic words that follow ys5 (Kelime bankası 1).
  ys7u13 (isimleştirme) guide explains -tion/-ment/-ity/-ance/-ence/-al noun families and why YDS
  sentences prefer nouns ("the introduction of the policy led to…"); its exercises practise verb ↔ noun.
  ys7u14 (temkin ve tutum) explains hedging (may, tend to, arguably, it is suggested that) and how it
  changes the strength of a claim — a frequent restatement/reading trap.
- Last unit ys7u15: after the chest add
  `{"id":"ys7u15m","type":"mock","title":"Kelime bankası 2 denemesi","description":"Bölümün 1.200 kelimesinden 30 soru, 35 dakika","examId":"yds","size":30,"minutes":35}`.
- Cards: id `yd_<word>` (spaces → `_`), `topic` = unit id; examples 12–22 words, academic context
  ("akademik" or "haber"); `family` for verbs/nouns wherever a real family exists (format "word (pos)").

## Self-check
`node tool/yds/check_unit.js <unitId>` until TAMAM (it knows ys7: list, 120–160 cloze, overlap with
general course s1–s8, ys1–ys5 and ys5 cards). Then re-solve every choice without looking at `answer`.
Do not edit other files; helper scripts in your own scratchpad subfolder.
