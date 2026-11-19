// Callable/scheduled wrappers for the owner dashboard (logic: stats.ts).
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import * as stats from "./stats.js";

/** { step } -> { ok }: an aggregated funnel step from the app (no identifiers stored). */
export const countFunnel = onCall({ region: "europe-west1", maxInstances: 5 }, (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return stats.countFunnel(getFirestore(), req.data, new Date());
});

/** { days? } -> { days: [{ day, counts }], premiumActiveNow } (Dilmaç staff only). */
export const getStats = onCall({ region: "europe-west1", maxInstances: 2 }, (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return stats.getStats(getFirestore(), { uid: req.auth.uid, claims: req.auth.token }, req.data, new Date());
});

/** Stores the day's active Premium count just before midnight (Turkish time). */
export const snapshotStats = onSchedule(
  { region: "europe-west1", schedule: "every day 23:50", timeZone: "Europe/Istanbul" },
  async () => {
    const n = await stats.snapshotPremium(getFirestore(), new Date());
    logger.info(`premium_active ${n}`);
  },
);
