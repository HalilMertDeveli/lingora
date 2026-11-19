// Invite programme ("Arkadaşını getir"): every user gets a short code. A new
// user redeems it, and once that friend has finished their first lesson both
// get REWARD_DAYS of Premium through entitlements/{uid} (source: "invite").
// Docs: docs/buyume-kampanya.md, docs/analitik.md#davet.
//
// Server-only collections (closed to clients by firestore.rules):
//   inviteCodes/{CODE}           { uid, createdAt }
//   referrals/{inviterUid}       { code, monthKey, monthCount, totalCount, deviceHashes[], updatedAt }
//   referralRedemptions/{uid}    { inviterUid, code, deviceHash, status: pending|rewarded, inviterRewarded, at, rewardedAt? }
//   referralDevices/{deviceHash} { uid, at }
//
// "First lesson" = users/{uid}.progress.lessonsDone >= 1 (the synced progress
// snapshot). redeemInvite rewards at once when it is already there; otherwise
// the inviteFirstLesson trigger (referral_api.ts) rewards when it appears.
import { createHash, randomInt } from "node:crypto";

import { DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const REWARD_DAYS = 7;
/** Rewards one inviter can earn per calendar month (Turkish time). */
export const MAX_REWARDS_PER_MONTH = 5;
/** Only accounts younger than this may redeem a code ("new user"). */
export const NEW_ACCOUNT_DAYS = 14;
/** productId stays "referral" so older app versions still recognise it. */
export const REFERRAL_PRODUCT_ID = "referral";
/** entitlements/{uid}.source of an invite reward. */
export const INVITE_SOURCE = "invite";
/** Sources this programme has written (the first version used "referral"). */
const INVITE_SOURCES = new Set([INVITE_SOURCE, "referral"]);
/** Install ids remembered per inviter (their own phones, for "same_device"). */
export const MAX_INVITER_DEVICES = 5;

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
  /** "pending" until the redeemer has finished their first lesson. */
  status: "pending" | "rewarded";
  rewardDays: number;
  /** New Premium end for the redeemer, ms since epoch (when rewarded). */
  expiresAt?: number;
  inviterRewarded: boolean;
}

