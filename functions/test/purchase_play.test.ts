// Real (non-emulator) purchase path and Play notifications, with a fake
// androidpublisher client: Google is never called.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { PACKAGE_NAME, PlayApi, PlayApiError, ProductPurchase, SubscriptionPurchaseV2 } from "../src/play.js";
import { handleRtdn, tokenHash, verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const DAY = 24 * 60 * 60 * 1000;
const now = new Date("2026-11-10T09:00:00Z");
const token = "play-token-0123456789";

class FakePlay implements PlayApi {
  subs = new Map<string, SubscriptionPurchaseV2>();
  products = new Map<string, ProductPurchase>();
  acks: string[] = [];
  error?: PlayApiError;

  async getSubscription(t: string): Promise<SubscriptionPurchaseV2> {
    if (this.error) throw this.error;
    const s = this.subs.get(t);
    if (!s) throw new PlayApiError(404, "not found");
    return structuredClone(s);
  }
  async getProduct(productId: string, t: string): Promise<ProductPurchase> {
    if (this.error) throw this.error;
    const p = this.products.get(`${productId}/${t}`);
    if (!p) throw new PlayApiError(404, "not found");
    return { ...p };
  }
  async acknowledgeSubscription(id: string, t: string): Promise<void> {
    this.acks.push(`sub:${id}:${t}`);
    const s = this.subs.get(t);
    if (s) s.acknowledgementState = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  }
  async acknowledgeProduct(id: string, t: string): Promise<void> {
    this.acks.push(`product:${id}:${t}`);
    const p = this.products.get(`${id}/${t}`);
    if (p) p.acknowledgementState = 1;
  }
}

function sub(
  state: string,
  expires: number,
  extra: Partial<SubscriptionPurchaseV2> = {},
  productId = "lingora_premium_monthly",
): SubscriptionPurchaseV2 {
  return {
    subscriptionState: `SUBSCRIPTION_STATE_${state}`,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    lineItems: [{ productId, expiryTime: new Date(expires).toISOString(), autoRenewingPlan: { autoRenewEnabled: true } }],
    ...extra,
  };
}

let play: FakePlay;
const opts = () => ({ testMode: false, now, play });
const buy = (uid: string, productId = "lingora_premium_monthly", t = token) =>
  verifyPurchase(db, uid, { productId, purchaseToken: t }, opts());
const ent = async (uid: string) => (await db.doc(`entitlements/${uid}`).get()).data();
const rtdn = (n: object, at = now) => handleRtdn(db, play, { packageName: PACKAGE_NAME, ...n }, at);
const subNote = (type: number, t = token) => ({
  subscriptionNotification: { notificationType: type, purchaseToken: t, subscriptionId: "lingora_premium_monthly" },
});

beforeEach(async () => {
  await clearFirestore();
  play = new FakePlay();
});

test("an active subscription grants Premium until Play's expiry and is acknowledged", async () => {
  const exp = now.getTime() + 30 * DAY;
  play.subs.set(token, sub("ACTIVE", exp));
  const r = await buy("u");
  assert.deepEqual(r, { active: true, premium: true, status: "active", productId: "lingora_premium_monthly", expiresAt: exp, packs: {} });
  const e = (await ent("u"))!;
  assert.equal(e.active, true);
  assert.equal(e.premium, true);
  assert.equal(e.status, "active");
  assert.equal(e.source, "play");
  assert.equal(e.productId, "lingora_premium_monthly");
  assert.equal(e.expiresAt.toMillis(), exp);
  assert.equal(e.purchaseTokenHash, tokenHash(token));
  assert.deepEqual(play.acks, [`sub:lingora_premium_monthly:${token}`]);
  const bound = (await db.doc(`purchases/${tokenHash(token)}`).get()).data()!;
  assert.equal(bound.uid, "u");
  assert.equal(bound.kind, "subscription");

  // Verifying again (restore) does not acknowledge twice.
  await buy("u");
  assert.equal(play.acks.length, 1);
});

test("Play's product id wins over the one the app sent", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 300 * DAY, {}, "lingora_premium_yearly"));
  const r = await buy("u", "lingora_premium_monthly");
  assert.equal(r.productId, "lingora_premium_yearly");
  assert.equal((await ent("u"))!.productId, "lingora_premium_yearly");
});

