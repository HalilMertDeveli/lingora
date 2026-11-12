# Brief: "Bol okuma 3" extensive-reading writer (YDS Faz 4b)

The final set of extensive reading, for the last ten weeks before the exam. These are B2 texts, read for
pleasure, to ease fatigue between mocks: lively, warm and well told. They are not exam texts.
Spec: `docs/sinav/yds-faz4-icerik.md` § F4b. If it is not on disk, read it with
`git show origin/feature/yds-arastirma-f4:docs/sinav/yds-faz4-icerik.md`.

Read `tool/yds/work/BRIEF_bol.md` (set 1) and `BRIEF_bol2.md` (set 2) first. Their format and rules apply,
with these differences:

| | Set 3 (you) |
|---|---|
| Output | `tool/yds/work/bol3_N.json` (N = your writer number), 10 texts |
| Level | `"B2"` for every text |
| Length | **600–900 words** |
| Known words | everything through ys12: the ys12 list is `tool/yds/work/words_ys12.json` |
| Recycling | **≥ 8 words per text** from ys9 (`tool/yds/work/words_ys9.json`) and ys12 (`words_ys12.json`) together. Inflected forms count; use them naturally. |

- **Unknown words:** ≤ 2% after glosses. Gloss what a B2 reader may not know; 20–45 glosses is typical.
- **Sentences:** varied, mostly 14–28 words. A natural, engaging voice.
- **Questions:** 2 comprehension questions per text, 4 options each.
  - Turkish `explain` that names the right option by its text, never by its position.
  - Spread `answer` over 0–3.
- **Ids:** `yb_<slug>`, unique. Grep `assets/reading/` and `tool/yds/work/bol*.json` first.
- **Facts:** original writing. Facts about real people and places must be true and hedged.
- **New topics only:**
  - The app already has a lot of reading: Bol okuma 1–2, Okuma evi 1–3, every mock, and yds_m15–m20 and
    yokdil_m1–m3 being written now.
  - Grep `assets/` and `tool/yds/work/` for a topic's key words before you pick it.
  - Then run `WORDFREQ=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/wordfreq/en.tsv node tool/yds/topic_scan.js bol3_N`
    until it prints "temiz".
  - Stay inside your assigned genre and theme so you don't collide with the other 10 writers.

## Self-check
- Run `NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_bol.js tool/yds/work/bol3_N.json`
  until it prints TAMAM.
- Run topic_scan until it prints "temiz".
- Re-answer your own questions without looking at `answer`.
- Write only your bol3 file. Helper scripts go in your scratchpad subfolder.
- Report: ids and a one-line topic for each, plus the final checker line.
