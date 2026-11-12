# Brief: "Bol okuma 1" extensive-reading writer (YDS Faz 2b)

Extensive reading for Turkish YDS learners at about B1+/B2: texts **one notch below** their level, read for
pleasure and fluency (not exam texts). Spec: `docs/sinav/yds-faz2-icerik.md` § Bol okuma.

## Format — the app's existing ReadingStory (see `assets/reading/stories.json`)
Your output file `tool/yds/work/bol_<n>.json` is a JSON **array** of objects:
```
{"id":"yb_<slug>","level":"B1"|"B1+","emoji":"🌍","title":"English title","titleTr":"Türkçe başlık",
 "text":"Paragraph one…\n\nParagraph two…",
 "glosses":{"lowercase word or phrase as in the text":"Türkçe karşılık", …},
 "questions":[{"q":"…?","options":["…","…","…","…"],"answer":1,"explain":"Türkçe açıklama…"}, {…}]}
```
- No other fields. `text` holds only the story (no title, no glosses). Paragraphs separated by a blank line.
- 400–700 words per text. Natural, warm, readable English; varied sentence length (B1: mostly 10–18 words;
  B1+: up to ~22). Narrative, biography, science story, travel, popular science.
- Unknown words ≤ 2% after glosses: give a Turkish gloss for every word/phrase a B1 reader may not know
  (keys lowercase and appearing verbatim in the text; 15–35 glosses per text is typical).
- 2 comprehension questions (not exam style), 4 options, Turkish `explain` naming the right option by its text,
  never by position. Spread `answer` over 0–3.
- Original writing; true, hedged facts for real people/places. No topic from the ys6/ys8 reading units
  (honeybees, volcanoes, Grand Bazaar, Semmelweis, Rize tea, Piri Reis, Göbekli Tepe, sebil, etc.) or another
  writer's list.

## Self-check
`NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/check_bol.js tool/yds/work/bol_<n>.json`
until TAMAM. Write only your bol file; helper scripts in your scratchpad subfolder.
