import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { verifyPurchase } from "../src/purchase.js";
import {
  MAX_REWARDS_PER_MONTH,
  REWARD_DAYS,
  getInviteCode,
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

test("redeeming gives both users 7 days of Premium", async () => {
  const { code } = await getInviteCode(db, "alice", now);
  const r = await redeemInvite(db, "bob", { code: code.toLowerCase(), deviceId: device(1) }, ctx());
  assert.equal(r.ok, true);
  assert.equal(r.inviterRewarded, true);
  assert.equal(r.expiresAt, now.getTime() + REWARD_DAYS * DAY);
  for (const uid of ["alice", "bob"]) {
    const e = (await db.doc(`entitlements/${uid}`).get()).data()!;
    assert.equal(e.active, true);
    assert.equal(e.source, "referral");
    assert.equal(e.productId, "referral");
    assert.equal((e.expiresAt as Timestamp).toMillis(), now.getTime() + REWARD_DAYS * DAY);
  }
  const info = await getInviteCode(db, "alice", now);
  assert.equal(info.rewardedThisMonth, 1);
  assert.equal(info.totalRewarded, 1);
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
    const r = await redeemInvite(db, `friend${i}`, { code, deviceId: device(i) }, ctx());
    assert.equal(r.inviterRewarded, i < MAX_REWARDS_PER_MONTH, `friend${i}`);
    // The new user is always rewarded.
    assert.equal((await db.doc(`entitlements/friend${i}`).get()).get("active"), true);
  }
  const alice = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal((alice.expiresAt as Timestamp).toMillis(), now.getTime() + MAX_REWARDS_PER_MONTH * REWARD_DAYS * DAY);
  assert.equal(alice.referralDays, MAX_REWARDS_PER_MONTH * REWARD_DAYS);

  // Next month the counter starts again.
  const later = new Date("2026-12-02T09:00:00Z");
  const r = await redeemInvite(db, "next", { code, deviceId: device("next") }, ctx({ now: later, accountCreatedAt: later }));
  assert.equal(r.inviterRewarded, true);
});

test("a running paid subscription is extended, not replaced", async () => {
  await verifyPurchase(db, "alice", { productId: "lingora_premium_monthly", purchaseToken: "test-token-0123456789" }, {
    testMode: true,
    now,
  });
  const paidUntil = ((await db.doc("entitlements/alice").get()).get("expiresAt") as Timestamp).toMillis();
  const { code } = await getInviteCode(db, "alice", now);
  await redeemInvite(db, "bob", { code, deviceId: device(1) }, ctx());
  const e = (await db.doc("entitlements/alice").get()).data()!;
  assert.equal(e.source, "test");
  assert.equal(e.productId, "lingora_premium_monthly");
  assert.equal((e.expiresAt as Timestamp).toMillis(), paidUntil + REWARD_DAYS * DAY);
});
