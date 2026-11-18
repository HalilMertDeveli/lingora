// Google Play Developer API (androidpublisher v3) — the small part Dilmaç uses.
//
// Authenticates with the Cloud Functions runtime service account through
// Application Default Credentials: no key file anywhere. That account must be
// invited in Play Console (docs/play-satin-alma-kurulum.md). Tests pass a fake
// [PlayApi] instead; nothing here is called in the emulator or in tests.
import { GoogleAuth } from "google-auth-library";

/** Android application id (android/app/build.gradle.kts). */
export const PACKAGE_NAME = "com.lingora.lingora";

const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const BASE = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/purchases`;

/** purchases.subscriptionsv2 resource (only the fields we read). */
export interface SubscriptionPurchaseV2 {
  subscriptionState?: string;
  acknowledgementState?: string;
  linkedPurchaseToken?: string;
  testPurchase?: object;
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
    autoRenewingPlan?: { autoRenewEnabled?: boolean };
  }>;
}

/** purchases.products resource (only the fields we read). */
export interface ProductPurchase {
  /** 0 purchased, 1 canceled, 2 pending. */
  purchaseState?: number;
  /** 0 not yet acknowledged, 1 acknowledged. */
  acknowledgementState?: number;
  /** 0 test purchase (license tester). */
  purchaseType?: number;
  orderId?: string;
}

export interface PlayApi {
  getSubscription(token: string): Promise<SubscriptionPurchaseV2>;
  getProduct(productId: string, token: string): Promise<ProductPurchase>;
  acknowledgeSubscription(subscriptionId: string, token: string): Promise<void>;
  acknowledgeProduct(productId: string, token: string): Promise<void>;
}

/** A failed Play API call; [status] is the HTTP status (0 when there was no response). */
export class PlayApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "PlayApiError";
  }

  /** The token is unknown to Google (fake, wrong app, or too old). */
  get notFound(): boolean {
    return this.status === 400 || this.status === 404 || this.status === 410;
  }

  /** Worth retrying later (network, quota, Google outage). */
  get transient(): boolean {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }
}

/** The real API, using the runtime service account. */
export function createPlayApi(): PlayApi {
  const auth = new GoogleAuth({ scopes: [SCOPE] });

  async function call<T>(method: "GET" | "POST", path: string): Promise<T> {
    try {
      const client = await auth.getClient();
      const res = await client.request<T>({ url: `${BASE}/${path}`, method, ...(method === "POST" ? { data: {} } : {}) });
      return res.data;
    } catch (e) {
      const err = e as { status?: number; response?: { status?: number }; message?: string };
      throw new PlayApiError(err.response?.status ?? err.status ?? 0, err.message ?? String(e));
    }
  }

  const t = encodeURIComponent;
  return {
    getSubscription: (token) => call("GET", `subscriptionsv2/tokens/${t(token)}`),
    getProduct: (productId, token) => call("GET", `products/${t(productId)}/tokens/${t(token)}`),
    acknowledgeSubscription: async (id, token) => {
      await call("POST", `subscriptions/${t(id)}/tokens/${t(token)}:acknowledge`);
    },
    acknowledgeProduct: async (productId, token) => {
      await call("POST", `products/${t(productId)}/tokens/${t(token)}:acknowledge`);
    },
  };
}

/** What a subscription purchase gives right now. */
export interface SubscriptionAccess {
  /** Premium now. */
  entitled: boolean;
  /** entitlements/{uid}.status: 'active' | 'grace' | 'pending' | 'expired'. */
  status: "active" | "grace" | "pending" | "expired";
  /** Play subscription id from the purchase (undefined if it has none). */
  productId?: string;
  /** End of the paid (or grace) period in ms; 0 when unknown. */
  expiresAt: number;
  autoRenewing: boolean;
  /** Raw subscriptionState, kept for support. */
  playState: string;
  needsAck: boolean;
}

/**
 * Reads a subscriptionsv2 purchase. [knownProducts] are our subscription ids;
 * the line item for one of them wins.
 *
 * Premium while ACTIVE, IN_GRACE_PERIOD, or CANCELED (cancelled auto-renew:
 * paid until expiryTime). Never while PENDING, ON_HOLD, PAUSED or EXPIRED.
 */
export function subscriptionAccess(s: SubscriptionPurchaseV2, knownProducts: string[], now: Date): SubscriptionAccess {
  const items = s.lineItems ?? [];
  const item = items.find((i) => i.productId !== undefined && knownProducts.includes(i.productId)) ?? items[0];
  const expiresAt = item?.expiryTime ? Date.parse(item.expiryTime) || 0 : 0;
  const state = s.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED";
  const inTime = expiresAt > now.getTime();
  let status: SubscriptionAccess["status"];
  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
    case "SUBSCRIPTION_STATE_CANCELED":
      status = inTime ? "active" : "expired";
      break;
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      status = inTime ? "grace" : "expired";
      break;
    case "SUBSCRIPTION_STATE_PENDING":
      status = "pending";
      break;
    default:
      status = "expired";
  }
  const entitled = status === "active" || status === "grace";
  return {
    entitled,
    status,
    productId: item?.productId,
    expiresAt,
    autoRenewing: item?.autoRenewingPlan?.autoRenewEnabled === true,
    playState: state,
    needsAck: entitled && s.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
  };
}
