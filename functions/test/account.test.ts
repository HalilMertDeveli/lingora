import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { deleteUserData } from "../src/account.js";
import { FAMILY_PRODUCT } from "../src/family.js";
import { createFamilyInvite, redeemFamilyCode } from "../src/family.js";
import { verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-18T09:00:00Z");

beforeEach(clearFirestore);

const exists = async (path: string) => (await db.doc(path).get()).exists;

test("deletes every document of the learner and keeps other people's", async () => {
  await db.doc("users/me").set({ progress: { xp: 10 } });
  await db.doc("users/me/notes/n1").set({ text: "hello" });
  await db.doc("users/other").set({ progress: { xp: 5 } });
  await db.doc("profiles/me").set({ name: "Ben" });
  await db.doc("usage/me").set({ day: "2026-11-18", count: 2 });
  await db.doc("explainUsage/me").set({ day: "2026-11-18", count: 4 });
  await db.doc("rehearsals/me/items/a").set({ score: 3 });
  await db.doc("friendCodes/ABCDEFGH").set({ uid: "me", name: "Ben" });
  await db.doc("friendCodes/HGFEDCBA").set({ uid: "other", name: "O" });
  await db.doc("friendships/me_other").set({ members: ["me", "other"] });
  await db.doc("friendships/me_other/cheers/c1").set({ from: "other" });
  await db.doc("friendRequests/x_me").set({ from: "x", to: "me" });
  await db.doc("phoneIndex/h1").set({ uid: "me" });
  await db.doc("referralRedemptions/me").set({ at: 1 });
  await verifyPurchase(db, "me", { productId: "lingora_premium_yearly", purchaseToken: "purchase-token-me-0001" }, {
    testMode: true,
    now,
  });

  const r = await deleteUserData(db, "me");
  assert.equal(r.deleted, true);

  for (const p of [
    "users/me",
    "users/me/notes/n1",
    "profiles/me",
    "usage/me",
    "explainUsage/me",
    "rehearsals/me/items/a",
    "friendCodes/ABCDEFGH",
    "friendships/me_other",
    "friendships/me_other/cheers/c1",
    "friendRequests/x_me",
    "phoneIndex/h1",
    "entitlements/me",
  ]) {
    assert.equal(await exists(p), false, p);
  }
  assert.equal(await exists("users/other"), true);
  assert.equal(await exists("friendCodes/HGFEDCBA"), true);
  // Anti-abuse record stays.
  assert.equal(await exists("referralRedemptions/me"), true);
  assert.equal(await exists("deletedAccounts/me"), true);

  // The purchase token is released: a new account can restore it.
  const restored = await verifyPurchase(db, "newMe", { productId: "lingora_premium_yearly", purchaseToken: "purchase-token-me-0001" }, {
    testMode: true,
    now,
  });
  assert.equal(restored.active, true);

  // Running it again is harmless.
  await deleteUserData(db, "me");
});

test("a family owner's members lose the shared plan, a member leaves the family", async () => {
  await verifyPurchase(db, "owner", { productId: FAMILY_PRODUCT, purchaseToken: "purchase-token-family-0001" }, { testMode: true, now });
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);
  assert.equal((await db.doc("entitlements/kid").get()).data()?.family?.role, "member");

  await deleteUserData(db, "owner");
  assert.equal(await exists("families/owner"), false);
  assert.equal(await exists(`familyCodes/${code}`), false);
  assert.equal((await db.doc("entitlements/kid").get()).data()?.family?.role, undefined);
});

test("a family member leaving by deletion frees the seat", async () => {
  await verifyPurchase(db, "owner", { productId: FAMILY_PRODUCT, purchaseToken: "purchase-token-family-0002" }, { testMode: true, now });
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);

  await deleteUserData(db, "kid");
  const fam = (await db.doc("families/owner").get()).data();
  assert.deepEqual(Object.keys(fam?.members ?? {}), []);
});