export interface RewardResult {
  /** The redeemer's Premium end, ms since epoch. */
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

function validDeviceId(raw: unknown): raw is string {
  return typeof raw === "string" && raw.length >= 8 && raw.length <= 128;
}

/** users/{uid}.progress.lessonsDone of a synced progress snapshot (0 when missing). */
export function lessonsDoneOf(data: Record<string, unknown> | undefined): number {
  const progress = data?.progress as Record<string, unknown> | undefined;
  const n = progress?.lessonsDone;
  return typeof n === "number" && Number.isFinite(n) ? n : 0;
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

/**
 * Returns the caller's invite code, creating it on first use. [deviceId] (the
 * app's install id) is remembered so a friend cannot redeem the code on the
 * inviter's own phone.
 */
export async function getInviteCode(db: Firestore, uid: string, now: Date, deviceId?: unknown): Promise<InviteInfo> {
  const refDoc = db.doc(`referrals/${uid}`);
  const deviceHash = validDeviceId(deviceId) ? hashDevice(deviceId) : null;
  for (let attempt = 0; attempt < 5; attempt++) {
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(refDoc);
      const existing = snap.get("code");
      const known = (snap.get("deviceHashes") as string[] | undefined) ?? [];
      const devices =
        deviceHash !== null && !known.includes(deviceHash) ? [...known, deviceHash].slice(-MAX_INVITER_DEVICES) : null;
      if (typeof existing === "string") {
        if (devices) tx.set(refDoc, { deviceHashes: devices }, { merge: true });
        return info(existing, snap, now);
      }
      const code = newCode();
      const codeRef = db.doc(`inviteCodes/${code}`);
      if ((await tx.get(codeRef)).exists) return null; // collision: retry
      tx.create(codeRef, { uid, createdAt: FieldValue.serverTimestamp() });
      tx.set(
        refDoc,
        {
          code,
          monthKey: monthKey(now),
          monthCount: 0,
          totalCount: 0,
          ...(devices ? { deviceHashes: devices } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return info(code, undefined, now);
    });
    if (result) return result;
  }
  throw new HttpsError("unavailable", "code_generation_failed");
}

/**
 * Adds [days] of Premium to entitlements/{uid} and never shortens one: a
 * running Premium from another source (Play, family, org) keeps its
 * source/product and is extended; an open-ended one (active without
 * expiresAt) is left alone. Otherwise the entitlement becomes an invite one.
 * Returns the new end, ms since epoch.
 */
function grant(tx: Transaction, db: Firestore, uid: string, snap: DocumentSnapshot, days: number, now: Date): number {
  const current = snap.get("expiresAt") as Timestamp | undefined;
  const active = snap.get("active") === true;
  if (active && current === undefined) return Number.MAX_SAFE_INTEGER;
  const running = active && current !== undefined && current.toMillis() > now.getTime();
  const expiresAt = (running ? current!.toMillis() : now.getTime()) + days * DAY_MS;
  const paid = running && !INVITE_SOURCES.has(snap.get("source"));
  tx.set(db.doc(`entitlements/${uid}`), {
    active: true,
    premium: true,
    status: "active",
    productId: paid ? snap.get("productId") : REFERRAL_PRODUCT_ID,
    source: paid ? snap.get("source") : INVITE_SOURCE,
    expiresAt: Timestamp.fromMillis(expiresAt),
    referralDays: FieldValue.increment(days),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return expiresAt;
}

/**
 * Rewards the redeemer and, within the monthly cap, the inviter, and updates
 * the inviter's counters. Call only after every read of [tx].
 */
function rewardBoth(
  tx: Transaction,
  db: Firestore,
  uid: string,
  inviterUid: string,
  inviter: DocumentSnapshot,
  myEnt: DocumentSnapshot,
  inviterEnt: DocumentSnapshot,
  now: Date,
): RewardResult {
  const month = monthKey(now);
  const monthCount = inviter.get("monthKey") === month ? (inviter.get("monthCount") ?? 0) : 0;
  const inviterRewarded = monthCount < MAX_REWARDS_PER_MONTH;
  const expiresAt = grant(tx, db, uid, myEnt, REWARD_DAYS, now);
  if (inviterRewarded) grant(tx, db, inviterUid, inviterEnt, REWARD_DAYS, now);
  tx.set(db.doc(`referrals/${inviterUid}`), {
    monthKey: month,
    monthCount: inviterRewarded ? monthCount + 1 : monthCount,
    totalCount: (inviter.get("totalCount") ?? 0) + (inviterRewarded ? 1 : 0),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { expiresAt, inviterRewarded };
}

/** { code, deviceId } -> RedeemResult. Abuse rules: docs/buyume-kampanya.md. */
export async function redeemInvite(db: Firestore, uid: string, data: unknown, ctx: RedeemContext): Promise<RedeemResult> {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const code = normalizeCode(d.code);
  const deviceId = d.deviceId;
  if (!validDeviceId(deviceId)) throw new HttpsError("invalid-argument", "invalid_device");
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
    const [mine, device, inviterRedemption, inviter, user, myEnt, inviterEnt] = await Promise.all([
      tx.get(mineRef),
      tx.get(deviceRef),
      tx.get(db.doc(`referralRedemptions/${inviterUid}`)),
      tx.get(db.doc(`referrals/${inviterUid}`)),
      tx.get(db.doc(`users/${uid}`)),
      tx.get(db.doc(`entitlements/${uid}`)),
      tx.get(db.doc(`entitlements/${inviterUid}`)),
    ]);
    if (mine.exists) throw new HttpsError("already-exists", "already_redeemed");
    if (device.exists) throw new HttpsError("already-exists", "device_used");
    // A second account on a phone the inviter uses.
    const inviterDevices = (inviter.get("deviceHashes") as string[] | undefined) ?? [];
    if (inviterDevices.includes(deviceHash)) throw new HttpsError("failed-precondition", "same_device");
    // A and B inviting each other in a loop.
    if (inviterRedemption.get("inviterUid") === uid) throw new HttpsError("failed-precondition", "mutual_invite");

    const reward = lessonsDoneOf(user.data()) >= 1
      ? rewardBoth(tx, db, uid, inviterUid, inviter, myEnt, inviterEnt, now)
      : null;
    tx.create(mineRef, {
      inviterUid,
      code,
      deviceHash,
      status: reward ? "rewarded" : "pending",
      inviterRewarded: reward?.inviterRewarded ?? false,
      at: FieldValue.serverTimestamp(),
      ...(reward ? { rewardedAt: FieldValue.serverTimestamp() } : {}),
    });
    tx.create(deviceRef, { uid, at: FieldValue.serverTimestamp() });
    if (!reward) return { ok: true as const, status: "pending" as const, rewardDays: REWARD_DAYS, inviterRewarded: false };
    return {
      ok: true as const,
      status: "rewarded" as const,
      rewardDays: REWARD_DAYS,
      expiresAt: reward.expiresAt,
      inviterRewarded: reward.inviterRewarded,
    };
  });
}

/**
 * Rewards [uid]'s pending redemption once their first lesson is synced.
 * Idempotent: null when there is nothing (left) to reward.
 */
export async function completeInviteReward(db: Firestore, uid: string, now: Date): Promise<RewardResult | null> {
  const mineRef = db.doc(`referralRedemptions/${uid}`);
  return db.runTransaction(async (tx) => {
    const mine = await tx.get(mineRef);
    if (!mine.exists || mine.get("status") !== "pending") return null;
    const inviterUid = mine.get("inviterUid") as string;
    const [user, inviter, myEnt, inviterEnt] = await Promise.all([
      tx.get(db.doc(`users/${uid}`)),
      tx.get(db.doc(`referrals/${inviterUid}`)),
      tx.get(db.doc(`entitlements/${uid}`)),
      tx.get(db.doc(`entitlements/${inviterUid}`)),
    ]);
    if (lessonsDoneOf(user.data()) < 1) return null;
    const reward = rewardBoth(tx, db, uid, inviterUid, inviter, myEnt, inviterEnt, now);
    tx.update(mineRef, {
      status: "rewarded",
      inviterRewarded: reward.inviterRewarded,
      rewardedAt: FieldValue.serverTimestamp(),
    });
    return reward;
  });
}

export interface InviteStatus {
  /** "none" (no code used), "pending" (first lesson missing) or "rewarded". */
  status: "none" | "pending" | "rewarded";
  rewardDays: number;
}

/** The caller's own redemption, for the invite screen. */
export async function inviteStatus(db: Firestore, uid: string): Promise<InviteStatus> {
  const mine = await db.doc(`referralRedemptions/${uid}`).get();
  if (!mine.exists) return { status: "none", rewardDays: REWARD_DAYS };
  // Redemptions from before the first-lesson rule have no status: rewarded.
  return { status: mine.get("status") === "pending" ? "pending" : "rewarded", rewardDays: REWARD_DAYS };
}
