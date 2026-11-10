// Callable wrappers for the invite programme (logic: referral.ts).
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import * as referral from "./referral.js";

/** {} -> { code, rewardDays, rewardedThisMonth, maxPerMonth, totalRewarded } */
export const getInviteCode = onCall((req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  return referral.getInviteCode(getFirestore(), req.auth.uid, new Date());
});

/** { code, deviceId } -> { ok, rewardDays, expiresAt, inviterRewarded } */
export const redeemInvite = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  const user = await getAuth().getUser(req.auth.uid);
  return referral.redeemInvite(getFirestore(), req.auth.uid, req.data, {
    now: new Date(),
    accountCreatedAt: new Date(user.metadata.creationTime),
    signInProvider: String(req.auth.token.firebase?.sign_in_provider ?? "unknown"),
  });
});
