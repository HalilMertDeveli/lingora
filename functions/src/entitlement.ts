// One answer to "does this learner have Premium right now?", for every
// Premium callable (converse, conversationReport, assessWriting,
// analyzeRehearsal) and for recomputing entitlements/{uid} when one source
// ends (leaving a family, losing an org seat, a family plan running out).
//
// Premium can come from several places at once. Each one is read from its
// own record, so losing one never hides another that is still running:
//
//   entitlements/{uid}           the effective grant (all writers) and
//                                `previous` (a grant another source took over)
//   purchases/{hash}             Play / emulator subscriptions: `entitledUntil`
//   families/{ownerUid}          family member seat (entitlements.family)
//   memberships + orgs/{orgId}   Çenebaz Kurumsal seat (members/{uid}.seat)
//   licenses/{uid}               Kurum lisansı seat (licenseCodes/{code}.claimedBy)
//
// Invite rewards (source "referral") live only in entitlements/{uid} (top
// level or `previous`).
//
// The app shows the same thing: premiumProvider = entitlements/{uid}
// (kept current here) OR licensePremiumProvider (licenses/{uid}),
// lib/services/billing/premium.dart.
import {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Query,
  QuerySnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

export type Source = "play" | "test" | "family" | "org" | "license" | "referral" | string;

export interface Grant {
  source: Source;
  /** Milliseconds since epoch. */
  until: number;
  productId: string | null;
}

/** Reads through a transaction or directly. */
export interface Reader {
  doc(ref: DocumentReference): Promise<DocumentSnapshot>;
  query(q: Query): Promise<QuerySnapshot>;
}

export const direct: Reader = { doc: (r) => r.get(), query: (q) => q.get() };
export const inTx = (tx: Transaction): Reader => ({ doc: (r) => tx.get(r), query: (q) => tx.get(q) });

const ms = (t: unknown) => (t as Timestamp | undefined)?.toMillis?.() ?? 0;

/** The grant written at the top level of entitlements/{uid}, if running. */
function topLevel(e: DocumentData | undefined, now: number): Grant | null {
  const on = e?.active === true || e?.premium === true;
  const until = ms(e?.expiresAt);
  if (!on || until <= now) return null;
  return { source: (e?.source as string) ?? "entitlement", until, productId: (e?.productId as string) ?? null };
}

/**
 * Every running Premium grant of [uid], best first. [exclude] skips sources
 * (e.g. "family" while the learner is being removed from one). [ent] is
 * entitlements/{uid} when the caller already read it.
 */
export async function premiumGrants(
  db: Firestore,
  uid: string,
  nowDate: Date,
  opts: { read?: Reader; exclude?: Source[]; excludeToken?: string; ent?: DocumentData | null } = {},
): Promise<Grant[]> {
  const read = opts.read ?? direct;
  const skip = new Set(opts.exclude ?? []);
  const now = nowDate.getTime();
  const out: Grant[] = [];
  const add = (g: Grant | null) => {
    if (g && g.until > now && !skip.has(g.source)) out.push(g);
  };

  const ent = opts.ent !== undefined ? (opts.ent ?? undefined) : (await read.doc(db.doc(`entitlements/${uid}`))).data();
  const [purchases, ship, license] = await Promise.all([
    read.query(db.collection("purchases").where("uid", "==", uid)),
    skip.has("org") ? undefined : read.doc(db.doc(`memberships/${uid}`)),
    skip.has("license") ? undefined : read.doc(db.doc(`licenses/${uid}`)),
  ]);

  // Play (and emulator) subscriptions, from their own token records.
  const subs = new Map<string, number>();
  for (const p of purchases.docs) {
    const kind = p.get("kind");
    if (kind !== "subscription" && kind !== "test") continue;
    if (p.id === opts.excludeToken) continue;
    const until = ms(p.get("entitledUntil"));
    subs.set(p.id, until);
    add({ source: kind === "test" ? "test" : "play", until, productId: (p.get("productId") as string) ?? null });
  }

  // A family seat is never taken from the member's own copy of the end date:
  // only the live families/{owner} doc (plan running + member listed) counts,
  // below. A stale member doc (plan ended or seat removed without that doc
  // being rewritten) must not keep Premium.
  const isFamily = (e: DocumentData | undefined) => e?.source === "family";
  if ((!opts.excludeToken || ent?.purchaseTokenHash !== opts.excludeToken) && !isFamily(ent)) add(topLevel(ent, now));
  const prev = ent?.previous as DocumentData | undefined;
  if (prev && !isFamily(prev)) {
    const hash = prev.purchaseTokenHash as string | undefined;
    // A Play grant parked in `previous` counts only while its token still does.
    const stale = (hash !== undefined && subs.has(hash) && subs.get(hash)! <= now) || (hash !== undefined && hash === opts.excludeToken);
    if (!stale) {
      add({ source: (prev.source as string) ?? "entitlement", until: ms(prev.expiresAt), productId: (prev.productId as string) ?? null });
    }
  }

  const reads: Promise<void>[] = [];
  const fam = ent?.family as { ownerUid?: string; role?: string } | undefined;
  if (!skip.has("family") && fam?.role === "member" && typeof fam.ownerUid === "string") {
    reads.push(
      read.doc(db.doc(`families/${fam.ownerUid}`)).then((f) => {
        const listed = uid in ((f.get("members") as Record<string, unknown>) ?? {});
        if (listed) add({ source: "family", until: ms(f.get("expiresAt")), productId: "lingora_premium_family_yearly" });
      }),
    );
  }
  const orgId = ship?.get("orgId");
  if (typeof orgId === "string") {
    reads.push(
      Promise.all([read.doc(db.doc(`orgs/${orgId}`)), read.doc(db.doc(`orgs/${orgId}/members/${uid}`))]).then(
        ([org, member]) => {
          if (member.get("seat") === true) add({ source: "org", until: ms(org.get("planExpiresAt")), productId: "org" });
        },
      ),
    );
  }
  const code = license?.get("code");
  if (typeof code === "string") {
    reads.push(
      read.doc(db.doc(`licenseCodes/${code}`)).then((c) => {
        // A seat the operator released (license_codes.mjs release) no longer counts.
        if (c.get("claimedBy") === uid) add({ source: "license", until: ms(license!.get("expiresAt")), productId: "license" });
      }),
    );
  }
  await Promise.all(reads);
  return out.sort((a, b) => b.until - a.until);
}

/** The best running grant of [uid], or null. */
export async function effectivePremium(db: Firestore, uid: string, now: Date): Promise<Grant | null> {
  return (await premiumGrants(db, uid, now))[0] ?? null;
}

/** True if [uid] has Premium from any source at [now]. */
export async function hasPremium(db: Firestore, uid: string, now: Date): Promise<boolean> {
  return (await effectivePremium(db, uid, now)) !== null;
}

/**
 * The fields to merge into entitlements/{uid} after the source in [exclude]
 * (or the subscription token [excludeToken]) stopped: the best other running grant, or Premium off. Kurum licences are
 * left out on purpose: the app reads licenses/{uid} itself, and a released
 * seat must not linger in entitlements.
 */
export async function recomputedEntitlement(
  db: Firestore,
  uid: string,
  now: Date,
  read: Reader,
  ent: DocumentData | undefined,
  exclude: Source | null,
  excludeToken?: string,
): Promise<DocumentData> {
  const skip: Source[] = exclude ? [exclude, "license"] : ["license"];
  const grants = await premiumGrants(db, uid, now, { read, ent: ent ?? null, exclude: skip, excludeToken });
  const best = grants[0];
  const base: DocumentData = { previous: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() };
  if (!best) {
    return { ...base, active: false, premium: false, status: "expired", expiresAt: Timestamp.fromDate(now) };
  }
  return {
    ...base,
    active: true,
    premium: true,
    status: "active",
    source: best.source,
    productId: best.productId ?? FieldValue.delete(),
    expiresAt: Timestamp.fromMillis(best.until),
  };
}

/** What to keep in `previous` when [source] takes over a running grant [e]. */
export function parkedGrant(e: DocumentData | undefined, takenOverBy: Source, now: Date): DocumentData | null {
  const g = topLevel(e, now.getTime());
  if (!g || g.source === takenOverBy) return null;
  return {
    source: g.source,
    productId: g.productId,
    expiresAt: e!.expiresAt,
    ...(typeof e?.purchaseTokenHash === "string" ? { purchaseTokenHash: e.purchaseTokenHash } : {}),
  };
}
