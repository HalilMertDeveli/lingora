// AI cost protection (audit finding 12): App Check, per-install soft limit,
// daily spend circuit breaker.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import {
  checkAiCall,
  costUsd,
  DEFAULTS,
  GuardContext,
  hashInstall,
  meteredClient,
  recordSpend,
  resetCaches,
  spentToday,
} from "../src/ai_guard.js";
import type { ClaudeClient } from "../src/converse.js";
import { dayKey } from "../src/week.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-19T09:00:00Z");

beforeEach(async () => {
  await clearFirestore();
  resetCaches();
});

const ctx = (over: Partial<GuardContext> = {}): GuardContext => ({
  uid: "u",
  appVerified: true,
  installId: "install-0123456789",
  premium: false,
  emulator: false,
  ...over,
});

test("App Check: enforced by default in production, off by default in the emulator", async () => {
  await rejectsWith(checkAiCall(db, ctx({ appVerified: false }), now), "failed-precondition", "app_check_required");
  resetCaches();
  await checkAiCall(db, ctx({ appVerified: false, emulator: true }), now);
  resetCaches();
  await checkAiCall(db, ctx({ appVerified: true }), now);
});

test("App Check mode comes from config/aiGuard (monitor lets calls through)", async () => {
  await db.doc("config/aiGuard").set({ appCheck: "monitor" });
  await checkAiCall(db, ctx({ appVerified: false }), now);
  resetCaches();
  await db.doc("config/aiGuard").set({ appCheck: "enforce" });
  await rejectsWith(checkAiCall(db, ctx({ appVerified: false, emulator: true }), now), "failed-precondition");
});

test("free calls per install are capped across guest accounts; Premium is exempt", async () => {
  await db.doc("config/aiGuard").set({ deviceFreeDaily: 3 });
  for (let i = 0; i < 3; i++) await checkAiCall(db, ctx({ uid: `guest${i}` }), now);
  await rejectsWith(checkAiCall(db, ctx({ uid: "guest-new" }), now), "resource-exhausted", "free_quota");
  await checkAiCall(db, ctx({ uid: "payer", premium: true }), now);
  // Another install, or the next Turkish day, starts again.
  await checkAiCall(db, ctx({ installId: "other-install-123" }), now);
  await checkAiCall(db, ctx(), new Date(now.getTime() + 24 * 3600 * 1000));
  const d = (await db.doc(`aiDevices/${hashInstall("install-0123456789")}`).get()).data();
  assert.equal(d?.count, 1);
  assert.equal("uid" in (d ?? {}), false);
});

test("old apps without an installId are not limited per install", async () => {
  await db.doc("config/aiGuard").set({ deviceFreeDaily: 0 });
  await checkAiCall(db, ctx({ installId: undefined }), now);
  await rejectsWith(checkAiCall(db, ctx(), now), "resource-exhausted", "free_quota");
  await checkAiCall(db, ctx({ installId: "../bad id" }), now);
});

test("daily spend circuit breaker: free stops first, then everyone", async () => {
  await db.doc("config/aiGuard").set({ freeDailyUsd: 1, dailyUsd: 2 });
  await recordSpend(db, 0.6, now);
  await recordSpend(db, 0.6, now);
  resetCaches();
  assert.ok(Math.abs((await spentToday(db, now)) - 1.2) < 1e-9);
  await rejectsWith(checkAiCall(db, ctx(), now), "resource-exhausted", "ai_budget");
  await checkAiCall(db, ctx({ premium: true }), now);
  await recordSpend(db, 1, now);
  resetCaches();
  await rejectsWith(checkAiCall(db, ctx({ premium: true }), now), "resource-exhausted", "ai_budget");
  // A new day starts from zero.
  resetCaches();
  await checkAiCall(db, ctx(), new Date(now.getTime() + 24 * 3600 * 1000));
});

test("defaults are sane", () => {
  assert.equal(DEFAULTS.appCheck, "enforce");
  assert.ok(DEFAULTS.freeDailyUsd < DEFAULTS.dailyUsd);
});

test("costs are priced from usage, and the metered client records them", async () => {
  assert.equal(costUsd({ input_tokens: 1_000_000, output_tokens: 1_000_000 }), 12);
  assert.equal(costUsd({ cache_read_input_tokens: 1_000_000 }), 0.1);
  assert.equal(costUsd(undefined), 0);

  const calls: unknown[] = [];
  const fake = {
    beta: {
      messages: {
        marker: "kept",
        async create(this: { marker: string }, body: unknown) {
          calls.push([this.marker, body]);
          return { usage: { input_tokens: 500_000, output_tokens: 100_000 }, content: [] };
        },
      },
    },
  } as unknown as ClaudeClient;
  const client = meteredClient(fake, db, () => now);
  const res = await client.beta.messages.create({ model: "x" } as never);
  assert.ok(res);
  assert.deepEqual(calls, [["kept", { model: "x" }]]);
  const snap = await db.collection("aiSpend").where("day", "==", dayKey(now)).get();
  const usd = snap.docs.reduce((s, d) => s + (d.get("usd") as number), 0);
  assert.ok(Math.abs(usd - 2) < 1e-9);
});
