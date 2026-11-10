// Google Play purchase check -> entitlements/{uid}.
//
// Only the emulator/test path is implemented: it trusts the token and grants
// Premium. Real verification is the TODO below. Contract with the app:
// lib/services/billing/entitlement_backend.dart (ServerEntitlement.fromJson).
import { createHash } from "node:crypto";

import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

/** Play product id -> Premium days per purchase (lib/services/billing/products.dart). */
export const PRODUCTS: Record<string, number> = {
  lingora_premium_monthly: 31,
  lingora_premium_yearly: 366,
};

export interface PurchaseResult {
  active: boolean;
  premium: boolean;
  status: "active";
  productId: string;
  /** Milliseconds since epoch. */
  expiresAt: number;
}

export function parsePurchaseInput(data: unknown): { productId: string; purchaseToken: string } {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  if (d.platform !== undefined && d.platform !== "android") {
    throw new HttpsError("invalid-argument", "unsupported_platform");
  }
  if (typeof d.productId !== "string" || !(d.productId in PRODUCTS)) {
    throw new HttpsError("invalid-argument", "unknown_product");
  }
  const token = d.purchaseToken;
  if (typeof token !== "string" || token.length < 8 || token.length > 4096 || /\s/.test(token)) {
    throw new HttpsError("invalid-argument", "invalid_token");
  }
  return { productId: d.productId, purchaseToken: token };
}

export async function verifyPurchase(
  db: Firestore,
  uid: string,
  data: unknown,
  opts: { testMode: boolean; now: Date },
): Promise<PurchaseResult> {
  const { productId, purchaseToken } = parsePurchaseInput(data);

  if (!opts.testMode) {
    // TODO(play-billing): verify with the Google Play Developer API before
    // launch. Needs a service account with access to the Play Console app
    // (Play Console > Users and permissions) and the androidpublisher API:
    //   GET https://androidpublisher.googleapis.com/androidpublisher/v3/
    //       applications/com.lingora.lingora/purchases/subscriptionsv2/tokens/{token}
    // Grant only if subscriptionState is ACTIVE or IN_GRACE_PERIOD (status
    // 'active' / 'grace'), take expiresAt from lineItems[].expiryTime,
    // acknowledge the purchase, and follow renewals and cancellations with
    // Real-time developer notifications (Pub/Sub).
    throw new HttpsError("unimplemented", "play_verification_not_configured");
  }

  const days = PRODUCTS[productId];
  const expiresAt = opts.now.getTime() + days * 24 * 60 * 60 * 1000;
  const tokenRef = db.doc(`purchases/${createHash("sha256").update(purchaseToken).digest("hex")}`);
  const entRef = db.doc(`entitlements/${uid}`);

  await db.runTransaction(async (tx) => {
    const bound = await tx.get(tokenRef);
    if (bound.exists && bound.get("uid") !== uid) throw new HttpsError("already-exists", "token_in_use");
    if (!bound.exists) tx.set(tokenRef, { uid, productId, createdAt: FieldValue.serverTimestamp() });
    tx.set(entRef, {
      active: true,
      premium: true,
      status: "active",
      productId,
      platform: "android",
      expiresAt: Timestamp.fromMillis(expiresAt),
      source: "test",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { active: true, premium: true, status: "active", productId, expiresAt };
}
