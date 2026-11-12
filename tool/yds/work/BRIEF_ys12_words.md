# Brief: ys12 word list picker (YDS Faz 4a)

Choose the 900 words and phrases of "Kelime bankası 4" and write `tool/yds/work/words_ys12.json`:
`{"ys12u1": [113 items], "ys12u2": [...], … "ys12u8": [...]}`, with **112 or 113 items per unit**
(four units 113, four 112). Spec: `docs/sinav/yds-faz4-icerik.md` § F4a (read it, from the branch
`origin/feature/yds-arastirma-f4` if it is not on disk yet: `git show origin/feature/yds-arastirma-f4:docs/sinav/yds-faz4-icerik.md`).

## Units (themes)
| Unit | Theme |
|---|---|
| ys12u1 | Cause and effect, impact verbs II (exacerbate-type verbs) |
| ys12u2 | Evaluation and criticism (dubious, compelling, flawed …) |
| ys12u3 | Change and process: adverbs and verbs of change (incrementally, abruptly, invariably …) |
| ys12u4 | Science and technology III |
| ys12u5 | Health and life sciences III |
| ys12u6 | Society, law and economics III |
| ys12u7 | Advanced collocations and idiomatic phrases ("bear the brunt of", "pose a threat to" …) |
| ys12u8 | Exam-confusable word families (pairs like adverse/averse, eminent/imminent, discrete/discreet) |

The spec's example words are often already taught; use them only as a guide to the register.

## Rules (`bands12.js` enforces them)
- **New only.** Nothing taught before: general course, YDS path ys1–ys11, any card in `assets/vocab/yds.json`.
  The script checks this, including simple inflections.
  - In ys12u8 the *new* member of a confusable pair is the card. Its partner may already be taught; the
    unit will contrast them.
- **Bands:**

  | Band | Target |
  |---|---|
  | Single words with wordfreq Zipf 2.8–4.0 (the "mid–advanced" band) | ≥ 60 % (≥ 540 items) |
  | Items of u7 + u8 outside that band | ≤ 20 % (≤ 180) |
  | Field terms (single words outside the band) and phrases in u1–u6 | ≤ 20 % (≤ 180) |
  | Multi-word phrases in all | ≤ 120 |

- **Candidates.** `C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/pool_ys12.tsv`
  lists ~20,700 untaught band words (`word\tzipf`). It is noisy (names, places, slang, inflected forms).
- **Exam-worthy only.**
  - Words a YDS/YÖKDİL reading passage or vocabulary question would use: general-academic, journalistic,
    scientific.
  - No proper names, slang, offensive words, brand names, archaic words or regionalisms.
  - Base forms only (no plural or -ed forms as separate items).
  - No word that is just an inflection of a taught word.
  - Phrases are lowercase, real fixed expressions, ≤ 6 words.
- Lowercase, trimmed, no duplicates across units.
- Each unit's items fit its theme. u4–u6 may use field terms (outside the band) within the ≤ 20 % limit.

## Check
`WORDFREQ=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/wordfreq/en.tsv NGSL=C:/Users/clt/AppData/Local/Temp/claude/b7669fb696de5774/ec03ee5e-25ba-4f0f-a1d7-80e637ba6f93/scratchpad/ngsl/ngsl_1.2.csv node tool/yds/bands12.js`
Run it until it prints TAMAM. Then read your list once more as a teacher would: drop anything a B2–C1 exam
taker would never need, and replace it.

Write only `words_ys12.json`; helper scripts go in your scratchpad subfolder. Report the per-unit band
counts, the final line, and 10 sample items per unit.
