// One Premium answer from every source (audit findings 4 and 9).
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { effectivePremium, hasPremium, premiumGrants } from "../src/entitlement.js";
import { createFamilyInvite, FAMILY_PRODUCT, leaveFamily, redeemFamilyCode, removeFamilyMember } from "../src/family.js";
import { Caller, createOrg, joinOrg, leaveOrg, removeMember, setMemberRole } from "../src/orgs.js";
import { PACKAGE_NAME, PlayApi, PlayApiError, ProductPurchase, SubscriptionPurchaseV2 } from "../src/play.js";
import { handleRtdn, verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore } from "./helpers.js";

const db = adminDb();
const DAY = 24 * 60 * 60 * 1000;
const now = new Date("2026-11-10T09:00:00Z");
const later = (days: number) => new Date(now.getTime() + days * DAY);
const staff: Caller = { uid: "staff", claims: { isLingoraAdmin: true } };

beforeEach(clearFirestore);

const ent = async (uid: string) => (await db.doc(`entitlements/${uid}`).get()).data();
const until = (e: Record<string, unknown> | undefined) => (e?.expiresAt as Timestamp | undefined)?.toMillis() ?? 0;
const buyTest = (uid: string, productId: string, token: string, at = now) =>
  verifyPurchase(db, uid, { productId, purchaseToken: token }, { testMode: true, now: at });

async function familyWith(member: string) {
  await buyTest("owner", FAMILY_PRODUCT, "family-token-owner-0001");
  const { code } = await createFamilyInvite(db, "owner", now);
  return redeemFamilyCode(db, member, { code }, now);
}

async function orgWithSeat(uid: string, days = 400) {
  const { orgId, adminCode } = await createOrg(
    db,
    staff,
    { name: "Okul", type: "okul", seats: 5, planExpiresAt: now.getTime() + days * DAY },
    now,
  );
  await joinOrg(db, { uid: "boss" }, { code: adminCode, displayName: "Müdür" }, now);
  const { createJoinCode } = await import("../src/orgs.js");
  const { code } = await createJoinCode(db, { uid: "boss" }, { orgId, role: "member" }, now);
  await joinOrg(db, { uid }, { code, displayName: "Öğrenci" }, now);
  return orgId;
}

test("no source, no Premium", async () => {
  assert.equal(await hasPremium(db, "nobody", now), false);
  await db.doc("entitlements/x").set({ active: true, expiresAt: Timestamp.fromMillis(now.getTime() - 1) });
  assert.equal(await hasPremium(db, "x", now), false);
});

test("a Kurum lisansı seat counts on the server (finding 4)", async () => {
  await db.doc("licenseCodes/ABCDEFGHJKLM").set({ org: "Okul", role: "student", claimedBy: "stu", expiresAt: Timestamp.fromDate(later(90)) });
  await db.doc("licenses/stu").set({ code: "ABCDEFGHJKLM", org: "Okul", role: "student", expiresAt: Timestamp.fromDate(later(90)) });
  assert.equal(await hasPremium(db, "stu", now), true);
  assert.equal((await effectivePremium(db, "stu", now))?.source, "license");
  assert.equal(await hasPremium(db, "stu", later(91)), false);

  // The operator released the seat (license_codes.mjs release): no Premium.
  await db.doc("licenseCodes/ABCDEFGHJKLM").update({ claimedBy: null });
  assert.equal(await hasPremium(db, "stu", now), false);
});

test("an org seat counts even when entitlements/{uid} says nothing", async () => {
  const orgId = await orgWithSeat("ali");
  await db.doc("entitlements/ali").delete();
  assert.equal((await effectivePremium(db, "ali", now))?.source, "org");
  // Admins manage, they do not hold a seat.
  assert.equal(await hasPremium(db, "boss", now), false);
  await db.doc(`orgs/${orgId}`).update({ planExpiresAt: Timestamp.fromDate(later(-1)) });
  assert.equal(await hasPremium(db, "ali", now), false);
});

