# Brief: full mock writers, YDS Faz 4c (yds_m15–yds_m20, yokdil_m1–yokdil_m3)

Spec: `docs/sinav/yds-faz4-icerik.md` § F4c. If the file is not on disk yet, read it from the branch:
`git show origin/feature/yds-arastirma-f4:docs/sinav/yds-faz4-icerik.md`.

First read `tool/yds/work/BRIEF_mock.md`. Its format, quality rules and self-check apply to you, except where
this brief says otherwise. It also points you to BRIEF_ys5.md § Exercise rules.

## YDS mocks: `yds_m15` … `yds_m20`
- Layout, ids and question order: as in BRIEF_mock.md (80 questions, same section order as yds_m1–m14).
- Title: "Tam Deneme N". **yds_m20** is titled "Tam Deneme 20 · Son prova".
- Difficulty:
  - m15–m18: real-exam level.
  - **m19–m20: one notch above.** Longer sentences, denser reading, reading texts of 280–380 words, more
    nominalisation, and subtler distractors. Never ambiguous.

## YÖKDİL mocks: `yokdil_m1` (fen), `yokdil_m2` (saglik), `yokdil_m3` (sosyal)
- File: `{"id":"yokdil_m1","title":"YÖKDİL Fen denemesi 1","field":"fen","textFields":[7 fields],"minutes":180,"questions":[80]}`.
- Titles:

  | Id | Title |
  |---|---|
  | yokdil_m1 | "YÖKDİL Fen denemesi 1" |
  | yokdil_m2 | "YÖKDİL Sağlık denemesi 1" |
  | yokdil_m3 | "YÖKDİL Sosyal denemesi 1" |

- Order and counts. Ids `<id>_q01` … `_q80`; sections `yokdil_*`; qtypes are the existing ones.

  | Section | Count | qtype |
  |---|---|---|
  | `yokdil_vocab` | 6 | vocabulary |
  | `yokdil_grammar` | 14 | grammar |
  | `yokdil_cloze` | 10 = 2 texts × 5 | cloze |
  | `yokdil_completion` | 11 | sentenceCompletion |
  | `yokdil_translation` | 12 = 6 EN→TR then 6 TR→EN | translation |
  | `yokdil_reading` | 15 = 5 texts × 3, 250–350 words each | reading |
  | `yokdil_paragraph` | 6 | paragraphCompletion |
  | `yokdil_irrelevant` | 6 | irrelevantSentence |

  **No dialogue and no restatement.**
- **Field weighting:**
  - YÖKDİL is a field exam: vocabulary, sentences and texts are academic texts of the mock's field.
  - `textFields` lists the field of the 2 cloze texts and the 5 reading texts, in order.
  - At least 5 of the 7 must be the mock's own field.
  - Paragraph, irrelevant-sentence and translation items should also mostly come from the field (≥ 70 %).
- Level: real YÖKDİL. Term-dense academic prose, long sentences, frequent passives and nominalisations.

## For every writer
- **Answers:** 16 per index, or as close as 80 allows.
- **Explanations:** Turkish. Name the right option and at least 3 wrong ones by their text, never by position.
- **Fresh topics,** short items included. The app now has many texts: every reading section, ys9–ys11,
  Bol okuma 1–2 and the mocks m1–m14.
  - Grep `assets/` and `tool/yds/work/` for a topic's key words before using it.
  - The checker rejects passages that overlap strongly.
  - Also run `WORDFREQ=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/wordfreq/en.tsv node tool/yds/topic_scan.js <your id> <every other F4c id that exists in tool/yds/work/>`
    until it prints "temiz".
  - Stay in the topic area your task gives you, so you don't collide with the other writers.
- **Facts:** true and hedged. No invented named studies.

## Self-check
- Run `node tool/yds/check_mock.js <id>` until it prints TAMAM.
- Run topic_scan until it prints "temiz".
- Re-solve all 80 without looking at `answer`, and fix any item with two defensible options.
- Write only `tool/yds/work/<id>.json`. Helper scripts go in your scratchpad subfolder.
- Report: the topic of each passage, the checker line, and your judgement calls.
