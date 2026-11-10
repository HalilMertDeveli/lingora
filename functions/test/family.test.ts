import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import {
  createFamilyInvite,
  FAMILY_PRODUCT,
  getFamily,
  leaveFamily,
  MAX_MEMBERS,
  normalizeCode,
  redeemFamilyCode,
  removeFamilyMember,
} from "../src/family.js";
import { verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-10T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;
const later = (days: number) => new Date(now.getTime() + days * DAY);

beforeEach(clearFirestore);

async function buyFamily(owner = "owner", at = now) {
  return verifyPurchase(
    db,
    owner,
    { productId: FAMILY_PRODUCT, purchaseToken: `family-token-${owner}-${at.getTime()}` },
    { testMode: true, now: at },
  );
}

const ent = async (uid: string) => (await db.doc(`entitlements/${uid}`).get()).data();

test("normalizes codes", () => {
  assert.equal(normalizeCode("abcd-efgh"), "ABCDEFGH");
  assert.equal(normalizeCode(" ABCD EFGH "), "ABCDEFGH");
  assert.equal(normalizeCode("ABCDEFG0"), null); // 0 is not in the alphabet
  assert.equal(normalizeCode("ABC"), null);
  assert.equal(normalizeCode(42), null);
});

test("only an active family plan can invite", async () => {
  await rejectsWith(createFamilyInvite(db, "owner", now), "failed-precondition", "no_family_plan");
  // A normal yearly Premium is not a family plan.
  await verifyPurchase(db, "owner", { productId: "lingora_premium_yearly", purchaseToken: "yearly-token-1" }, {
    testMode: true,
    now,
  });
  await rejectsWith(createFamilyInvite(db, "owner", now), "failed-precondition", "no_family_plan");
});

test("owner buys, invites; member redeems and gets family Premium", async () => {
  const bought = await buyFamily();
  assert.equal(bought.active, true);
  const owner = await ent("owner");
  assert.deepEqual(owner!.family, { ownerUid: "owner", role: "owner" });
  assert.equal(owner!.productId, FAMILY_PRODUCT);

  const { code, expiresAt } = await createFamilyInvite(db, "owner", now);
  assert.equal(code.length, 8);
  assert.equal(expiresAt, now.getTime() + 7 * DAY);

  const r = await redeemFamilyCode(db, "kid", { code: `${code.slice(0, 4).toLowerCase()}-${code.slice(4)}` }, now);
  assert.equal(r.active, true);
  assert.equal(r.ownerUid, "owner");
  assert.equal(r.expiresAt, bought.expiresAt);
  const kid = await ent("kid");
  assert.equal(kid!.active, true);
  assert.equal(kid!.source, "family");
  assert.equal(kid!.productId, FAMILY_PRODUCT);
  assert.deepEqual(kid!.family, { ownerUid: "owner", role: "member" });
  assert.equal(kid!.expiresAt.toMillis(), bought.expiresAt);

  // Redeeming again is harmless.
  await redeemFamilyCode(db, "kid", { code }, now);
  const info = await getFamily(db, "owner", now);
  assert.equal(info.role, "owner");
  if (info.role === "owner") {
    assert.deepEqual(
      info.members.map((m) => m.uid),
      ["kid"],
    );
    assert.equal(info.code, code);
    assert.equal(info.seats, 5);
  }
  const mine = await getFamily(db, "kid", now);
  assert.equal(mine.role, "member");
  assert.deepEqual(await getFamily(db, "stranger", now), { role: "none" });
});

test("bad, expired and replaced codes", async () => {
  await buyFamily();
  await rejectsWith(redeemFamilyCode(db, "kid", { code: "nope" }, now), "invalid-argument");
  await rejectsWith(redeemFamilyCode(db, "kid", { code: "ABCDEFGH" }, now), "not-found");
  const { code } = await createFamilyInvite(db, "owner", now);
  await rejectsWith(redeemFamilyCode(db, "owner", { code }, now), "failed-precondition", "own_family");
  await rejectsWith(redeemFamilyCode(db, "kid", { code }, later(8)), "deadline-exceeded");
  const { code: fresh } = await createFamilyInvite(db, "owner", now);
  assert.notEqual(fresh, code);
  await rejectsWith(redeemFamilyCode(db, "kid", { code }, now), "not-found");
  await redeemFamilyCode(db, "kid", { code: fresh }, now);
});

test("a family has at most 5 people", async () => {
  await buyFamily();
  const { code } = await createFamilyInvite(db, "owner", now);
  for (let i = 0; i < MAX_MEMBERS; i++) await redeemFamilyCode(db, `m${i}`, { code }, now);
  await rejectsWith(redeemFamilyCode(db, "extra", { code }, now), "resource-exhausted", "family_full");
  await removeFamilyMember(db, "owner", { memberUid: "m0" });
  await redeemFamilyCode(db, "extra", { code }, now);
});

test("owner removes a member: family Premium ends, other fields stay", async () => {
  await buyFamily();
  const { code } = await createFamilyInvite(db, "owner", now);
  await verifyPurchase(db, "kid", { productId: "lingora_pack_lgs_full", purchaseToken: "lgs-pack-token" }, {
    testMode: true,
    now,
  });
  await redeemFamilyCode(db, "kid", { code }, now);
  await rejectsWith(removeFamilyMember(db, "owner", { memberUid: "nobody" }), "not-found");
  await rejectsWith(removeFamilyMember(db, "owner", { memberUid: "owner" }), "invalid-argument");
  // Someone else cannot remove members of this family.
  await rejectsWith(removeFamilyMember(db, "kid", { memberUid: "owner" }), "not-found");

  assert.deepEqual(await removeFamilyMember(db, "owner", { memberUid: "kid" }), { removed: true });
  const kid = await ent("kid");
  assert.equal(kid!.active, false);
  assert.equal(kid!.family, undefined);
  assert.deepEqual(kid!.packs, { lgs: true });
  const info = await getFamily(db, "owner", now);
  assert.equal(info.role === "owner" && info.members.length, 0);
});

test("a member's own longer Premium is kept on join and on removal", async () => {
  await buyFamily("owner", now);
  const own = await verifyPurchase(db, "adult", { productId: "lingora_premium_monthly", purchaseToken: "adult-monthly" }, {
    testMode: true,
    now: later(-200), // bought long ago -> expired
  });
  assert.ok(own.expiresAt! < now.getTime());
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "adult", { code }, now);
  assert.equal((await ent("adult"))!.source, "family");

  // Second family: user with their own yearly Premium that outlasts it.
  await buyFamily("owner2", later(-300));
  await verifyPurchase(db, "rich", { productId: "lingora_premium_yearly", purchaseToken: "rich-yearly" }, {
    testMode: true,
    now,
  });
  const { code: code2 } = await createFamilyInvite(db, "owner2", now);
  await redeemFamilyCode(db, "rich", { code: code2 }, now);
  let rich = await ent("rich");
  assert.equal(rich!.source, "test");
  assert.equal(rich!.productId, "lingora_premium_yearly");
  await removeFamilyMember(db, "owner2", { memberUid: "rich" });
  rich = await ent("rich");
  assert.equal(rich!.active, true); // own subscription untouched
});

