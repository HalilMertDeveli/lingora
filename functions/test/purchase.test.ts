import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-10T09:00:00Z");
const test_ = { testMode: true, now };
const token = "test-token-0123456789";

beforeEach(clearFirestore);

test("validates input", async () => {
  await rejectsWith(verifyPurchase(db, "u", { productId: "x", purchaseToken: token }, test_), "invalid-argument");
  await rejectsWith(
    verifyPurchase(db, "u", { productId: "lingora_premium_monthly", purchaseToken: "short" }, test_),
    "invalid-argument",
  );
  await rejectsWith(verifyPurchase(db, "u", null, test_), "invalid-argument");
  await rejectsWith(
    verifyPurchase(db, "u", { platform: "ios", productId: "lingora_premium_monthly", purchaseToken: token }, test_),
    "invalid-argument",
  );
});

test("test mode writes the entitlement", async () => {
  const r = await verifyPurchase(
    db,
    "u",
    { platform: "android", productId: "lingora_premium_yearly", purchaseToken: token },
    test_,
  );
  assert.equal(r.active, true);
  assert.equal(r.premium, true);
  assert.equal(r.status, "active");
  assert.equal(r.expiresAt, now.getTime() + 366 * 24 * 60 * 60 * 1000);
  const e = (await db.doc("entitlements/u").get()).data()!;
  assert.equal(e.active, true);
  assert.equal(e.premium, true);
  assert.equal(e.status, "active");
  assert.equal(e.platform, "android");
  assert.equal(e.productId, "lingora_premium_yearly");
  assert.equal(e.source, "test");
  assert.equal(e.expiresAt.toMillis(), r.expiresAt);
});

test("a token cannot be shared between accounts", async () => {
  const data = { productId: "lingora_premium_monthly", purchaseToken: token };
  await verifyPurchase(db, "a", data, test_);
  await verifyPurchase(db, "a", data, test_); // same user again is fine
  await rejectsWith(verifyPurchase(db, "b", data, test_), "already-exists");
});

test("production mode is not implemented yet", async () => {
  await rejectsWith(
    verifyPurchase(db, "u", { productId: "lingora_premium_monthly", purchaseToken: token }, { testMode: false, now }),
    "unimplemented",
  );
  assert.equal((await db.doc("entitlements/u").get()).exists, false);
});

test("exam packs are stored next to Premium and survive Premium writes", async () => {
  const pack = await verifyPurchase(db, "u", { productId: "lingora_pack_yds_full", purchaseToken: token }, test_);
  assert.equal(pack.active, false);
  assert.deepEqual(pack.packs, { yds: true });
  assert.equal(pack.expiresAt, undefined);
  let e = (await db.doc("entitlements/u").get()).data()!;
  assert.deepEqual(e.packs, { yds: true });
  assert.equal(e.active, undefined);

  const sub = await verifyPurchase(
    db,
    "u",
    { productId: "lingora_premium_monthly", purchaseToken: "monthly-token-1" },
    test_,
  );
  assert.equal(sub.active, true);
  assert.deepEqual(sub.packs, { yds: true });
  const lgs = await verifyPurchase(db, "u", { productId: "lingora_pack_lgs_full", purchaseToken: "lgs-token-1" }, test_);
  assert.equal(lgs.active, true);
  assert.equal(lgs.expiresAt, sub.expiresAt);
  e = (await db.doc("entitlements/u").get()).data()!;
  assert.deepEqual(e.packs, { yds: true, lgs: true });
  assert.equal(e.active, true);
  assert.equal(e.productId, "lingora_premium_monthly");
});

test("a shorter purchase never shortens a longer Premium", async () => {
  const y = await verifyPurchase(db, "u", { productId: "lingora_premium_yearly", purchaseToken: "y-token-123" }, test_);
  const m = await verifyPurchase(db, "u", { productId: "lingora_premium_monthly", purchaseToken: token }, test_);
  assert.equal(m.expiresAt, y.expiresAt);
});
