import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { verifyPurchase } from "../src/purchase.js";
import {
  CLIENT_STEPS,
  countActivePremium,
  countFunnel,
  getStats,
  lastDays,
  snapshotPremium,
  statsDayRef,
} from "../src/stats.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const DAY = 24 * 60 * 60 * 1000;
// 23:30 Turkish time on 10 Nov.
const now = new Date("2026-11-10T20:30:00Z");
const owner = { uid: "owner" };

beforeEach(async () => {
  await clearFirestore();
  await db.doc("config/lingoraAdmins").set({ uids: ["owner"] });
});

async function day(key: string) {
  return (await statsDayRef(db, key).get()).data() ?? {};
}

test("countFunnel adds one per call to the Turkish day, nothing else", async () => {
  await countFunnel(db, { step: "first_open" }, now);
  await countFunnel(db, { step: "first_open" }, now);
  await countFunnel(db, { step: "paywall_view" }, now);
  // 21:00 UTC is already the next day in Turkey.
  await countFunnel(db, { step: "first_open" }, new Date("2026-11-10T21:00:00Z"));
  const d = await day("2026-11-10");
  assert.equal(d.first_open, 2);
  assert.equal(d.paywall_view, 1);
  assert.equal(d.day, "2026-11-10");
  assert.deepEqual(Object.keys(d).sort(), ["day", "first_open", "paywall_view", "updatedAt"]);
  assert.equal((await day("2026-11-11")).first_open, 1);
});

test("countFunnel accepts only known steps", async () => {
  for (const step of CLIENT_STEPS) await countFunnel(db, { step }, now);
  await rejectsWith(countFunnel(db, { step: "purchase_verified" }, now), "invalid-argument");
  await rejectsWith(countFunnel(db, { step: "__proto__" }, now), "invalid-argument");
  await rejectsWith(countFunnel(db, null, now), "invalid-argument");
  await rejectsWith(countFunnel(db, { step: 3 }, now), "invalid-argument");
});

test("a verified purchase is counted once, re-verification is not", async () => {
  const opts = { testMode: true, now };
  await verifyPurchase(db, "u1", { productId: "lingora_premium_monthly", purchaseToken: "tok-1-0123456789" }, opts);
  await verifyPurchase(db, "u1", { productId: "lingora_premium_monthly", purchaseToken: "tok-1-0123456789" }, opts);
  await verifyPurchase(db, "u2", { productId: "lingora_premium_yearly", purchaseToken: "tok-2-0123456789" }, opts);
  assert.equal((await day("2026-11-10")).purchase_verified, 2);
});

test("active Premium counts only entitlements that are on and not expired", async () => {
  const future = Timestamp.fromMillis(now.getTime() + DAY);
  const past = Timestamp.fromMillis(now.getTime() - DAY);
  await db.doc("entitlements/a").set({ active: true, expiresAt: future });
  await db.doc("entitlements/b").set({ active: true, expiresAt: future, source: "family" });
  await db.doc("entitlements/c").set({ active: true, expiresAt: past });
  await db.doc("entitlements/d").set({ active: false, expiresAt: future });
  await db.doc("entitlements/e").set({ packs: { yds: true } });
  assert.equal(await countActivePremium(db, now), 2);
  assert.equal(await snapshotPremium(db, now), 2);
  assert.equal((await day("2026-11-10")).premium_active, 2);
});

test("lastDays lists Turkish days oldest first", () => {
  assert.deepEqual(lastDays(now, 3), ["2026-11-08", "2026-11-09", "2026-11-10"]);
  assert.deepEqual(lastDays(new Date("2026-03-01T21:30:00Z"), 2), ["2026-03-01", "2026-03-02"]);
});

test("getStats is for Çenebaz staff only and returns every day, empty ones too", async () => {
  await countFunnel(db, { step: "first_open" }, now);
  await countFunnel(db, { step: "return_d1" }, new Date(now.getTime() - DAY));
  await db.doc("entitlements/a").set({ active: true, expiresAt: Timestamp.fromMillis(now.getTime() + DAY) });

  await rejectsWith(getStats(db, { uid: "someone" }, {}, now), "permission-denied", "lingora_admin_only");
  const r = await getStats(db, owner, { days: 3 }, now);
  assert.deepEqual(
    r.days.map((d) => d.day),
    ["2026-11-08", "2026-11-09", "2026-11-10"],
  );
  assert.deepEqual(r.days[0].counts, {});
  assert.equal(r.days[1].counts.return_d1, 1);
  assert.equal(r.days[2].counts.first_open, 1);
  assert.equal(r.premiumActiveNow, 1);
  // Staff claim works without the config list.
  const claimed = await getStats(db, { uid: "x", claims: { isLingoraAdmin: true } }, {}, now);
  assert.equal(claimed.days.length, 28);
  await rejectsWith(getStats(db, owner, { days: 0 }, now), "invalid-argument");
  await rejectsWith(getStats(db, owner, { days: 500 }, now), "invalid-argument");
  await rejectsWith(getStats(db, owner, { days: "7; drop" }, now), "invalid-argument");
});
