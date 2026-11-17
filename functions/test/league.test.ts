import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import {
  addLeagueXp,
  GROUP_SIZE,
  groupIdOf,
  joinLeague,
  leaveLeague,
  MAX_XP_PER_DAY,
  MAX_XP_PER_MINUTE,
  nextTier,
  parseJoinInput,
  parseLook,
  rankMembers,
  settleFinishedWeeks,
  TIER_COUNT,
  zones,
} from "../src/league.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const WEEK1 = new Date("2026-11-10T09:00:00Z"); // week 2026-11-09
const WEEK2 = new Date("2026-11-17T09:00:00Z"); // week 2026-11-16
const later = (d: Date, s: number) => new Date(d.getTime() + s * 1000);
const input = (name: string, country: string | null = "TR") => ({ name, avatar: "🦊", country, photo: null, look: null });
/** A tiny valid-looking JPEG: FF D8 FF and padding. */
const jpeg = (n = 200) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(n - 4, 1)]);

beforeEach(clearFirestore);

test("parseJoinInput cleans names and checks country and photo", () => {
  assert.deepEqual(parseJoinInput({ name: "  Ayşe\n K. ", country: "DE" }), {
    name: "Ayşe K.",
    avatar: "⭐",
    country: "DE",
    photo: null,
    look: null,
  });
  assert.equal(parseJoinInput({}).name, "Dilmaç öğrencisi");
  assert.equal(parseJoinInput({}).country, null);
  assert.equal(parseJoinInput({ name: "x".repeat(50) }).name.length, 24);
  assert.throws(() => parseJoinInput({ name: "   " }));
  assert.throws(() => parseJoinInput({ country: "tr" }));
  assert.throws(() => parseJoinInput({ country: "TUR" }));

  const photo = jpeg();
  assert.deepEqual(parseJoinInput({ photo: photo.toString("base64") }).photo, photo);
  assert.throws(() => parseJoinInput({ photo: Buffer.alloc(200, 7).toString("base64") })); // not a JPEG
  assert.throws(() => parseJoinInput({ photo: jpeg(9000).toString("base64") })); // too big
  assert.throws(() => parseJoinInput({ photo: 42 }));
});

test("zones: 15/10 up, 0/5/10 down, scaled for small groups", () => {
  assert.deepEqual(zones(0), { promote: 15, demote: 0 });
  assert.deepEqual(zones(2), { promote: 15, demote: 5 });
  assert.deepEqual(zones(3), { promote: 10, demote: 5 });
  assert.deepEqual(zones(5), { promote: 10, demote: 10 });
  assert.deepEqual(zones(TIER_COUNT - 1), { promote: 0, demote: 10 });
  // A group of 3 still sends its winner up and nobody down.
  assert.deepEqual(zones(4, 3), { promote: 1, demote: 0 });
  assert.deepEqual(zones(6, 20), { promote: 2, demote: 2 });
  assert.deepEqual(zones(6, 1), { promote: 1, demote: 0 });

  assert.equal(nextTier(0, 15, 10), 1);
  assert.equal(nextTier(0, 16, 10), 0);
  assert.equal(nextTier(0, 1, 0), 0); // no XP, no promotion
  assert.equal(nextTier(0, 100, 0), 0); // Bronz cannot drop
  assert.equal(nextTier(3, 95, 50), 3);
  assert.equal(nextTier(3, 96, 50), 2);
  assert.equal(nextTier(TIER_COUNT - 1, 1, 999), TIER_COUNT - 1); // Elmas is the top

  const ranked = rankMembers([
    { uid: "a", xp: 5, reachedAt: 2 },
    { uid: "b", xp: 9, reachedAt: 3 },
    { uid: "c", xp: 5, reachedAt: 1 },
  ]);
  assert.deepEqual(
    ranked.map((m) => m.uid),
    ["b", "c", "a"],
  );
});

test("joinLeague is idempotent, starts in Bronz and fills groups of 100", async () => {
  const first = await joinLeague(db, "u0", input("U0"), WEEK1);
  assert.deepEqual(first, { groupId: groupIdOf("2026-11-09", 0, 0), weekKey: "2026-11-09", tier: 0 });
  assert.deepEqual(await joinLeague(db, "u0", input("U0"), WEEK1), first);

  const countries = ["TR", "DE", "US", "AZ", "NL"];
  for (let i = 1; i < GROUP_SIZE; i++) {
    await joinLeague(db, `u${i}`, input(`U${i}`, countries[i % countries.length]), WEEK1);
  }
  const overflow = await joinLeague(db, "u100", input("U100"), WEEK1);
  assert.equal(overflow.groupId, groupIdOf("2026-11-09", 0, 1));

  const g0 = await db.doc(`leagues/${first.groupId}`).get();
  assert.equal(g0.get("size"), GROUP_SIZE);
  const members = await db.collection(`leagues/${first.groupId}/members`).get();
  assert.equal(members.size, GROUP_SIZE);
  // People from every country share one group.
  assert.deepEqual(new Set(members.docs.map((m) => m.get("country"))), new Set(countries));
});

