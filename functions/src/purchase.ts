// Google Play purchase check -> entitlements/{uid}.
//
// Production asks the Google Play Developer API (play.ts) and follows later
// changes (renewal, cancel, grace, on hold, refund) through Real-time
// developer notifications on Pub/Sub (handleRtdn). The emulator path trusts the
// token and grants the product. Contract with the app:
// lib/services/billing/entitlement_backend.dart (ServerEntitlement.fromJson).
// Owner setup: docs/play-satin-alma-kurulum.md.
//
// entitlements/{uid} is shared by several writers (purchases, family plan,
// organisations, referrals). Every writer merges its own fields and never
// shortens an active Premium that another source granted for longer.
//
// purchases/{sha256(token)} (server only) binds a purchase token to one uid:
//   { uid, productId, kind: "subscription" | "pack" | "test", purchaseToken?, createdAt, updatedAt?,
//     entitledUntil? (subscriptions: the Premium end this token grants on its own, entitlement.ts) }
//
// Exam packs, contract with the app (exam_packs.dart):
//   entitlements/{uid}.packs       { [examId]: boolean }  examId "yds" | "lgs"
//   entitlements/{uid}.packTokens  { [examId]: tokenHash } the purchase that granted it
// A grant writes `true`; a refund / void / cancellation writes `false` and
// removes packTokens.{examId}. The key is never deleted: every examId present
// is authoritative (true = owned, false = revoked); a doc without `packs`
// says nothing about packs. The callable result carries the same map.
import { createHash } from "node:crypto";