test("one token cannot be used by two accounts", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  await buy("a");
  await rejectsWith(buy("b"), "already-exists", "token_in_use");
  assert.equal(await ent("b"), undefined);

  play.products.set(`lingora_pack_yds_full/${token}-pack`, { purchaseState: 0, acknowledgementState: 0 });
  await buy("a", "lingora_pack_yds_full", `${token}-pack`);
  await rejectsWith(buy("b", "lingora_pack_yds_full", `${token}-pack`), "already-exists");
});

test("unknown tokens are rejected, Play outages are not", async () => {
  await rejectsWith(buy("u"), "invalid-argument", "invalid_token");
  play.error = new PlayApiError(403, "no access");
  await rejectsWith(buy("u"), "unavailable");
  play.error = new PlayApiError(503, "down");
  await rejectsWith(buy("u", "lingora_pack_yds_full"), "unavailable");
  assert.equal(await ent("u"), undefined);
  assert.equal((await db.doc(`purchases/${tokenHash(token)}`).get()).exists, false);
});

test("pending, grace and expired purchases", async () => {
  play.subs.set(token, sub("PENDING", 0));
  let r = await buy("u");
  assert.equal(r.active, false);
  assert.equal(r.status, "pending");
  assert.equal(await ent("u"), undefined);

  play.subs.set(token, sub("IN_GRACE_PERIOD", now.getTime() + 3 * DAY));
  r = await buy("u");
  assert.equal(r.active, true);
  assert.equal(r.status, "grace");
  assert.equal((await ent("u"))!.status, "grace");

  play.subs.set(token, sub("EXPIRED", now.getTime() - DAY));
  r = await buy("u");
  assert.equal(r.active, false);
  assert.equal(r.status, "expired");
  const e = (await ent("u"))!;
  assert.equal(e.active, false);
  assert.equal(e.premium, false);
  assert.equal(e.status, "expired");
  assert.equal(play.acks.length, 1); // only the grace period one
});

