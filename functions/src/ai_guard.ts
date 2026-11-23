// Cost protection for the AI callables (converse, conversationReport,
// assessWriting, analyzeRehearsal). Free quotas are per uid, and a guest
// account is one tap away, so three more layers sit in front of Claude:
//
// 1. Firebase App Check (Play Integrity on Android): only the genuine app
//    from Play may call. Mode in config/aiGuard.appCheck:
//      "enforce" (default in production) | "monitor" (log only) | "off"
//    The emulator defaults to "off" (debug provider, CI).
// 2. Per-install soft limit for free use: the app sends its random
//    `installId` (installIdProvider); free AI calls per install per Turkish
//    day are capped at config/aiGuard.deviceFreeDaily (aiDevices/{sha256}).
//    New guest accounts on the same phone share the cap. Premium is exempt.
// 3. Global daily spend circuit breaker: every Claude response's token usage
//    is priced and added to aiSpend/{day}_{shard}. Above freeDailyUsd free
//    calls stop for the day; above dailyUsd every AI call stops
//    ("ai_budget"). Totals are cached per instance for CACHE_MS, so the
//    overshoot is bounded by maxInstances x CACHE_MS of traffic.
// 4. Per-user monthly fair use (Premium): the same cost is also added to
//    aiUserSpend/{uid}_{yyyy-mm} (Turkish month). Once a Premium user's month
//    reaches premiumMonthlyUsd, their daily AI limits drop to THROTTLED until
//    the month ends (not a hard block); hitting a throttled limit returns
//    "resource-exhausted" with reason MONTHLY_FAIR_USE.
//
// config/aiGuard (server-only, edited in the console; all fields optional):
//   { appCheck, deviceFreeDaily, freeDailyUsd, dailyUsd, premiumMonthlyUsd }
// Owner steps: docs/ai-maliyet-korumasi.md.
import { createHash, randomInt } from "node:crypto";

import { FieldValue, Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError } from "firebase-functions/v2/https";

import type { ClaudeClient } from "./converse.js";
import { dayKey, monthKey } from "./week.js";

export type AppCheckMode = "enforce" | "monitor" | "off";

export interface GuardConfig {
  appCheck: AppCheckMode;
  /** Free AI calls per install per Turkish day (all features together). */
  deviceFreeDaily: number;
  /** Above this many US$ today, free users get no AI. */
  freeDailyUsd: number;
  /** Above this many US$ today, nobody gets AI (hard stop). */
  dailyUsd: number;
  /** A Premium user's AI cost this month at or above this: THROTTLED daily limits. */
  premiumMonthlyUsd: number;
}

/** Default monthly AI cost (US$) per Premium user before the fair-use throttle. */
export const PREMIUM_MONTHLY_USD_CAP = 4;

export const DEFAULTS: GuardConfig = {
  appCheck: "enforce",
  deviceFreeDaily: 20,
  freeDailyUsd: 30,
  dailyUsd: 150,
  premiumMonthlyUsd: PREMIUM_MONTHLY_USD_CAP,
};

/**
 * Premium daily limits for the rest of the month once the user is over
 * premiumMonthlyUsd (normal values: talk.ts, converse.ts, explain_more.ts,
 * assess_writing.ts, conversation_report.ts, rehearsal.ts).
 */
export const THROTTLED = {
  talkMinutes: 10,
  /** converse + talk messages (one shared counter). */
  messages: 50,
  explain: 10,
  writing: 5,
  report: 3,
  rehearsal: 2,
} as const;

/** Reason sent with "resource-exhausted" when a throttled daily limit is hit. */
export const MONTHLY_FAIR_USE = "monthly_fair_use";
/** Also in the error details; the app maps the reason to the same text (aiGuardMessage). */
export const MONTHLY_FAIR_USE_MESSAGE =
  "Bu ay yapay zekâ kullanımın adil kullanım sınırını aştı. Ay sonuna kadar günlük hakların azaltıldı; " +
  "dersler ve diğer özellikler sınırsız açık.";

/** The error for a throttled daily limit (same code as the normal daily limits). */
export function monthlyFairUseError(): HttpsError {
  return new HttpsError("resource-exhausted", MONTHLY_FAIR_USE, { message: MONTHLY_FAIR_USE_MESSAGE });
}

