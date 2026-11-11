// Dilbaz topic-theme objects: original flat vector drawings, written by hand
// for this project (no third-party artwork). One 64×64 viewBox per object.
//
// Style guide (docs/tasarim/temalar.md):
// - one ink outline, 2.5 px at 64 px, round joins and caps
// - flat fills from PALETTE only, one white highlight, no gradients
// - a soft ground shadow (ink at 12 %) under objects that stand
//
// Run `node tool/themes/gen_theme_svgs.mjs` to write assets/themes/.

export const PALETTE = {
  ink: '#3D2B1F',
  red: '#E4572E',
  orange: '#F39A3D',
  yellow: '#F4C542',
  green: '#5BA55B',
  teal: '#2EA4A6',
  blue: '#3C7DD9',
  navy: '#2B3A67',
  purple: '#8E5BC9',
  pink: '#EE7FA6',
  brown: '#A0673A',
  cream: '#FFF4DE',
  white: '#FFFFFF',
  gray: '#A9B2BC',
  light: '#DDE3E8',
  skin: '#F2C29B',
  tea: '#B23A17',
};
const {
  ink: K,
  red: R,
  orange: O,
  yellow: Y,
  green: G,
  teal: T,
  blue: B,
  navy: N,
  purple: P,
  pink: PK,
  brown: BR,
  cream: CR,
  white: W,
  gray: GR,
  light: LG,
  skin: SK,
  tea: TEA,
} = PALETTE;

const S = `stroke="${K}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"`;
const r = (x, y, w, h, rx, f) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${f}" ${S}/>`;
const c = (x, y, rr, f) => `<circle cx="${x}" cy="${y}" r="${rr}" fill="${f}" ${S}/>`;
const e = (x, y, rx, ry, f) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${f}" ${S}/>`;
const p = (d, f = 'none') => `<path d="${d}" fill="${f}" ${S}/>`;
const l = (x1, y1, x2, y2) => `<path d="M${x1} ${y1}L${x2} ${y2}" fill="none" ${S}/>`;
// Fill-only shapes (no outline) for details and highlights.
const fc = (x, y, rr, f, o = 1) => `<circle cx="${x}" cy="${y}" r="${rr}" fill="${f}" opacity="${o}"/>`;
const fp = (d, f, o = 1) => `<path d="${d}" fill="${f}" opacity="${o}"/>`;
const hl = (d) => `<path d="${d}" fill="none" stroke="${W}" stroke-width="2.5" stroke-linecap="round" opacity=".7"/>`;
const shadow = (w = 20) => `<ellipse cx="32" cy="59" rx="${w}" ry="3" fill="${K}" opacity=".12"/>`;
const star = (cx, cy, ro, ri, f) => {
  let d = '';
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const rr = i % 2 ? ri : ro;
    d += `${i ? 'L' : 'M'}${(cx + Math.cos(a) * rr).toFixed(1)} ${(cy + Math.sin(a) * rr).toFixed(1)}`;
  }
  return p(d + 'Z', f);
};

