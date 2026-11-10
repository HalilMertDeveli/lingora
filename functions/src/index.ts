// Lingora Cloud Functions (2nd gen). Deploy steps: docs/firebase-backend.md.
import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import * as conversation from "./converse.js";
import * as league from "./league.js";
import * as purchase from "./purchase.js";

initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
let claude: Anthropic | undefined;

function requireUid(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return req.auth.uid;
}

/** { name?, avatar?, tier? } -> { groupId, weekKey, tier } */
export const joinLeague = onCall((req) =>
  league.joinLeague(getFirestore(), requireUid(req), league.parseJoinInput(req.data), new Date()),
);

/** { xp } -> { xp: weekly total, accepted } */
export const addLeagueXp = onCall((req) =>
  league.addLeagueXp(getFirestore(), requireUid(req), req.data, new Date()),
);

/** Closes last week's groups every Monday just after midnight (Turkish time). */
export const settleLeagues = onSchedule(
  { schedule: "every monday 00:05", timeZone: "Europe/Istanbul" },
  async () => {
    const n = await league.settleFinishedWeeks(getFirestore(), new Date());
    logger.info(`settled ${n} league groups`);
  },
);

/** { scenarioId, messages } -> { reply, correction, tip_tr, done, remaining } */
export const converse = onCall({ secrets: [anthropicApiKey], timeoutSeconds: 90 }, (req) => {
  const uid = requireUid(req);
  claude ??= new Anthropic({ apiKey: anthropicApiKey.value() });
  return conversation.converse(getFirestore(), claude, uid, req.data, new Date());
});

/** { productId, purchaseToken } -> { active, productId, expiresAt } */
export const verifyPurchase = onCall((req) =>
  purchase.verifyPurchase(getFirestore(), requireUid(req), req.data, {
    // Only the emulator grants Premium without a real Play check.
    testMode: process.env.FUNCTIONS_EMULATOR === "true",
    now: new Date(),
  }),
);
