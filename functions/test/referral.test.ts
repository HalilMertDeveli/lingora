import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { verifyPurchase } from "../src/purchase.js";
import {
  MAX_REWARDS_PER_MONTH,
  REWARD_DAYS,
  completeInviteReward,
  getInviteCode,
  inviteStatus,
  lessonsDoneOf,
  monthKey,
  normalizeCode,
  redeemInvite,
} from "../src/referral.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const DAY = 24 * 60 * 60 * 1000;
const now = new Date("2026-11-10T09:00:00Z");
const ctx = (over: Partial<{ now: Date; accountCreatedAt: Date; signInProvider: string }> = {}) => ({
  now,
  accountCreatedAt: new Date(now.getTime() - DAY),
  signInProvider: "password",
  ...over,
});
const device = (n: number | string) => `device-${n}-0123456789`;

/** The friend's synced progress after their first lesson. */
async function firstLesson(uid: string, at = now) {
  await db.doc(`users/${uid}`).set({ progress: { lessonsDone: 1 } }, { merge: true });
  return completeInviteReward(db, uid, at);
}

/** Redeems and finishes the first lesson. */
async function redeemAndLearn(uid: string, code: string, dev: string, c = ctx()) {
  const r = await redeemInvite(db, uid, { code, deviceId: dev }, c);
  assert.equal(r.status, "pending");
  return firstLesson(uid, c.now);
}

beforeEach(clearFirestore);

test("month key uses Turkish time", () => {
  assert.equal(monthKey(new Date("2026-11-30T20:59:00Z")), "2026-11");
  assert.equal(monthKey(new Date("2026-11-30T21:00:00Z")), "2026-12");
});

test("codes are normalised and validated", () => {
  assert.equal(normalizeCode(" abc-23 45 "), "ABC2345");
  assert.throws(() => normalizeCode("ABC0123"), /invalid_code/); // 0 and 1 are not in the alphabet
  assert.throws(() => normalizeCode("SHORT"), /invalid_code/);
  assert.throws(() => normalizeCode(42), /invalid_code/);
});

test("getInviteCode creates one stable code per user", async () => {
  const a = await getInviteCode(db, "alice", now);
  assert.match(a.code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{7}$/);
  assert.equal(a.rewardDays, REWARD_DAYS);
  assert.equal(a.maxPerMonth, MAX_REWARDS_PER_MONTH);
  assert.equal(a.rewardedThisMonth, 0);
  assert.deepEqual(await getInviteCode(db, "alice", now), a);
  assert.equal((await db.doc(`inviteCodes/${a.code}`).get()).get("uid"), "alice");
  const b = await getInviteCode(db, "bob", now);
  assert.notEqual(b.code, a.code);
});

test("both users get 7 days of Premium after the friend's first lesson", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  const r = await redeemInvite(db, "bob", { code: code.toLowerCase(), deviceId: device(1) }, ctx());
  assert.equal(r.ok, true);
  assert.equal(r.status, "pending");
  assert.equal(r.expiresAt, undefined);
  assert.equal((await inviteStatus(db, "bob")).status, "pending");
  // Nothing yet: bob has not finished a lesson.
  assert.equal((await db.doc("entitlements/bob").get()).exists, false);
  assert.equal((await db.doc("entitlements/alice").get()).exists, false);
  assert.equal(await completeInviteReward(db, "bob", now), null);

  const reward = await firstLesson("bob");
  assert.deepEqual(reward, { expiresAt: now.getTime() + REWARD_DAYS * DAY, inviterRewarded: true });
  for (const uid of ["alice", "bob"]) {
    const e = (await db.doc(`entitlements/${uid}`).get()).data()!;
    assert.equal(e.active, true);
    assert.equal(e.source, "invite");
    assert.equal(e.productId, "referral");
    assert.equal((e.expiresAt as Timestamp).toMillis(), now.getTime() + REWARD_DAYS * DAY);
  }
  assert.equal((await inviteStatus(db, "bob")).status, "rewarded");
  const info = await getInviteCode(db, "alice", now);
  assert.equal(info.rewardedThisMonth, 1);
  assert.equal(info.totalRewarded, 1);
  // Idempotent: a second sync does not add another week.
  assert.equal(await firstLesson("bob"), null);
  const e = (await db.doc("entitlements/bob").get()).data()!;
  assert.equal((e.expiresAt as Timestamp).toMillis(), now.getTime() + REWARD_DAYS * DAY);
});

test("a friend who already finished a lesson is rewarded at once", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  await db.doc("users/bob").set({ progress: { lessonsDone: 3 } });
  const r = await redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx());
  assert.equal(r.status, "rewarded");
  assert.equal(r.inviterRewarded, true);
  assert.equal(r.expiresAt, now.getTime() + REWARD_DAYS * DAY);
  assert.equal((await db.doc("entitlements/alice").get()).get("source"), "invite");
  assert.equal(await completeInviteReward(db, "bob", now), null);
});

test("lessonsDoneOf reads the synced progress snapshot", () => {
  assert.equal(lessonsDoneOf(undefined), 0);
  assert.equal(lessonsDoneOf({}), 0);
  assert.equal(lessonsDoneOf({ progress: { lessonsDone: "5" } }), 0);
  assert.equal(lessonsDoneOf({ progress: { lessonsDone: 2 } }), 2);
});

