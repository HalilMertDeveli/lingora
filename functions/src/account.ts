// Account deletion (Google Play "account deletion" policy): removes everything
// the server keeps about a learner, then the caller deletes the Auth user.
//
// Kept on purpose (no personal content):
//   deletedAccounts/{uid}: tombstone, see firestore.rules match /users.
//   referralRedemptions/{uid}, referralDevices/{hash}: stop the same device
//   from collecting invite rewards again with a fresh account.
import { DocumentReference, FieldValue, Firestore } from "firebase-admin/firestore";

import * as family from "./family.js";
import * as league from "./league.js";

/** Single documents keyed by uid. */
const UID_DOCS = [
  "users",
  "profiles",
  "leagueState",
  "entitlements",
  "memberships",
  "licenses",
  "classLinks",
  "usage",
  "usageWriting",
  "reportUsage",
  "usageRehearsal",
  "referrals",
  "rehearsals",
];

/** Collections with a field that holds the owner's uid. */
const OWNED_BY_FIELD: Array<[collection: string, field: string]> = [
  ["friendCodes", "uid"],
  ["phoneIndex", "uid"],
  ["friendRequests", "from"],
  ["friendRequests", "to"],
  // Purchase tokens: released so a still-running Play subscription can be
  // restored on a new account (otherwise verifyPurchase says token_in_use).
  ["purchases", "uid"],
];

export interface DeleteResult {
  deleted: true;
  docs: number;
}

/** Deletes all server data of [uid]. Safe to call again after a partial failure. */
export async function deleteUserData(db: Firestore, uid: string): Promise<DeleteResult> {
  let docs = 0;

  // Tombstone first: the rules then refuse users/{uid} writes from phones
  // still signed in to this account. No personal data; uids are never reused.
  await db.doc(`deletedAccounts/${uid}`).set({ at: FieldValue.serverTimestamp() });

  // Leave shared groups first so other people's views stay consistent.
  await ignoreErrors(() => league.leaveLeague(db, uid));
  const ent = (await db.doc(`entitlements/${uid}`).get()).data();
  if (ent?.family?.role === "member") await ignoreErrors(() => family.leaveFamily(db, uid));
  const fam = (await db.doc(`families/${uid}`).get()).data();
  if (fam) {
    for (const m of Object.keys((fam.members as Record<string, unknown>) ?? {})) {
      await ignoreErrors(() => family.removeFamilyMember(db, uid, { memberUid: m }));
    }
    if (typeof fam.code === "string") await db.doc(`familyCodes/${fam.code}`).delete();
    await db.doc(`families/${uid}`).delete();
    docs++;
  }
  const ship = (await db.doc(`memberships/${uid}`).get()).data();
  if (typeof ship?.orgId === "string") {
    await db.doc(`orgs/${ship.orgId}/members/${uid}`).delete();
    docs++;
  }

  const friendships = await db.collection("friendships").where("members", "array-contains", uid).get();
  const refs: DocumentReference[] = friendships.docs.map((d) => d.ref);
  for (const [col, field] of OWNED_BY_FIELD) {
    const snap = await db.collection(col).where(field, "==", uid).get();
    refs.push(...snap.docs.map((d) => d.ref));
  }
  for (const ref of refs) {
    // recursiveDelete also removes subcollections (friendships/*/cheers).
    await db.recursiveDelete(ref);
    docs++;
  }
  for (const col of UID_DOCS) {
    const ref = db.doc(`${col}/${uid}`);
    if ((await ref.get()).exists || (await ref.listCollections()).length > 0) docs++;
    await db.recursiveDelete(ref);
  }
  return { deleted: true, docs };
}

async function ignoreErrors(f: () => Promise<unknown>): Promise<void> {
  try {
    await f();
  } catch {
    // Already out of the group, or the group is gone: nothing to undo.
  }
}
