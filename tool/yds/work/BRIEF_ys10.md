# Brief: ys10 "Okuma evi 3" writers (YDS Faz 3b)

Spec: `docs/sinav/yds-faz3-icerik.md` § F3b. ys10 follows ys8 (`tool/yds/work/BRIEF_ys8.md`, which builds on
`BRIEF_ys6.md` and `BRIEF_ys5.md` § Exercise rules); read those three first. The differences are below.
Model a finished unit on `assets/courses/exam_yds/08_okuma_evi_2.json` (any unit). Never copy its content.

## Unit writers: output `tool/yds/work/ys10uN.json`
Same shape as a ys8 unit: `{id,title,description,color,theme,guide,nodes:[l1,l2,l3,l4,t,c]}`. No mock node
(mocks are added at build time).

### Texts (the checker enforces every rule)
- Real YÖKDİL field-text level, B2. **280–340 words** per text (6 lesson texts and 2 test texts).
- Average sentence **23–27 words**. Term density rises: per text ≥ 3 passives, ≥ 2 relative clauses,
  ≥ 3 nominalisations.
- Unknown words ≤ 5%. "Known" = the general course, the whole YDS path including ys9, and NGSL 1–1000.
- Recycling: **≥ 10 ys9 words** (`tool/yds/work/words_ys9.json`) and **≥ 5 ys7 words**
  (`tool/yds/work/words_ys7.json`) per text. Inflected forms count.
- Each text lesson's `reading` = `{"field": …, "words": <sum of both texts>, "cefr": "B2", "ys9": [...], "ys7": [...]}`.
- Fields:

  | Units | Field |
  |---|---|
  | u1–u2 | `fen` |
  | u3–u4 | `saglik` |
  | u5–u6 | `sosyal` |
  | u7–u8 | mixed, one text per field across the lessons |

- **New topics only.** The checker rejects any text whose vocabulary overlaps strongly with a passage in the
  app or another ys10 unit.
  - Before writing, grep `assets/` and `tool/yds/work/` for a topic's key words and pick another if found.
  - Then run `WORDFREQ=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/wordfreq/en.tsv node tool/yds/topic_scan.js ys10uN`.
    It must print "temiz".
- Facts must be true and hedged ("about", "more than", "some studies suggest"). No invented statistics
  presented as real findings.
  - For clinical or risk texts, describe study designs generically ("a trial of about 2,000 adults"),
    or use well-established facts.
- Draft check: `NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_reading.js --text "<text>" --sec ys10`

### Questions per text: 4, all carrying the text as `passage`
1. ≥ 1 `reading` inference or attitude/purpose question. The stem must say so: "It can be inferred…",
   "The author's attitude…", "The main purpose…".
2. ≥ 1 passage-level `paragraphCompletion` or `irrelevantSentence` item (stems in English):
   - `paragraphCompletion`: "Which of the following sentences would best follow the last sentence of the
     passage?" or "…best be inserted after the sentence ending '…'?" The 4 wrong options must be plausible
     topic sentences that break the logic: a wrong connector, a contradiction, or a jump in focus.
   - `irrelevantSentence`: "Which of the following sentences, if added to the passage's second paragraph,
     would be irrelevant?" Four options fit the paragraph; one stays on the SAME topic but shifts to a
     different aspect. No topic jump.
3. The remaining questions are `reading` (main idea or title, detail, reference, word in context).

Lessons l1–l3 each have 2 texts × 4 questions, plus 2 vocabulary items on ys9 words met in the texts
(10 exercises in all).

### Lesson 4 "Cümle çözümleme" (8–10 grammar/translation, ≥ 3 translation)
- Long YÖKDİL-style sentences from the unit's field.
- "ana fiil" items need verb-like distractors.
- Translation options differ in tense, voice, negation, quantifier and hedge.
- In u7, l4 has ≥ 6 translation items, both EN→TR and TR→EN.

### Test
- 2 new texts × 4 questions, under the same rules: ≥ 1 inference/attitude and ≥ 1 paragraph item per text.
- Plus 7 sentence-level items: 4 translation and 3 sentenceCompletion.
- `rewardXp` 25, description "2 yeni metin ve 7 cümle sorusu; …".

### Guide (≤ 250 words, sections `## Strateji`, `## Nasıl uygulanır`, `## Örnek`, `## Sınav ipucu`)
The unit's texts must suit its strategy:

| Unit | Strategy |
|---|---|
| u1 | Main idea in a term-dense text: skip unknown terms and find the claim |
| u2 | Experiment report: hypothesis, method, result, limitation |
| u3 | Clinical study summary: participants, intervention, outcome, caveat |
| u4 | Risk and ratio expressions: relative vs absolute risk, "twice as likely", "per 1,000" |
| u5 | Theory comparison: two views, where they differ, the author's position |
| u6 | Historical narrative: chronology and cause |
| u7 | YÖKDİL-style long-sentence translation: find the core, then the modifiers |
| u8 | Timed, 10 minutes per text, mixed fields |

### Self-check
- Run `node tool/yds/check_reading.js ys10uN` with the NGSL prefix until it prints TAMAM.
- Run topic_scan until it prints "temiz".
- Re-solve every choice without looking at `answer`; fix any item with two defensible options.
- Write only your unit file. Helper scripts go in your scratchpad subfolder.

## Half-mock writers: output `tool/yds/work/ys10u3m.json` | `ys10u5m.json` | `ys10u7m.json`
- File shape: `{"exercises":[40 choice]}`. Real YDS level (B2). Follow the format of the existing half mock
  `tool/yds/work/ys8m.json` (read it, and never copy it).
- Exact distribution:

  | Type | Count |
  |---|---|
  | vocabulary | 3 |
  | grammar | 5 |
  | cloze | 5 (1 text) |
  | sentenceCompletion | 5 |
  | translation | 3 |
  | reading | 8 (2 texts × 4, 250–340 words) |
  | dialogue | 3 |
  | restatement | 2 |
  | paragraphCompletion | 2 |
  | irrelevantSentence | 4 |

- Correct answers 8 per index.
- All topics new, in short items too: grep first, then run topic_scan as above, with all three half-mock ids.
- Check: `node tool/yds/check_reading.js ys10u3m` until TAMAM. Then re-solve all 40 blind.