/** name → SVG body (inside a 64×64 viewBox). */
export const OBJECTS = {
  // ---- tea house -----------------------------------------------------
  cay_bardagi:
    shadow(18) +
    e(32, 52, 20, 5, R) +
    p('M20 10H44C43 20 37 25 37 31C37 36 41 39 41 45C41 49 38 50 36 50H28C26 50 23 49 23 45C23 39 27 36 27 31C27 25 21 20 20 10Z', W) +
    fp('M25.5 22H38.5C37 26 35.5 28 35.5 31C35.5 36 39.5 39 39.5 45C39.5 48 37.5 48.5 36 48.5H28C26.5 48.5 24.5 48 24.5 45C24.5 39 28.5 36 28.5 31C28.5 28 27 26 25.5 22Z', TEA) +
    hl('M24 14C25 19 27 22 29 25') +
    l(20, 10, 44, 10),
  demlik:
    shadow(22) +
    p('M14 34C14 26 22 24 32 24C42 24 50 26 50 34V48C50 52 47 54 43 54H21C17 54 14 52 14 48Z', R) +
    p('M50 36C56 35 58 30 58 24L54 26C54 30 52 32 50 32', R) +
    p('M22 24C22 16 26 12 32 12C38 12 42 16 42 24Z', O) +
    e(32, 12, 7, 2.5, Y) +
    c(32, 8, 2.5, Y) +
    p('M16 40H48', 'none') +
    hl('M19 30C21 28 24 27 27 27'),
  lale:
    shadow(12) +
    p('M32 30V56') +
    p('M32 54C24 52 20 46 22 38C27 42 30 47 32 54Z', G) +
    p('M32 54C40 52 44 46 42 38C37 42 34 47 32 54Z', G) +
    p('M32 32C22 30 20 20 22 10C26 14 28 16 32 12C36 16 38 14 42 10C44 20 42 30 32 32Z', R) +
    p('M32 12C29 18 29 26 32 32', 'none'),
  simit:
    shadow(22) +
    e(32, 36, 24, 18, O) +
    e(32, 36, 9, 6, CR) +
    [
      [14, 30],
      [20, 24],
      [30, 21],
      [40, 22],
      [48, 28],
      [50, 38],
      [44, 47],
      [34, 51],
      [22, 49],
      [15, 41],
    ]
      .map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="1.6" ry="1" fill="${CR}"/>`)
      .join(''),

  // ---- food ----------------------------------------------------------
  tabak:
    shadow(24) +
    e(32, 38, 24, 14, W) +
    e(32, 38, 15, 8, CR) +
    fc(27, 37, 4, R) +
    fc(35, 39, 4, G) +
    fc(31, 34, 3, Y) +
    p('M6 14V30M3 14V22C3 25 9 25 9 22V14', 'none') +
    p('M58 14C54 16 54 24 56 28V36', 'none'),
  elma:
    shadow(16) +
    p('M32 20C24 14 12 18 12 32C12 46 22 56 32 52C42 56 52 46 52 32C52 18 40 14 32 20Z', R) +
    p('M32 20C32 14 34 10 36 8') +
    p('M34 14C38 8 46 8 48 12C44 16 38 16 34 14Z', G) +
    hl('M19 28C19 24 21 22 24 21'),
  corba:
    shadow(22) +
    p('M10 30H54C54 44 44 52 32 52C20 52 10 44 10 30Z', T) +
    e(32, 30, 22, 5, Y) +
    fc(25, 30, 2, R) +
    fc(36, 29, 2, G) +
    p('M40 28L56 10', 'none') +
    e(57, 9, 3, 4, LG) +
    p('M22 22C20 18 24 16 22 12M32 22C30 18 34 16 32 12', 'none'),
  piknik_sepeti:
    shadow(24) +
    p('M18 28C18 14 46 14 46 28', 'none') +
    p('M8 28H56L50 54H14Z', BR) +
    p('M12 36H52M14 44H50M24 28V54M32 28V54M40 28V54', 'none') +
    p('M8 28H56V32H8Z', R) +
    fc(40, 22, 5, R) +
    p('M40 17L42 13', 'none'),
  kasik_catal: p('M22 8V56M17 8V20C17 26 27 26 27 20V8') + e(42, 18, 6, 10, LG) + p('M42 28V56'),

  // ---- family & home -------------------------------------------------
  ev:
    shadow(24) +
    r(14, 30, 36, 26, 2, CR) +
    p('M8 32L32 10L56 32Z', R) +
    r(27, 40, 10, 16, 2, BR) +
    r(17, 36, 8, 8, 1, Y) +
    r(40, 36, 8, 8, 1, Y) +
    r(42, 12, 6, 12, 1, BR),
  kapi:
    shadow(18) +
    r(16, 6, 32, 50, 3, BR) +
    r(21, 12, 22, 16, 2, O) +
    r(21, 32, 22, 18, 2, O) +
    c(42, 32, 2.5, Y) +
    r(10, 54, 44, 4, 1, GR),
  pencere:
    shadow(20) +
    r(12, 10, 40, 40, 3, B) +
    l(32, 10, 32, 50) +
    l(12, 30, 52, 30) +
    hl('M17 16L24 23M38 16L45 23') +
    p('M8 50H56V56H8Z', BR) +
    fc(18, 50, 3, R) +
    fc(46, 50, 3, PK),
  anahtar:
    shadow(16) +
    c(20, 24, 12, Y) +
    c(20, 24, 4.5, CR) +
    p('M30 30L52 52M44 44L48 40M48 48L53 43', 'none'),
  kurabiye_kavanozu:
    shadow(20) +
    r(14, 18, 36, 38, 8, LG) +
    r(18, 10, 28, 9, 3, R) +
    fc(26, 34, 6, O) +
    fc(39, 42, 6, O) +
    fc(27, 48, 4, O) +
    fc(25, 33, 1, BR) +
    fc(40, 41, 1, BR) +
    hl('M19 26V40'),
  cicek_saksi:
    shadow(14) +
    p('M20 40H44L40 56H24Z', O) +
    p('M32 40V24') +
    c(32, 18, 7, PK) +
    fc(32, 18, 3, Y) +
    p('M32 34C26 34 22 30 22 26C28 26 32 30 32 34Z', G),

  // ---- time ----------------------------------------------------------
  duvar_saati: shadow(18) + c(32, 32, 22, CR) + c(32, 32, 2.5, K) + p('M32 32V18M32 32L42 38', 'none') + [0, 3, 6, 9].map((i) => fc(32 + Math.cos((i * Math.PI) / 6) * 17, 32 + Math.sin((i * Math.PI) / 6) * 17, 2, K)).join('') + c(32, 32, 22, 'none'),
  takvim:
    shadow(20) +
    r(10, 14, 44, 42, 4, W) +
    p('M10 18C10 16 12 14 14 14H50C52 14 54 16 54 18V26H10Z', R) +
    l(20, 8, 20, 18) +
    l(44, 8, 44, 18) +
    `<text x="32" y="50" font-family="Arial, sans-serif" font-weight="700" font-size="20" text-anchor="middle" fill="${K}">7</text>`,
  kum_saati:
    shadow(16) +
    r(14, 6, 36, 6, 2, BR) +
    r(14, 52, 36, 6, 2, BR) +
    p('M18 12H46C46 24 36 28 36 32C36 36 46 40 46 52H18C18 40 28 36 28 32C28 28 18 24 18 12Z', LG) +
    fp('M22 50H42C40 44 34 42 32 40C30 42 24 44 22 50Z', Y) +
    fp('M24 18H40C38 22 34 25 32 27C30 25 26 22 24 18Z', Y),
  calar_saat:
    shadow(18) +
    p('M18 52L14 58M46 52L50 58', 'none') +
    c(32, 34, 20, R) +
    c(32, 34, 15, CR) +
    c(16, 14, 6, Y) +
    c(48, 14, 6, Y) +
    p('M32 34V24M32 34L39 38', 'none'),
  zaman_kapsulu:
    shadow(20) +
    r(14, 10, 36, 46, 18, T) +
    p('M14 32H50', 'none') +
    r(24, 26, 16, 12, 3, Y) +
    fc(32, 32, 2, K) +
    hl('M20 18C19 22 19 26 19 28'),

  // ---- shopping & colours --------------------------------------------
  poset:
    shadow(20) +
    p('M14 22H50L54 56H10Z', PK) +
    p('M24 22C24 10 40 10 40 22', 'none') +
    fc(32, 40, 6, W, 0.8) +
    p('M28 40L31 43L37 37', 'none'),
  boya_kalemi:
    shadow(14) +
    p('M26 54V20L32 6L38 20V54Z', B) +
    p('M26 20H38', 'none') +
    fp('M29.5 13H34.5L32 6Z', K) +
    r(26, 44, 12, 10, 1, Y),
  etiket:
    shadow(18) +
    p('M30 8H54V32L32 54L8 30Z', Y) +
    c(46, 16, 3.5, W) +
    `<text x="30" y="38" font-family="Arial, sans-serif" font-weight="700" font-size="16" text-anchor="middle" fill="${K}" transform="rotate(-45 30 34)">₺</text>`,
  cuzdan:
    shadow(22) +
    r(8, 18, 48, 36, 6, BR) +
    p('M8 26H56', 'none') +
    r(38, 32, 20, 12, 4, O) +
    c(46, 38, 2.5, Y) +
    p('M14 18L40 10L44 18', G),
  hediye_kutusu:
    shadow(22) +
    r(12, 28, 40, 28, 3, R) +
    r(8, 20, 48, 10, 3, R) +
    p('M32 20V56', 'none') +
    fp('M29 20H35V56H29Z', Y) +
    p('M32 20C26 10 16 12 20 18C22 20 28 20 32 20C36 20 42 20 44 18C48 12 38 10 32 20Z', Y),

  // ---- daily routine -------------------------------------------------
  dis_fircasi:
    shadow(18) +
    r(8, 34, 40, 8, 4, T) +
    r(42, 30, 14, 8, 2, W) +
    [44, 48, 52].map((x) => l(x, 22, x, 30)).join('') +
    p('M42 18C46 14 52 14 56 18C56 22 42 22 42 18Z', B),
  kupa:
    shadow(18) +
    p('M14 22H44V48C44 52 41 54 37 54H21C17 54 14 52 14 48Z', O) +
    p('M44 28C54 28 54 44 44 44', 'none') +
    p('M22 16C20 12 24 10 22 6M30 16C28 12 32 10 30 6M38 16C36 12 40 10 38 6', 'none') +
    hl('M19 28V44'),
  sirt_cantasi:
    shadow(18) +
    r(14, 16, 36, 40, 10, G) +
    p('M24 16C24 8 40 8 40 16', 'none') +
    r(20, 34, 24, 16, 4, Y) +
    l(26, 40, 38, 40),
  kahvalti_tepsisi:
    shadow(26) +
    r(4, 42, 56, 10, 4, BR) +
    c(18, 34, 8, W) +
    fc(18, 34, 4, Y) +
    p('M30 24H42V40H30Z', W) +
    fp('M31.5 30H40.5V38.5H31.5Z', TEA) +
    e(50, 36, 6, 6, G),

  // ---- travel --------------------------------------------------------
  bavul:
    shadow(22) +
    r(12, 18, 40, 36, 6, O) +
    p('M24 18V12C24 10 26 8 28 8H36C38 8 40 10 40 12V18', 'none') +
    l(22, 18, 22, 54) +
    l(42, 18, 42, 54) +
    r(26, 30, 12, 8, 2, Y),
  bilet:
    shadow(22) +
    p('M6 18H58V28C54 28 54 36 58 36V46H6V36C10 36 10 28 6 28Z', B) +
    p('M42 18V46', 'none') +
    l(14, 26, 34, 26) +
    l(14, 34, 28, 34) +
    fp('M48 28L54 32L48 36Z', W),
  ucak:
    shadow(22) +
    p('M8 34C8 30 12 28 18 28H50C56 28 58 30 58 32C58 34 56 36 50 36H18C12 36 8 36 8 34Z', W) +
    p('M30 28L22 10H28L42 28Z', B) +
    p('M30 36L22 54H28L42 36Z', B) +
    p('M14 28L8 18H13L20 28Z', R) +
    fc(46, 31, 1.5, B) +
    fc(40, 31, 1.5, B),
  oda_anahtari:
    shadow(18) +
    p('M8 10H30L36 16V36L30 42H8Z', R) +
    c(15, 18, 3, W) +
    p('M30 30L50 50M44 44L48 40M48 48L52 44', 'none'),
  hediye_bavul:
    shadow(22) +
    r(12, 22, 40, 32, 6, T) +
    p('M24 22V16C24 14 26 12 28 12H36C38 12 40 14 40 16V22', 'none') +
    fp('M29 22H35V54H29Z', Y) +
    p('M32 22C26 12 16 14 20 20C22 22 28 22 32 22C36 22 42 22 44 20C48 14 38 12 32 22Z', Y),
  palmiye:
    shadow(16) +
    p('M32 56C34 44 34 32 30 22', 'none') +
    p('M30 22C22 12 12 14 8 20C16 18 24 20 30 22Z', G) +
    p('M30 22C38 12 50 12 56 18C46 18 38 20 30 22Z', G) +
    p('M30 22C26 22 20 26 18 34C24 30 28 26 30 22Z', G) +
    p('M30 22C36 22 44 26 46 34C40 30 34 26 30 22Z', G) +
    fc(30, 24, 3, BR),
  pusula:
    shadow(18) +
    c(32, 32, 22, CR) +
    c(32, 32, 16, W) +
    p('M32 16L37 32H27Z', R) +
    p('M32 48L37 32H27Z', GR) +
    c(32, 32, 2.5, K),

  // ---- city ----------------------------------------------------------
  tabela:
    shadow(14) +
    l(32, 14, 32, 58) +
    p('M14 12H48L54 18L48 24H14Z', G) +
    p('M50 28H16L10 34L16 40H50Z', B),
  trafik_lambasi:
    shadow(12) +
    l(32, 46, 32, 58) +
    r(22, 6, 20, 42, 6, N) +
    c(32, 15, 4.5, R) +
    c(32, 27, 4.5, Y) +
    c(32, 39, 4.5, G),
  tramvay:
    shadow(24) +
    p('M32 4V12M24 4H40', 'none') +
    r(10, 12, 44, 38, 8, R) +
    r(15, 18, 15, 12, 2, W) +
    r(34, 18, 15, 12, 2, W) +
    r(10, 36, 44, 4, 0, CR) +
    c(20, 52, 4, K) +
    c(44, 52, 4, K),
  vapur:
    shadow(26) +
    p('M4 40H60L52 52H12Z', W) +
    fp('M7 45H57L54 48H10Z', R) +
    r(16, 28, 32, 12, 2, CR) +
    r(36, 14, 8, 14, 1, R) +
    fp('M36 14H44V18H36Z', K) +
    [20, 26, 32].map((x) => fc(x, 34, 2, B)).join('') +
    p('M4 56C10 52 16 60 22 56C28 52 34 60 40 56C46 52 52 60 58 56', 'none'),
  balonlar:
    shadow(10) +
    p('M32 58C30 50 22 46 22 40M32 58C32 50 34 44 36 36M32 58C34 50 42 46 44 42', 'none') +
    e(22, 26, 9, 11, R) +
    e(36, 22, 9, 11, Y) +
    e(46, 32, 8, 10, B) +
    hl('M18 22C18 20 19 19 20 18'),
  sokak_lambasi:
    shadow(12) +
    p('M32 58V18C32 12 40 10 44 14', 'none') +
    p('M38 14H52L49 22H41Z', N) +
    fc(45, 24, 3, Y) +
    r(26, 52, 12, 6, 2, N),
  agac: shadow(14) + r(28, 36, 8, 20, 2, BR) + c(32, 24, 16, G) + fc(26, 20, 3, W, 0.4) + fc(38, 28, 2, W, 0.3),

  // ---- the past ------------------------------------------------------
  foto_albumu:
    shadow(22) +
    r(10, 10, 44, 46, 4, BR) +
    r(16, 16, 32, 26, 2, CR) +
    p('M18 38L26 28L32 34L38 26L46 38Z', G) +
    fc(41, 22, 3, Y) +
    l(10, 48, 54, 48),
  polaroid:
    shadow(18) +
    `<g transform="rotate(-8 32 32)">${r(14, 8, 36, 44, 2, W)}${r(18, 12, 28, 26, 1, B)}${fp('M19 36L28 26L34 32L39 27L45 36Z', G)}${fc(39, 19, 3, Y)}</g>`,
  radyo:
    shadow(22) +
    l(40, 6, 48, 18) +
    r(8, 18, 48, 36, 6, BR) +
    c(24, 36, 10, CR) +
    [0, 1, 2].map((i) => l(18, 32 + i * 4, 30, 32 + i * 4)).join('') +
    c(46, 30, 4, Y) +
    c(46, 44, 4, Y),
  gunluk_defter:
    shadow(20) +
    r(12, 8, 38, 48, 4, P) +
    r(46, 8, 6, 48, 2, Y) +
    r(18, 18, 22, 8, 2, CR) +
    p('M24 56V62L28 58L32 62V56', R),
  ani_sandigi:
    shadow(24) +
    p('M8 28C8 16 56 16 56 28Z', BR) +
    r(8, 28, 48, 26, 3, BR) +
    r(8, 26, 48, 6, 1, Y) +
    r(28, 30, 8, 10, 2, Y) +
    fc(32, 35, 1.5, K) +
    fc(20, 18, 2, Y) +
    fc(44, 20, 2, Y),

  // ---- health --------------------------------------------------------
  kalp:
    shadow(18) +
    p('M32 54C14 42 6 32 8 22C10 12 22 8 32 18C42 8 54 12 56 22C58 32 50 42 32 54Z', R) +
    hl('M15 22C15 18 18 15 21 15'),
  ilac:
    shadow(20) +
    `<g transform="rotate(-35 32 32)">${r(10, 22, 44, 20, 10, W)}${fp('M32 23.5H44C49 23.5 52.5 27 52.5 32C52.5 37 49 40.5 44 40.5H32Z', R)}${l(32, 22, 32, 42)}</g>`,
  termometre:
    shadow(12) +
    r(26, 6, 12, 40, 6, W) +
    c(32, 48, 8, R) +
    fp('M30 22H34V46H30Z', R) +
    [14, 20, 26].map((y) => l(38, y, 42, y)).join(''),
  stetoskop:
    shadow(18) +
    p('M18 8V22C18 32 26 36 32 36C38 36 46 32 46 22V8', 'none') +
    p('M32 36V44C32 52 42 54 46 48', 'none') +
    c(48, 44, 6, GR) +
    c(18, 8, 2.5, K) +
    c(46, 8, 2.5, K),
  ilk_yardim:
    shadow(22) +
    p('M24 18V12H40V18', 'none') +
    r(8, 18, 48, 36, 6, W) +
    fp('M28 26H36V32H42V40H36V46H28V40H22V32H28Z', R),

  // ---- weather -------------------------------------------------------
  gunes:
    [0, 1, 2, 3, 4, 5, 6, 7]
      .map((i) => {
        const a = (i * Math.PI) / 4;
        return l(32 + Math.cos(a) * 18, 30 + Math.sin(a) * 18, 32 + Math.cos(a) * 26, 30 + Math.sin(a) * 26);
      })
      .join('') +
    c(32, 30, 13, Y) +
    fc(28, 26, 2, W, 0.6),
  bulut: p('M16 46C8 46 6 36 12 32C10 24 20 18 26 24C28 14 44 12 46 24C54 22 60 30 56 38C60 44 54 48 50 46Z', W) + fp('M16 42H48', 'none'),
  semsiye:
    shadow(14) +
    p('M6 30C6 14 58 14 58 30C54 26 48 26 45 30C42 26 36 26 32 30C28 26 22 26 19 30C16 26 10 26 6 30Z', R) +
    p('M32 12V8M32 30V52C32 56 26 56 26 52', 'none') +
    fp('M19 29C22 20 26 16 32 13C28 18 26 22 25 28Z', W, 0.35),
  kar_tanesi:
    [0, 1, 2]
      .map((i) => {
        const a = (i * Math.PI) / 3;
        const dx = Math.cos(a) * 24,
          dy = Math.sin(a) * 24;
        return l(32 - dx, 32 - dy, 32 + dx, 32 + dy);
      })
      .join('') +
    [0, 1, 2, 3, 4, 5]
      .map((i) => {
        const a = (i * Math.PI) / 3;
        const x = 32 + Math.cos(a) * 15,
          y = 32 + Math.sin(a) * 15;
        const a1 = a + 0.7,
          a2 = a - 0.7;
        return p(
          `M${(x + Math.cos(a1) * 6).toFixed(1)} ${(y + Math.sin(a1) * 6).toFixed(1)}L${x.toFixed(1)} ${y.toFixed(1)}L${(x + Math.cos(a2) * 6).toFixed(1)} ${(y + Math.sin(a2) * 6).toFixed(1)}`,
        );
      })
      .join('') +
    c(32, 32, 5, B),
  gokkusagi:
    p('M6 48C6 30 18 18 32 18C46 18 58 30 58 48H50C50 36 42 26 32 26C22 26 14 36 14 48Z', R) +
    fp('M14 48C14 36 22 26 32 26C42 26 50 36 50 48H45C45 39 39 31 32 31C25 31 19 39 19 48Z', Y) +
    fp('M19 48C19 39 25 31 32 31C39 31 45 39 45 48H40C40 42 36 36 32 36C28 36 24 42 24 48Z', G) +
    p('M4 50C2 44 8 40 12 44C14 40 22 42 20 50Z', W) +
    p('M44 50C42 44 48 40 52 44C54 40 62 42 60 50Z', W),

  // ---- plans & dreams ------------------------------------------------
  harita:
    shadow(24) +
    p('M6 14L22 8L42 14L58 8V50L42 56L22 50L6 56Z', CR) +
    l(22, 8, 22, 50) +
    l(42, 14, 42, 56) +
    `<path d="M12 44C18 36 26 40 30 32C34 24 42 28 48 20" fill="none" stroke="${R}" stroke-width="2.5" stroke-dasharray="3 4" stroke-linecap="round"/>` +
    p('M45 16L52 23M52 16L45 23', 'none'),
  yildiz: star(32, 32, 24, 11, Y) + hl('M24 26L28 24'),
  roket:
    shadow(14) +
    p('M32 4C42 12 44 26 42 40H22C20 26 22 12 32 4Z', W) +
    c(32, 22, 5, B) +
    p('M22 32L12 44L22 44Z', R) +
    p('M42 32L52 44L42 44Z', R) +
    p('M26 40L28 52L32 46L36 52L38 40Z', O),
  dilek_feneri:
    p('M20 14C20 8 44 8 44 14L48 40C48 46 16 46 16 40Z', O) +
    p('M22 44L24 52H40L42 44', 'none') +
    fc(32, 50, 4, Y) +
    fp('M26 20C27 16 30 14 33 14', 'none') +
    hl('M24 18L22 34'),
  hazine_sandigi:
    shadow(24) +
    p('M8 30C8 16 56 16 56 30Z', BR) +
    fc(18, 18, 3, Y) +
    fc(32, 14, 3, Y) +
    fc(44, 18, 3, Y) +
    r(8, 30, 48, 24, 3, BR) +
    r(8, 28, 48, 6, 1, Y) +
    r(28, 32, 8, 10, 2, Y) +
    l(16, 30, 16, 54) +
    l(48, 30, 48, 54),

  // ---- office --------------------------------------------------------
  dosya:
    shadow(22) +
    p('M8 18C8 15 10 14 12 14H26L30 18H52C54 18 56 19 56 22V50C56 52 54 54 52 54H12C10 54 8 52 8 50Z', Y) +
    r(14, 22, 36, 18, 2, W) +
    p('M8 28H56V50C56 52 54 54 52 54H12C10 54 8 52 8 50Z', O),
  atas: p('M24 50V16C24 8 40 8 40 16V44C40 50 30 50 30 44V20', 'none') + `<path d="M24 50V16C24 8 40 8 40 16V44C40 50 30 50 30 44V20" fill="none" stroke="${GR}" stroke-width="1.2"/>`,
  evrak_cantasi:
    shadow(22) +
    p('M24 18V12C24 10 26 9 28 9H36C38 9 40 10 40 12V18', 'none') +
    r(8, 18, 48, 36, 5, BR) +
    p('M8 32H56', 'none') +
    r(28, 28, 8, 8, 2, Y),
  kupa_odul:
    shadow(16) +
    p('M18 8H46V22C46 32 40 38 32 38C24 38 18 32 18 22Z', Y) +
    p('M18 14C8 14 8 28 20 28M46 14C56 14 56 28 44 28', 'none') +
    r(28, 38, 8, 8, 1, Y) +
    r(20, 46, 24, 10, 2, BR) +
    star(32, 20, 6, 2.6, W),

  // ---- technology ----------------------------------------------------
  telefon: shadow(14) + r(18, 6, 28, 50, 6, N) + r(21, 12, 22, 36, 2, B) + c(32, 52, 2, W) + fp('M24 18H40V22H24Z', W, 0.7) + fp('M24 26H36V30H24Z', W, 0.5),
  dizustu:
    shadow(26) +
    r(12, 12, 40, 30, 3, N) +
    r(16, 16, 32, 22, 1, T) +
    p('M6 42H58L54 50H10Z', GR) +
    `<path d="M20 22L24 26L20 30M28 30H36" fill="none" stroke="${W}" stroke-width="2.5" stroke-linecap="round"/>`,
  kulaklik:
    p('M12 38V30C12 18 22 10 32 10C42 10 52 18 52 30V38', 'none') +
    r(8, 34, 12, 20, 5, R) +
    r(44, 34, 12, 20, 5, R),
  wifi:
    `<g fill="none" stroke="${B}" stroke-width="6" stroke-linecap="round"><path d="M10 26C22 14 42 14 54 26"/><path d="M18 34C26 26 38 26 46 34"/><path d="M26 42C29 39 35 39 38 42"/></g>` +
    c(32, 50, 4, K),
  robot:
    shadow(18) +
    l(32, 6, 32, 14) +
    c(32, 6, 3, R) +
    r(14, 14, 36, 26, 6, LG) +
    c(24, 26, 4, B) +
    c(40, 26, 4, B) +
    l(26, 34, 38, 34) +
    r(18, 42, 28, 14, 4, T),

  // ---- writing -------------------------------------------------------
  zarf: shadow(22) + r(6, 16, 52, 36, 4, W) + p('M6 20L32 38L58 20', 'none') + c(32, 36, 5, R),
  dolma_kalem:
    shadow(12) +
    `<g transform="rotate(35 32 32)">${r(26, 4, 12, 34, 4, N)}${p('M26 38H38L34 52L32 58L30 52Z', Y)}${l(32, 46, 32, 56)}${r(36, 8, 3, 18, 1, Y)}</g>`,
  pul: shadow(18) + `<rect x="12" y="10" width="40" height="44" rx="2" fill="${W}" stroke="${K}" stroke-width="2.5" stroke-dasharray="3 2.5"/>` + r(17, 15, 30, 34, 2, T) + fp('M20 44L29 30L35 38L40 32L44 44Z', CR) + fc(38, 22, 3, Y),
  posta_kutusu: shadow(16) + l(32, 40, 32, 58) + p('M10 22C10 14 18 10 26 10H40C48 10 54 16 54 24V42H10Z', R) + r(16, 26, 16, 6, 3, K) + p('M44 24V8H54V14H44', Y),
  koli:
    shadow(22) +
    p('M8 22L32 12L56 22V48L32 58L8 48Z', O) +
    p('M8 22L32 32L56 22M32 32V58', 'none') +
    fp('M18 18L42 27V33L18 24Z', CR, 0.7),

  // ---- feelings ------------------------------------------------------
  gulen_yuz: shadow(16) + c(32, 30, 22, Y) + fc(24, 25, 3, K) + fc(40, 25, 3, K) + p('M22 36C26 44 38 44 42 36', 'none') + fc(19, 33, 3, PK, 0.8) + fc(45, 33, 3, PK, 0.8),
  saskin_yuz: shadow(16) + c(32, 30, 22, O) + c(24, 25, 4, W) + c(40, 25, 4, W) + fc(24, 25, 1.6, K) + fc(40, 25, 1.6, K) + e(32, 40, 4, 5, K),
  kalp_balon: p('M8 12C8 9 10 8 12 8H52C54 8 56 9 56 12V40C56 42 54 44 52 44H26L14 54V44H12C10 44 8 42 8 40Z', W) + p('M32 38C24 32 20 28 21 23C22 18 28 17 32 22C36 17 42 18 43 23C44 28 40 32 32 38Z', R),
  buket:
    shadow(12) +
    p('M24 36L32 58L40 36Z', CR) +
    c(24, 22, 7, PK) +
    c(40, 22, 7, R) +
    c(32, 14, 7, Y) +
    c(32, 28, 6, P) +
    p('M28 46H36', 'none'),
  pasta:
    shadow(24) +
    r(10, 32, 44, 22, 4, PK) +
    p('M10 38C14 42 18 42 22 38C26 42 30 42 34 38C38 42 42 42 46 38C50 42 54 40 54 38', 'none') +
    r(16, 22, 32, 10, 3, CR) +
    l(32, 12, 32, 22) +
    fp('M32 4C35 8 34 11 32 11C30 11 29 8 32 4Z', O),

  // ---- nature --------------------------------------------------------
  zeytin_dali:
    p('M8 54C20 44 36 30 56 10', 'none') +
    [
      [18, 44, -40],
      [28, 34, 40],
      [36, 28, -40],
      [46, 18, 40],
    ]
      .map(([x, y, a]) => `<ellipse cx="${x}" cy="${y}" rx="8" ry="3.5" fill="${G}" ${S} transform="rotate(${a} ${x} ${y})"/>`)
      .join('') +
    e(24, 50, 4, 5, '#4E5A2B') +
    e(42, 32, 4, 5, '#4E5A2B'),
  yaprak: shadow(14) + p('M10 54C10 30 26 10 54 8C54 36 36 54 10 54Z', G) + p('M10 54L42 22M24 40V30M32 32H42', 'none'),
  ari:
    `<ellipse cx="24" cy="18" rx="9" ry="6" fill="${W}" opacity=".9" ${S} transform="rotate(-25 24 18)"/>` +
    `<ellipse cx="40" cy="18" rx="9" ry="6" fill="${W}" opacity=".9" ${S} transform="rotate(25 40 18)"/>` +
    e(32, 36, 16, 12, Y) +
    fp('M26 25H31V47H26Z', K) +
    fp('M35 25H40V47H35Z', K) +
    e(32, 36, 16, 12, 'none') +
    fc(44, 33, 2, K) +
    p('M16 36L10 38', 'none'),
  bal_kavanozu: shadow(18) + r(14, 20, 36, 36, 8, O) + r(16, 12, 32, 9, 3, R) + r(22, 30, 20, 14, 3, CR) + fp('M28 37L32 33L36 37L32 41Z', O) + fp('M20 21C22 26 18 30 22 34C24 30 26 26 24 21Z', Y),
  cicek: shadow(12) + p('M32 34V56') + [0, 1, 2, 3, 4].map((i) => c(32 + Math.cos(i * 1.2566 - 1.57) * 10, 22 + Math.sin(i * 1.2566 - 1.57) * 10, 7, PK)).join('') + c(32, 22, 6, Y) + p('M32 48C38 48 42 44 42 40C36 40 32 44 32 48Z', G),

  // ---- sport ---------------------------------------------------------
  top: shadow(16) + c(32, 30, 22, W) + p('M32 22L40 28L37 37H27L24 28Z', K) + p('M32 22V9M40 28L52 23M37 37L44 48M27 37L20 48M24 28L12 23', 'none'),
  raket:
    shadow(16) +
    `<g transform="rotate(-30 32 32)">${e(32, 22, 14, 17, 'none')}${'M22 14H42M20 22H44M22 30H42M26 8V36M32 5V39M38 8V36'
      .split('M')
      .filter(Boolean)
      .map((s) => `<path d="M${s}" stroke="${GR}" stroke-width="1.3"/>`)
      .join('')}${e(32, 22, 14, 17, 'none')}${r(29, 39, 6, 20, 3, R)}</g>` +
    c(50, 50, 5, Y),
  bisiklet: shadow(26) + c(16, 42, 11, 'none') + c(48, 42, 11, 'none') + p('M16 42L26 26H44L48 42M26 26L34 42L44 26M34 42H16', 'none') + l(24, 20, 30, 20) + p('M44 26L42 18H48', 'none') + fc(34, 42, 3, R),
  madalya: p('M20 6L28 26M44 6L36 26', 'none') + fp('M18 6H26L32 22L38 6H46L36 30H28Z', B) + c(32, 40, 15, Y) + star(32, 40, 8, 3.6, O),

  // ---- music & art ---------------------------------------------------
  nota: shadow(14) + e(20, 48, 9, 7, P) + e(46, 42, 9, 7, P) + p('M28 48V12L54 6V42', 'none') + p('M28 12L54 6V14L28 20Z', K),
  palet: shadow(22) + p('M32 8C48 8 58 18 58 30C58 40 50 42 44 40C38 38 34 44 38 50C40 54 36 56 30 56C16 56 6 44 6 32C6 18 18 8 32 8Z', CR) + c(22, 22, 4.5, R) + c(34, 18, 4.5, Y) + c(46, 24, 4.5, B) + c(18, 36, 4.5, G) + e(32, 42, 3, 4, CR),
  gitar:
    shadow(18) +
    `<g transform="rotate(30 32 32)">${r(29, 2, 6, 30, 1, BR)}${p('M32 26C22 26 18 32 22 38C16 42 18 54 32 56C46 54 48 42 42 38C46 32 42 26 32 26Z', O)}${c(32, 40, 4, K)}${l(32, 4, 32, 50)}</g>`,
  film_seridi:
    `<g transform="rotate(-12 32 32)">${r(6, 18, 52, 28, 2, N)}${[10, 20, 30, 40, 50].map((x) => fp(`M${x} 21H${x + 4}V24H${x}Z`, W) + fp(`M${x} 40H${x + 4}V43H${x}Z`, W)).join('')}${r(12, 27, 12, 10, 1, B)}${r(26, 27, 12, 10, 1, Y)}${r(40, 27, 12, 10, 1, R)}</g>`,
  patlamis_misir: shadow(18) + p('M16 26H48L44 56H20Z', W) + fp('M22 26H27L26 56H21Z', R) + fp('M37 26H42L43 56H38Z', R) + [18, 26, 34, 42, 30, 22, 38].map((x, i) => c(x + 2, i < 4 ? 22 : 14, 6, CR)).join(''),

  // ---- library -------------------------------------------------------
  kitap: shadow(24) + p('M6 14C14 10 24 10 32 16C40 10 50 10 58 14V52C50 48 40 48 32 54C24 48 14 48 6 52Z', W) + l(32, 16, 32, 54) + p('M12 22C17 20 22 20 26 22M12 30C17 28 22 28 26 30M38 22C42 20 47 20 52 22', 'none'),
  kalem: shadow(14) + `<g transform="rotate(40 32 32)">${r(27, 10, 10, 36, 1, Y)}${p('M27 46H37L32 58Z', SK)}${fp('M30.4 54H33.6L32 58Z', K)}${r(27, 4, 10, 8, 2, PK)}${l(32, 12, 32, 46)}</g>`,
  gozluk: c(18, 34, 11, LG) + c(46, 34, 11, LG) + p('M29 32C31 29 33 29 35 32M7 30L4 22M57 30L60 22', 'none') + hl('M13 30L17 27M41 30L45 27'),
  kep: shadow(16) + p('M18 32V44C24 50 40 50 46 44V32', N) + p('M4 26L32 14L60 26L32 38Z', N) + p('M52 30V44', 'none') + c(52, 46, 3, Y),
  kure: shadow(12) + l(32, 46, 32, 54) + r(20, 52, 24, 5, 2, BR) + c(32, 26, 18, B) + fp('M22 16C28 14 30 20 26 24C22 28 28 32 24 38C18 34 16 22 22 16Z', G) + fp('M38 22C44 22 46 30 42 34C38 30 36 26 38 22Z', G) + p('M10 26C10 40 20 48 32 48', 'none'),

  // ---- news & media --------------------------------------------------
  gazete: shadow(22) + r(8, 10, 48, 44, 3, W) + fp('M14 16H50V24H14Z', K) + r(14, 30, 16, 14, 1, LG) + [30, 34, 38, 42].map((y) => l(34, y, 50, y)).join('') + l(14, 48, 50, 48),
  mikrofon: shadow(12) + r(22, 6, 20, 30, 10, GR) + [14, 20, 26].map((y) => l(24, y, 40, y)).join('') + p('M16 28C16 38 22 44 32 44C42 44 48 38 48 28M32 44V54M22 56H42', 'none'),
  kamera: shadow(22) + r(6, 18, 52, 34, 5, N) + r(18, 12, 14, 8, 2, N) + c(32, 35, 11, LG) + c(32, 35, 6, B) + c(48, 25, 2.5, R) + hl('M28 31L30 29'),
  televizyon: shadow(22) + p('M24 6L32 14L40 6', 'none') + r(6, 14, 52, 38, 6, BR) + r(12, 20, 32, 26, 3, T) + c(50, 26, 3, Y) + c(50, 36, 3, Y) + hl('M16 25L20 23'),

  // ---- meetings ------------------------------------------------------
  ampul: shadow(12) + p('M32 6C20 6 14 14 14 24C14 32 22 36 22 44H42C42 36 50 32 50 24C50 14 44 6 32 6Z', Y) + r(22, 44, 20, 10, 3, GR) + l(24, 49, 40, 49) + p('M26 34L32 26L38 34', 'none') + hl('M20 20C21 16 24 13 27 12'),
  grafik: shadow(24) + r(8, 8, 48, 46, 3, W) + r(14, 34, 8, 14, 1, B) + r(26, 26, 8, 22, 1, G) + r(38, 16, 8, 32, 1, O) + p('M14 26L26 18L34 22L48 12', 'none'),
  sunum_panosu: shadow(18) + p('M20 44L14 58M44 44L50 58M32 44V54', 'none') + r(8, 8, 48, 36, 3, W) + r(8, 4, 48, 6, 2, BR) + p('M14 34L24 24L32 30L46 16', 'none') + fc(46, 16, 3, R),
  konusma: p('M6 10C6 8 8 6 10 6H36C38 6 40 8 40 10V26C40 28 38 30 36 30H18L10 38V30C8 30 6 28 6 26Z', B) + p('M24 34C24 32 26 30 28 30H54C56 30 58 32 58 34V50C58 52 56 54 54 54H52V60L44 54H28C26 54 24 52 24 50Z', O) + [14, 22, 30].map((x) => fc(x + 1, 18, 2, W)).join(''),
  el_sikisma: shadow(22) + p('M4 30L16 22H26L34 28L28 34C24 36 22 32 26 30', SK) + p('M60 30L48 22H38L22 40C20 44 26 46 28 42L30 44C32 48 36 46 36 44L38 46C40 48 44 46 42 42L44 44C46 46 50 44 48 40L54 36Z', '#C98A5C') + r(0, 26, 8, 14, 2, B) + r(56, 26, 8, 14, 2, R),

  // ---- stage ---------------------------------------------------------
  maske: shadow(20) + p('M8 14C16 10 26 10 32 14V30C32 42 22 48 18 48C14 48 8 42 8 30Z', Y) + fc(15, 26, 2.5, K) + fc(25, 26, 2.5, K) + p('M14 36C18 40 22 40 26 36', 'none') + p('M32 22C38 18 48 18 56 22V36C56 48 48 54 44 54C40 54 32 48 32 36Z', P) + fc(39, 32, 2.5, K) + fc(49, 32, 2.5, K) + p('M39 46C43 42 47 42 50 46', 'none'),
  perde: r(4, 4, 56, 6, 2, Y) + p('M6 10H28C26 26 22 40 26 56H6Z', R) + p('M58 10H36C38 26 42 40 38 56H58Z', R) + p('M12 10V56M20 10C18 26 18 40 20 56M52 10V56M44 10C46 26 46 40 44 56', 'none') + star(32, 36, 6, 2.6, Y),
  spot: shadow(16) + fp('M24 26L4 60H44Z', Y, 0.35) + `<g transform="rotate(-30 32 20)">${r(22, 10, 22, 18, 3, N)}${e(44, 19, 3, 9, Y)}</g>` + p('M30 30L26 40H38L34 30', 'none'),

  // ---- detective -----------------------------------------------------
  buyutec: shadow(16) + p('M38 38L56 56', 'none') + `<path d="M40 40L55 55" stroke="${BR}" stroke-width="6" stroke-linecap="round"/>` + c(26, 26, 16, LG) + hl('M18 22C19 18 22 15 26 14'),
  ayak_izi: [ [22, 42, -12], [42, 22, 12] ].map(([x, y, a]) => `<g transform="rotate(${a} ${x} ${y})">${e(x, y, 7, 10, BR)}${fc(x - 5, y - 13, 2.5, BR)}${fc(x - 1, y - 15, 2.5, BR)}${fc(x + 4, y - 14, 2.5, BR)}</g>`).join(''),
  fotr: shadow(24) + e(32, 44, 28, 8, BR) + p('M14 42C14 28 18 16 32 16C46 16 50 28 50 42Z', BR) + p('M14 36C24 40 40 40 50 36V42C40 46 24 46 14 42Z', K) + p('M26 16C30 20 34 20 38 16', 'none'),
  parmak_izi: [6, 11, 16, 21].map((rr) => `<path d="M${32 - rr} ${34 + rr * 0.2}C${32 - rr} ${34 - rr * 1.4} ${32 + rr} ${34 - rr * 1.4} ${32 + rr} ${34 + rr * 0.2}${rr > 10 ? `C${32 + rr} ${34 + rr} ${32 + rr * 0.5} ${34 + rr * 1.1} ${32 + rr * 0.2} ${34 + rr * 1.2}` : ''}" fill="none" stroke="${P}" stroke-width="3" stroke-linecap="round"/>`).join('') + `<path d="M32 34V48" fill="none" stroke="${P}" stroke-width="3" stroke-linecap="round"/>`,
  kasa: shadow(22) + r(8, 8, 48, 46, 5, GR) + r(14, 14, 36, 34, 3, LG) + c(32, 31, 9, W) + [0, 1, 2, 3].map((i) => l(32 + Math.cos(i * 1.57) * 4, 31 + Math.sin(i * 1.57) * 4, 32 + Math.cos(i * 1.57) * 9, 31 + Math.sin(i * 1.57) * 9)).join('') + r(42, 26, 4, 10, 1, K),

  // ---- possibilities -------------------------------------------------
  zar: shadow(20) + p('M10 22L32 12L54 22V44L32 54L10 44Z', W) + p('M10 22L32 32L54 22M32 32V54', 'none') + fc(32, 21, 2.5, R) + fc(19, 34, 2.2, K) + fc(24, 42, 2.2, K) + fc(40, 36, 2.2, K) + fc(46, 44, 2.2, K) + fc(43, 40, 2.2, K),
  yol_ayrimi: shadow(16) + `<path d="M32 58V36L16 14M32 36L48 14" fill="none" stroke="${GR}" stroke-width="10" stroke-linecap="round"/>` + `<path d="M32 58V36L16 14M32 36L48 14" fill="none" stroke="${W}" stroke-width="1.6" stroke-dasharray="3 3"/>` + l(52, 30, 52, 50) + p('M44 24H58V32H44Z', Y),
  madeni_para: shadow(18) + e(32, 32, 20, 22, Y) + e(32, 32, 14, 16, O) + `<text x="32" y="39" font-family="Arial, sans-serif" font-weight="700" font-size="18" text-anchor="middle" fill="${CR}">1</text>`,
  yonca: shadow(12) + p('M32 34C34 44 36 50 42 56', 'none') + c(24, 20, 9, G) + c(40, 20, 9, G) + c(24, 34, 9, G) + c(40, 34, 9, G) + fc(32, 27, 4, G) + p('M32 27L26 21M32 27L38 21M32 27L26 33M32 27L38 33', 'none'),

  // ---- repairs -------------------------------------------------------
  ingiliz_anahtari: shadow(16) + `<g transform="rotate(-45 32 32)">${r(28, 18, 8, 40, 4, GR)}${p('M22 6C22 16 26 20 32 20C38 20 42 16 42 6L37 6V12H27V6Z', GR)}</g>`,
  boya_rulosu: shadow(14) + r(8, 8, 40, 14, 6, B) + p('M48 15H54V28H32V38', 'none') + r(28, 38, 8, 20, 3, BR) + fp('M12 22C12 28 16 28 16 24C16 28 20 30 20 22Z', B),
  makas: shadow(16) + c(18, 46, 7, 'none') + c(32, 50, 7, 'none') + p('M22 40L48 8M28 44L54 16', 'none') + fp('M22 40L48 8L46 18L28 44Z', GR, 0.5) + c(18, 46, 7, R) + c(32, 50, 7, R) + fc(18, 46, 3, W) + fc(32, 50, 3, W),
  araba: shadow(26) + p('M6 40V32C6 30 8 28 10 28L18 18H42L52 28C56 28 58 30 58 34V40Z', T) + p('M22 22H30V28H16ZM34 22H40L46 28H34Z', W) + c(18, 42, 6, K) + c(46, 42, 6, K) + fc(18, 42, 2, LG) + fc(46, 42, 2, LG),
  alet_cantasi: shadow(24) + p('M22 20V14C22 12 24 11 26 11H38C40 11 42 12 42 14V20', 'none') + r(6, 20, 52, 34, 4, R) + p('M6 32H58', 'none') + r(26, 28, 12, 8, 2, GR),

  // ---- interview -----------------------------------------------------
  cv: shadow(20) + r(12, 6, 40, 50, 3, W) + c(24, 18, 5, SK) + p('M17 28C17 24 31 24 31 28', B) + [20, 24].map((y) => l(36, y - 4, 46, y - 4)).join('') + [34, 40, 46].map((y) => l(18, y, 46, y)).join(''),
  kravat: shadow(12) + p('M24 6H40L36 14H28Z', B) + p('M28 14H36L42 46L32 58L22 46Z', R) + l(26, 30, 38, 26) + l(25, 40, 40, 34),
  mulakat_masasi: shadow(28) + r(4, 34, 56, 6, 2, BR) + l(10, 40, 10, 58) + l(54, 40, 54, 58) + r(12, 26, 14, 8, 1, W) + p('M38 34V24H50V34', B) + c(44, 18, 6, SK),

  // ---- hotel ---------------------------------------------------------
  resepsiyon_zili: shadow(24) + r(6, 46, 52, 8, 3, BR) + p('M12 46C12 30 22 22 32 22C42 22 52 30 52 46Z', Y) + c(32, 18, 4, Y) + hl('M18 38C19 32 22 28 27 26'),
  havlu: shadow(22) + r(10, 14, 44, 40, 4, T) + r(10, 22, 44, 6, 0, W) + r(10, 40, 44, 6, 0, W) + p('M22 6H42L44 14H20Z', PK) + fc(32, 10, 2, W),
  kapi_askisi: shadow(14) + p('M18 22V54C18 56 20 58 22 58H42C44 58 46 56 46 54V22C46 14 40 6 32 6C24 6 18 14 18 22Z', P) + c(32, 18, 6, W) + `<text x="32" y="44" font-family="Arial, sans-serif" font-weight="700" font-size="10" text-anchor="middle" fill="${W}">Zzz</text>`,

  // ---- code ----------------------------------------------------------
  terminal: shadow(24) + r(6, 10, 52, 44, 5, N) + p('M6 15C6 12 8 10 11 10H53C56 10 58 12 58 15V20H6Z', GR) + fc(12, 15, 2, R) + fc(18, 15, 2, Y) + fc(24, 15, 2, G) + `<path d="M14 30L22 36L14 42M28 42H42" fill="none" stroke="${G}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`,
  kod: `<path d="M22 14L8 32L22 50M42 14L56 32L42 50" fill="none" stroke="${B}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>` + `<path d="M36 10L28 54" fill="none" stroke="${O}" stroke-width="6" stroke-linecap="round"/>`,
  bocek: shadow(16) + p('M20 26L8 20M20 36H6M22 46L10 54M44 26L56 20M44 36H58M42 46L54 54M26 16L22 8M38 16L42 8', 'none') + e(32, 36, 14, 18, G) + c(32, 18, 8, K) + l(32, 22, 32, 54) + fc(26, 32, 3, K) + fc(38, 42, 3, K),
  git_dali: `<path d="M18 10V54M18 40C18 28 46 32 46 18" fill="none" stroke="${K}" stroke-width="4" stroke-linecap="round"/>` + c(18, 12, 6, O) + c(18, 52, 6, O) + c(46, 16, 6, T),

  // ---- costumes (hats, drawn to sit on the mascot) -------------------
  sapka_asci: p('M18 44V32C10 32 8 22 14 18C16 10 26 8 30 14C34 6 46 8 46 16C54 16 56 28 46 32V44Z', W) + r(16, 42, 32, 10, 2, W) + l(26, 32, 26, 42) + l(38, 32, 38, 42),
  sapka_kaptan: p('M10 34C10 22 20 14 32 14C44 14 54 22 54 34Z', W) + r(10, 34, 44, 8, 2, N) + p('M10 42C20 50 44 50 54 42', N) + c(32, 26, 4, Y),
  sapka_kask: p('M8 42C8 26 18 16 32 16C46 16 56 26 56 42Z', Y) + r(4, 40, 56, 6, 3, Y) + p('M28 16V30M36 16V30', 'none'),
  sapka_parti: p('M20 52L32 8L44 52Z', PK) + p('M24 38L40 34M22 46L42 42', 'none') + c(32, 8, 4, Y) + e(32, 52, 14, 4, Y),
  sapka_bere: p('M8 40C6 26 22 16 38 18C52 20 60 30 54 40Z', R) + r(10, 38, 44, 6, 3, R) + l(36, 18, 38, 12),
  sapka_hasir: e(32, 42, 28, 8, Y) + p('M18 40C18 28 22 20 32 20C42 20 46 28 46 40Z', Y) + p('M18 34C26 37 38 37 46 34V40C38 43 26 43 18 40Z', R),
};

/** Small objects used as a band pattern: drawn single-colour by the app. */
export const BAND_ONLY = new Set(['kasik_catal']);
