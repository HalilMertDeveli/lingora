# Brief: full YDS mock writer (yds_m9 / yds_m10, YDS Faz 2c)

Write ONE complete, original 80-question YDS mock for `assets/exam_packs/yds_full.json`. Spec:
`docs/sinav/yds-faz2-icerik.md` § F2c. Difficulty = the average of the existing mocks yds_m1–yds_m8 (real YDS).

## Read first
- `assets/exam_packs/yds_full.json`, mocks `yds_m1` and `yds_m5`: copy their FORMAT exactly — question wording
  per section, how cloze blanks are written ("(1) ----"), how dialogues / restatement / paragraph completion /
  irrelevant-sentence items are laid out (options, roman numerals, passage vs text). Never copy their content.
- `tool/yds/work/BRIEF_ys5.md` § Exercise rules: 5 distinct options, Turkish explanation (> 40 chars) naming the
  right option AND ≥ 3 wrong ones by their text in ‘…’, never by position or letter; no a/an giveaway; no `**`.

## Output: `tool/yds/work/<id>.json`
`{"id":"yds_m9","title":"Tam Deneme 9","minutes":180,"questions":[80 items]}`, each item
`{"id":"yds_m9_q01","section":"yds_vocab","qtype":"vocabulary","text":"…","options":[5],"answer":0-4,"explanation":"…"}`
plus `"passage"` for cloze/reading items (identical string within a passage). Order and counts (ids q01…q80):
vocab 6 (vocabulary) · grammar 10 (grammar) · cloze 10 = 2 texts × 5 (cloze) · completion 10 (sentenceCompletion) ·
translation 6 = 3 EN→TR + 3 TR→EN (translation) · reading 20 = 5 texts × 4, 250–330 words each (reading) ·
dialogue 6 (dialogue) · restatement 3 (restatement) · paragraph 4 (paragraphCompletion) · irrelevant 5 (irrelevantSentence).

## Quality rules
- All texts new: science, health, social science, history, technology, as in YDS. The checker rejects any
  passage whose vocabulary overlaps strongly with a passage already in the app (reading sections, mocks
  m1–m8, extensive reading, the other new mock) — pick fresh topics.
- Use the academic word banks (`tool/yds/work/words.json`, `words_ys7.json`) generously.
- Irrelevant-sentence items: the odd sentence stays on the SAME topic but a different aspect (no topic jump).
- Grammar items on structure / main verb use verb-like distractors.
- Reading: per text main idea or title, detail, inference, and attitude/purpose or reference or word in context.
- Facts true and hedged. Correct answers spread ≈ 16 per index (checker: each index 12–30%).

## Self-check
`node tool/yds/check_mock.js <id>` until TAMAM, then re-solve all 80 without looking at `answer` and fix any
item with two defensible options. Write only your output file; helper scripts in your scratchpad subfolder.
Report: topics per passage, judgement calls.
