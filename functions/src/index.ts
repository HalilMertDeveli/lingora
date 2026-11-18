// Dilmaç Cloud Functions (2nd gen). Deploy steps: docs/firebase-backend.md.
import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { stubClaude, stubClaudeEnabled } from "./ai_stub.js";
import * as writing from "./assess_writing.js";
import * as conversation from "./converse.js";
import * as karne from "./conversation_report.js";
import * as family from "./family.js";
import * as league from "./league.js";
import * as purchase from "./purchase.js";
import * as rehearsal from "./rehearsal.js";

initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
let claude: conversation.ClaudeClient | undefined;

/** The Claude client: the real one, or the QA fake inside the emulator only (see ai_stub.ts). */
function claudeClient(): conversation.ClaudeClient {
  claude ??= stubClaudeEnabled() ? stubClaude() : new Anthropic({ apiKey: anthropicApiKey.value() });
  return claude;
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

/** { scenarioId, messages } -> { reply, correction, tip_tr, done, remaining, free } */
export const converse = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, (req) => {
  const uid = requireUid(req);
  return conversation.converse(getFirestore(), claudeClient(), uid, req.data, new Date());
});

/** { scenarioId, messages, pronunciation } -> { mistakes, summary_tr, weak_words, remaining } (voice coach karne) */
export const conversationReport = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, (req) => {
  const uid = requireUid(req);
  return karne.conversationReport(getFirestore(), claudeClient(), uid, req.data, new Date());
});

/** { taskId, text } -> { scores, corrections, next_tr, remaining } (general course writing tasks) */
export const assessWriting = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, (req) => {
  const uid = requireUid(req);
  return writing.assessWriting(getFirestore(), claudeClient(), uid, req.data, new Date());
});

/** { rehearsalId, kind, items: [{ question, answer }], previousTags?, previousGaps? } -> analysis (Mülakat Provası) */
export const analyzeRehearsal = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 120 }, (req) => {
  const uid = requireUid(req);
  claude ??= new Anthropic({ apiKey: anthropicApiKey.value() });
  return rehearsal.analyzeRehearsal(getFirestore(), claude, uid, req.data, new Date());
});

/** { productId, purchaseToken } -> { active, productId, expiresAt?, packs } (subscriptions, family plan, exam packs) */
export const verifyPurchase = onCall((req) =>
  purchase.verifyPurchase(getFirestore(), requireUid(req), req.data, {
    // Only the emulator grants Premium without a real Play check.
    testMode: process.env.FUNCTIONS_EMULATOR === "true",
    now: new Date(),
  }),
);

// Dilmaç Kurumsal (orgs, seats, classes, assignments): orgs_api.ts, docs/kurumsal.md.
export * from "./orgs_api.js";

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
