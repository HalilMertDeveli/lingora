// Account deletion (Google Play "account deletion" policy; the app says
// "buluttaki her şey silinir"): removes or anonymises everything the server
// keeps about a learner, then the caller deletes the Auth user.
//
// Every collection in firestore.rules and functions/src is listed in
// PERSONAL_DATA below with what happens to it; test/account.test.ts seeds
// each one and fails when a new collection is missing from the list.
//
// Kept on purpose (abuse prevention, no personal content):
//   deletedAccounts/{uid}: tombstone, see firestore.rules match /users.
//   referralRedemptions/{uid}: stops the same person collecting invite
//     rewards again (the doc id is a uid that no longer exists anywhere).
//   referralDevices/{hash}: same, for the device; its `uid` is anonymised.
import { DocumentReference, FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";

import * as family from "./family.js";
import * as league from "./league.js";
import * as orgs from "./orgs.js";

/** Written into fields that pointed at the deleted account. */
export const DELETED = "deleted";

/**
 * League member rows carry `uid` from this PR on; groups created before this
 * date are also looked into one by one. Must be later than the deploy of
 * this change (a bounded, one-off set of pre-launch groups).
 */
export const LEAGUE_UID_SINCE = Date.parse("2027-02-01T00:00:00Z");

/** What deleteUserData does with each collection (keys: top-level collection or path pattern). */
export const PERSONAL_DATA: Record<string, string> = {
  users: "deleted with subcollections",
  profiles: "deleted",
  leagueState: "deleted",
  entitlements: "deleted",
  memberships: "deleted (after leaving the org)",
  licenses: "deleted",
  classLinks: "deleted",
  usage: "deleted",
  usageWriting: "deleted",
  reportUsage: "deleted",
  usageRehearsal: "deleted",
  voiceUsage: "deleted",
  explainUsage: "deleted",
  reportLimits: "deleted",
  reports: "uid anonymised: the question report stays for the content team",
  referrals: "deleted",
  rehearsals: "deleted with items",
  friendCodes: "deleted (uid field)",
  phoneIndex: "deleted (uid field)",
  friendRequests: "deleted (from / to)",
  friendships: "deleted with cheers (members)",
  purchases: "deleted (uid field): a running subscription can be restored on a new account",
  inviteCodes: "deleted (uid field): nobody can redeem the code any more",
  members: "subcollection: see leagues/*/members, orgs/*/members, classes/*/members",
  cheers: "friendships/*/cheers: only exist in the account's friendships, deleted with them",
  "leagues/*/members": "deleted in every group, current and past",
  leagues: "group docs: no personal data; size kept in step for open groups",
  leagueWeeks: "counters: no personal data",
  families: "owned family deleted (members keep their other Premium); membership left",
  familyCodes: "deleted with the owned family",
  "orgs/*/members": "left through orgs.leaveOrg (seat freed, seatsUsed - 1)",
  "orgs/*/classes": "teacherUid cleared",
  "orgs/*/assignments": "createdBy anonymised",
  orgs: "createdBy anonymised",
  orgCodes: "createdBy anonymised",
  "classes/*/members": "the learner's own row deleted in every joined class (classLinks)",
  speaking: "classes/*/speaking/{uid}: the teacher's copy, deleted in every joined class",
  speakingStats: "deleted",
  leads: "no uid: sales quote requests from the public /kurumsal page (staff delete them)",
  leadRate: "no uid: hashed-IP daily counters for the quote form",
  classes: "classes the account teaches deleted with their rows",
  licenseCodes: "seat released (claimedBy cleared), the org can hand it out again",
  config: "uid removed from config/lingoraAdmins",
  deletedAccounts: "kept: tombstone",
  referralRedemptions: "kept: abuse prevention",
  referralDevices: "kept: abuse prevention, uid anonymised",
  aiDevices: "no uid: per-install free AI counters (ai_guard.ts)",
  aiSpend: "no uid: daily AI cost totals (ai_guard.ts)",
  daily: "no uid: Günün okuması, shared by everyone (daily_reading.ts)",
  levels: "daily/*/levels: shared readings, no uid",
  stats: "no uid: aggregated daily counters (stats.ts)",
  ttsCache: "no uid: shared MP3 cache keyed by text hash, expires by TTL (tts.ts)",
};

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
  "explainUsage",
  "voiceUsage",
  "referrals",
  "rehearsals",
  "speakingStats",
  "reportLimits",
];

/** Collections with a field that holds the owner's uid; the documents are deleted. */
const OWNED_BY_FIELD: Array<[collection: string, field: string]> = [
  ["friendCodes", "uid"],
  ["phoneIndex", "uid"],
  ["friendRequests", "from"],
  ["friendRequests", "to"],
  // Purchase tokens: released so a still-running Play subscription can be
  // restored on a new account (otherwise verifyPurchase says token_in_use).
  ["purchases", "uid"],
  // Invite code: otherwise a later redeem would grant days to the deleted uid.
  ["inviteCodes", "uid"],
  // Kurum classes the account teaches (with the students' rows in them).
  ["classes", "ownerUid"],
];

/** Fields pointing at the uid in other people's or the org's documents: anonymised. */
const ANONYMISE: Array<[collectionGroup: string, field: string, value: string, under: string]> = [
  ["orgCodes", "createdBy", DELETED, ""],
  ["orgs", "createdBy", DELETED, ""],
  ["assignments", "createdBy", DELETED, "orgs/"],
  ["classes", "teacherUid", "", "orgs/"],
  ["referralDevices", "uid", DELETED, ""],
  // "Soruyu bildir": the report is about the content, so it stays without the uid.
  ["reports", "uid", DELETED, ""],
];

export interface DeleteResult {
  deleted: true;
  docs: number;
}

