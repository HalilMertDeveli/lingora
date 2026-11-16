// Dilmaç Dünya Ligi: weekly groups of up to 100 signed-in learners from any
// country, ten tiers Bronz -> Elmas. lib/data/league.dart has the same tier
// list and zone rules for the on-device preview.
//
// Everything here runs with the Admin SDK; firestore.rules keep leagues/**
// and leagueState/** read-only for clients, so nobody can write a row.
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { dayKey, weekKey } from "./week.js";

export const TIER_COUNT = 10;
export const GROUP_SIZE = 100;

/**
 * XP limits. The app reports its weekly total; the server accepts the
 * difference to what it already has, at most this much per minute and per
 * Turkish day. A normal lesson gives 10-30 XP, a mock exam up to ~150.
 */
export const MAX_XP_PER_MINUTE = 300;
export const MAX_XP_PER_DAY = 3000;
/** Calls closer together than this are refused (cost guard). */
export const MIN_XP_INTERVAL_MS = 2000;

const MAX_NAME = 24;
const MAX_AVATAR = 8;
/** Thumbnail photo the app sends on join: a small JPEG, base64. */
export const MAX_PHOTO_BYTES = 8 * 1024;
const DEFAULT_NAME = "Dilmaç öğrencisi";
const DEFAULT_AVATAR = "⭐";

export interface LeagueResult {
  weekKey: string;
  oldTier: number;
  newTier: number;
  rank: number;
  size: number;
  xp: number;
}

export interface LeagueState {
  tier: number;
  weekKey?: string | null;
  groupId?: string | null;
  optedOut?: boolean;
  lastResult?: LeagueResult;
  xpDay?: string;
  xpDayTotal?: number;
  xpMinute?: number;
  xpMinuteTotal?: number;
  lastXpAt?: Timestamp;
}

export interface JoinInput {
  name: string;
  avatar: string;
  country: string | null;
  photo: Buffer | null;
}

export interface JoinResult {
  groupId: string;
  weekKey: string;
  tier: number;
}

export const groupIdOf = (week: string, tier: number, group: number) => `${week}_${tier}_${group}`;

/**
 * How many move up and down at the end of the week in a group of [size].
 * A full group of 100: 15 up in Bronz-Altın, 10 up above; nobody drops out
 * of Bronz, 5 drop in Gümüş-Yakut, 10 from Zümrüt up; Elmas is the top.
 * Smaller groups scale down (promotion rounds up, so a tiny group still
 * sends its winner up; dropping rounds down).
 */
export function zones(tier: number, size: number = GROUP_SIZE): { promote: number; demote: number } {
  const promoteFull = tier >= TIER_COUNT - 1 ? 0 : tier <= 2 ? 15 : 10;
  const demoteFull = tier === 0 ? 0 : tier <= 4 ? 5 : 10;
  const n = Math.max(0, Math.min(size, GROUP_SIZE));
  const promote = Math.ceil((n * promoteFull) / GROUP_SIZE);
  const demote = Math.min(Math.floor((n * demoteFull) / GROUP_SIZE), n - promote);
  return { promote, demote: Math.max(0, demote) };
}

function cleanText(raw: unknown, max: number): string {
  if (typeof raw !== "string") return "";
  // Drop control characters, collapse whitespace.
  return Array.from(raw.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim())
    .slice(0, max)
    .join("");
}

/** True for bytes that start like a JPEG (FF D8 FF). */
const isJpeg = (b: Buffer) => b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;

export function parseJoinInput(data: unknown): JoinInput {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const name = cleanText(d.name, MAX_NAME);
  if (d.name !== undefined && !name) throw new HttpsError("invalid-argument", "name must be a non-empty string");
  const avatar = cleanText(d.avatar, MAX_AVATAR);

  let country: string | null = null;
  if (d.country !== undefined && d.country !== null) {
    if (typeof d.country !== "string" || !/^[A-Z]{2}$/.test(d.country)) {
      throw new HttpsError("invalid-argument", "country must be an ISO 3166 alpha-2 code");
    }
    country = d.country;
  }

  let photo: Buffer | null = null;
  if (d.photo !== undefined && d.photo !== null) {
    if (typeof d.photo !== "string" || d.photo.length > Math.ceil((MAX_PHOTO_BYTES * 4) / 3) + 4) {
      throw new HttpsError("invalid-argument", "photo too large");
    }
    photo = Buffer.from(d.photo, "base64");
    if (photo.length < 100 || photo.length > MAX_PHOTO_BYTES || !isJpeg(photo)) {
      throw new HttpsError("invalid-argument", "photo must be a small JPEG");
    }
  }
  return { name: name || DEFAULT_NAME, avatar: avatar || DEFAULT_AVATAR, country, photo };
}

function memberProfile(input: JoinInput): Record<string, unknown> {
  return { name: input.name, avatar: input.avatar, country: input.country, photo: input.photo };
}

