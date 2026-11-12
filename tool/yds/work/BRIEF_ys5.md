# Brief: ys5 "Kelime bankası 1" unit writer

You write ONE (or two) units of a new YDS section for Dilbaz, a Turkish-speaking learners' English app.
Learner: finished A1–A2 general course, now A2→B1, preparing for YDS (Turkish academic English exam).
All content must be ORIGINAL (no copied dictionary examples, no ÖSYM questions). Turkish text uses proper
Turkish characters (ç ğ ı ö ş ü İ). English uses British spelling (behaviour, analyse) consistently.

## Inputs
- Word list per unit: `tool/yds/work/words.json` (80 items for your unit; phrases contain spaces).
  Earlier units' words are in the same file (needed for the test's mixed questions).
- Format examples: `assets/courses/exam_yds.json` (unit ys1u11: guide + vocab lesson), cloze format in
  `assets/courses/exam_yds/03_soru_tipleri.json` (unit ys3u1, passages with `(1)----`).

## Output files (write with the Write tool, UTF-8 JSON, no BOM)
1. `tool/yds/work/<unitId>.json` – the unit object:
```
{"id":"ys5u3","title":"…","description":"…","color":"0xFF……","theme":"<theme id>","guide":"…markdown…","nodes":[
  {"id":"ys5u3l1","type":"lesson","title":"Kelimeler 1: …","description":"…","vocab":true,"exercises":[…]},
  {"id":"ys5u3l2",… vocab:true},{"id":"ys5u3l3",… vocab:true},
  {"id":"ys5u3l4","type":"lesson","title":"Bağlamda","description":"…","exercises":[…]},
  {"id":"ys5u3t","type":"test","title":"Ünite testi","description":"15 soruluk ünite testi; geçmek için %80 doğru yap","rewardXp":25,"exercises":[15 choice]},
  {"id":"ys5u3c","type":"chest","title":"Ünite ödülü","description":"Üniteyi bitir, bonus XP kazan","rewardXp":20}
]}
```
   ys5u10 only: after the chest add
   `{"id":"ys5u10m","type":"mock","title":"Kelime bankası 1 denemesi","description":"Bölümün 800 kelimesinden 30 soru, 35 dakika","examId":"yds","size":30,"minutes":35}`.
2. `tool/yds/work/<unitId>.cards.json` – array of exactly 80 vocab cards, one per word, in word-list order:
```
{"id":"yd_carry_out","word":"carry out","pos":"phrasal verb","topic":"ys5u10",
 "senses":[{"tr":"yürütmek, gerçekleştirmek","def":"to do a piece of work, research or a task"}],
 "examples":[{"en":"The team carried out a survey of 500 farmers.","tr":"Ekip 500 çiftçiyle bir anket yürüttü.","context":"genel","target":"carried out"}],
 "collocations":[{"phrase":"carry out research","answer":"carry out","tr":"araştırma yapmak"}],
 "family":["…"], "synonym":"conduct", "tip":"Türkçe ipucu (isteğe bağlı ama en az yarısında olsun)"}
```
   - id = "yd_" + word with spaces → "_". `target` must appear verbatim in `en`; collocation `answer` verbatim in `phrase`.
   - pos: noun / verb / adjective / adverb / phrasal verb / linking phrase / preposition. `family` (array of
     related forms, e.g. ["analysis (n)","analytical (adj)"]) required for verbs and nouns; use [] if none.
   - Example sentences: 10–20 words, B1, YDS-like topics (science, health, society, economy), natural Turkish translation.
   - context: "genel" | "akademik" | "haber".

