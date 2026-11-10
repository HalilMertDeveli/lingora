// Google Play purchase check -> entitlements/{uid}.
//
// Only the emulator/test path is implemented: it trusts the token and grants
// the product. Real verification is the TODO below. Contract with the app:
// lib/services/billing/entitlement_backend.dart (ServerEntitlement.fromJson).
//
// entitlements/{uid} is shared by several writers (purchases, family plan,
// organisations). Every writer merges its own fields and never shortens an
// active Premium that another source granted for longer.
import { createHash } from "node:crypto";

import { DocumentData, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { FAMILY_PRODUCT, FAMILY_SEATS } from "./family.js";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Premium subscription id -> Premium days per purchase (lib/services/billing/products.dart). */
export const PRODUCTS: Record<string, number> = {
  lingora_premium_monthly: 31,
  lingora_premium_yearly: 366,
  [FAMILY_PRODUCT]: 366,
};

/** One-time exam pack id -> field under entitlements/{uid}.packs (lib/services/billing/products.dart). */
export const PACK_PRODUCTS: Record<string, string> = {
  lingora_pack_yds_full: "yds",
  lingora_pack_lgs_full: "lgs",
};

export interface PurchaseResult {
  /** Premium right now (after this purchase). */
  active: boolean;
  premium: boolean;
  status: "active" | "expired";
  productId: string;
  /** Milliseconds since epoch; absent when there is no Premium. */
  expiresAt?: number;
  /** Exam packs owned, e.g. { yds: true }. */
  packs: Record<string, boolean>;
}

export function parsePurchaseInput(data: unknown): { productId: string; purchaseToken: string } {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  if (d.platform !== undefined && d.platform !== "android") {
    throw new HttpsError("invalid-argument", "unsupported_platform");
  }
  if (typeof d.productId !== "string" || !(d.productId in PRODUCTS || d.productId in PACK_PRODUCTS)) {
    throw new HttpsError("invalid-argument", "unknown_product");
  }
  const token = d.purchaseToken;
  if (typeof token !== "string" || token.length < 8 || token.length > 4096 || /\s/.test(token)) {
    throw new HttpsError("invalid-argument", "invalid_token");
  }
  return { productId: d.productId, purchaseToken: token };
}

/** Premium end (ms) currently granted by [e], or 0. */
export function premiumUntil(e: DocumentData | undefined, now: Date): number {
  const on = e?.active === true || e?.premium === true;
  const exp = (e?.expiresAt as Timestamp | undefined)?.toMillis() ?? 0;
  return on && exp > now.getTime() ? exp : 0;
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
    //   subscriptions: GET .../applications/com.lingora.lingora/purchases/subscriptionsv2/tokens/{token}
    //     grant only if subscriptionState is ACTIVE or IN_GRACE_PERIOD, take
    //     expiresAt from lineItems[].expiryTime;
    //   exam packs (one-time products): GET .../purchases/products/{productId}/tokens/{token}
    //     grant only if purchaseState == 0 (purchased);
    // acknowledge the purchase, and follow renewals, cancellations and refunds
    // with Real-time developer notifications (Pub/Sub).
    throw new HttpsError("unimplemented", "play_verification_not_configured");
  }

  const tokenRef = db.doc(`purchases/${createHash("sha256").update(purchaseToken).digest("hex")}`);
  const entRef = db.doc(`entitlements/${uid}`);
  const now = opts.now.getTime();

  return db.runTransaction(async (tx) => {
    const bound = await tx.get(tokenRef);
    if (bound.exists && bound.get("uid") !== uid) throw new HttpsError("already-exists", "token_in_use");
    const current = (await tx.get(entRef)).data();
    const familyRef = db.doc(`families/${uid}`);
    const family = productId === FAMILY_PRODUCT ? (await tx.get(familyRef)).data() : undefined;
    const memberUids = Object.keys((family?.members as Record<string, unknown>) ?? {});
    const memberEnts = await Promise.all(memberUids.map((m) => tx.get(db.doc(`entitlements/${m}`))));
    if (!bound.exists) tx.set(tokenRef, { uid, productId, createdAt: FieldValue.serverTimestamp() });

    const packs: Record<string, boolean> = { ...((current?.packs as Record<string, boolean>) ?? {}) };
    const pack = PACK_PRODUCTS[productId];
    if (pack) {
      packs[pack] = true;
      tx.set(entRef, { packs: { [pack]: true }, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      const until = premiumUntil(current, opts.now);
      return {
        active: until > 0,
        premium: until > 0,
        status: until > 0 ? "active" : "expired",
        productId,
        ...(until > 0 ? { expiresAt: until } : {}),
        packs,
      };
    }

    const purchased = now + PRODUCTS[productId] * DAY_MS;
    const expiresAt = Math.max(purchased, premiumUntil(current, opts.now));
    const ent: DocumentData = {
      active: true,
      premium: true,
      status: "active",
      productId,
      platform: "android",
      expiresAt: Timestamp.fromMillis(expiresAt),
      source: "test",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (productId === FAMILY_PRODUCT) {
      ent.family = { ownerUid: uid, role: "owner" };
      writeFamilyOwner(tx, db, uid, family, memberEnts, purchased);
    }
    tx.set(entRef, ent, { merge: true });
    return { active: true, premium: true, status: "active", productId, expiresAt, packs };
  });
}

/**
 * Creates or extends families/{ownerUid} and moves the Premium end of every
 * member that got Premium from this family to the new [expiresAt].
 */
function writeFamilyOwner(
  tx: Transaction,
  db: Firestore,
  ownerUid: string,
  family: DocumentData | undefined,
  memberEnts: DocumentSnapshot[],
  expiresAt: number,
): void {
  const until = Timestamp.fromMillis(expiresAt);
  tx.set(
    db.doc(`families/${ownerUid}`),
    {
      ownerUid,
      seats: FAMILY_SEATS,
      expiresAt: until,
      ...(family ? {} : { members: {}, createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  for (const snap of memberEnts) {
    // Members whose Premium came from elsewhere are left alone.
    const e = snap.data();
    if (e?.source !== "family" || e?.family?.ownerUid !== ownerUid) continue;
    tx.set(
      snap.ref,
      { active: true, premium: true, status: "active", expiresAt: until, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
}