test("an invite redeemed before this rule counts as rewarded", async () => {
  await db.doc("referralRedemptions/old").set({ inviterUid: "alice", code: "ABCDEFG", inviterRewarded: true });
  assert.equal((await inviteStatus(db, "old")).status, "rewarded");
  assert.equal(await completeInviteReward(db, "old", now), null);
  assert.equal((await inviteStatus(db, "nobody")).status, "none");
});

test("a friend cannot redeem on the inviter's own phone", async () => {
  const { code } = await getInviteCode(db, "alice", now, device("alice-phone"));
  await rejectsWith(
    redeemInvite(db, "bob", { code, deviceId: device("alice-phone") }, ctx()),
    "failed-precondition",
    "same_device",
  );
  // A phone alice uses later is remembered too.
  await getInviteCode(db, "alice", now, device("alice-tablet"));
  await rejectsWith(
    redeemInvite(db, "bob", { code, deviceId: device("alice-tablet") }, ctx()),
    "failed-precondition",
    "same_device",
  );
  const r = await redeemInvite(db, "bob", { code, deviceId: device("bob-phone") }, ctx());
  assert.equal(r.status, "pending");
});

test("the inviter's device list stays small", async () => {
  for (let i = 0; i < 8; i++) await getInviteCode(db, "alice", now, device(`a${i}`));
  const hashes = (await db.doc("referrals/alice").get()).get("deviceHashes") as string[];
  assert.equal(hashes.length, 5);
});

test("one redemption per account and per device", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  const other = (await getInviteCode(db, "carol", now)).code;
  await redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx());
  await rejectsWith(redeemInvite(db, "bob", { code: other, deviceId: device(2) }, ctx()), "already-exists", "already_redeemed");
  await rejectsWith(redeemInvite(db, "dave", { code, deviceId: device(1) }, ctx()), "already-exists", "device_used");
});

test("rejects own code, unknown codes, mutual invites, old and anonymous accounts", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  await rejectsWith(redeemInvite(db, "alice", { code, deviceId: device(1) }, ctx()), "failed-precondition", "own_code");
  await rejectsWith(redeemInvite(db, "bob", { code: "ZZZZZZZ", deviceId: device(1) }, ctx()), "not-found", "unknown_code");
  await rejectsWith(redeemInvite(db, "bob", { code, deviceId: "x" }, ctx()), "invalid-argument", "invalid_device");
  await rejectsWith(
    redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx({ signInProvider: "anonymous" })),
    "failed-precondition",
    "sign_in_required",
  );
  await rejectsWith(
    redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx({ accountCreatedAt: new Date(now.getTime() - 30 * DAY) })),
    "failed-precondition",
    "not_new_user",
  );
  // bob redeems alice's code; alice may not then redeem bob's.
  await redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx());
  const bobCode = (await getInviteCode(db, "bob", now)).code;
  await rejectsWith(
    redeemInvite(db, "alice", { code: bobCode, deviceId: device(2) }, ctx()),
    "failed-precondition",
    "mutual_invite",
  );
  // Nothing was written for the rejected attempts.
  assert.equal((await db.doc("referralRedemptions/alice").get()).exists, false);
});

test("an inviter earns at most MAX_REWARDS_PER_MONTH rewards a month", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  for (let i = 0; i < MAX_REWARDS_PER_MONTH + 1; i++) {
    const r = await redeemAndLearn(`friend${i}`, code, device(i));
    assert.equal(r?.inviterRewarded, i < MAX_REWARDS_PER_MONTH, `friend${i}`);
    // The new user is always rewarded.
    assert.equal((await db.doc(`entitlements/friend${i}`).get()).get("active"), true);
  }
  const alice = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal((alice.expiresAt as Timestamp).toMillis(), now.getTime() + MAX_REWARDS_PER_MONTH * REWARD_DAYS * DAY);
  assert.equal(alice.referralDays, MAX_REWARDS_PER_MONTH * REWARD_DAYS);

  // Next month the counter starts again.
  const later = new Date("2026-12-02T09:00:00Z");
  const r = await redeemAndLearn("next", code, device("next"), ctx({ now: later, accountCreatedAt: later }));
  assert.equal(r?.inviterRewarded, true);
});

test("a running paid subscription is extended, not replaced", async () => {
  await verifyPurchase(db, "alice", { productId: "lingora_premium_monthly", purchaseToken: "test-token-0123456789" }, {
    testMode: true,
    now,
  });
  const paidUntil = ((await db.doc("entitlements/alice").get()).get("expiresAt") as Timestamp).toMillis();
  const { code } = await getInviteCode(db, "alice", now);
  await redeemAndLearn("bob", code, device(1));
  const e = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal(e.source, "test");
  assert.equal(e.productId, "lingora_premium_monthly");
  assert.equal((e.expiresAt as Timestamp).toMillis(), paidUntil + REWARD_DAYS * DAY);
});

test("a longer open-ended Premium is never shortened", async () => {
  await db.doc("entitlements/alice").set({ active: true, premium: true, source: "test", productId: "lifetime" });
  const { code } = await getInviteCode(db, "alice", now);
  await redeemAndLearn("bob", code, device(1));
  const e = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal(e.expiresAt, undefined);
  assert.equal(e.productId, "lifetime");
});

test("an expired invite Premium restarts from today", async () => {
  await db.doc("entitlements/alice").set({
    active: true,
    source: "invite",
    productId: "referral",
    expiresAt: Timestamp.fromMillis(now.getTime() - DAY),
  });
  const { code } = await getInviteCode(db, "alice", now);
  await redeemAndLearn("bob", code, device(1));
  const e = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal((e.expiresAt as Timestamp).toMillis(), now.getTime() + REWARD_DAYS * DAY);
});