function sameProfile(m: FirebaseFirestore.DocumentData | undefined, input: JoinInput): boolean {
  if (!m) return false;
  const photo = m.photo as Buffer | Uint8Array | null | undefined;
  const samePhoto =
    (photo == null && input.photo == null) ||
    (photo != null && input.photo != null && Buffer.compare(Buffer.from(photo), input.photo) === 0);
  return m.name === input.name && m.avatar === input.avatar && (m.country ?? null) === input.country && samePhoto;
}

/**
 * Puts the user into a group for the current week (idempotent) and keeps
 * their name, avatar, country and photo there up to date. Everybody starts
 * in Bronz: the on-device tier cannot be trusted.
 */
export async function joinLeague(db: Firestore, uid: string, input: JoinInput, now: Date): Promise<JoinResult> {
  const week = weekKey(now);
  const stateRef = db.doc(`leagueState/${uid}`);

  // A previous week the scheduler has not closed yet is closed here, so the
  // new week starts from the right tier.
  const before = (await stateRef.get()).data() as LeagueState | undefined;
  if (before?.groupId && before.weekKey && before.weekKey < week) {
    await settleGroup(db, before.groupId, now);
  }

  return db.runTransaction(async (tx) => {
    const state = (await tx.get(stateRef)).data() as LeagueState | undefined;
    if (state?.weekKey === week && state.groupId) {
      const memberRef = db.doc(`leagues/${state.groupId}/members/${uid}`);
      const member = await tx.get(memberRef);
      if (member.exists && !sameProfile(member.data(), input)) tx.update(memberRef, memberProfile(input));
      if (state.optedOut) tx.update(stateRef, { optedOut: false });
      return { groupId: state.groupId, weekKey: week, tier: state.tier };
    }

    const tier = state?.tier ?? 0;
    const counterRef = db.doc(`leagueWeeks/${week}_${tier}`);
    const counter = (await tx.get(counterRef)).data() as { openGroup: number; openCount: number } | undefined;
    let group = counter?.openGroup ?? 0;
    let count = counter?.openCount ?? 0;
    if (count >= GROUP_SIZE) {
      group += 1;
      count = 0;
    }
    const groupId = groupIdOf(week, tier, group);
    const groupRef = db.doc(`leagues/${groupId}`);
    if (count === 0) {
      tx.set(groupRef, { weekKey: week, tier, group, size: 1, settled: false, createdAt: FieldValue.serverTimestamp() });
    } else {
      tx.update(groupRef, { size: FieldValue.increment(1) });
    }
    tx.set(counterRef, { openGroup: group, openCount: count + 1 });
    tx.set(db.doc(`leagues/${groupId}/members/${uid}`), {
      ...memberProfile(input),
      xp: 0,
      joinedAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    tx.set(stateRef, { tier, weekKey: week, groupId, optedOut: false }, { merge: true });
    return { groupId, weekKey: week, tier };
  });
}

/**
 * Leaves this week's group: the row disappears for everyone and the app
 * stops joining until the learner joins again. The tier is kept.
 */
export async function leaveLeague(db: Firestore, uid: string): Promise<{ left: boolean }> {
  const stateRef = db.doc(`leagueState/${uid}`);
  return db.runTransaction(async (tx) => {
    const state = (await tx.get(stateRef)).data() as LeagueState | undefined;
    if (!state) return { left: false };
    if (state.groupId) {
      const memberRef = db.doc(`leagues/${state.groupId}/members/${uid}`);
      const groupRef = db.doc(`leagues/${state.groupId}`);
      const [member, group] = [await tx.get(memberRef), await tx.get(groupRef)];
      if (member.exists && group.exists && group.get("settled") !== true) {
        tx.delete(memberRef);
        tx.update(groupRef, { size: FieldValue.increment(-1) });
      }
    }
    tx.update(stateRef, { optedOut: true, groupId: null, weekKey: null });
    return { left: true };
  });
}

/**
 * The app reports its XP for the league week; the server adds what it has
 * not seen yet, within the per-minute and per-day limits. Repeating a call
 * never counts twice. Returns the weekly total on the server and how much
 * is still waiting (the app retries it later).
 */
export async function addLeagueXp(
  db: Firestore,
  uid: string,
  data: unknown,
  now: Date,
): Promise<{ xp: number; accepted: number; pending: number }> {
  const d = (data ?? {}) as Record<string, unknown>;
  const claimed = d.weekXp;
  if (!Number.isInteger(claimed) || (claimed as number) < 0 || (claimed as number) > 7 * MAX_XP_PER_DAY * 10) {
    throw new HttpsError("invalid-argument", "weekXp must be a non-negative integer");
  }
  const week = weekKey(now);
  // The app counts its week in local time; near the boundary another time
  // zone may still report last week. Nothing is added then.
  if (d.weekKey !== undefined && d.weekKey !== week) {
    throw new HttpsError("failed-precondition", "other_week");
  }
  const day = dayKey(now);
  const minute = Math.floor(now.getTime() / 60000);
  const stateRef = db.doc(`leagueState/${uid}`);

  return db.runTransaction(async (tx) => {
    const state = (await tx.get(stateRef)).data() as LeagueState | undefined;
    if (!state || state.weekKey !== week || !state.groupId) {
      throw new HttpsError("failed-precondition", "not_joined");
    }
    const memberRef = db.doc(`leagues/${state.groupId}/members/${uid}`);
    const member = await tx.get(memberRef);
    if (!member.exists) throw new HttpsError("failed-precondition", "not_joined");

    const current = (member.get("xp") as number) ?? 0;
    const wanted = (claimed as number) - current;
    if (wanted <= 0) return { xp: current, accepted: 0, pending: 0 };

    if (state.lastXpAt && now.getTime() - state.lastXpAt.toMillis() < MIN_XP_INTERVAL_MS) {
      throw new HttpsError("resource-exhausted", "too_fast");
    }
    const usedToday = state.xpDay === day ? (state.xpDayTotal ?? 0) : 0;
    const usedMinute = state.xpMinute === minute ? (state.xpMinuteTotal ?? 0) : 0;
    const accepted = Math.max(0, Math.min(wanted, MAX_XP_PER_DAY - usedToday, MAX_XP_PER_MINUTE - usedMinute));
    if (accepted === 0) return { xp: current, accepted: 0, pending: wanted };

    tx.update(memberRef, { xp: current + accepted, updatedAt: Timestamp.fromDate(now) });
    tx.update(stateRef, {
      xpDay: day,
      xpDayTotal: usedToday + accepted,
      xpMinute: minute,
      xpMinuteTotal: usedMinute + accepted,
      lastXpAt: Timestamp.fromDate(now),
    });
    return { xp: current + accepted, accepted, pending: wanted - accepted };
  });
}

interface RankedMember {
  uid: string;
  xp: number;
  /** When the member last gained XP (or joined): reaching a score first wins a tie. */
  reachedAt: number;
}

/** Highest XP first; on a tie whoever got there earlier ranks higher. */
export function rankMembers<T extends RankedMember>(members: T[]): T[] {
  return [...members].sort((a, b) => b.xp - a.xp || a.reachedAt - b.reachedAt || a.uid.localeCompare(b.uid));
}

/** Next week's tier for [rank] (1-based) in a group of [size]. */
export function nextTier(tier: number, rank: number, xp: number, size: number = GROUP_SIZE): number {
  const z = zones(tier, size);
  if (xp > 0 && rank <= z.promote) return tier + 1;
  if (rank > size - z.demote) return tier - 1;
  return tier;
}

/**
 * Closes one finished group: stores each member's result and next tier in
 * leagueState. Idempotent, and refuses groups whose week is still running.
 */
export async function settleGroup(db: Firestore, groupId: string, now: Date): Promise<boolean> {
  const groupRef = db.doc(`leagues/${groupId}`);
  return db.runTransaction(async (tx) => {
    const group = await tx.get(groupRef);
    if (!group.exists || group.get("settled") === true) return false;
    const week = group.get("weekKey") as string;
    if (week >= weekKey(now)) return false;
    const tier = group.get("tier") as number;

    const members = await tx.get(groupRef.collection("members"));
    const ranked = rankMembers(
      members.docs.map((m) => ({
        uid: m.id,
        xp: (m.get("xp") as number) ?? 0,
        reachedAt: ((m.get("updatedAt") ?? m.get("joinedAt")) as Timestamp | undefined)?.toMillis() ?? 0,
      })),
    );
    const size = ranked.length;
    const stateRefs = ranked.map((m) => db.doc(`leagueState/${m.uid}`));
    const states = stateRefs.length ? await tx.getAll(...stateRefs) : [];

    ranked.forEach((m, i) => {
      const rank = i + 1;
      const newTier = nextTier(tier, rank, m.xp, size);
      tx.update(groupRef.collection("members").doc(m.uid), { rank });
      const state = states[i];
      // Only touch the state if it still points at this group.
      if (state.exists && state.get("groupId") === groupId) {
        tx.update(stateRefs[i], {
          tier: newTier,
          weekKey: null,
          groupId: null,
          lastResult: { weekKey: week, oldTier: tier, newTier, rank, size, xp: m.xp },
        });
      }
    });
    tx.update(groupRef, { settled: true, settledAt: FieldValue.serverTimestamp() });
    return true;
  });
}

/** Closes every finished, unsettled group. Run weekly by the scheduler. */
export async function settleFinishedWeeks(db: Firestore, now: Date): Promise<number> {
  const current = weekKey(now);
  const open = await db.collection("leagues").where("settled", "==", false).get();
  let settled = 0;
  for (const g of open.docs) {
    if ((g.get("weekKey") as string) >= current) continue;
    if (await settleGroup(db, g.id, now)) settled++;
  }
  return settled;
}