test("joining a second family needs leaving the first", async () => {
  await buyFamily("a");
  await buyFamily("b");
  const { code: ca } = await createFamilyInvite(db, "a", now);
  const { code: cb } = await createFamilyInvite(db, "b", now);
  await redeemFamilyCode(db, "kid", { code: ca }, now);
  await rejectsWith(redeemFamilyCode(db, "kid", { code: cb }, now), "already-exists", "in_other_family");
  // Owners cannot join another family either.
  await rejectsWith(redeemFamilyCode(db, "a", { code: cb }, now), "failed-precondition", "owns_family");
  assert.deepEqual(await leaveFamily(db, "kid"), { left: true });
  assert.equal((await ent("kid"))!.active, false);
  await rejectsWith(leaveFamily(db, "kid"), "failed-precondition");
  await redeemFamilyCode(db, "kid", { code: cb }, now);
});

test("expired family plan: no new members; renewal extends members", async () => {
  const first = await buyFamily("owner", now);
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);
  await rejectsWith(redeemFamilyCode(db, "late", { code }, later(400)), "deadline-exceeded");
  await rejectsWith(createFamilyInvite(db, "owner", later(400)), "failed-precondition");

  const renewal = await verifyPurchase(
    db,
    "owner",
    { productId: FAMILY_PRODUCT, purchaseToken: "family-renewal-token" },
    { testMode: true, now: later(360) },
  );
  assert.ok(renewal.expiresAt! > first.expiresAt!);
  const kid = await ent("kid");
  assert.equal(kid!.expiresAt.toMillis(), later(360).getTime() + 366 * DAY);
  const fam = (await db.doc("families/owner").get()).data()!;
  assert.equal(fam.expiresAt.toMillis(), kid!.expiresAt.toMillis());
});