import { DocumentData, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";

import { inTx, recomputedEntitlement } from "./entitlement.js";
import { FAMILY_PRODUCT, FAMILY_SEATS } from "./family.js";
import { PACKAGE_NAME, PlayApi, PlayApiError, SubscriptionAccess, subscriptionAccess } from "./play.js";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Premium subscription id -> Premium days per purchase (lib/services/billing/products.dart). */
export const PRODUCTS: Record<string, number> = {
  lingora_premium_monthly: 31,
  lingora_premium_yearly: 366,
  [FAMILY_PRODUCT]: 366,
};

/** One-time exam pack id -> field under entitlements/{uid}.packs (lib/services/billing/products.dart). */
export const PACK_PRODUCTS: Record<string, string> = {
  lingora_pack_yds_full: "yds",
  lingora_pack_lgs_full: "lgs",
};

export interface PurchaseResult {
  /** Premium right now (after this purchase). */
  active: boolean;
  premium: boolean;
  status: "active" | "grace" | "pending" | "expired";
  productId: string;
  /** Milliseconds since epoch; absent when there is no Premium. */
  expiresAt?: number;
  /** Exam packs owned, e.g. { yds: true }. */
  packs: Record<string, boolean>;
}

export function parsePurchaseInput(data: unknown): { productId: string; purchaseToken: string } {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  if (d.platform !== undefined && d.platform !== "android") {
    throw new HttpsError("invalid-argument", "unsupported_platform");
  }
  if (typeof d.productId !== "string" || !(Object.hasOwn(PRODUCTS, d.productId) || Object.hasOwn(PACK_PRODUCTS, d.productId))) {
    throw new HttpsError("invalid-argument", "unknown_product");
  }
  const token = d.purchaseToken;
  if (!validToken(token)) throw new HttpsError("invalid-argument", "invalid_token");
  return { productId: d.productId, purchaseToken: token };
}

function validToken(token: unknown): token is string {
  return typeof token === "string" && token.length >= 8 && token.length <= 4096 && !/\s/.test(token);
}

export function tokenHash(purchaseToken: string): string {
  return createHash("sha256").update(purchaseToken).digest("hex");
}

const ms = (t: unknown) => (t as Timestamp | undefined)?.toMillis?.() ?? 0;

/** Premium end (ms) currently granted by [e], or 0. */
export function premiumUntil(e: DocumentData | undefined, now: Date): number {
  const on = e?.active === true || e?.premium === true;
  const exp = ms(e?.expiresAt);
  return on && exp > now.getTime() ? exp : 0;
}

function packsOf(e: DocumentData | undefined): Record<string, boolean> {
  return { ...((e?.packs as Record<string, boolean>) ?? {}) };
}

/** Callable result from the entitlement as it is after this call. */
function resultOf(
  e: DocumentData | undefined,
  now: Date,
  productId: string,
  fallbackStatus: PurchaseResult["status"] = "expired",
): PurchaseResult {
  const until = premiumUntil(e, now);
  const status = until > 0 ? (e?.status === "grace" ? "grace" : "active") : fallbackStatus;
  return {
    active: until > 0,
    premium: until > 0,
    status,
    productId,
    ...(until > 0 ? { expiresAt: until } : {}),
    packs: packsOf(e),
  };
}

export interface VerifyOptions {
  /** Emulator only: trust the token without asking Google. */
  testMode: boolean;
  now: Date;
  /** Google Play Developer API; required outside test mode. */
  play?: PlayApi;
}

export async function verifyPurchase(db: Firestore, uid: string, data: unknown, opts: VerifyOptions): Promise<PurchaseResult> {
  const { productId, purchaseToken } = parsePurchaseInput(data);
  if (opts.testMode) return grantTestPurchase(db, uid, productId, purchaseToken, opts.now);
  if (!opts.play) throw new HttpsError("unimplemented", "play_verification_not_configured");
  if (Object.hasOwn(PACK_PRODUCTS, productId)) {
    return syncPack(db, opts.play, purchaseToken, productId, opts.now, { caller: uid });
  }
  const r = await syncSubscription(db, opts.play, purchaseToken, opts.now, { caller: uid, productId });
  return r.result!;
}

// ---------------------------------------------------------------------------
// Play API calls

/** Maps a Play API failure for the callable. invalid-argument makes the app stop trusting the store. */
function callableError(e: unknown): HttpsError {
  if (e instanceof PlayApiError) {
    if (e.notFound) return new HttpsError("invalid-argument", "invalid_token");
    logger.error("play_api_error", { status: e.status, detail: e.message });
    // Misconfiguration (401/403) or an outage: the app keeps trusting the
    // store and re-verifies on the next restore.
    return new HttpsError("unavailable", "play_unavailable");
  }
  return e instanceof HttpsError ? e : new HttpsError("internal", "play_error");
}

async function acknowledge(what: string, ack: () => Promise<void>): Promise<void> {
  try {
    await ack();
  } catch (e) {
    // Not fatal: the next verify or notification tries again (Play refunds
    // purchases left unacknowledged for 3 days).
    logger.warn("play_ack_failed", { what, error: e instanceof Error ? e.message : String(e) });
  }
}

// ---------------------------------------------------------------------------
// Subscriptions

export interface SyncOutcome {
  /** "granted" | "revoked" | "pending" | "unchanged" | "unbound". */
  outcome: string;
  uid?: string;
  /** Set for callable calls. */
  result?: PurchaseResult;
}

/**
 * Re-reads a subscription token from Play and writes the owner's
 * entitlement. [caller] binds the token to that uid (callable); without it
 * (notifications) the token must already be bound, directly or through
 * linkedPurchaseToken (upgrade / resubscribe). [revoke] forces Premium off
 * (voided purchase).
 */
export async function syncSubscription(
  db: Firestore,
  play: PlayApi,
  purchaseToken: string,
  now: Date,
  opts: { caller?: string; productId?: string; revoke?: boolean },
): Promise<SyncOutcome> {
  let sub;
  try {
    sub = await play.getSubscription(purchaseToken);
  } catch (e) {
    if (opts.caller) throw callableError(e);
    throw e;
  }
  const access = subscriptionAccess(sub, Object.keys(PRODUCTS), now);
  if (opts.revoke) Object.assign(access, { entitled: false, status: "expired", needsAck: false });
  const productId = access.productId;
  if (!productId || !Object.hasOwn(PRODUCTS, productId)) {
    if (opts.caller) throw new HttpsError("invalid-argument", "unknown_product");
    return { outcome: "unknown_product" };
  }

  const hash = tokenHash(purchaseToken);
  const tokenRef = db.doc(`purchases/${hash}`);
  const linkedRef = sub.linkedPurchaseToken ? db.doc(`purchases/${tokenHash(sub.linkedPurchaseToken)}`) : undefined;

  const out = await db.runTransaction(async (tx): Promise<SyncOutcome> => {
    const bound = await tx.get(tokenRef);
    const linkedUid = linkedRef ? (await tx.get(linkedRef)).get("uid") as string | undefined : undefined;
    let uid = bound.get("uid") as string | undefined;
    if (opts.caller) {
      // One purchase, one account.
      if (uid && uid !== opts.caller) throw new HttpsError("already-exists", "token_in_use");
      if (linkedUid && linkedUid !== opts.caller) throw new HttpsError("already-exists", "token_in_use");
      uid = opts.caller;
    } else if (!uid && linkedRef) {
      uid = linkedUid;
    }
    if (!uid) return { outcome: "unbound" };

    const entRef = db.doc(`entitlements/${uid}`);
    const current = (await tx.get(entRef)).data();
    const family = productId === FAMILY_PRODUCT ? (await tx.get(db.doc(`families/${uid}`))).data() : undefined;
    const memberUids = Object.keys((family?.members as Record<string, unknown>) ?? {});
    const memberEnts = await Promise.all(memberUids.map((m) => tx.get(db.doc(`entitlements/${m}`))));
    const end = access.entitled ? access.expiresAt : Math.min(access.expiresAt || now.getTime(), now.getTime());
    // Reads before any write: what is left when this purchase stops granting.
    const mine = current?.source === "play" && current?.purchaseTokenHash === hash;
    const fallback =
      !access.entitled && mine ? await recomputedEntitlement(db, uid, now, inTx(tx), current, null, hash) : undefined;
    const memberFallbacks = await familyFallbacks(tx, db, uid, memberEnts, end, now);

    tx.set(
      tokenRef,
      {
        uid,
        productId,
        kind: "subscription",
        purchaseToken,
        playState: access.playState,
        // Per-source record of this subscription (entitlement.ts reads it).
        entitledUntil: Timestamp.fromMillis(end),
        updatedAt: FieldValue.serverTimestamp(),
        ...(bound.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    );

    const next = applySubscription(tx, db, uid, current, hash, productId, access, now, family, memberEnts, {
      fallback,
      memberFallbacks,
    });
    return {
      outcome: next.outcome,
      uid,
      result: resultOf(next.ent, now, productId, access.status === "pending" ? "pending" : "expired"),
    };
  });

  if (out.uid && access.needsAck) {
    await acknowledge(productId, () => play.acknowledgeSubscription(productId, purchaseToken));
  }
  return out;
}

/** Writes [access] into entitlements/{uid}; returns the outcome and the merged entitlement. */
function applySubscription(
  tx: Transaction,
  db: Firestore,
  uid: string,
  current: DocumentData | undefined,
  hash: string,
  productId: string,
  access: SubscriptionAccess,
  now: Date,
  family: DocumentData | undefined,
  memberEnts: DocumentSnapshot[],
  recomputed: { fallback?: DocumentData; memberFallbacks: Map<string, DocumentData> },
): { outcome: string; ent: DocumentData | undefined } {
  const entRef = db.doc(`entitlements/${uid}`);
  const mine = current?.source === "play" && current?.purchaseTokenHash === hash;
  const isFamily = productId === FAMILY_PRODUCT;

  if (access.entitled) {
    // Days added on top of this subscription by others (e.g. referrals extend a
    // running paid plan) stay on top of the new Play end.
    const bonus = mine && premiumUntil(current, now) > 0 ? Math.max(0, ms(current?.expiresAt) - ms(current?.playExpiresAt)) : 0;
    const other = mine ? 0 : premiumUntil(current, now);
    const expiresAt = Math.max(access.expiresAt + bonus, other);
    const ent: DocumentData = {
      active: true,
      premium: true,
      status: access.status,
      productId,
      platform: "android",
      source: "play",
      expiresAt: Timestamp.fromMillis(expiresAt),
      playExpiresAt: Timestamp.fromMillis(access.expiresAt),
      purchaseTokenHash: hash,
      autoRenewing: access.autoRenewing,
      playState: access.playState,
      updatedAt: FieldValue.serverTimestamp(),
    };
    // Taking over from another running source (not an older Play token, which
    // this one replaces): remember it, so a later refund gives it back.
    if (!mine && other > 0 && current?.source !== "play") {
      ent.previous = { source: current?.source ?? null, productId: current?.productId ?? null, expiresAt: current?.expiresAt };
    }
    if (isFamily) {
      ent.family = { ownerUid: uid, role: "owner" };
      writeFamilyOwner(tx, db, uid, family, memberEnts, access.expiresAt, now, recomputed.memberFallbacks);
    }
    tx.set(entRef, ent, { merge: true });
    return { outcome: "granted", ent: { ...current, ...ent } };
  }

  // Not entitled. Only the purchase that granted the current Premium may end it.
  if (!mine) return { outcome: access.status === "pending" ? "pending" : "unchanged", ent: current };
  const end = Math.min(access.expiresAt || now.getTime(), now.getTime());
  // The best other running source (a parked grant, an org seat, a family,
  // another subscription), recomputed in syncSubscription; else Premium off.
  const fallback = recomputed.fallback;
  const ent: DocumentData =
    fallback?.active === true
      ? { ...fallback }
      : { ...fallback, active: false, premium: false, status: access.status, expiresAt: Timestamp.fromMillis(end) };
  Object.assign(ent, {
    playExpiresAt: Timestamp.fromMillis(end),
    purchaseTokenHash: FieldValue.delete(),
    previous: FieldValue.delete(),
    autoRenewing: false,
    playState: access.playState,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (isFamily) writeFamilyOwner(tx, db, uid, family, memberEnts, end, now, recomputed.memberFallbacks);
  tx.set(entRef, ent, { merge: true });
  const merged: DocumentData = { ...current, ...ent };
  if (ent.active !== true) Object.assign(merged, { active: false, premium: false });
  return { outcome: "revoked", ent: merged };
}

// ---------------------------------------------------------------------------
// One-time exam packs

/**
 * Re-reads an exam pack token from Play and grants or removes the pack.
 * [caller] binds the token (callable); otherwise the token must be bound.
 */
export async function syncPack(
  db: Firestore,
  play: PlayApi,
  purchaseToken: string,
  productId: string,
  now: Date,
  opts: { caller?: string; revoke?: boolean },
): Promise<PurchaseResult> {
  const pack = PACK_PRODUCTS[productId];
  let p;
  try {
    p = await play.getProduct(productId, purchaseToken);
  } catch (e) {
    if (opts.caller) throw callableError(e);
    throw e;
  }
  const state = opts.revoke ? 1 : p.purchaseState;
  const hash = tokenHash(purchaseToken);
  const tokenRef = db.doc(`purchases/${hash}`);

  const out = await db.runTransaction(async (tx) => {
    const bound = await tx.get(tokenRef);
    let uid = bound.get("uid") as string | undefined;
    if (opts.caller) {
      if (uid && uid !== opts.caller) throw new HttpsError("already-exists", "token_in_use");
      uid = opts.caller;
    }
    if (!uid) return { uid: undefined, result: undefined };
    const entRef = db.doc(`entitlements/${uid}`);
    const current = (await tx.get(entRef)).data();
    const packs = packsOf(current);
    tx.set(
      tokenRef,
      {
        uid,
        productId,
        kind: "pack",
        purchaseToken,
        purchaseState: state ?? null,
        updatedAt: FieldValue.serverTimestamp(),
        ...(bound.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    );
    if (state === 0) {
      packs[pack] = true;
      tx.set(
        entRef,
        { packs: { [pack]: true }, packTokens: { [pack]: hash }, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    } else if (state === 1 && current?.packTokens?.[pack] === hash) {
      // Cancelled or refunded: only the purchase that granted the pack removes it.
      packs[pack] = false;
      tx.set(
        entRef,
        { packs: { [pack]: false }, packTokens: { [pack]: FieldValue.delete() }, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    return { uid, result: resultOf({ ...current, packs }, now, productId, state === 2 ? "pending" : "expired") };
  });

  if (out.uid && state === 0 && p.acknowledgementState === 0) {
    await acknowledge(productId, () => play.acknowledgeProduct(productId, purchaseToken));
  }
  return out.result ?? resultOf(undefined, now, productId);
}

// ---------------------------------------------------------------------------
// Real-time developer notifications (Pub/Sub topic play-rtdn)

/** DeveloperNotification JSON from Play (only the fields we read). */
export interface DeveloperNotification {
  packageName?: string;
  subscriptionNotification?: { notificationType?: number; purchaseToken?: string; subscriptionId?: string };
  oneTimeProductNotification?: { notificationType?: number; purchaseToken?: string; sku?: string };
  /** productType: 1 subscription, 2 one-time product. */
  voidedPurchaseNotification?: { purchaseToken?: string; productType?: number };
  testNotification?: object;
}

/**
 * Handles one notification: re-reads the token from Play (never trusts the
 * message itself) and updates the bound user's entitlement. Returns what
 * happened, for logs and tests. Throws only on errors worth a Pub/Sub retry.
 */
export async function handleRtdn(db: Firestore, play: PlayApi, msg: DeveloperNotification | undefined, now: Date): Promise<string> {
  if (!msg || typeof msg !== "object") return "ignored:malformed";
  if (msg.packageName !== PACKAGE_NAME) return "ignored:package";
  if (msg.testNotification) return "test";
  try {
    const sub = msg.subscriptionNotification;
    if (sub) {
      if (!validToken(sub.purchaseToken)) return "ignored:malformed";
      return `subscription:${(await syncSubscription(db, play, sub.purchaseToken, now, {})).outcome}`;
    }
    const one = msg.oneTimeProductNotification;
    if (one) {
      if (!validToken(one.purchaseToken) || !one.sku || !Object.hasOwn(PACK_PRODUCTS, one.sku)) return "ignored:product";
      await syncPack(db, play, one.purchaseToken, one.sku, now, {});
      return "pack:synced";
    }
    const voided = msg.voidedPurchaseNotification;
    if (voided) {
      if (!validToken(voided.purchaseToken)) return "ignored:malformed";
      const bound = (await db.doc(`purchases/${tokenHash(voided.purchaseToken)}`).get()).data();
      if (!bound) return "voided:unbound";
      if (bound.kind === "pack") {
        await syncPack(db, play, voided.purchaseToken, bound.productId as string, now, { revoke: true });
        return "voided:pack";
      }
      return `voided:${(await syncSubscription(db, play, voided.purchaseToken, now, { revoke: true })).outcome}`;
    }
  } catch (e) {
    if (e instanceof PlayApiError && !e.transient) {
      // Unknown token or no access: retrying won't help; the app re-verifies on restore.
      logger.warn("rtdn_play_error", { status: e.status, detail: e.message });
      return `error:${e.status}`;
    }
    throw e;
  }
  return "ignored:unknown";
}

// ---------------------------------------------------------------------------
// Emulator / tests

async function grantTestPurchase(
  db: Firestore,
  uid: string,
  productId: string,
  purchaseToken: string,
  nowDate: Date,
): Promise<PurchaseResult> {
  const tokenRef = db.doc(`purchases/${tokenHash(purchaseToken)}`);
  const entRef = db.doc(`entitlements/${uid}`);
  const now = nowDate.getTime();

  return db.runTransaction(async (tx) => {
    const bound = await tx.get(tokenRef);
    if (bound.exists && bound.get("uid") !== uid) throw new HttpsError("already-exists", "token_in_use");
    const current = (await tx.get(entRef)).data();
    const familyRef = db.doc(`families/${uid}`);
    const family = productId === FAMILY_PRODUCT ? (await tx.get(familyRef)).data() : undefined;
    const memberUids = Object.keys((family?.members as Record<string, unknown>) ?? {});
    const memberEnts = await Promise.all(memberUids.map((m) => tx.get(db.doc(`entitlements/${m}`))));
    const pack = Object.hasOwn(PACK_PRODUCTS, productId) ? PACK_PRODUCTS[productId] : undefined;
    const purchased = now + PRODUCTS[productId] * DAY_MS;
    tx.set(
      tokenRef,
      {
        uid,
        productId,
        kind: "test",
        ...(pack ? {} : { entitledUntil: Timestamp.fromMillis(purchased) }),
        ...(bound.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    );

    const packs = packsOf(current);
    if (pack) {
      packs[pack] = true;
      // Same shape as syncPack, so a refund in the emulator removes it too.
      tx.set(
        entRef,
        { packs: { [pack]: true }, packTokens: { [pack]: tokenHash(purchaseToken) }, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      return resultOf({ ...current, packs }, nowDate, productId);
    }

    const expiresAt = Math.max(purchased, premiumUntil(current, nowDate));
    const ent: DocumentData = {
      active: true,
      premium: true,
      status: "active",
      productId,
      platform: "android",
      expiresAt: Timestamp.fromMillis(expiresAt),
      source: "test",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (productId === FAMILY_PRODUCT) {
      ent.family = { ownerUid: uid, role: "owner" };
      writeFamilyOwner(tx, db, uid, family, memberEnts, purchased, nowDate);
    }
    tx.set(entRef, ent, { merge: true });
    return { active: true, premium: true, status: "active", productId, expiresAt, packs };
  });
}

/**
 * Reads (inside [tx], before any write) what each family member of
 * [ownerUid] keeps once the family plan ends at [end]. Empty while it runs.
 */
async function familyFallbacks(
  tx: Transaction,
  db: Firestore,
  ownerUid: string,
  memberEnts: DocumentSnapshot[],
  end: number,
  now: Date,
): Promise<Map<string, DocumentData>> {
  const out = new Map<string, DocumentData>();
  if (end > now.getTime()) return out;
  for (const snap of memberEnts) {
    const e = snap.data();
    if (e?.source !== "family" || e?.family?.ownerUid !== ownerUid) continue;
    out.set(snap.id, await recomputedEntitlement(db, snap.id, now, inTx(tx), e, "family"));
  }
  return out;
}

/**
 * Creates or updates families/{ownerUid} and moves the Premium end of every
 * member that got Premium from this family to [expiresAt] (ended if that is
 * not after [now]).
 */
function writeFamilyOwner(
  tx: Transaction,
  db: Firestore,
  ownerUid: string,
  family: DocumentData | undefined,
  memberEnts: DocumentSnapshot[],
  expiresAt: number,
  now: Date,
  fallbacks: Map<string, DocumentData> = new Map(),
): void {
  const until = Timestamp.fromMillis(expiresAt);
  const on = expiresAt > now.getTime();
  if (!family && !on) return;
  tx.set(
    db.doc(`families/${ownerUid}`),
    {
      ownerUid,
      seats: FAMILY_SEATS,
      expiresAt: until,
      ...(family ? {} : { members: {}, createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  for (const snap of memberEnts) {
    // Members whose Premium came from elsewhere are left alone.
    const e = snap.data();
    if (e?.source !== "family" || e?.family?.ownerUid !== ownerUid) continue;
    // Plan over: the member keeps whatever else they have (own subscription, invite days, org seat).
    const fallback = on ? undefined : fallbacks.get(snap.id);
    if (fallback) {
      tx.set(snap.ref, fallback, { merge: true });
      continue;
    }
    tx.set(
      snap.ref,
      {
        active: on,
        premium: on,
        status: on ? "active" : "expired",
        expiresAt: until,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}
