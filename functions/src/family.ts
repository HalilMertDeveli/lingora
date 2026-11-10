// Family plan: the owner buys `lingora_premium_family_yearly` (verifyPurchase
// creates families/{ownerUid}), then shares an invite code. Up to
// FAMILY_SEATS - 1 other people redeem it and get Premium in
// entitlements/{uid} with `source: "family"` until the owner's plan ends.
//
// Firestore (server-only, see firestore.rules catch-all):
//   families/{ownerUid}: { ownerUid, seats, expiresAt, members: { uid: { joinedAt } }, code?, codeExpiresAt? }
//   familyCodes/{code}:  { ownerUid, expiresAt }
import { randomInt } from "node:crypto";

import { DocumentData, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const FAMILY_PRODUCT = "lingora_premium_family_yearly";

/** People in a family plan, the owner included. */
export const FAMILY_SEATS = 5;
export const MAX_MEMBERS = FAMILY_SEATS - 1;

/** How long an invite code works. */
export const CODE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/** No 0/O, 1/I/L: codes are read aloud and typed by hand. */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 8;

export function newCode(): string {
  let s = "";
  for (let i = 0; i < CODE_LENGTH; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

/** Accepts "abcd-efgh", spaces and lower case; returns null if it can't be a code. */
export function normalizeCode(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > 32) return null;
  const c = raw.toUpperCase().replace(/[\s-]/g, "");
  if (c.length !== CODE_LENGTH) return null;
  for (const ch of c) if (!ALPHABET.includes(ch)) return null;
  return c;
}

const ms = (t: unknown) => (t as Timestamp | undefined)?.toMillis() ?? 0;

function familyRef(db: Firestore, ownerUid: string) {
  return db.doc(`families/${ownerUid}`);
}

/** Owner only: makes a new invite code (the previous one stops working). */
export async function createFamilyInvite(
  db: Firestore,
  ownerUid: string,
  now: Date,
): Promise<{ code: string; expiresAt: number }> {
  const ref = familyRef(db, ownerUid);
  return db.runTransaction(async (tx) => {
    const fam = (await tx.get(ref)).data();
    if (!fam || ms(fam.expiresAt) <= now.getTime()) {
      throw new HttpsError("failed-precondition", "no_family_plan");
    }
    let code = newCode();
    for (let i = 0; i < 5 && (await tx.get(db.doc(`familyCodes/${code}`))).exists; i++) code = newCode();
    const expiresAt = Math.min(now.getTime() + CODE_TTL_MS, ms(fam.expiresAt));
    if (typeof fam.code === "string") tx.delete(db.doc(`familyCodes/${fam.code}`));
    tx.set(db.doc(`familyCodes/${code}`), { ownerUid, expiresAt: Timestamp.fromMillis(expiresAt) });
    tx.update(ref, { code, codeExpiresAt: Timestamp.fromMillis(expiresAt), updatedAt: FieldValue.serverTimestamp() });
    return { code, expiresAt };
  });
}

export interface RedeemResult {
  active: true;
  premium: true;
  status: "active";
  productId: string;
  expiresAt: number;
  ownerUid: string;
}

/** A signed-in user joins a family with an invite code. */
export async function redeemFamilyCode(
  db: Firestore,
  uid: string,
  data: unknown,
  now: Date,
): Promise<RedeemResult> {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const code = normalizeCode(d.code);
  if (!code) throw new HttpsError("invalid-argument", "invalid_code");
  const entRef = db.doc(`entitlements/${uid}`);

  return db.runTransaction(async (tx) => {
    const invite = (await tx.get(db.doc(`familyCodes/${code}`))).data();
    if (!invite) throw new HttpsError("not-found", "unknown_code");
    if (ms(invite.expiresAt) <= now.getTime()) throw new HttpsError("deadline-exceeded", "code_expired");
    const ownerUid = invite.ownerUid as string;
    if (ownerUid === uid) throw new HttpsError("failed-precondition", "own_family");
    const ref = familyRef(db, ownerUid);
    const fam = (await tx.get(ref)).data();
    if (!fam || fam.code !== code) throw new HttpsError("not-found", "unknown_code");
    if (ms(fam.expiresAt) <= now.getTime()) throw new HttpsError("failed-precondition", "family_expired");
    const members = (fam.members as Record<string, unknown>) ?? {};
    const ent = (await tx.get(entRef)).data();
    const ownFamily = (await tx.get(familyRef(db, uid))).data();
    if (ownFamily && ms(ownFamily.expiresAt) > now.getTime()) {
      throw new HttpsError("failed-precondition", "owns_family");
    }
    const current = ent?.family?.role === "member" ? (ent.family.ownerUid as string) : null;
    if (current && current !== ownerUid) throw new HttpsError("already-exists", "in_other_family");
    if (!(uid in members) && Object.keys(members).length >= MAX_MEMBERS) {
      throw new HttpsError("resource-exhausted", "family_full");
    }

    const famUntil = ms(fam.expiresAt);
    if (!(uid in members)) {
      tx.update(ref, {
        [`members.${uid}`]: { joinedAt: FieldValue.serverTimestamp() },
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    const update: DocumentData = { family: { ownerUid, role: "member" }, updatedAt: FieldValue.serverTimestamp() };
    const ownOn = ent?.active === true || ent?.premium === true;
    const ownUntil = ownOn ? ms(ent?.expiresAt) : 0;
    // Keep a longer Premium the user already has from somewhere else.
    if (ownUntil < famUntil || ent?.source === "family") {
      Object.assign(update, {
        active: true,
        premium: true,
        status: "active",
        productId: FAMILY_PRODUCT,
        expiresAt: Timestamp.fromMillis(famUntil),
        source: "family",
      });
    }
    tx.set(entRef, update, { merge: true });
    return {
      active: true,
      premium: true,
      status: "active",
      productId: FAMILY_PRODUCT,
      expiresAt: Math.max(famUntil, ownUntil),
      ownerUid,
    };
  });
}

/** Removes [memberUid] from the family of [ownerUid] inside [tx] (reads first). */
async function dropMember(tx: Transaction, db: Firestore, ownerUid: string, memberUid: string): Promise<boolean> {
  const ref = familyRef(db, ownerUid);
  const entRef = db.doc(`entitlements/${memberUid}`);
  const fam = (await tx.get(ref)).data();
  const ent = (await tx.get(entRef)).data();
  const listed = !!fam && memberUid in ((fam.members as Record<string, unknown>) ?? {});
  const linked = ent?.family?.ownerUid === ownerUid && ent?.family?.role === "member";
  if (!listed && !linked) return false;
  if (listed) {
    tx.update(ref, { [`members.${memberUid}`]: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
  }
  if (linked) {
    const update: DocumentData = { family: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() };
    if (ent?.source === "family") {
      Object.assign(update, { active: false, premium: false, status: "expired", expiresAt: Timestamp.now() });
    }
    tx.set(entRef, update, { merge: true });
  }
  return true;
}

/** Owner removes a member; the member's family Premium ends now. */
export async function removeFamilyMember(
  db: Firestore,
  ownerUid: string,
  data: unknown,
): Promise<{ removed: boolean }> {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const memberUid = d.memberUid;
  if (typeof memberUid !== "string" || !memberUid || memberUid.length > 128 || memberUid.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid_member");
  }
  if (memberUid === ownerUid) throw new HttpsError("invalid-argument", "cannot_remove_owner");
  const removed = await db.runTransaction((tx) => dropMember(tx, db, ownerUid, memberUid));
  if (!removed) throw new HttpsError("not-found", "not_a_member");
  return { removed };
}

/** A member leaves the family they joined. */
export async function leaveFamily(db: Firestore, uid: string): Promise<{ left: boolean }> {
  const ent = (await db.doc(`entitlements/${uid}`).get()).data();
  const ownerUid = ent?.family?.role === "member" ? (ent.family.ownerUid as string) : null;
  if (!ownerUid) throw new HttpsError("failed-precondition", "not_in_family");
  return { left: await db.runTransaction((tx) => dropMember(tx, db, ownerUid, uid)) };
}

export interface FamilyMember {
  uid: string;
  displayName: string | null;
  joinedAt: number | null;
}

export type FamilyInfo =
  | { role: "none" }
  | { role: "member"; ownerUid: string; ownerName: string | null; expiresAt: number }
  | {
      role: "owner";
      seats: number;
      expiresAt: number;
      active: boolean;
      members: FamilyMember[];
      code: string | null;
      codeExpiresAt: number | null;
    };

async function displayName(db: Firestore, uid: string): Promise<string | null> {
  const n = (await db.doc(`users/${uid}`).get()).get("displayName");
  return typeof n === "string" ? n : null;
}

/** What the family screen shows. */
export async function getFamily(db: Firestore, uid: string, now: Date): Promise<FamilyInfo> {
  const fam = (await familyRef(db, uid).get()).data();
  if (fam) {
    const members = Object.entries((fam.members as Record<string, { joinedAt?: Timestamp }>) ?? {});
    const codeLive = typeof fam.code === "string" && ms(fam.codeExpiresAt) > now.getTime();
    return {
      role: "owner",
      seats: FAMILY_SEATS,
      expiresAt: ms(fam.expiresAt),
      active: ms(fam.expiresAt) > now.getTime(),
      members: await Promise.all(
        members.map(async ([m, v]) => ({
          uid: m,
          displayName: await displayName(db, m),
          joinedAt: v?.joinedAt ? ms(v.joinedAt) : null,
        })),
      ),
      code: codeLive ? (fam.code as string) : null,
      codeExpiresAt: codeLive ? ms(fam.codeExpiresAt) : null,
    };
  }
  const ent = (await db.doc(`entitlements/${uid}`).get()).data();
  if (ent?.family?.role === "member") {
    const ownerUid = ent.family.ownerUid as string;
    const owner = (await familyRef(db, ownerUid).get()).data();
    return { role: "member", ownerUid, ownerName: await displayName(db, ownerUid), expiresAt: ms(owner?.expiresAt) };
  }
  return { role: "none" };
}