test("a cancelled subscription keeps Premium until the paid period ends", async () => {
  const exp = now.getTime() + 10 * DAY;
  play.subs.set(token, sub("CANCELED", exp, { acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" }));
  const r = await buy("u");
  assert.equal(r.active, true);
  assert.equal(r.expiresAt, exp);
  assert.equal((await ent("u"))!.autoRenewing, true);
  assert.equal(play.acks.length, 0);
});

test("notifications follow renewal, grace, on hold, recovery and expiry", async () => {
  const first = now.getTime() + 30 * DAY;
  play.subs.set(token, sub("ACTIVE", first));
  await buy("u");

  const renewed = first + 31 * DAY;
  play.subs.set(token, sub("ACTIVE", renewed, { acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" }));
  assert.equal(await rtdn(subNote(2)), "subscription:granted");
  assert.equal((await ent("u"))!.expiresAt.toMillis(), renewed);

  const later = new Date(renewed + DAY);
  play.subs.set(token, sub("IN_GRACE_PERIOD", renewed + 7 * DAY));
  assert.equal(await rtdn(subNote(6), later), "subscription:granted");
  assert.equal((await ent("u"))!.status, "grace");

  play.subs.set(token, sub("ON_HOLD", renewed));
  assert.equal(await rtdn(subNote(5), later), "subscription:revoked");
  let e = (await ent("u"))!;
  assert.equal(e.active, false);
  assert.equal(e.status, "expired");
  assert.equal(e.playState, "SUBSCRIPTION_STATE_ON_HOLD");

  play.subs.set(token, sub("ACTIVE", later.getTime() + 31 * DAY, { acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" }));
  assert.equal(await rtdn(subNote(1), later), "subscription:granted");
  e = (await ent("u"))!;
  assert.equal(e.active, true);
  assert.equal(e.expiresAt.toMillis(), later.getTime() + 31 * DAY);

  play.subs.set(token, sub("EXPIRED", later.getTime()));
  assert.equal(await rtdn(subNote(13), later), "subscription:revoked");
  assert.equal((await ent("u"))!.premium, false);
});

test("a voided (refunded) subscription ends Premium even if Play still says active", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  await buy("u");
  assert.equal(await rtdn({ voidedPurchaseNotification: { purchaseToken: token, productType: 1 } }), "voided:revoked");
  const e = (await ent("u"))!;
  assert.equal(e.active, false);
  assert.ok(e.expiresAt.toMillis() <= now.getTime());
});

test("notifications for tokens nobody verified yet change nothing", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  assert.equal(await rtdn(subNote(4)), "subscription:unbound");
  assert.equal(play.acks.length, 0);
  assert.equal((await db.doc(`purchases/${tokenHash(token)}`).get()).exists, false);
  assert.equal(await rtdn({ voidedPurchaseNotification: { purchaseToken: token, productType: 1 } }), "voided:unbound");
});

test("an upgrade cannot be claimed by another account before its notification arrives", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  await buy("owner");
  const upgraded = "upgrade-token-other-account";
  play.subs.set(upgraded, sub("ACTIVE", now.getTime() + 366 * DAY, { linkedPurchaseToken: token }, "lingora_premium_yearly"));
  await rejectsWith(buy("other", "lingora_premium_yearly", upgraded), "already-exists", "token_in_use");
  assert.equal(await ent("other"), undefined);
  assert.equal((await db.doc(`purchases/${tokenHash(upgraded)}`).get()).exists, false);
  assert.equal(play.acks.length, 1);
  const restored = await buy("owner", "lingora_premium_yearly", upgraded);
  assert.equal(restored.active, true);
  assert.equal((await db.doc(`purchases/${tokenHash(upgraded)}`).get()).get("uid"), "owner");
});

test("an upgrade token is bound to the owner of the token it replaces", async () => {
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  await buy("u");
  const newToken = "upgrade-token-987654321";
  const exp = now.getTime() + 366 * DAY;
  play.subs.set(newToken, sub("ACTIVE", exp, { linkedPurchaseToken: token }, "lingora_premium_yearly"));
  assert.equal(await rtdn(subNote(4, newToken)), "subscription:granted");
  let e = (await ent("u"))!;
  assert.equal(e.productId, "lingora_premium_yearly");
  assert.equal(e.purchaseTokenHash, tokenHash(newToken));
  assert.ok(play.acks.includes(`sub:lingora_premium_yearly:${newToken}`));

  // The replaced token expiring later does not end the new plan.
  play.subs.set(token, sub("EXPIRED", now.getTime()));
  assert.equal(await rtdn(subNote(13)), "subscription:unchanged");
  e = (await ent("u"))!;
  assert.equal(e.active, true);
  assert.equal(e.expiresAt.toMillis(), exp);
});

test("never shortens a longer Premium from another source, and gives it back on refund", async () => {
  const orgUntil = now.getTime() + 200 * DAY;
  await db.doc("entitlements/u").set({
    active: true,
    premium: true,
    status: "active",
    source: "org",
    productId: "org",
    expiresAt: Timestamp.fromMillis(orgUntil),
  });
  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  const r = await buy("u");
  assert.equal(r.expiresAt, orgUntil);

  play.subs.set(token, sub("EXPIRED", now.getTime()));
  await rtdn(subNote(12));
  const e = (await ent("u"))!;
  assert.equal(e.active, true);
  assert.equal(e.source, "org");
  assert.equal(e.productId, "org");
  assert.equal(e.expiresAt.toMillis(), orgUntil);
  assert.equal(e.previous, undefined);
});

test("days added on top of a subscription survive its renewal", async () => {
  const first = now.getTime() + 30 * DAY;
  play.subs.set(token, sub("ACTIVE", first));
  await buy("u");
  // A referral reward extends the running paid plan by 7 days (referral.ts).
  await db.doc("entitlements/u").update({ expiresAt: Timestamp.fromMillis(first + 7 * DAY) });
  play.subs.set(token, sub("ACTIVE", first + 31 * DAY));
  await rtdn(subNote(2));
  assert.equal((await ent("u"))!.expiresAt.toMillis(), first + 38 * DAY);
});

test("family plan: members follow the owner's renewals and cancellation", async () => {
  const exp = now.getTime() + 366 * DAY;
  play.subs.set(token, sub("ACTIVE", exp, {}, "lingora_premium_family_yearly"));
  await buy("owner", "lingora_premium_family_yearly");
  assert.equal((await db.doc("families/owner").get()).get("expiresAt").toMillis(), exp);
  await db.doc("families/owner").update({ "members.m": { joinedAt: Timestamp.fromDate(now) } });
  await db.doc("entitlements/m").set({
    active: true,
    premium: true,
    status: "active",
    source: "family",
    family: { ownerUid: "owner", role: "member" },
    expiresAt: Timestamp.fromMillis(exp),
  });

  play.subs.set(token, sub("EXPIRED", now.getTime(), {}, "lingora_premium_family_yearly"));
  await rtdn(subNote(13));
  assert.equal((await ent("owner"))!.active, false);
  const m = (await ent("m"))!;
  assert.equal(m.active, false);
  assert.equal(m.status, "expired");
  assert.ok((await db.doc("families/owner").get()).get("expiresAt").toMillis() <= now.getTime());
});

test("exam packs: purchased, pending, and refunded", async () => {
  const id = "lingora_pack_yds_full";
  play.products.set(`${id}/${token}`, { purchaseState: 2, acknowledgementState: 0 });
  let r = await buy("u", id);
  assert.equal(r.status, "pending");
  assert.deepEqual(r.packs, {});

  play.products.set(`${id}/${token}`, { purchaseState: 0, acknowledgementState: 0 });
  r = await buy("u", id);
  assert.deepEqual(r.packs, { yds: true });
  assert.equal(r.active, false);
  assert.deepEqual(play.acks, [`product:${id}:${token}`]);
  assert.deepEqual((await ent("u"))!.packs, { yds: true });

  assert.equal(await rtdn({ voidedPurchaseNotification: { purchaseToken: token, productType: 2 } }), "voided:pack");
  assert.deepEqual((await ent("u"))!.packs, { yds: false });
});

test("a refunded pack does not remove the same pack bought again with another token", async () => {
  const id = "lingora_pack_lgs_full";
  play.products.set(`${id}/${token}`, { purchaseState: 0, acknowledgementState: 1 });
  play.products.set(`${id}/second-token-123`, { purchaseState: 0, acknowledgementState: 1 });
  await buy("u", id);
  await buy("u", id, "second-token-123");
  play.products.set(`${id}/${token}`, { purchaseState: 1 });
  assert.equal(await rtdn({ oneTimeProductNotification: { notificationType: 2, purchaseToken: token, sku: id } }), "pack:synced");
  assert.deepEqual((await ent("u"))!.packs, { lgs: true });
});

test("notification guards", async () => {
  assert.equal(await handleRtdn(db, play, { packageName: "com.other.app", ...subNote(2) }, now), "ignored:package");
  assert.equal(await handleRtdn(db, play, undefined, now), "ignored:malformed");
  assert.equal(await rtdn({ testNotification: { version: "1.0" } }), "test");
  assert.equal(await rtdn(subNote(2, "x")), "ignored:malformed");

  play.subs.set(token, sub("ACTIVE", now.getTime() + 30 * DAY));
  await buy("u");
  // Permanent errors are logged and dropped; transient ones are retried by Pub/Sub.
  play.error = new PlayApiError(410, "gone");
  assert.equal(await rtdn(subNote(2)), "error:410");
  play.error = new PlayApiError(503, "down");
  await assert.rejects(rtdn(subNote(2)), PlayApiError);
  assert.equal((await ent("u"))!.active, true);
});
