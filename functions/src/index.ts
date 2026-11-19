// Dilmaç Cloud Functions (2nd gen). Deploy steps: docs/firebase-backend.md.
import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { onSchedule } from "firebase-functions/v2/scheduler";

import * as account from "./account.js";
import * as aiGuard from "./ai_guard.js";
import { stubClaude, stubClaudeEnabled, stubTts } from "./ai_stub.js";
import * as writing from "./assess_writing.js";
import * as conversation from "./converse.js";
import { hasPremium } from "./entitlement.js";
import * as daily from "./daily_reading.js";
import * as karne from "./conversation_report.js";
import * as explain from "./explain_more.js";
import * as family from "./family.js";
import * as league from "./league.js";
import * as play from "./play.js";
import * as purchase from "./purchase.js";
import * as rehearsal from "./rehearsal.js";
import * as speaking from "./speaking_stats.js";
import * as talking from "./talk.js";
import * as tts from "./tts.js";

initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
let claude: conversation.ClaudeClient | undefined;

/** The Claude client: the real one, or the QA fake inside the emulator only (see ai_stub.ts). */
function claudeClient(): conversation.ClaudeClient {
  // Metered: every response's cost feeds the daily circuit breaker (ai_guard.ts).
  claude ??= aiGuard.meteredClient(
    stubClaudeEnabled() ? stubClaude() : new Anthropic({ apiKey: anthropicApiKey.value() }),
    getFirestore(),
  );
  return claude;
}

/**
 * App Check, the daily spend circuit breaker and the per-install free limit,
 * in front of every AI callable (ai_guard.ts). Returns the caller's uid.
 */
async function guardAi(req: CallableRequest, now: Date, opts: { countFreeUse?: boolean } = {}): Promise<string> {
  const uid = requireUid(req);
  const db = getFirestore();
  const data = (typeof req.data === "object" && req.data !== null ? req.data : {}) as Record<string, unknown>;
  await aiGuard.checkAiCall(
    db,
    {
      uid,
      appVerified: req.app !== undefined,
      // Not counted against the per-install free limit (warm-up, Premium-only voice).
      installId: opts.countFreeUse === false ? undefined : data.installId,
      premium: await hasPremium(db, uid, now),
      emulator: process.env.FUNCTIONS_EMULATOR === "true",
    },
    now,
  );
  return uid;
}

function requireUid(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return req.auth.uid;
}

/** Signed in with Google, e-mail or phone (not a guest). */
function requireAccount(req: CallableRequest): string {
  const uid = requireUid(req);
  const provider = (req.auth?.token.firebase as { sign_in_provider?: string } | undefined)?.sign_in_provider;
  if (provider === "anonymous") throw new HttpsError("permission-denied", "account_required");
  return uid;
}

/** { name?, avatar?, country?, photo? (base64 JPEG) } -> { groupId, weekKey, tier } */
export const joinLeague = onCall((req) =>
  league.joinLeague(getFirestore(), requireAccount(req), league.parseJoinInput(req.data), new Date()),
);

/** { weekXp, weekKey? } -> { xp: weekly total on the server, accepted, pending } */
export const addLeagueXp = onCall((req) =>
  league.addLeagueXp(getFirestore(), requireAccount(req), req.data, new Date()),
);

/** {} -> { left } */
export const leaveLeague = onCall((req) => league.leaveLeague(getFirestore(), requireUid(req)));

/** Closes last week's groups every Monday just after midnight (Turkish time). */
export const settleLeagues = onSchedule(
  { schedule: "every monday 00:05", timeZone: "Europe/Istanbul" },
  async () => {
    const n = await league.settleFinishedWeeks(getFirestore(), new Date());
    logger.info(`settled ${n} league groups`);
  },
);

/** "Günün okuması": one reading per CEFR band, written once a day for everyone (daily_reading.ts). */
export const generateDailyReadings = onSchedule(
  {
    schedule: "every day 00:20",
    timeZone: "Europe/Istanbul",
    secrets: [anthropicApiKey],
    timeoutSeconds: 540,
    retryCount: 2,
  },
  async () => {
    const r = await daily.generateDailyReadings(getFirestore(), claudeClient(), new Date());
    logger.info("daily_readings", r);
    if (r.failed.length) throw new Error(`daily readings failed: ${r.failed.join(",")}`);
  },
);

/** { scenarioId, messages } -> { reply, correction, tip_tr, done, remaining, free } */
export const converse = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, async (req) => {
  const now = new Date();
  const uid = await guardAi(req, now);
  return conversation.converse(getFirestore(), claudeClient(), uid, req.data, now);
});

let ttsClient: tts.TtsClient | undefined;
/** Google Cloud TTS (Chirp 3 HD), or the silent fake inside the emulator with LINGORA_AI_STUB=1. */
function textToSpeech(): tts.TtsClient {
  ttsClient ??= stubClaudeEnabled() ? stubTts() : tts.googleTts();
  return ttsClient;
}

/**
 * Doğal konuşma (talk.ts), a streaming callable: { scenarioId | mode: "free" |
 * characterId, topic?, level?, goal?, voice?, messages } -> chunks { type:
 * "sentence", i, text, audio } then { reply, correction, tip_tr, done,
 * remaining, free, voice, talkSecondsLeft, timing }.
 */