## Exercise rules (the checker enforces these)
- Lessons 1–3 (vocab:true): ~27 of the unit's words each, in word-list order (l1 words 1–27, l2 28–54, l3 55–80).
  10–12 exercises each: ≥2 `match` with EXACTLY 5 pairs `[["Türkçe","english"],…]` (pairs introduce the
  words; aim for 3 matches = 15 words), ≥3 `fillBlank`, ≥4 `choice`, 1–2 `translate` (lang "tr").
  - `fillBlank`: `{"type":"fillBlank","text":"English sentence with one ___ blank.","translation":"Türkçe çeviri.","answer":"word","choices":["word","x","y"]}`
  - `translate`: `{"type":"translate","text":"Türkçe cümle.","lang":"tr","answers":["English answer.","Alternative answer"],"tokens":[every word of the first answer + 3–4 distractor words]}`
    Short (6–10 words). The first answer must be buildable from tokens (punctuation ignored, case-insensitive).
  - `choice` (YDS vocabulary type, B1): `{"type":"choice","question":"Sentence with ---- blank.","options":[5 distinct],"answer":<0-4>,"explanation":"Türkçe…"}`
- Lesson 4 "Bağlamda": 10–12 exercises. TWO original cloze paragraphs, 80–120 words each, blanks `(1)----`…
  each with 3–4 `choice` questions (`"passage"` = the full paragraph text, identical across its questions;
  `"question":"(1) numaralı boşluk için en uygun kelimeyi seçin."`). The two paragraphs together must use
  at least 15 of the unit's words (in the running text, not only in the blanks). Rest: mixed choice/fillBlank.
- Test: exactly 15 `choice`: 10 vocabulary, 3 sentence completion (B1; options are clauses), 2 short-paragraph
  questions (a 50–80 word paragraph in `passage`, question e.g. "Parçaya göre … ?" or a blank in it).
  At least 4 test questions use words from EARLIER units of ys5 (ys5u1 has none: skip that rule).
- Every `choice` carries `"qtype"`: "vocabulary" (word questions), "cloze" (lesson-4 `(1)----` paragraph
  blanks), "sentenceCompletion" (options are clauses), "reading" (comprehension of a short paragraph).
- Every `choice`: 5 options, one clearly right answer; Turkish `explanation` that names the right option by its
  TEXT in quotes (‘…’) and says briefly why 1–2 distractors fail. NEVER refer to options by position
  ("ilk şık", "son seçenek", "A şıkkı" …). Spread correct answers evenly over indexes 0–4 (each ≈20%).
- No a/an giveaway: never write "a ----" / "an ----" / "a ___" unless all options start with the same
  vowel/consonant class. Prefer "the ----" or put the article inside the options.
- No duplicate options (case-insensitive) and no duplicate questions. No `**` outside `guide`. No double spaces,
  no leading/trailing spaces in any string.
- COVERAGE: every one of your 80 words must appear in English context (a question sentence, a fillBlank
  sentence, a translate answer, or a paragraph — options/match pairs don't count) AT LEAST TWICE inside
  the unit. Pack several unit words into each sentence/paragraph to achieve this. Inflected forms count.
- Difficulty rises inside the unit: l1 easiest, test hardest (still B1).

Words are chosen by frequency (NGSL 1000–3000, untaught so far), so the core words of the theme (e.g.
increase/reduce, evidence) were already taught in ys1–ys4; the guide says in one line that this unit is the
next layer after them.

## Guide (≤ 250 words, markdown: `## Başlık`, `- madde`, `**kalın**`, `*italik*`)
Sections: `## Kelime aileleri` (4–6 families from the unit, e.g. *analyse → analysis → analytical*),
`## Türklerin sık yaptığı 3 hata` (3 concrete mistakes: make/do, say/tell, preposition collocations, false
friends… tied to this unit's words), `## Nasıl çalışmalı` (cards + context: learn each word with its
collocation and example, review the cards in the Kelime kartları screen on days 1, 3, 7; say/write one own
sentence — explain briefly WHY: retrieval practice and spaced repetition).

## Self-check (mandatory)
Run `node tool/yds/check_unit.js <unitId>` from `D:\Lingora-wt\yds-icerik` and fix until it prints TAMAM
(warnings marked `!` are OK). Then INDEPENDENTLY re-solve every choice question yourself without looking at
`answer` and confirm exactly one option is correct; fix ambiguous items. Do not edit any other file.
Report: unit id, counts (exercises, choice, contexts), checker result, and any judgement calls.