test("joinLeague keeps the profile row up to date", async () => {
  const r = await joinLeague(db, "u", input("Old"), WEEK1);
  const photo = jpeg();
  await joinLeague(db, "u", { name: "New", avatar: "🐼", country: "DE", photo, look: null }, WEEK1);
  const m = await db.doc(`leagues/${r.groupId}/members/u`).get();
  assert.equal(m.get("name"), "New");
  assert.equal(m.get("avatar"), "🐼");
  assert.equal(m.get("country"), "DE");
  assert.deepEqual(Buffer.from(m.get("photo")), photo);
  await joinLeague(db, "u", { name: "New", avatar: "🐼", country: "DE", photo: null, look: null }, WEEK1);
  assert.equal((await db.doc(`leagues/${r.groupId}/members/u`).get()).get("photo"), null);
});

test("addLeagueXp takes the weekly total, never counts twice and caps per minute and day", async () => {
  await rejectsWith(addLeagueXp(db, "u", { weekXp: 10 }, WEEK1), "failed-precondition");
  const { groupId } = await joinLeague(db, "u", input("U"), WEEK1);
  await rejectsWith(addLeagueXp(db, "u", { weekXp: -1 }, WEEK1), "invalid-argument");
  await rejectsWith(addLeagueXp(db, "u", { weekXp: "5" }, WEEK1), "invalid-argument");
  await rejectsWith(addLeagueXp(db, "u", { weekXp: 1.5 }, WEEK1), "invalid-argument");
  await rejectsWith(addLeagueXp(db, "u", { weekXp: 5, weekKey: "2026-11-02" }, WEEK1), "failed-precondition");

  assert.deepEqual(await addLeagueXp(db, "u", { weekXp: 30, weekKey: "2026-11-09" }, WEEK1), {
    xp: 30,
    accepted: 30,
    pending: 0,
  });
  // The same total again (a retry) adds nothing, even right away.
  assert.deepEqual(await addLeagueXp(db, "u", { weekXp: 30 }, later(WEEK1, 1)), { xp: 30, accepted: 0, pending: 0 });
  await rejectsWith(addLeagueXp(db, "u", { weekXp: 40 }, later(WEEK1, 1)), "resource-exhausted");

  // A jump of 1000 XP: only the rest of this minute's allowance goes in.
  const t1 = later(WEEK1, 3);
  const r1 = await addLeagueXp(db, "u", { weekXp: 1030 }, t1);
  assert.equal(r1.accepted, MAX_XP_PER_MINUTE - 30);
  assert.equal(r1.pending, 1030 - MAX_XP_PER_MINUTE);
  assert.equal((await addLeagueXp(db, "u", { weekXp: 1030 }, later(t1, 10))).accepted, 0);
  // Next minute: another 300.
  assert.equal((await addLeagueXp(db, "u", { weekXp: 1030 }, later(t1, 61))).xp, 2 * MAX_XP_PER_MINUTE);

  let t = later(t1, 61);
  let total = 2 * MAX_XP_PER_MINUTE;
  for (let i = 0; i < 20 && total < MAX_XP_PER_DAY; i++) {
    t = later(t, 61);
    total = (await addLeagueXp(db, "u", { weekXp: 99999 }, t)).xp;
  }
  assert.equal(total, MAX_XP_PER_DAY);
  assert.deepEqual(await addLeagueXp(db, "u", { weekXp: 99999 }, later(t, 61)), {
    xp: MAX_XP_PER_DAY,
    accepted: 0,
    pending: 99999 - MAX_XP_PER_DAY,
  });
  // The daily cap resets on the next Turkish day.
  const nextDay = new Date("2026-11-11T09:00:00Z");
  assert.equal((await addLeagueXp(db, "u", { weekXp: MAX_XP_PER_DAY + 10 }, nextDay)).accepted, 10);
  assert.equal((await db.doc(`leagues/${groupId}/members/u`).get()).get("xp"), MAX_XP_PER_DAY + 10);
});