/** US$ per million tokens for claude-sonnet-5-5 (converse.ts MODEL). */
export const PRICE = { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 };

export const SHARDS = 10;
export const CACHE_MS = 60_000;

export interface GuardContext {
  uid: string;
  /** req.app is set: the App Check token was valid. */
  appVerified: boolean;
  /** `installId` from the request data, if the app sent one. */
  installId?: unknown;
  premium: boolean;
  /** Running in the Functions emulator. */
  emulator: boolean;
}

let cachedConfig: { at: number; data: Record<string, unknown> } | undefined;
let cachedSpend: { at: number; day: string; usd: number } | undefined;

/** Clears the per-instance caches (tests). */
export function resetCaches(): void {
  cachedConfig = undefined;
  cachedSpend = undefined;
}

export async function loadConfig(db: Firestore, now: Date, emulator: boolean): Promise<GuardConfig> {
  if (!cachedConfig || now.getTime() - cachedConfig.at > CACHE_MS) {
    cachedConfig = { at: now.getTime(), data: (await db.doc("config/aiGuard").get()).data() ?? {} };
  }
  const d = cachedConfig.data;
  const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : fallback);
  const mode = d.appCheck;
  return {
    appCheck: mode === "enforce" || mode === "monitor" || mode === "off" ? mode : emulator ? "off" : DEFAULTS.appCheck,
    deviceFreeDaily: num(d.deviceFreeDaily, DEFAULTS.deviceFreeDaily),
    freeDailyUsd: num(d.freeDailyUsd, DEFAULTS.freeDailyUsd),
    dailyUsd: num(d.dailyUsd, DEFAULTS.dailyUsd),
    premiumMonthlyUsd: num(d.premiumMonthlyUsd, DEFAULTS.premiumMonthlyUsd),
  };
}

/** US$ spent on Claude today (Turkish day), cached for CACHE_MS. */
export async function spentToday(db: Firestore, now: Date): Promise<number> {
  const day = dayKey(now);
  if (!cachedSpend || cachedSpend.day !== day || now.getTime() - cachedSpend.at > CACHE_MS) {
    const snap = await db.collection("aiSpend").where("day", "==", day).get();
    const usd = snap.docs.reduce((sum, d) => sum + ((d.get("usd") as number) ?? 0), 0);
    cachedSpend = { at: now.getTime(), day, usd };
  }
  return cachedSpend.usd;
}

/** Cost of one response's usage in US$. */
export function costUsd(usage: unknown): number {
  const u = (typeof usage === "object" && usage !== null ? usage : {}) as Record<string, unknown>;
  const n = (k: string) => (typeof u[k] === "number" ? (u[k] as number) : 0);
  return (
    (n("input_tokens") * PRICE.input +
      n("output_tokens") * PRICE.output +
      n("cache_read_input_tokens") * PRICE.cacheRead +
      n("cache_creation_input_tokens") * PRICE.cacheWrite) /
    1_000_000
  );
}

/** aiUserSpend doc of [uid] for the Turkish month containing [now] (server-only). */
export function userSpendRef(db: Firestore, uid: string, now: Date) {
  return db.doc(`aiUserSpend/${uid}_${monthKey(now)}`);
}

/**
 * Adds [usd] to today's total (sharded: AI calls are frequent) and, with a
 * [uid], to that user's total for this Turkish month.
 */