test("owner's family doc ended but member doc not updated -> no Premium (stale member date is not trusted)", async () => {
  await familyWith("kid");
  assert.equal(await hasPremium(db, "kid", now), true);
  // Only families/{owner} is moved; entitlements/kid still says "active until next year".
  await db.doc("families/owner").update({ expiresAt: Timestamp.fromDate(later(-1)) });
  assert.equal((await ent("kid"))?.active, true);
  assert.equal(await hasPremium(db, "kid", now), false);
  assert.equal((await premiumGrants(db, "kid", now)).some((g) => g.source === "family"), false);
});

test("member removed from families/{owner} without their doc rewritten -> no Premium", async () => {
  await familyWith("kid");
  await db.doc("families/owner").update({ "members.kid": FieldValue.delete() });
  assert.equal(await hasPremium(db, "kid", now), false);
});

test("a family grant parked in `previous` also follows the live family doc", async () => {
  await familyWith("kid");
  const e = (await ent("kid"))!;
  await db.doc("entitlements/kid").set({
    ...e,
    source: "referral",
    active: true,
    premium: true,
    expiresAt: Timestamp.fromDate(later(-2)),
    previous: { source: "family", productId: FAMILY_PRODUCT, expiresAt: e.expiresAt },
  });
  assert.equal((await effectivePremium(db, "kid", now))?.source, "family"); // plan still runs
  await db.doc("families/owner").update({ expiresAt: Timestamp.fromDate(later(-1)) });
  assert.equal(await hasPremium(db, "kid", now), false);
});

test("a family seat counts while the owner's plan runs", async () => {
  await familyWith("kid");
  await db.doc("entitlements/kid").update({ active: false, premium: false });
  assert.equal((await effectivePremium(db, "kid", now))?.source, "family");
});

test("leaving a family gives back a still-running personal subscription (finding 9)", async () => {
  await buyTest("kid", "lingora_premium_monthly", "kid-monthly-token-0001");
  const own = until(await ent("kid"));
  await familyWith("kid");
  let e = await ent("kid");
  assert.equal(e?.source, "family");
  assert.equal(e?.previous?.source, "test");

  await leaveFamily(db, "kid", now);
  e = await ent("kid");
  assert.equal(e?.active, true);
  assert.equal(e?.source, "test");
  assert.equal(until(e), own);
  assert.equal(e?.previous, undefined);
  assert.equal(e?.family, undefined);
});

test("removal by the owner keeps invite days and an org seat", async () => {
  await db.doc("entitlements/kid").set({
    active: true,
    premium: true,
    source: "referral",
    productId: "referral",
    expiresAt: Timestamp.fromDate(later(7)),
  });
  await familyWith("kid");
  await removeFamilyMember(db, "owner", { memberUid: "kid" }, now);
  let e = await ent("kid");
  assert.equal(e?.source, "referral");
  assert.equal(until(e), later(7).getTime());

  // Org seat joined while in the family: removal falls back to it.
  await db.doc("entitlements/kid2").delete();
  await familyWith("kid2");
  await orgWithSeat("kid2", 30);
  await removeFamilyMember(db, "owner", { memberUid: "kid2" }, now);
  e = await ent("kid2");
  assert.equal(e?.active, true);
  assert.equal(e?.source, "org");
});

test("without any other source, leaving ends Premium", async () => {
  await familyWith("kid");
  await leaveFamily(db, "kid", now);
  const e = await ent("kid");
  assert.equal(e?.active, false);
  assert.equal(await hasPremium(db, "kid", now), false);
});