export const talk = onCall(
  { secrets: [anthropicApiKey], timeoutSeconds: 90, memory: "512MiB", concurrency: 40 },
  async (req, res) => {
    const now = new Date();
    const warm = (req.data as { warm?: unknown } | null)?.warm === true;
    const uid = await guardAi(req, now, { countFreeUse: !warm });
    if (warm) return talking.warmTalk(claudeClient(), textToSpeech());
    const send = req.acceptsStreaming ? (c: talking.TalkSentence) => res?.sendChunk(c) : null;
    return talking.talk(getFirestore(), claudeClient(), textToSpeech(), uid, req.data, now, send);
  },
);

/** { text, voice?, rate? } -> { audio: base64 MP3 | null, cached, reason? } (Premium neural voice) */
export const speak = onCall({ timeoutSeconds: 30, concurrency: 40 }, async (req) => {
  const now = new Date();
  const uid = await guardAi(req, now, { countFreeUse: false });
  return tts.speak(getFirestore(), textToSpeech(), uid, req.data, now);
});

/** { scenarioId, messages, pronunciation } -> { mistakes, summary_tr, weak_words, remaining } (voice coach karne) */
export const conversationReport = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, async (req) => {
  const now = new Date();
  const uid = await guardAi(req, now);
  const result = await karne.conversationReport(getFirestore(), claudeClient(), uid, req.data, now);
  // Teacher report (speaking_stats.ts); never fails the learner's karne.
  await speaking
    .recordSpeaking(getFirestore(), uid, req.data, result, now)
    .catch((e) => logger.error("recordSpeaking failed", e));
  return result;
});

/** { question, options, answer, picked?, explanation, mode, text?, history? } -> { answer_tr, remaining } ("Neden yanlış?" follow-up, Premium) */
export const explainMore = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 60 }, (req) => {
  const uid = requireUid(req);
  return explain.explainMore(getFirestore(), claudeClient(), uid, req.data, new Date());
});

/** { taskId, text } -> { scores, corrections, next_tr, remaining } (general course writing tasks) */
export const assessWriting = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, async (req) => {
  const now = new Date();
  const uid = await guardAi(req, now);
  return writing.assessWriting(getFirestore(), claudeClient(), uid, req.data, now);
});

/** { rehearsalId, kind, items: [{ question, answer }], previousTags?, previousGaps? } -> analysis (Mülakat Provası) */
export const analyzeRehearsal = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 120 }, async (req) => {
  const now = new Date();
  const uid = await guardAi(req, now);
  return rehearsal.analyzeRehearsal(getFirestore(), claudeClient(), uid, req.data, now);
});

/** { productId, purchaseToken } -> { active, productId, expiresAt?, packs } (subscriptions, family plan, exam packs) */
export const verifyPurchase = onCall((req) =>
  purchase.verifyPurchase(getFirestore(), requireUid(req), req.data, {
    // Only the emulator grants Premium without a real Play check.
    testMode: process.env.FUNCTIONS_EMULATOR === "true",
    now: new Date(),
    play: playApi(),
  }),
);

let playClient: play.PlayApi | undefined;
function playApi(): play.PlayApi {
  return (playClient ??= play.createPlayApi());
}

/** Play Real-time developer notifications (topic play-rtdn, docs/play-satin-alma-kurulum.md). */
export const playRtdn = onMessagePublished({ topic: "play-rtdn", retry: true }, async (event) => {
  let msg: purchase.DeveloperNotification | undefined;
  try {
    msg = event.data.message.json as purchase.DeveloperNotification;
  } catch {
    msg = undefined;
  }
  const outcome = await purchase.handleRtdn(getFirestore(), playApi(), msg, new Date());
  logger.info("play_rtdn", { outcome, messageId: event.data.message.messageId });
});

// Dilmaç Kurumsal (orgs, seats, classes, assignments): orgs_api.ts, docs/kurumsal.md.
export * from "./orgs_api.js";

// Kurumsal sales: quote form (submitLead), leads and trial codes for staff (sales_api.ts).
export * from "./sales_api.js";

// Invite programme: getInviteCode, redeemInvite (functions/src/referral_api.ts).
export * from "./referral_api.js";
// Family plan (functions/src/family.ts).
/** {} -> { code, expiresAt } (owner of an active family plan) */
export const createFamilyInvite = onCall((req) => family.createFamilyInvite(getFirestore(), requireUid(req), new Date()));
/** { code } -> { active, productId, expiresAt, ownerUid } */
export const redeemFamilyCode = onCall((req) =>
  family.redeemFamilyCode(getFirestore(), requireUid(req), req.data, new Date()),
);
/** { memberUid } -> { removed } (owner) */
export const removeFamilyMember = onCall((req) =>
  family.removeFamilyMember(getFirestore(), requireUid(req), req.data),
);
/** {} -> { left } (member) */
export const leaveFamily = onCall((req) => family.leaveFamily(getFirestore(), requireUid(req)));
/** {} -> { role: 'none' | 'member' | 'owner', ... } */
export const getFamily = onCall((req) => family.getFamily(getFirestore(), requireUid(req), new Date()));

// Account deletion (Profil > Hesap > Hesabımı sil): functions/src/account.ts.
/** {} -> { deleted, docs }: all server data, then the Auth user. */
export const deleteAccount = onCall({ timeoutSeconds: 120 }, async (req) => {
  const uid = requireUid(req);
  const result = await account.deleteUserData(getFirestore(), uid);
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
  }
  return result;
});

// Owner dashboard (admin panel > Panel): functions/src/stats_api.ts.
export * from "./stats_api.js";
