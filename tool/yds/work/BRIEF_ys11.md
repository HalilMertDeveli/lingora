# Brief: ys11 "Ara denemeler" review-unit writer (YDS Faz 3d)

One mixed-review unit that prepares the learner for the half mock that follows it (the mock is already
written; you write the unit). Spec: `docs/sinav/yds-faz3-icerik.md` § F3d. Level B1+–B2. All content NEW:
never copy sentences from the units listed as coverage — they only tell you which topics the learner knows.

## Output: `tool/yds/work/<unitId>.json`
```
{"id":"ys11u1","title":"…","description":"…","color":"0xFF……","theme":"…","guide":"…","nodes":[
 {"id":"ys11u1l1","type":"lesson","title":"Dilbilgisi ve cloze","description":"…","exercises":[10–12 choice]},
 {"id":"ys11u1l2","type":"lesson","title":"Cümle tamamlama ve çeviri",…},
 {"id":"ys11u1l3","type":"lesson","title":"Okuma",…},
 {"id":"ys11u1l4","type":"lesson","title":"Diyalog, restatement, paragraf",…},
 {"id":"ys11u1t","type":"test","title":"Ünite testi","description":"15 karışık soru; geçmek için %80 doğru yap","rewardXp":25,"exercises":[15 choice]},
 {"id":"ys11u1c","type":"chest","title":"Ünite ödülü","description":"Üniteyi bitir, bonus XP kazan","rewardXp":20}]}
```
No mock node (added at build time).

## Lessons (qtype per lesson)
1. grammar + cloze (one cloze text 130–170 words with 4–5 blanks + grammar items).
2. sentenceCompletion + translation (EN→TR and TR→EN).
3. reading: two texts of 200–280 words × 4–5 questions (main idea, detail, inference, reference/attitude).
4. dialogue, restatement, paragraphCompletion, irrelevantSentence (at least one of each; the odd sentence
   stays on the SAME topic but a different aspect).
Test: 15 mixed items covering at least 7 question types. Grammar items about structure/main verb use
verb-like distractors. Rules from `tool/yds/work/BRIEF_ys5.md` § Exercise rules (5 options, qtype, Turkish
explanation naming the right option and ≥ 3 wrong ones by text, never by position/letter, no a/an giveaway).
Every passage on a NEW topic (the checker rejects overlap with any text in the app or the other ys11 files).

## Guide (≤ 250 words)
What question types the learner has met by this week, a time plan for the half mock (90 minutes: e.g.
vocabulary/grammar 20 min, cloze/completion 25 min, reading 30 min, rest 15 min), and the after-mock analysis
steps (mark each wrong answer's reason in the Hata defteri, redo the weakest type, re-read the explanations).

## Self-check
`node tool/yds/check_review.js <unitId>` until TAMAM; re-solve every choice without looking at `answer`.
Write only your unit file; helper scripts in your scratchpad subfolder.
