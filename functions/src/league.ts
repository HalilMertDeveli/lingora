// Real leagues: weekly groups of up to 15 people per tier. The rules match the
// on-device league in lib/data/league.dart: top 5 move up (only with some XP),
// ranks 11-15 move down, five tiers Bronz -> Elmas.
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { dayKey, weekKey } from "./week.js";

export const TIER_COUNT = 5;
export const LEAGUE_SIZE = 15;
export const PROMOTE_COUNT = 5;
export const DEMOTE_COUNT = 5;

/** addLeagueXp limits: per call, per Turkish day, and time between calls. */
export const MAX_XP_PER_CALL = 500;
export const MAX_XP_PER_DAY = 3000;
export const MIN_XP_INTERVAL_MS = 3000;

const MAX_NAME = 24;
const MAX_AVATAR = 8;
const DEFAULT_NAME = "Dilbaz öğrencisi";
const DEFAULT_AVATAR = "⭐";

export interface LeagueResult {
  weekKey: string;
  oldTier: number;
  newTier: number;
  rank: number;
}

export interface LeagueState {
  tier: number;
  weekKey?: string | null;
  groupId?: string | null;
  name?: string;
  avatar?: string;
  lastResult?: LeagueResult;
  xpDay?: string;
  xpDayTotal?: number;
  lastXpAt?: Timestamp;
}

export interface JoinResult {
  groupId: string;
  weekKey: string;
  tier: number;
}

export const groupIdOf = (week: string, tier: number, group: number) => `${week}_${tier}_${group}`;

function cleanText(raw: unknown, max: number): string {
  if (typeof raw !== "string") return "";
  // Drop control characters, collapse whitespace.
  return Array.from(raw.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim())
    .slice(0, max)
    .join("");
}

export function parseJoinInput(data: unknown): { name: string; avatar: string; tier: number | null } {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const name = cleanText(d.name, MAX_NAME);
  if (d.name !== undefined && !name) throw new HttpsError("invalid-argument", "name must be a non-empty string");
  const avatar = cleanText(d.avatar, MAX_AVATAR);
  let tier: number | null = null;
  if (d.tier !== undefined && d.tier !== null) {
    if (!Number.isInteger(d.tier) || (d.tier as number) < 0 || (d.tier as number) >= TIER_COUNT) {
      throw new HttpsError("invalid-argument", "tier must be an integer 0-4");
    }
    tier = d.tier as number;
  }
  return { name: name || DEFAULT_NAME, avatar: avatar || DEFAULT_AVATAR, tier };
}

/**
 * Puts the user into a group for the current week (idempotent). New users
 * start in the tier the app reports (their offline league) or Bronz.
 */