test("weekly settlement promotes, demotes and stores results", async () => {
  // A Safir (tier 3) group of 20: u0 has the most XP, u19 none.
  // Zones for 20 in Safir: 2 up, 1 down.
  for (let i = 0; i < 20; i++) {
    await db.doc(`leagueState/u${i}`).set({ tier: 3 });
    await joinLeague(db, `u${i}`, input(`U${i}`), WEEK1);
    if (i < 19) await addLeagueXp(db, `u${i}`, { weekXp: 300 - i * 10 }, later(WEEK1, i));
  }
  // Still the same week: nothing settles.
  assert.equal(await settleFinishedWeeks(db, later(WEEK1, 3600)), 0);
  assert.equal(await settleFinishedWeeks(db, WEEK2), 1);
  assert.equal(await settleFinishedWeeks(db, WEEK2), 0); // idempotent

  const state = async (uid: string) => (await db.doc(`leagueState/${uid}`).get()).data()!;
  assert.deepEqual((await state("u0")).lastResult, {
    weekKey: "2026-11-09",
    oldTier: 3,
    newTier: 4,
    rank: 1,
    size: 20,
    xp: 300,
  });
  assert.equal((await state("u1")).tier, 4);
  assert.equal((await state("u2")).tier, 3);
  assert.equal((await state("u18")).tier, 3);
  assert.deepEqual((await state("u19")).lastResult, {
    weekKey: "2026-11-09",
    oldTier: 3,
    newTier: 2,
    rank: 20,
    size: 20,
    xp: 0,
  });
  assert.equal((await state("u0")).groupId, null);

  // Next week u0 plays in Yakut.
  const next = await joinLeague(db, "u0", input("U0"), WEEK2);
  assert.deepEqual(next, { groupId: groupIdOf("2026-11-16", 4, 0), weekKey: "2026-11-16", tier: 4 });
});

test("joining a new week settles the old group if the scheduler has not", async () => {
  await joinLeague(db, "a", input("A"), WEEK1);
  await addLeagueXp(db, "a", { weekXp: 50 }, WEEK1);
  const r = await joinLeague(db, "a", input("A"), WEEK2);
  assert.equal(r.tier, 1); // rank 1 of 1 with XP -> promoted
  assert.equal((await db.doc(`leagues/${groupIdOf("2026-11-09", 0, 0)}`).get()).get("settled"), true);
});

test("leaveLeague removes the row and stops XP until the learner joins again", async () => {
  const { groupId } = await joinLeague(db, "a", input("A"), WEEK1);
  await joinLeague(db, "b", input("B"), WEEK1);
  assert.deepEqual(await leaveLeague(db, "a"), { left: true });
  assert.equal((await db.doc(`leagues/${groupId}/members/a`).get()).exists, false);
  assert.equal((await db.doc(`leagues/${groupId}`).get()).get("size"), 1);
  const s = (await db.doc("leagueState/a").get()).data()!;
  assert.equal(s.optedOut, true);
  await rejectsWith(addLeagueXp(db, "a", { weekXp: 10 }, WEEK1), "failed-precondition");
  assert.deepEqual(await leaveLeague(db, "nobody"), { left: false });

  const again = await joinLeague(db, "a", input("A"), later(WEEK1, 60));
  assert.equal(again.groupId, groupId);
  assert.equal((await db.doc("leagueState/a").get()).get("optedOut"), false);
});

test("parseLook keeps known catalog ids in their slots and drops the rest", () => {
  assert.deepEqual(
    parseLook({ avatar: "av_kedi", frame: "fr_altin", theme: "th_iznik", mascot: "mx_tac", pofuduk: "px_kep", useAvatar: true }),
    { avatar: "av_kedi", frame: "fr_altin", theme: "th_iznik", mascot: "mx_tac", pofuduk: "px_kep", useAvatar: true },
  );
  // Unknown ids, wrong slots and junk are dropped, not refused.
  assert.deepEqual(parseLook({ avatar: "av_bilinmeyen", frame: "av_kedi", theme: 42, mascot: "mx_tac" }), {
    avatar: null,
    frame: null,
    theme: null,
    mascot: "mx_tac",
    pofuduk: null,
    useAvatar: false,
  });
  assert.equal(parseLook("th_iznik"), null);
  assert.equal(parseJoinInput({ look: { theme: "th_lokum" } }).look?.theme, "th_lokum");
});

test("joinLeague stores the worn look on the row and refreshes it", async () => {
  const look = parseLook({ avatar: "av_kedi", theme: "th_iznik", frame: "fr_yok" });
  const seat = await joinLeague(db, "u", { ...input("Ayşe"), look }, WEEK1);
  const row = (await db.doc(`leagues/${seat.groupId}/members/u`).get()).data();
  assert.equal(row?.look?.avatar, "av_kedi");
  assert.equal(row?.look?.theme, "th_iznik");
  assert.equal(row?.look?.frame, null);
  await joinLeague(db, "u", { ...input("Ayşe"), look: parseLook({ theme: "th_lokum" }) }, WEEK1);
  const after = (await db.doc(`leagues/${seat.groupId}/members/u`).get()).data();
  assert.equal(after?.look?.theme, "th_lokum");
  assert.equal(after?.look?.avatar, null);
});
