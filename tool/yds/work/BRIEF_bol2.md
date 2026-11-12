# Brief: "Bol okuma 2" extensive-reading writer (YDS Faz 3b)

Extensive reading for Turkish YDS learners in their second half-year, at about B2. The texts are read for
pleasure and fluency, not as exam texts. Spec: `docs/sinav/yds-faz3-icerik.md` § Bol okuma 2.
Read `tool/yds/work/BRIEF_bol.md` (set 1) first: the format and rules there apply, with these differences:

| | Set 1 | **Set 2 (you)** |
|---|---|---|
| Output | `bol_N.json` | **`tool/yds/work/bol2_N.json`** (N = your writer number) |
| Levels | B1, B1+ | **5 texts `"B1+"` and 5 texts `"B2"`** |
| Length | 400–700 | **500–800 words** |
| Known words | through ys7 | through ys9 (`tool/yds/work/words_ys9.json` words count as known; use them freely) |

- **Unknown words:** ≤ 2% after glosses. Gloss every word or phrase a B1+ reader may not know. Keys are
  lowercase and appear verbatim in the text; 20–40 glosses per text is typical.
- **Sentence length:** B1+ texts mostly 12–22 words; B2 texts up to ~28.
- **Genres:**
  - Narrative non-fiction: biography, discovery story, travel, popular science, history, culture.
  - B2 texts may argue a little: present two views and weigh them.
- **Questions:** 2 comprehension questions per text, 4 options each.
  - Turkish `explain` that names the right option by its text, never by its position.
  - Spread `answer` over 0–3.
- **Ids:** `yb_<slug>`, unique. Grep `assets/reading/` and `tool/yds/work/bol*.json` so the slug is new.
- **Content:** original writing. Facts about real people and places must be true and hedged.
- **New topics only:**
  - Before you pick a topic, grep `assets/` and `tool/yds/work/` for its key words and drop it if the app
    already has it.
  - Then run `WORDFREQ=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/wordfreq/en.tsv node tool/yds/topic_scan.js bol2_N`
    and make it print "temiz".
  - Stay inside your assigned theme so you don't collide with the other 7 writers.

## Self-check
- Run `NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_bol.js tool/yds/work/bol2_N.json`
  until it prints TAMAM.
- Run topic_scan until it prints "temiz".
- Re-answer your own questions without looking at `answer`.
- Write only your bol2 file. Helper scripts go in your scratchpad subfolder.
