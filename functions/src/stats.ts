// Owner dashboard counters (admin panel > Panel, docs/panel-istatistik.md).
//
// Aggregated daily counts only, never who did what:
//   stats/daily/days/{yyyy-mm-dd}  { day, first_open, first_lesson, paywall_view,
//                                    purchase_start, return_d1, return_d7,
//                                    purchase_verified, premium_active, updatedAt }
// Days are Turkish calendar days (week.ts dayKey). Clients cannot read or
// write stats/ (firestore.rules); the app reports funnel steps through
// countFunnel (only with analytics consent, at most once per device and step,
// see lib/services/growth/funnel_stats.dart), verifyPurchase counts verified
// purchases, and a daily job stores how many Premium entitlements are active.
import { DocumentData, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { Caller, isLingoraAdmin } from "./orgs.js";
import { dayKey } from "./week.js";

/** Steps the app may report (countFunnel). */
export const CLIENT_STEPS = [
  "first_open",
  "first_lesson",
  "paywall_view",
  "purchase_start",
  "return_d1",
  "return_d7",
] as const;
export type ClientStep = (typeof CLIENT_STEPS)[number];

/** Counted by the server itself. */
export const SERVER_FIELDS = ["purchase_verified", "premium_active"] as const;

export const MAX_DAYS = 120;
const DAY_MS = 24 * 60 * 60 * 1000;

export function statsDayRef(db: Firestore, day: string) {
  return db.doc(`stats/daily/days/${day}`);
}

function increment(field: string, now: Date): DocumentData {
  return { day: dayKey(now), [field]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() };
}

/** Adds one to [field] of today's stats inside [tx] (call after all reads). */
export function countInTx(tx: Transaction, db: Firestore, field: string, now: Date): void {
  tx.set(statsDayRef(db, dayKey(now)), increment(field, now), { merge: true });
}

/** { step } -> { ok }: one funnel step from the app. Nothing about the caller is stored. */
export async function countFunnel(db: Firestore, data: unknown, now: Date): Promise<{ ok: true }> {
  const step = (data as { step?: unknown } | null)?.step;
  if (typeof step !== "string" || !(CLIENT_STEPS as readonly string[]).includes(step)) {
    throw new HttpsError("invalid-argument", "unknown_step");
  }
  await statsDayRef(db, dayKey(now)).set(increment(step, now), { merge: true });
  return { ok: true };
}

/** Number of entitlements that give Premium right now (paid, family, referral, org, test). */
export async function countActivePremium(db: Firestore, now: Date): Promise<number> {
  const snap = await db
    .collection("entitlements")
    .where("active", "==", true)
    .where("expiresAt", ">", Timestamp.fromDate(now))
    .count()
    .get();
  return snap.data().count;
}

/** Daily job: stores today's active Premium count. */
export async function snapshotPremium(db: Firestore, now: Date): Promise<number> {
  const n = await countActivePremium(db, now);
  await statsDayRef(db, dayKey(now)).set(
    { day: dayKey(now), premium_active: n, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return n;
}

export interface StatsDay {
  day: string;
  counts: Record<string, number>;
}

export interface StatsResult {
  days: StatsDay[];
  premiumActiveNow: number;
}

/** "yyyy-mm-dd" keys of the [n] Turkish days ending today, oldest first. */
export function lastDays(now: Date, n: number): string[] {
  const out: string[] = [];
  for (let i = n - 1; i >= 0; i--) out.push(dayKey(new Date(now.getTime() - i * DAY_MS)));
  return out;
}

/** { days? } -> StatsResult. Çenebaz staff (the owner) only. */
export async function getStats(db: Firestore, caller: Caller, data: unknown, now: Date): Promise<StatsResult> {
  if (!(await isLingoraAdmin(db, caller))) throw new HttpsError("permission-denied", "lingora_admin_only");
  const raw = (data as { days?: unknown } | null)?.days;
  const n = raw === undefined ? 28 : Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > MAX_DAYS) throw new HttpsError("invalid-argument", "bad_days");
  const keys = lastDays(now, n);
  const snaps = await db.getAll(...keys.map((k) => statsDayRef(db, k)));
  const days = snaps.map((s, i): StatsDay => {
    const counts: Record<string, number> = {};
    for (const [k, v] of Object.entries(s.data() ?? {})) {
      if (typeof v === "number") counts[k] = v;
    }
    return { day: keys[i], counts };
  });
  return { days, premiumActiveNow: await countActivePremium(db, now) };
}
