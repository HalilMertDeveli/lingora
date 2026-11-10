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
});

test("test mode writes the entitlement", async () => {
  const r = await verifyPurchase(db, "u", { productId: "lingora_premium_yearly", purchaseToken: token }, test_);
  assert.equal(r.active, true);
  assert.equal(r.expiresAt, now.getTime() + 365 * 24 * 60 * 60 * 1000);
  const e = (await db.doc("entitlements/u").get()).data()!;
  assert.equal(e.active, true);
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
