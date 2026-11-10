// Invite programme ("Arkadaşını davet et"): every user gets a short code;
// when a new user redeems it, both get REWARD_DAYS of Premium through
// entitlements/{uid} (source: "referral"). Docs: docs/analitik.md#davet.
//
// Server-only collections (closed to clients by firestore.rules):
//   inviteCodes/{CODE}           { uid, createdAt }
//   referrals/{inviterUid}       { code, monthKey, monthCount, totalCount, updatedAt }
//   referralRedemptions/{uid}    { inviterUid, code, deviceHash, inviterRewarded, at }
//   referralDevices/{deviceHash} { uid, at }
import { createHash, randomInt } from "node:crypto";

import { DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const REWARD_DAYS = 7;
/** Rewards one inviter can earn per calendar month (Turkish time). */
export const MAX_REWARDS_PER_MONTH = 5;
/** Only accounts younger than this may redeem a code ("new user"). */
export const NEW_ACCOUNT_DAYS = 14;
export const REFERRAL_PRODUCT_ID = "referral";

// No 0/O, 1/I/L: easy to read aloud and type.
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LENGTH = 7;
const CODE_RE = new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`);
const DAY_MS = 24 * 60 * 60 * 1000;

export interface InviteInfo {
  code: string;
  rewardDays: number;
  rewardedThisMonth: number;
  maxPerMonth: number;
  totalRewarded: number;
}

export interface RedeemResult {
  ok: true;
  rewardDays: number;
  /** New Premium end for the redeemer, ms since epoch. */
  expiresAt: number;
  inviterRewarded: boolean;
}

export interface RedeemContext {
  now: Date;
  /** Firebase Auth creation time of the redeemer. */
  accountCreatedAt: Date;
  /** sign_in_provider from the ID token, e.g. "anonymous", "password". */
  signInProvider: string;
}

/** "2026-11" in Europe/Istanbul (UTC+3 all year since 2016). */
export function monthKey(now: Date): string {
  const tr = new Date(now.getTime() + 3 * 60 * 60 * 1000);
  return `${tr.getUTCFullYear()}-${String(tr.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function normalizeCode(raw: unknown): string {
  if (typeof raw !== "string") throw new HttpsError("invalid-argument", "invalid_code");
  const code = raw.trim().toUpperCase().replace(/[\s-]/g, "");
  if (!CODE_RE.test(code)) throw new HttpsError("invalid-argument", "invalid_code");
  return code;
}

function newCode(): string {
  let s = "";
  for (let i = 0; i < CODE_LENGTH; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

function hashDevice(deviceId: string): string {
  return createHash("sha256").update(`lingora-device:${deviceId}`).digest("hex");
}

function info(code: string, ref: DocumentSnapshot | undefined, now: Date): InviteInfo {
  const sameMonth = ref?.get("monthKey") === monthKey(now);
  return {
    code,
    rewardDays: REWARD_DAYS,
    rewardedThisMonth: sameMonth ? (ref?.get("monthCount") ?? 0) : 0,
    maxPerMonth: MAX_REWARDS_PER_MONTH,
    totalRewarded: ref?.get("totalCount") ?? 0,
  };
}

/** Returns the caller's invite code, creating it on first use. */
export async function getInviteCode(db: Firestore, uid: string, now: Date): Promise<InviteInfo> {
  const refDoc = db.doc(`referrals/${uid}`);
  for (let attempt = 0; attempt < 5; attempt++) {
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(refDoc);
      const existing = snap.get("code");
      if (typeof existing === "string") return info(existing, snap, now);
      const code = newCode();
      const codeRef = db.doc(`inviteCodes/${code}`);
      if ((await tx.get(codeRef)).exists) return null; // collision: retry
      tx.create(codeRef, { uid, createdAt: FieldValue.serverTimestamp() });
      tx.set(refDoc, { code, monthKey: monthKey(now), monthCount: 0, totalCount: 0, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return info(code, undefined, now);
    });
    if (result) return result;
  }
  throw new HttpsError("unavailable", "code_generation_failed");
}

/**
 * Adds [days] of Premium to entitlements/{uid}. A running paid subscription
 * keeps its source/product and is extended; otherwise the entitlement
 * becomes a referral one.
 */
function grant(tx: Transaction, db: Firestore, uid: string, snap: DocumentSnapshot, days: number, now: Date): number {
  const current = snap.get("expiresAt") as Timestamp | undefined;
  const running = snap.get("active") === true && current !== undefined && current.toMillis() > now.getTime();
  const expiresAt = (running ? current!.toMillis() : now.getTime()) + days * DAY_MS;
  const paid = running && snap.get("source") !== "referral";
  tx.set(db.doc(`entitlements/${uid}`), {
    active: true,
    premium: true,
    status: "active",
    productId: paid ? snap.get("productId") : REFERRAL_PRODUCT_ID,
    source: paid ? snap.get("source") : "referral",
    expiresAt: Timestamp.fromMillis(expiresAt),
    referralDays: FieldValue.increment(days),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return expiresAt;
}

/** { code, deviceId } -> RedeemResult. Abuse rules: docs/analitik.md#davet. */
export async function redeemInvite(db: Firestore, uid: string, data: unknown, ctx: RedeemContext): Promise<RedeemResult> {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const code = normalizeCode(d.code);
  const deviceId = d.deviceId;
  if (typeof deviceId !== "string" || deviceId.length < 8 || deviceId.length > 128) {
    throw new HttpsError("invalid-argument", "invalid_device");
  }
  if (ctx.signInProvider === "anonymous") throw new HttpsError("failed-precondition", "sign_in_required");
  if (ctx.now.getTime() - ctx.accountCreatedAt.getTime() > NEW_ACCOUNT_DAYS * DAY_MS) {
    throw new HttpsError("failed-precondition", "not_new_user");
  }

  const now = ctx.now;
  const deviceHash = hashDevice(deviceId);
  return db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(db.doc(`inviteCodes/${code}`));
    if (!codeSnap.exists) throw new HttpsError("not-found", "unknown_code");
    const inviterUid = codeSnap.get("uid") as string;
    if (inviterUid === uid) throw new HttpsError("failed-precondition", "own_code");

    const mineRef = db.doc(`referralRedemptions/${uid}`);
    const deviceRef = db.doc(`referralDevices/${deviceHash}`);
    const inviterRedemptionRef = db.doc(`referralRedemptions/${inviterUid}`);
    const inviterRef = db.doc(`referrals/${inviterUid}`);
    const [mine, device, inviterRedemption, inviter, myEnt, inviterEnt] = await Promise.all([
      tx.get(mineRef),
      tx.get(deviceRef),
      tx.get(inviterRedemptionRef),
      tx.get(inviterRef),
      tx.get(db.doc(`entitlements/${uid}`)),
      tx.get(db.doc(`entitlements/${inviterUid}`)),
    ]);
    if (mine.exists) throw new HttpsError("already-exists", "already_redeemed");
    if (device.exists) throw new HttpsError("already-exists", "device_used");
    // A and B inviting each other in a loop.
    if (inviterRedemption.get("inviterUid") === uid) throw new HttpsError("failed-precondition", "mutual_invite");

    const month = monthKey(now);
    const monthCount = inviter.get("monthKey") === month ? (inviter.get("monthCount") ?? 0) : 0;
    const inviterRewarded = monthCount < MAX_REWARDS_PER_MONTH;

    const expiresAt = grant(tx, db, uid, myEnt, REWARD_DAYS, now);
    if (inviterRewarded) grant(tx, db, inviterUid, inviterEnt, REWARD_DAYS, now);

    tx.create(mineRef, { inviterUid, code, deviceHash, inviterRewarded, at: FieldValue.serverTimestamp() });
    tx.create(deviceRef, { uid, at: FieldValue.serverTimestamp() });
    tx.set(inviterRef, {
      monthKey: month,
      monthCount: inviterRewarded ? monthCount + 1 : monthCount,
      totalCount: (inviter.get("totalCount") ?? 0) + (inviterRewarded ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true as const, rewardDays: REWARD_DAYS, expiresAt, inviterRewarded };
  });
}
