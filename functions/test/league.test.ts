import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import {
  addLeagueXp,
  groupIdOf,
  joinLeague,
  LEAGUE_SIZE,
  MAX_XP_PER_DAY,
  nextTier,
  parseJoinInput,
  rankMembers,
  settleFinishedWeeks,
} from "../src/league.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const WEEK1 = new Date("2026-11-10T09:00:00Z"); // week 2026-11-09
const WEEK2 = new Date("2026-11-17T09:00:00Z"); // week 2026-11-16
const later = (d: Date, s: number) => new Date(d.getTime() + s * 1000);
const input = (name: string, tier: number | null = null) => ({ name, avatar: "🦊", tier });

beforeEach(clearFirestore);

test("parseJoinInput cleans names and validates tier", () => {
  assert.deepEqual(parseJoinInput({ name: "  Ayşe\n K. ", tier: 2 }), { name: "Ayşe K.", avatar: "⭐", tier: 2 });
  assert.equal(parseJoinInput({}).name, "Lingora öğrencisi");
  assert.equal(parseJoinInput({ name: "x".repeat(50) }).name.length, 24);
  assert.throws(() => parseJoinInput({ tier: 5 }));
  assert.throws(() => parseJoinInput({ tier: 1.5 }));
  assert.throws(() => parseJoinInput({ name: "   " }));
});

test("zones match the local league rules", () => {
  assert.equal(nextTier(0, 1, 10), 1);
  assert.equal(nextTier(0, 5, 10), 1);
  assert.equal(nextTier(0, 1, 0), 0); // no XP, no promotion
  assert.equal(nextTier(0, 15, 0), 0); // Bronz cannot drop
  assert.equal(nextTier(2, 11, 50), 1);
  assert.equal(nextTier(2, 10, 50), 2);
  assert.equal(nextTier(4, 1, 999), 4); // Elmas is the top
  const ranked = rankMembers([
    { uid: "a", xp: 5, joinedAt: 2 },
    { uid: "b", xp: 9, joinedAt: 3 },
    { uid: "c", xp: 5, joinedAt: 1 },
  ]);
  assert.deepEqual(
    ranked.map((m) => m.uid),
    ["b", "c", "a"],
  );
});

test("joinLeague is idempotent and fills groups of 15", async () => {
  const first = await joinLeague(db, "u0", input("U0"), WEEK1);
  assert.deepEqual(first, { groupId: groupIdOf("2026-11-09", 0, 0), weekKey: "2026-11-09", tier: 0 });
  assert.deepEqual(await joinLeague(db, "u0", input("U0"), WEEK1), first);

  for (let i = 1; i < LEAGUE_SIZE; i++) await joinLeague(db, `u${i}`, input(`U${i}`), WEEK1);
  const overflow = await joinLeague(db, "u15", input("U15"), WEEK1);
  assert.equal(overflow.groupId, groupIdOf("2026-11-09", 0, 1));

  const g0 = await db.doc(`leagues/${first.groupId}`).get();
  assert.equal(g0.get("size"), LEAGUE_SIZE);
  assert.equal((await db.collection(`leagues/${first.groupId}/members`).get()).size, LEAGUE_SIZE);
});

test("joinLeague takes the offline tier only for new users and updates the name", async () => {
  const r = await joinLeague(db, "u", input("Old", 3), WEEK1);
  assert.equal(r.tier, 3);
  await joinLeague(db, "u", { name: "New", avatar: "🐼", tier: 0 }, WEEK1);
  const m = await db.doc(`leagues/${r.groupId}/members/u`).get();
  assert.equal(m.get("name"), "New");
  assert.equal(m.get("avatar"), "🐼");
  assert.equal((await db.doc("leagueState/u").get()).get("tier"), 3);
});

test("addLeagueXp validates, rate-limits and caps per day", async () => {
  await rejectsWith(addLeagueXp(db, "u", { xp: 10 }, WEEK1), "failed-precondition");
  const { groupId } = await joinLeague(db, "u", input("U"), WEEK1);
  await rejectsWith(addLeagueXp(db, "u", { xp: 0 }, WEEK1), "invalid-argument");
  await rejectsWith(addLeagueXp(db, "u", { xp: 501 }, WEEK1), "invalid-argument");
  await rejectsWith(addLeagueXp(db, "u", { xp: "5" }, WEEK1), "invalid-argument");

  assert.deepEqual(await addLeagueXp(db, "u", { xp: 30 }, WEEK1), { xp: 30, accepted: 30 });
  await rejectsWith(addLeagueXp(db, "u", { xp: 30 }, later(WEEK1, 1)), "resource-exhausted");

  let t = WEEK1;
  let total = 30;
  while (total < MAX_XP_PER_DAY) {
    t = later(t, 5);
    total = (await addLeagueXp(db, "u", { xp: 500 }, t)).xp;
  }
  assert.equal(total, MAX_XP_PER_DAY);
  assert.deepEqual(await addLeagueXp(db, "u", { xp: 10 }, later(t, 5)), { xp: MAX_XP_PER_DAY, accepted: 0 });
  // The cap resets on the next Turkish day.
  const nextDay = new Date("2026-11-11T09:00:00Z");
  assert.equal((await addLeagueXp(db, "u", { xp: 10 }, nextDay)).accepted, 10);
  assert.equal((await db.doc(`leagues/${groupId}/members/u`).get()).get("xp"), MAX_XP_PER_DAY + 10);
});

test("weekly settlement promotes, demotes and stores results", async () => {
  // A full Gümüş (tier 1) group: u0 has the most XP, u14 none.
  for (let i = 0; i < LEAGUE_SIZE; i++) {
    await joinLeague(db, `u${i}`, input(`U${i}`, 1), WEEK1);
    if (i < 14) await addLeagueXp(db, `u${i}`, { xp: 300 - i * 10 }, later(WEEK1, i));
  }
  // Still the same week: nothing settles.
  assert.equal(await settleFinishedWeeks(db, later(WEEK1, 3600)), 0);
  assert.equal(await settleFinishedWeeks(db, WEEK2), 1);
  assert.equal(await settleFinishedWeeks(db, WEEK2), 0); // idempotent

  const state = async (uid: string) => (await db.doc(`leagueState/${uid}`).get()).data()!;
  assert.deepEqual((await state("u0")).lastResult, { weekKey: "2026-11-09", oldTier: 1, newTier: 2, rank: 1 });
  assert.equal((await state("u4")).tier, 2);
  assert.equal((await state("u5")).tier, 1);
  assert.equal((await state("u10")).tier, 0);
  assert.deepEqual((await state("u14")).lastResult, { weekKey: "2026-11-09", oldTier: 1, newTier: 0, rank: 15 });
  assert.equal((await state("u0")).groupId, null);

  // Next week u0 plays in Altın.
  const next = await joinLeague(db, "u0", input("U0"), WEEK2);
  assert.deepEqual(next, { groupId: groupIdOf("2026-11-16", 2, 0), weekKey: "2026-11-16", tier: 2 });
});

test("joining a new week settles the old group if the scheduler has not", async () => {
  await joinLeague(db, "a", input("A"), WEEK1);
  await addLeagueXp(db, "a", { xp: 50 }, WEEK1);
  const r = await joinLeague(db, "a", input("A"), WEEK2);
  assert.equal(r.tier, 1); // rank 1 of 1 with XP -> promoted
  assert.equal((await db.doc(`leagues/${groupIdOf("2026-11-09", 0, 0)}`).get()).get("settled"), true);
});