test("losing an org seat gives back a parked subscription; a role change too", async () => {
  await buyTest("ali", "lingora_premium_monthly", "ali-monthly-token-0001");
  const own = until(await ent("ali"));
  const orgId = await orgWithSeat("ali");
  assert.equal((await ent("ali"))?.source, "org");
  await leaveOrg(db, { uid: "ali" }, {}, now);
  let e = await ent("ali");
  assert.equal(e?.source, "test");
  assert.equal(until(e), own);

  await buyTest("veli", "lingora_premium_monthly", "veli-monthly-token-0001");
  const { createJoinCode } = await import("../src/orgs.js");
  const { code } = await createJoinCode(db, { uid: "boss" }, { orgId, role: "member" }, now);
  await joinOrg(db, { uid: "veli" }, { code, displayName: "Veli" }, now);
  await setMemberRole(db, { uid: "boss" }, { orgId, uid: "veli", role: "admin" }, now);
  e = await ent("veli");
  assert.equal(e?.source, "test");

  // Removed by the admin with nothing else: off.
  const { code: c2 } = await createJoinCode(db, { uid: "boss" }, { orgId, role: "member" }, now);
  await joinOrg(db, { uid: "ayse" }, { code: c2, displayName: "Ayşe" }, now);
  await removeMember(db, { uid: "boss" }, { orgId, uid: "ayse" }, now);
  assert.equal((await ent("ayse"))?.active, false);
});

// ---- Play path: the family plan ends, members fall back -----------------

class FakePlay implements PlayApi {
  subs = new Map<string, SubscriptionPurchaseV2>();
  async getSubscription(t: string): Promise<SubscriptionPurchaseV2> {
    const s = this.subs.get(t);
    if (!s) throw new PlayApiError(404, "not found");
    return structuredClone(s);
  }
  async getProduct(): Promise<ProductPurchase> {
    throw new PlayApiError(404, "not found");
  }
  async acknowledgeSubscription(): Promise<void> {}
  async acknowledgeProduct(): Promise<void> {}
}

function sub(state: string, expires: number, productId: string): SubscriptionPurchaseV2 {
  return {
    subscriptionState: `SUBSCRIPTION_STATE_${state}`,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    lineItems: [{ productId, expiryTime: new Date(expires).toISOString(), autoRenewingPlan: { autoRenewEnabled: true } }],
  };
}

test("when the family plan ends, a member keeps their own subscription; tokens record entitledUntil", async () => {
  const play = new FakePlay();
  const famToken = "play-family-token-0001";
  const kidToken = "play-kid-token-000001";
  play.subs.set(famToken, sub("ACTIVE", later(366).getTime(), FAMILY_PRODUCT));
  play.subs.set(kidToken, sub("ACTIVE", later(30).getTime(), "lingora_premium_monthly"));
  const opts = { testMode: false, now, play };
  await verifyPurchase(db, "owner", { productId: FAMILY_PRODUCT, purchaseToken: famToken }, opts);
  await verifyPurchase(db, "kid", { productId: "lingora_premium_monthly", purchaseToken: kidToken }, opts);
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);
  assert.equal((await ent("kid"))?.source, "family");

  // The family subscription is refunded.
  await handleRtdn(db, play, { packageName: PACKAGE_NAME, voidedPurchaseNotification: { purchaseToken: famToken, productType: 1 } }, now);
  const e = await ent("kid");
  assert.equal(e?.active, true);
  assert.equal(e?.source, "play");
  assert.equal(until(e), later(30).getTime());
  assert.equal((await ent("owner"))?.active, false);

  const grants = await premiumGrants(db, "kid", now);
  assert.equal(grants[0].source, "play");
  assert.equal(grants.some((g) => g.source === "family"), false);
});

test("a refunded subscription falls back to an org seat instead of turning Premium off", async () => {
  const play = new FakePlay();
  const t = "play-ali-token-0000001";
  play.subs.set(t, sub("ACTIVE", later(500).getTime(), "lingora_premium_yearly"));
  await orgWithSeat("ali", 100);
  await verifyPurchase(db, "ali", { productId: "lingora_premium_yearly", purchaseToken: t }, { testMode: false, now, play });
  assert.equal((await ent("ali"))?.source, "play");
  await handleRtdn(db, play, { packageName: PACKAGE_NAME, voidedPurchaseNotification: { purchaseToken: t, productType: 1 } }, now);
  const e = await ent("ali");
  assert.equal(e?.active, true);
  assert.equal(e?.source, "org");
  assert.equal(until(e), later(100).getTime());
});
