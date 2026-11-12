# Brief: full cards for the old YDS path's words (ydm_, YDS Faz 2c)

The YDS path ys1–ys4 taught ~800 words in its vocabulary lessons, but the app only shows them as thin
"bridge" cards (English + Turkish). You turn your slice of `tool/yds/work/ydm_list.json` into full cards in the
same format as `assets/vocab/yds.json` (read 3–4 entries there first, e.g. `yd_analyse`).

## Input items
`{"id":"ydm_…","word":"…","tr":"…"|null,"topic":"ys2u4","bridge":true|false}`

## Output: `tool/yds/work/ydm_<n>.json` — array of cards, one per input item, same order
```
{"id":"ydm_carry_out","word":"carry out","pos":"phrasal verb","topic":"ys2u3",
 "senses":[{"tr":"…","def":"English definition"}],
 "examples":[{"en":"…","tr":"…","context":"akademik","target":"carried out"}],
 "collocations":[{"phrase":"carry out research","answer":"carry out","tr":"araştırma yapmak"}],
 "family":["…"], "synonym":"…", "tip":"…"}
```
- **bridge: true** → keep `id` and `word` EXACTLY as given (learners' progress is stored under that id; a test
  checks `id == "ydm_" + word.trim().toLowerCase() with spaces → "_"`). The first sense's `tr` = the given `tr`
  (you may add a second sense).
- **bridge: false** → the item may be an inflected form ("deciphered", "subsidies", "withdrew", "carried out").
  Write the card for the dictionary headword ("decipher", "subsidy", "withdraw", "carry out") and set
  `"word"` to it and `"id"` to `"ydm_" + headword.toLowerCase()` with spaces → `_`. If two items of your slice
  share a headword, write it once. Give a natural Turkish sense.
- `topic` = given topic. `pos`: noun / verb / adjective / adverb / phrasal verb / linking phrase / preposition.
- Examples: 12–22 words, academic or news register (YDS topics), natural Turkish translation; `target` appears
  verbatim in `en`; `context` "akademik" | "haber" | "genel". Original sentences, no dictionary copies.
- ≥ 1 collocation (`answer` verbatim in `phrase`); `family` for verbs/nouns where a real family exists, format
  "word (pos)", else []; `synonym` only if a real one exists; `tip` (Turkish learner tip) on at least half the cards.
- No `**`, no double/leading/trailing spaces.

## Self-check
`node tool/yds/check_ydm.js tool/yds/work/ydm_<n>.json` until TAMAM. Write only your output file; helper
scripts in your scratchpad subfolder. Report counts and any items you merged or found odd.