/** Deletes all server data of [uid]. Safe to call again after a partial failure. */
export async function deleteUserData(db: Firestore, uid: string, now: Date = new Date()): Promise<DeleteResult> {
  let docs = 0;

  // Tombstone first: the rules then refuse users/{uid} writes from phones
  // still signed in to this account. No personal data; uids are never reused.
  await db.doc(`deletedAccounts/${uid}`).set({ at: FieldValue.serverTimestamp() });

  // Leave shared groups first so other people's views stay consistent.
  await ignoreErrors(() => league.leaveLeague(db, uid));
  docs += await deleteLeagueRows(db, uid);
  const ent = (await db.doc(`entitlements/${uid}`).get()).data();
  if (ent?.family?.role === "member") await ignoreErrors(() => family.leaveFamily(db, uid, now));
  const fam = (await db.doc(`families/${uid}`).get()).data();
  if (fam) {
    for (const m of Object.keys((fam.members as Record<string, unknown>) ?? {})) {
      await ignoreErrors(() => family.removeFamilyMember(db, uid, { memberUid: m }, now));
    }
    if (typeof fam.code === "string") await db.doc(`familyCodes/${fam.code}`).delete();
    await db.doc(`families/${uid}`).delete();
    docs++;
  }

  // Dilmaç Kurumsal: frees the seat (seatsUsed - 1) in the same transaction.
  const ship = (await db.doc(`memberships/${uid}`).get()).data();
  if (typeof ship?.orgId === "string") {
    await ignoreErrors(() => orgs.leaveOrg(db, { uid }, {}, now));
    // A row left behind by an earlier, interrupted run.
    const stray = db.doc(`orgs/${ship.orgId}/members/${uid}`);
    if ((await stray.get()).exists) await stray.delete();
    docs++;
  }

  // Kurum lisansı: the learner's summary and the teacher's speaking copy in
  // each joined class (classLinks itself is in UID_DOCS), and the seat.
  const links = (await db.doc(`classLinks/${uid}`).get()).get("codes");
  for (const code of Array.isArray(links) ? links : []) {
    if (typeof code !== "string" || !/^[A-Z0-9]{1,16}$/.test(code)) continue;
    for (const row of [db.doc(`classes/${code}/members/${uid}`), db.doc(`classes/${code}/speaking/${uid}`)]) {
      if ((await row.get()).exists) {
        await row.delete();
        docs++;
      }
    }
  }
  const seats = await db.collection("licenseCodes").where("claimedBy", "==", uid).get();
  for (const s of seats.docs) {
    await s.ref.update({ claimedBy: null, claimedAt: FieldValue.delete() });
    docs++;
  }

  const friendships = await db.collection("friendships").where("members", "array-contains", uid).get();
  const refs: DocumentReference[] = friendships.docs.map((d) => d.ref);
  for (const [col, field] of OWNED_BY_FIELD) {
    const snap = await db.collection(col).where(field, "==", uid).get();
    refs.push(...snap.docs.map((d) => d.ref));
  }
  for (const ref of refs) {
    // recursiveDelete also removes subcollections (friendships/*/cheers, classes/*/members).
    await db.recursiveDelete(ref);
    docs++;
  }

  for (const [group, field, value, under] of ANONYMISE) {
    // Top-level collections need no collection group index.
    const source = under ? db.collectionGroup(group) : db.collection(group);
    const snap = await source.where(field, "==", uid).get();
    for (const d of snap.docs) {
      if (under && !d.ref.path.startsWith(under)) continue;
      await d.ref.update({ [field]: value });
      docs++;
    }
  }
  const admins = db.doc("config/lingoraAdmins");
  const adminUids = (await admins.get()).get("uids");
  if (Array.isArray(adminUids) && adminUids.includes(uid)) {
    await admins.update({ uids: FieldValue.arrayRemove(uid) });
    docs++;
  }

  for (const col of UID_DOCS) {
    const ref = db.doc(`${col}/${uid}`);
    if ((await ref.get()).exists || (await ref.listCollections()).length > 0) docs++;
    await db.recursiveDelete(ref);
  }
  return { deleted: true, docs };
}

/**
 * Deletes the learner's row in every league group: rows with a `uid` field
 * through a collection group query, older rows by looking into each group
 * created before LEAGUE_UID_SINCE. Open groups shrink by one.
 */
async function deleteLeagueRows(db: Firestore, uid: string): Promise<number> {
  const rows = new Map<string, DocumentReference>();
  const tagged = await db.collectionGroup("members").where("uid", "==", uid).get();
  for (const d of tagged.docs) if (d.ref.path.startsWith("leagues/")) rows.set(d.ref.path, d.ref);

  const legacy = await db.collection("leagues").where("createdAt", "<", Timestamp.fromMillis(LEAGUE_UID_SINCE)).select().get();
  const candidates = legacy.docs.map((g) => g.ref.collection("members").doc(uid));
  for (let i = 0; i < candidates.length; i += 100) {
    const chunk = candidates.slice(i, i + 100);
    if (chunk.length === 0) continue;
    for (const s of await db.getAll(...chunk)) if (s.exists) rows.set(s.ref.path, s.ref);
  }
  for (const row of rows.values()) {
    const groupRef = row.parent.parent!;
    await db.runTransaction(async (tx) => {
      const [member, group] = await Promise.all([tx.get(row), tx.get(groupRef)]);
      if (!member.exists) return;
      tx.delete(row);
      if (group.exists && group.get("settled") !== true) tx.update(groupRef, { size: FieldValue.increment(-1) });
    });
  }
  return rows.size;
}

async function ignoreErrors(f: () => Promise<unknown>): Promise<void> {
  try {
    await f();
  } catch {
    // Already out of the group, or the group is gone: nothing to undo.
  }
}