export async function recordSpend(db: Firestore, usd: number, now: Date, uid?: string): Promise<void> {
  if (!(usd > 0)) return;
  const day = dayKey(now);
  await Promise.all([
    db
      .doc(`aiSpend/${day}_${randomInt(SHARDS)}`)
      .set({ day, usd: FieldValue.increment(usd), calls: FieldValue.increment(1) }, { merge: true }),
    uid
      ? userSpendRef(db, uid, now).set(
          {
            uid,
            month: monthKey(now),
            usd: FieldValue.increment(usd),
            calls: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        )
      : undefined,
  ]);
  if (cachedSpend?.day === day) cachedSpend.usd += usd;
}

/** US$ [uid] has spent on Claude this Turkish month. */
export async function userSpendThisMonth(db: Firestore, uid: string, now: Date): Promise<number> {
  const usd = (await userSpendRef(db, uid, now).get()).get("usd");
  return typeof usd === "number" ? usd : 0;
}

/**
 * True when this (Premium) user's AI cost this month has reached
 * premiumMonthlyUsd: their daily limits are THROTTLED until the month ends.
 */
export async function premiumThrottled(db: Firestore, uid: string, now: Date): Promise<boolean> {
  const [cfg, spent] = await Promise.all([
    loadConfig(db, now, process.env.FUNCTIONS_EMULATOR === "true"),
    userSpendThisMonth(db, uid, now),
  ]);
  return spent >= cfg.premiumMonthlyUsd;
}

/**
 * A Premium daily limit: [normal], or [throttled] once the user is over the
 * monthly fair-use cost. error() is what to throw when the limit is reached:
 * "resource-exhausted" with [reason], or with MONTHLY_FAIR_USE when throttled.
 */
export async function premiumDailyLimit(
  db: Firestore,
  uid: string,
  now: Date,
  normal: number,
  throttled: number,
  reason: string,
): Promise<{ limit: number; throttled: boolean; error: () => HttpsError }> {
  return (await premiumThrottled(db, uid, now))
    ? { limit: throttled, throttled: true, error: monthlyFairUseError }
    : { limit: normal, throttled: false, error: () => new HttpsError("resource-exhausted", reason) };
}

export function hashInstall(installId: string): string {
  return createHash("sha256").update(`lingora-install:${installId}`).digest("hex");
}

function validInstallId(v: unknown): v is string {
  return typeof v === "string" && v.length >= 8 && v.length <= 128 && /^[A-Za-z0-9_-]+$/.test(v);
}

/**
 * Throws unless this AI call may go ahead. Counts a free call against the
 * install's daily cap (not refunded: it is a soft limit).
 */
export async function checkAiCall(db: Firestore, ctx: GuardContext, now: Date): Promise<void> {
  const cfg = await loadConfig(db, now, ctx.emulator);

  if (!ctx.appVerified && cfg.appCheck !== "off") {
    if (cfg.appCheck === "enforce") throw new HttpsError("failed-precondition", "app_check_required");
    logger.warn("ai_app_check_missing", { uid: ctx.uid });
  }

  const spent = await spentToday(db, now);
  if (spent >= cfg.dailyUsd || (!ctx.premium && spent >= cfg.freeDailyUsd)) {
    logger.error("ai_budget_reached", { spent, premium: ctx.premium });
    throw new HttpsError("resource-exhausted", "ai_budget");
  }

  if (ctx.premium || !validInstallId(ctx.installId)) return;
  const ref = db.doc(`aiDevices/${hashInstall(ctx.installId)}`);
  const day = dayKey(now);
  await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data();
    const used = d?.day === day ? ((d.count as number) ?? 0) : 0;
    // Same code the per-uid free quota uses, so the app shows the same upsell.
    if (used >= cfg.deviceFreeDaily) throw new HttpsError("resource-exhausted", "free_quota");
    tx.set(ref, { day, count: used + 1 });
  });
}

/**
 * [client] with every response's cost added to the daily total and, with a
 * [uid], to that user's monthly total.
 */
export function meteredClient(
  client: ClaudeClient,
  db: Firestore,
  now: () => Date = () => new Date(),
  uid?: string,
): ClaudeClient {
  const messages = client.beta.messages;
  const create = (async (...args: Parameters<typeof messages.create>) => {
    const res = await (messages.create as (...a: unknown[]) => Promise<{ usage?: unknown }>).apply(messages, args);
    await recordSpend(db, costUsd(res?.usage), now(), uid).catch((e) => logger.warn("ai_spend_record_failed", e));
    return res;
  }) as unknown as typeof messages.create;
  const wrappedMessages = new Proxy(messages, {
    get: (target, prop, receiver) => (prop === "create" ? create : Reflect.get(target, prop, receiver)),
  });
  const beta = new Proxy(client.beta, {
    get: (target, prop, receiver) => (prop === "messages" ? wrappedMessages : Reflect.get(target, prop, receiver)),
  });
  return { beta } as ClaudeClient;
}
