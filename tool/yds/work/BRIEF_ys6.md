# Brief: ys6 "Okuma evi 1" unit writer

You write ONE or TWO units of a new YDS reading section for Dilbaz (English app for Turkish speakers).
Learner: finished the general course A1–A2 and is now A2→B1, doing the ys5 word bank in parallel
(800 words: `assets/vocab/yds.json`, unit lists in `tool/yds/work/words.json`). Goal: intensive reading of
YDS-like texts (science news, health, history, society, environment, technology, biography).
Everything ORIGINAL: no copied articles, no ÖSYM questions. Facts must be true and uncontroversial — keep
numbers round and hedged ("about", "more than") unless you are certain. Turkish uses proper characters.
British spelling. Read first: `tool/yds/work/BRIEF_ys5.md` § "Exercise rules" for general choice/match/fillBlank
rules (5 options, Turkish explanation naming the right option by its text in ‘…’, never by position or letter,
no a/an giveaway, no `**` outside guide, no double/leading/trailing spaces, match sides ≤ 18 characters).

## Output: `tool/yds/work/<unitId>.json`
```
{"id":"ys6u2","title":"…","description":"…","color":"0xFF……","theme":"…","guide":"…markdown…","nodes":[
 {"id":"ys6u2l1","type":"lesson","title":"Fen: <kısa başlık>","description":"Metin 1: … Metin 2: … ys5 kelimeleri: a, b, c, …",
  "reading":{"field":"fen","words":<sum of both texts' word counts>,"cefr":"A2+"|"B1"},"exercises":[10]},
 {"id":"ys6u2l2", … "field":"saglik" …}, {"id":"ys6u2l3", … "field":"sosyal" …},
 {"id":"ys6u2l4","type":"lesson","title":"Cümle çözümleme","description":"…","exercises":[8–10 choice]},
 {"id":"ys6u2t","type":"test","title":"Ünite testi","description":"2 yeni metin ve 7 cümle sorusu; geçmek için %80 doğru yap","rewardXp":25,"exercises":[15 choice]},
 {"id":"ys6u2c","type":"chest","title":"Ünite ödülü","description":"Üniteyi bitir, bonus XP kazan","rewardXp":20}]}
```
cefr: ys6u1–u2 "A2+", ys6u3–u6 "B1".

## Texts (the checker measures all of this)
- Length: ys6u1–u2 150–220 words; ys6u3–u6 200–350 words. Lesson texts AND the 2 test texts.
- Unknown words ≤ 5%: words outside the general course, the old YDS path, ys5 and very common words
  (proper nouns don't count). Check each draft:
  `NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_reading.js --text "<text>"`
  It prints unknown words, ys5 words used, passives, relative clauses. Replace or explain unknown words
  (e.g. "a tardigrade, a tiny water animal,").
- Recycling: ≥ 8 ys5 words per text (any unit of ys5; inflected forms count). List them in the lesson
  `description` after "ys5 kelimeleri:" (both texts' words, comma-separated).
- Sentences: average 15–22 words; each text has ≥ 2 passives and ≥ 2 relative clauses (which/who/whose,
  ", where"), no heavy nesting.
- Paragraphing: use "\n\n" between paragraphs (2–4 paragraphs).

## Lessons 1–3 (10 exercises each)
For each of the 2 texts, 4 `choice` questions with `"passage": <full text>` (identical string) and `"qtype":"reading"`:
1. main idea / purpose ("What is the main idea of the passage?" / "The passage is mainly about ----.")
2. detail ("According to the passage, ----.")
3. inference or reference ("The word ‘they’ in paragraph 2 refers to ----." / "It can be inferred from the passage that ----.")
4. word in context or author's attitude ("The word ‘…’ in paragraph 1 is closest in meaning to ----." / "The author's attitude … is ----.")
Question stems in English (as in YDS). Options: full, parallel, similar length; distractors use words from
the text but say something wrong/unsupported. Then 2 extra exercises: `match` (5 pairs, text words ↔ Turkish)
or `fillBlank` (sentence from the text).

## Lesson 4 "Cümle çözümleme" (8–10 choice, qtype "grammar" or "translation")
Take long sentences from THIS unit's texts. Types: "Bu cümlenin ana fiili hangisidir?" (grammar),
"Cümledeki ‘which’ neyi nitelemektedir?" (grammar), "Bu cümlenin en uygun Türkçe karşılığı hangisidir?"
(translation; options are 5 Turkish sentences differing in subject, tense, negation or modifier — one exact).
At least 3 translation items. Put the English sentence in the question in quotes ‘…’. This targets the
Turkish SOV → English SVO difficulty: explanations show the skeleton (özne + ana fiil + nesne).

## Test (15 choice)
2 NEW texts (not in lessons) × 4 reading questions (same 4 types), + 7 sentence-level items:
4 `translation` (2 EN→TR, 2 TR→EN) and 3 `sentenceCompletion` (YDS style, a clause with ---- and 5 clause options).

## Guide (≤ 250 words) — this unit's reading strategy
Sections: `## Strateji` (the strategy, why it works), `## Nasıl uygulanır` (numbered steps), `## Örnek`
(apply it to a 2–3 sentence mini text), `## Sınav ipucu`. Strategy per unit:
u1 önce soruyu oku · u2 ana fikir paragrafın neresinde · u3 gönderim zincirleri (it/this/they) ·
u4 bağlaçla yön değişimi (however, in contrast) · u5 bilinmeyen kelimeyi bağlamdan tahmin ·
u6 zamanlı okuma (metin başına 10 dk).

## Difficulty
Within the section difficulty rises (u1 easiest). Within a unit: l1 < l2 < l3 < test.

## Self-check (mandatory)
`node tool/yds/check_reading.js <unitId>` (with the NGSL=… prefix above) until TAMAM. Then re-solve every
choice question yourself without looking at `answer`; exactly one option must be defensible. Correct answers
spread ≈ evenly over 0–4. Do not edit other files. Report: per-text words / unknown % / ys5 words, topics,
judgement calls.
