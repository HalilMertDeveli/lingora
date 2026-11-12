# Brief: ys12 "Kelime bankası 4" unit writer (YDS Faz 4a)

Read `tool/yds/work/BRIEF_ys9.md` first, and the BRIEF_ys5 and BRIEF_ys7 files it points to. ys12 follows
ys9 exactly (4 vocab lessons + Bağlamda + test + chest, card format, exercise rules) with the differences
below. Spec: `docs/sinav/yds-faz4-icerik.md` § F4a. If it is not on disk, read it with
`git show origin/feature/yds-arastirma-f4:docs/sinav/yds-faz4-icerik.md`.

## Differences from ys9
- **Level:** B2–C1, the register of the last weeks before the exam. The word list is
  `tool/yds/work/words_ys12.json` (112–113 per unit).
- **Vocab lessons:** l1 has words 1–28, l2 has 29–56, l3 has 57–84, and l4 has 85 to the end.
- **l5 "Bağlamda":** two cloze paragraphs of **150–190 words** (B2–C1, YÖKDİL-like), 3–4 blanks each, using at
  least 15 unit words.
- **Node ids:** `<unit>l1` … `<unit>l5`, `<unit>t`, `<unit>c`. After the chest of ys12u8 comes
  `{"id":"ys12u8m","type":"mock","title":"Kelime bankası 4 denemesi","description":"Bölümün 900 kelimesinden 30 soru, 35 dakika","examId":"yds","size":30,"minutes":35}`.
- **Test:** 15 choice items (10 vocabulary, 3 sentenceCompletion, 2 reading).
  - At least 4 vocabulary items at real YDS difficulty or slightly above.
  - At least 4 items use words from earlier ys12 units. ys12u1 uses ys9 words instead
    (`tool/yds/work/words_ys9.json`).
- **Guide (≤ 250 words):** the "next layer" line says these words follow Kelime bankası 1–3. Theme notes:
  - **u3 (change adverbs):** show how adverbs like these change the meaning of a sentence-completion option.
  - **u7 (advanced collocations):** for each phrase, its fixed parts and a typical YDS context; warn about
    near-miss distractors ("bear the brunt" vs "take the brunt").
  - **u8 (confusable families):** contrast each pair with one example each and a memory tip. The partner word
    may be an earlier card; the new card is the list word.
- **Cards:**
  - id `yd_<word>` (spaces become `_`), topic = unit id.
  - Examples 12–24 words, context "akademik" or "haber".
  - Family for verbs and nouns where it is real.
- **Coverage:** every unit word appears in English context at least twice inside the unit.

## Self-check
- Run `node tool/yds/check_unit.js <unitId>` until it prints TAMAM.
- Re-solve every choice without looking at `answer`.
- Write only `tool/yds/work/<unitId>.json` and `<unitId>.cards.json`. Helper scripts go in your scratchpad
  subfolder.