export async function joinLeague(
  db: Firestore,
  uid: string,
  input: { name: string; avatar: string; tier: number | null },
  now: Date,
): Promise<JoinResult> {
  const week = weekKey(now);
  const stateRef = db.doc(`leagueState/${uid}`);

  // A previous week that the scheduler has not closed yet is closed here, so
  // the new week starts from the right tier.
  const before = (await stateRef.get()).data() as LeagueState | undefined;
  if (before?.groupId && before.weekKey && before.weekKey < week) {
    await settleGroup(db, before.groupId, now);
  }

  return db.runTransaction(async (tx) => {
    const state = (await tx.get(stateRef)).data() as LeagueState | undefined;
    if (state?.weekKey === week && state.groupId) {
      const memberRef = db.doc(`leagues/${state.groupId}/members/${uid}`);
      if (state.name !== input.name || state.avatar !== input.avatar) {
        tx.update(memberRef, { name: input.name, avatar: input.avatar });
        tx.update(stateRef, { name: input.name, avatar: input.avatar });
      }
      return { groupId: state.groupId, weekKey: week, tier: state.tier };
    }

    const tier = state ? state.tier : (input.tier ?? 0);
    const counterRef = db.doc(`leagueWeeks/${week}_${tier}`);
    const counter = (await tx.get(counterRef)).data() as { openGroup: number; openCount: number } | undefined;
    let group = counter?.openGroup ?? 0;
    let count = counter?.openCount ?? 0;
    if (count >= LEAGUE_SIZE) {
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
      name: input.name,
      avatar: input.avatar,
      xp: 0,
      joinedAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    tx.set(stateRef, { tier, weekKey: week, groupId, name: input.name, avatar: input.avatar }, { merge: true });
    return { groupId, weekKey: week, tier };
  });
}

/** Adds XP the app earned to this week's group. Returns the new weekly XP. */
export async function addLeagueXp(
  db: Firestore,
  uid: string,
  data: unknown,
  now: Date,
): Promise<{ xp: number; accepted: number }> {
  const raw = (data as Record<string, unknown> | null)?.xp;
  if (!Number.isInteger(raw) || (raw as number) <= 0 || (raw as number) > MAX_XP_PER_CALL) {
    throw new HttpsError("invalid-argument", `xp must be an integer 1-${MAX_XP_PER_CALL}`);
  }
  const xp = raw as number;
  const week = weekKey(now);
  const day = dayKey(now);
  const stateRef = db.doc(`leagueState/${uid}`);

  return db.runTransaction(async (tx) => {
    const state = (await tx.get(stateRef)).data() as LeagueState | undefined;
    if (!state || state.weekKey !== week || !state.groupId) {
      throw new HttpsError("failed-precondition", "not_joined");
    }
    const memberRef = db.doc(`leagues/${state.groupId}/members/${uid}`);
    const member = await tx.get(memberRef);
    if (!member.exists) throw new HttpsError("failed-precondition", "not_joined");

    if (state.lastXpAt && now.getTime() - state.lastXpAt.toMillis() < MIN_XP_INTERVAL_MS) {
      throw new HttpsError("resource-exhausted", "too_fast");
    }
    const usedToday = state.xpDay === day ? (state.xpDayTotal ?? 0) : 0;
    const accepted = Math.min(xp, MAX_XP_PER_DAY - usedToday);
    const current = (member.get("xp") as number) ?? 0;
    if (accepted <= 0) return { xp: current, accepted: 0 };

    tx.update(memberRef, { xp: current + accepted, updatedAt: Timestamp.fromDate(now) });
    tx.update(stateRef, { xpDay: day, xpDayTotal: usedToday + accepted, lastXpAt: Timestamp.fromDate(now) });
    return { xp: current + accepted, accepted };
  });
}

interface RankedMember {
  uid: string;
  xp: number;
  joinedAt: number;
}

/** Highest XP first; on a tie whoever joined earlier ranks higher. */
export function rankMembers(members: RankedMember[]): RankedMember[] {
  return [...members].sort((a, b) => b.xp - a.xp || a.joinedAt - b.joinedAt || a.uid.localeCompare(b.uid));
}

/** Next week's tier, with the same zones as the app's local league. */
export function nextTier(tier: number, rank: number, xp: number): number {
  if (xp > 0 && tier < TIER_COUNT - 1 && rank <= PROMOTE_COUNT) return tier + 1;
  if (tier > 0 && rank > LEAGUE_SIZE - DEMOTE_COUNT) return tier - 1;
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
        joinedAt: (m.get("joinedAt") as Timestamp | undefined)?.toMillis() ?? 0,
      })),
    );
    const stateRefs = ranked.map((m) => db.doc(`leagueState/${m.uid}`));
    const states = stateRefs.length ? await tx.getAll(...stateRefs) : [];

    ranked.forEach((m, i) => {
      const rank = i + 1;
      const newTier = nextTier(tier, rank, m.xp);
      tx.update(groupRef.collection("members").doc(m.uid), { rank });
      const state = states[i];
      // Only touch the state if it still points at this group.
      if (state.exists && state.get("groupId") === groupId) {
        tx.update(stateRefs[i], {
          tier: newTier,
          weekKey: null,
          groupId: null,
          lastResult: { weekKey: week, oldTier: tier, newTier, rank },
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
