// Callable wrappers and the trigger for the invite programme (logic: referral.ts).
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import * as referral from "./referral.js";

/** { deviceId? } -> { code, rewardDays, rewardedThisMonth, maxPerMonth, totalRewarded } */
export const getInviteCode = onCall((req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  const deviceId = (req.data as { deviceId?: unknown } | null)?.deviceId;
  return referral.getInviteCode(getFirestore(), req.auth.uid, new Date(), deviceId);
});

/** { code, deviceId } -> { ok, status: pending|rewarded, rewardDays, expiresAt?, inviterRewarded } */
export const redeemInvite = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  const user = await getAuth().getUser(req.auth.uid);
  return referral.redeemInvite(getFirestore(), req.auth.uid, req.data, {
    now: new Date(),
    accountCreatedAt: new Date(user.metadata.creationTime),
    signInProvider: String(req.auth.token.firebase?.sign_in_provider ?? "unknown"),
  });
});

/** {} -> { status: none|pending|rewarded, rewardDays } */
export const getInviteStatus = onCall((req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return referral.inviteStatus(getFirestore(), req.auth.uid);
});

/**
 * Rewards a pending invite when the friend's synced progress shows their
 * first finished lesson (users/{uid}.progress.lessonsDone goes 0 -> 1+).
 */
export const inviteFirstLesson = onDocumentWritten("users/{uid}", async (event) => {
  const before = referral.lessonsDoneOf(event.data?.before.data());
  const after = referral.lessonsDoneOf(event.data?.after.data());
  if (after < 1 || before >= 1) return;
  const reward = await referral.completeInviteReward(getFirestore(), event.params.uid, new Date());
  if (reward) logger.info("invite_rewarded", { inviterRewarded: reward.inviterRewarded });
});
