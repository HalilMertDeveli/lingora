# Brief: ys8 "Okuma evi 2" unit writer (YDS Faz 2b)

Read `tool/yds/work/BRIEF_ys6.md` first — ys8 follows it (unit shape, question types, rules from BRIEF_ys5
§ Exercise rules) with the differences below. Spec: `docs/sinav/yds-faz2-icerik.md` §F2b.

## Level and texts (the checker enforces all of this)
- B2, real YDS length: **250–320 words** per text (lesson texts AND the 2 test texts).
- Vocabulary: ≥ 10 ys7 words and ≥ 3 ys5 words per text (lists: `tool/yds/work/words_ys7.json`,
  `tool/yds/work/words.json`; inflected forms count). Unknown words ≤ 5%.
- Average sentence 19–25 words; per text ≥ 3 passives, ≥ 2 relative clauses (which/who/whose, ", where"),
  ≥ 2 nominalisations (-tion/-sion/-ment/-ity/-ance/-ence nouns).
- Each lesson's `reading` = `{"field": …, "words": <sum>, "cefr": "B2", "ys7": [ys7 words used], "ys5": [ys5 words used]}`;
  `description` = "Metin 1: … Metin 2: … ys7 kelimeleri: first 8 … ve N kelime daha." (keep it short).
- Check drafts: `NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_reading.js --text "<text>" --sec ys8`
- Facts true and hedged ("about", "more than"); no claim you cannot stand behind. Original texts only.
- The whole unit is in ONE field (`fen` | `saglik` | `sosyal`; ys8u10 mixes all three). Topics: see your task;
  never reuse a topic from ys6 (list in `tool/yds/work/BRIEF_ys6.md` agents' prompts: bees, volcanoes, sleep,
  walking, gardens, libraries, Grand Bazaar, e-waste, tardigrades, leaves, sugar drinks, Semmelweis,
  four-day week, bilingual children, tea, scooters, coral, GPS, antibiotics, noise, remote work,
  volunteering, Silk Road, desalination, plastic bacteria, earthquakes, vaccines, screens, housing,
  fast fashion, Göbekli Tepe, vertical farming, light pollution, bird migration, gut bacteria, heat waves,
  gig economy, museums, Piri Reis, lab meat, glaciers, telescope, sugar tax, air pollution, basic income,
  ageing, sebil, deposit schemes, microplastics, handwriting, Olympics).

## Questions
- Per text 4 `reading` questions covering YDS reading types: main idea / best title, detail, inference,
  reference, author's attitude or purpose, word in context. **Every text has ≥ 1 inference or
  attitude/purpose question** whose stem says so ("It can be inferred…", "The author's attitude…",
  "The main purpose of the passage is…"). Stems in English.
- Lesson 4 "Cümle çözümleme" (8–10, grammar/translation, ≥ 3 translation): **"ana fiil" questions must have
  verb-like distractors** — the relative-clause verb, a participle (-ing/-ed), an auxiliary, an infinitive —
  never nouns (F1 review). Translation options differ in tense, voice, negation, quantifier, hedge.
- Test: 2 new texts × 4 + 7 sentence-level (4 translation: 2 EN→TR, 2 TR→EN; 3 sentenceCompletion).
- Explanations: name the right option and ≥ 3 wrong ones by text (checker rule).

## Guide (≤ 250 words) — the unit's strategy
u1 başlık sorusu · u2 çıkarım · u3 yazarın tutumu · u4 karşılaştırma metinleri · u5 sayı ve istatistik
içeren metin · u6 tanım ve örnek · u7 problem–çözüm · u8 neden–sonuç zinciri · u9 metin başına 12 dk
zamanlı · u10 karışık zamanlı. Sections: `## Strateji`, `## Nasıl uygulanır`, `## Örnek`, `## Sınav ipucu`.
The unit's texts should suit its strategy (u4 texts compare two views/things; u5 texts carry numbers…).

## Self-check
`node tool/yds/check_reading.js <unitId>` (NGSL prefix) until TAMAM; then re-solve every choice without
looking at `answer`. Write only `tool/yds/work/<unitId>.json`; helper scripts in your scratchpad subfolder.
