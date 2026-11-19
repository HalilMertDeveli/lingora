import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { Timestamp } from "firebase-admin/firestore";

import { deleteUserData, PERSONAL_DATA } from "../src/account.js";
import { createJoinCode, createOrg, joinOrg } from "../src/orgs.js";
import { FAMILY_PRODUCT } from "../src/family.js";
import { createFamilyInvite, redeemFamilyCode } from "../src/family.js";
import { verifyPurchase } from "../src/purchase.js";
import { adminDb, clearFirestore } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-18T09:00:00Z");

beforeEach(clearFirestore);

const exists = async (path: string) => (await db.doc(path).get()).exists;

test("deletes every document of the learner and keeps other people's", async () => {
  await db.doc("users/me").set({ progress: { xp: 10 } });
  await db.doc("users/me/notes/n1").set({ text: "hello" });
  await db.doc("users/other").set({ progress: { xp: 5 } });
  await db.doc("profiles/me").set({ name: "Ben" });
  await db.doc("usage/me").set({ day: "2026-11-18", count: 2 });
  await db.doc("rehearsals/me/items/a").set({ score: 3 });
  await db.doc("friendCodes/ABCDEFGH").set({ uid: "me", name: "Ben" });
  await db.doc("friendCodes/HGFEDCBA").set({ uid: "other", name: "O" });
  await db.doc("friendships/me_other").set({ members: ["me", "other"] });
  await db.doc("friendships/me_other/cheers/c1").set({ from: "other" });
  await db.doc("friendRequests/x_me").set({ from: "x", to: "me" });
  await db.doc("phoneIndex/h1").set({ uid: "me" });
  await db.doc("referralRedemptions/me").set({ at: 1 });
  await verifyPurchase(db, "me", { productId: "lingora_premium_yearly", purchaseToken: "purchase-token-me-0001" }, {
    testMode: true,
    now,
  });

  const r = await deleteUserData(db, "me");
  assert.equal(r.deleted, true);

  for (const p of [
    "users/me",
    "users/me/notes/n1",
    "profiles/me",
    "usage/me",
    "rehearsals/me/items/a",
    "friendCodes/ABCDEFGH",
    "friendships/me_other",
    "friendships/me_other/cheers/c1",
    "friendRequests/x_me",
    "phoneIndex/h1",
    "entitlements/me",
  ]) {
    assert.equal(await exists(p), false, p);
  }
  assert.equal(await exists("users/other"), true);
  assert.equal(await exists("friendCodes/HGFEDCBA"), true);
  // Anti-abuse record stays.
  assert.equal(await exists("referralRedemptions/me"), true);
  assert.equal(await exists("deletedAccounts/me"), true);

  // The purchase token is released: a new account can restore it.
  const restored = await verifyPurchase(db, "newMe", { productId: "lingora_premium_yearly", purchaseToken: "purchase-token-me-0001" }, {
    testMode: true,
    now,
  });
  assert.equal(restored.active, true);

  // Running it again is harmless.
  await deleteUserData(db, "me");
});

test("a family owner's members lose the shared plan, a member leaves the family", async () => {
  await verifyPurchase(db, "owner", { productId: FAMILY_PRODUCT, purchaseToken: "purchase-token-family-0001" }, { testMode: true, now });
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);
  assert.equal((await db.doc("entitlements/kid").get()).data()?.family?.role, "member");

  await deleteUserData(db, "owner");
  assert.equal(await exists("families/owner"), false);
  assert.equal(await exists(`familyCodes/${code}`), false);
  assert.equal((await db.doc("entitlements/kid").get()).data()?.family?.role, undefined);
});

test("a family member leaving by deletion frees the seat", async () => {
  await verifyPurchase(db, "owner", { productId: FAMILY_PRODUCT, purchaseToken: "purchase-token-family-0002" }, { testMode: true, now });
  const { code } = await createFamilyInvite(db, "owner", now);
  await redeemFamilyCode(db, "kid", { code }, now);

  await deleteUserData(db, "kid");
  const fam = (await db.doc("families/owner").get()).data();
  assert.deepEqual(Object.keys(fam?.members ?? {}), []);
});

// ---- Audit findings 1 and 10: every collection, seats ---------------------

/** Top-level collection names in firestore.rules and in functions/src (doc/collection literals). */
function knownCollections(): Set<string> {
  const names = new Set<string>();
  const rules = readFileSync(join(process.cwd(), "..", "firestore.rules"), "utf8");
  for (const m of rules.matchAll(/match \/([A-Za-z]+)\/\{/g)) names.add(m[1]);
  for (const f of readdirSync(join(process.cwd(), "src")).filter((f) => f.endsWith(".ts"))) {
    const src = readFileSync(join(process.cwd(), "src", f), "utf8");
    for (const m of src.matchAll(/(?:doc|collection|collectionGroup)\(\s*[`"']([A-Za-z]+)[/`"']/g)) names.add(m[1]);
  }
  names.delete("databases");
  return names;
}

test("every collection has a deletion rule in PERSONAL_DATA", () => {
  const missing = [...knownCollections()].filter((c) => !(c in PERSONAL_DATA));
  assert.deepEqual(missing, [], `add these to PERSONAL_DATA in account.ts: ${missing.join(", ")}`);
});

test("seeds every per-user collection and leaves nothing that names the account", async () => {
  const ts = Timestamp.fromDate(new Date(now.getTime() + 30 * 86400000));
  const old = Timestamp.fromDate(new Date("2026-10-01T00:00:00Z"));
  const seed: Record<string, Record<string, unknown>> = {
    "users/me": { progress: {} },
    "users/me/notes/n": { t: 1 },
    "profiles/me": { name: "Ben" },
    "leagueState/me": { tier: 2 },
    "entitlements/me": { active: true, expiresAt: ts },
    "licenses/me": { code: "ABCDEFGHJKLM", org: "Okul", role: "teacher", expiresAt: ts },
    "licenseCodes/ABCDEFGHJKLM": { org: "Okul", role: "teacher", claimedBy: "me", claimedAt: old, expiresAt: ts },
    "classLinks/me": { codes: ["KLASKOD2"], updatedAt: old },
    "classes/KLASKOD2": { ownerUid: "teacher", name: "9-A", teacherName: "T", org: "Okul", open: true },
    "classes/KLASKOD2/members/me": { name: "Ben", streak: 1 },
    "classes/KLASKOD2/members/other": { name: "O", streak: 1 },
    "classes/KLASKOD2/speaking/me": { conversations: 2 },
    "speakingStats/me": { conversations: 2, lastSummary: "x" },
    "reportLimits/me": { n: 1, count: 1 },
    "reports/me_1": { uid: "me", reason: "unclear", note: "benim notum", questionId: "q1", status: "yeni" },
    "reports/x_1": { uid: "x", reason: "unclear", questionId: "q2", status: "bakildi", statusBy: "me" },
    "classes/BENIMKOD": { ownerUid: "me", name: "Benim", teacherName: "Ben", org: "Okul", open: true },
    "classes/BENIMKOD/members/stu": { name: "S", streak: 0 },
    "usage/me": { day: "x", count: 1 },
    "usageWriting/me": { day: "x", count: 1 },
    "reportUsage/me": { day: "x", count: 1 },
    "usageRehearsal/me": { count: 1 },
    "referrals/me": { code: "ABCDEFG" },
    "inviteCodes/ABCDEFG": { uid: "me" },
    "inviteCodes/HJKMNPQ": { uid: "other" },
    "referralRedemptions/me": { inviterUid: "x" },
    "referralDevices/h1": { uid: "me" },
    "rehearsals/me/items/r": { kind: "job" },
    "friendCodes/AAAAAAAA": { uid: "me" },
    "phoneIndex/p": { uid: "me" },
    "friendRequests/r1": { from: "me", to: "x" },
    "friendships/me_x": { members: ["me", "x"] },
    "purchases/t1": { uid: "me", kind: "subscription" },
    "leagues/2026-W40_0_0": { weekKey: "2026-W40", tier: 0, size: 2, settled: true, createdAt: old },
    "leagues/2026-W40_0_0/members/me": { name: "Ben", photo: "x", xp: 10 },
    "leagues/2026-W40_0_0/members/x": { name: "X", xp: 5 },
    "leagues/2027-W10_0_0": {
      weekKey: "2027-W10",
      tier: 0,
      size: 2,
      settled: false,
      createdAt: Timestamp.fromDate(new Date("2027-03-01T00:00:00Z")),
    },
    "leagues/2027-W10_0_0/members/me": { uid: "me", name: "Ben", xp: 10 },
    "orgs/o1": { name: "Otel", seats: 5, seatsUsed: 2, planExpiresAt: ts, createdBy: "me" },
    "orgs/o1/members/me": { role: "teacher", seat: true, classIds: ["c1"] },
    "orgs/o1/members/y": { role: "member", seat: true, classIds: ["c1"] },
    "orgs/o1/classes/c1": { name: "Resepsiyon", teacherUid: "me" },
    "orgs/o1/assignments/a1": { classId: "c1", createdBy: "me" },
    "orgCodes/ORGKOD22": { orgId: "o1", role: "member", createdBy: "me", active: true },
    "memberships/me": { orgId: "o1", role: "teacher" },
    "config/lingoraAdmins": { uids: ["me", "staff"] },
  };
  for (const [p, d] of Object.entries(seed)) await db.doc(p).set(d);

  await deleteUserData(db, "me", now);

  for (const p of [
    "users/me",
    "users/me/notes/n",
    "profiles/me",
    "leagueState/me",
    "entitlements/me",
    "licenses/me",
    "classLinks/me",
    "classes/KLASKOD2/members/me",
    "classes/KLASKOD2/speaking/me",
    "speakingStats/me",
    "reportLimits/me",
    "classes/BENIMKOD",
    "classes/BENIMKOD/members/stu",
    "usage/me",
    "usageWriting/me",
    "reportUsage/me",
    "usageRehearsal/me",
    "referrals/me",
    "inviteCodes/ABCDEFG",
    "rehearsals/me/items/r",
    "friendCodes/AAAAAAAA",
    "phoneIndex/p",
    "friendRequests/r1",
    "friendships/me_x",
    "purchases/t1",
    "leagues/2026-W40_0_0/members/me",
    "leagues/2027-W10_0_0/members/me",
    "orgs/o1/members/me",
    "memberships/me",
  ]) {
    assert.equal(await exists(p), false, p);
  }
  for (const p of ["classes/KLASKOD2/members/other", "inviteCodes/HJKMNPQ", "leagues/2026-W40_0_0/members/x", "orgs/o1/members/y"]) {
    assert.equal(await exists(p), true, p);
  }
  // Finding 10: the seat is freed together with the removal.
  assert.equal((await db.doc("orgs/o1").get()).get("seatsUsed"), 1);
  // An open league group shrinks; settled history keeps its size.
  assert.equal((await db.doc("leagues/2027-W10_0_0").get()).get("size"), 1);
  assert.equal((await db.doc("leagues/2026-W40_0_0").get()).get("size"), 2);
  // The Kurum seat goes back to the school.
  assert.equal((await db.doc("licenseCodes/ABCDEFGHJKLM").get()).get("claimedBy"), null);
  // Anonymised references.
  assert.equal((await db.doc("orgs/o1").get()).get("createdBy"), "deleted");
  assert.equal((await db.doc("orgs/o1/classes/c1").get()).get("teacherUid"), "");
  assert.equal((await db.doc("orgs/o1/assignments/a1").get()).get("createdBy"), "deleted");
  assert.equal((await db.doc("orgCodes/ORGKOD22").get()).get("createdBy"), "deleted");
  assert.equal((await db.doc("referralDevices/h1").get()).get("uid"), "deleted");
  assert.deepEqual((await db.doc("config/lingoraAdmins").get()).get("uids"), ["staff"]);
  const report = (await db.doc("reports/me_1").get()).data();
  assert.equal(report?.uid, "deleted");
  assert.equal(report?.note, undefined);
  assert.equal(report?.questionId, "q1");
  assert.equal((await db.doc("reports/x_1").get()).get("statusBy"), "deleted");
  // Kept on purpose.
  assert.equal(await exists("referralRedemptions/me"), true);
  assert.equal(await exists("deletedAccounts/me"), true);

  // Nothing left anywhere that still names the account.
  const leftovers: string[] = [];
  const walk = async (docs: FirebaseFirestore.DocumentReference[]) => {
    for (const ref of docs) {
      const top = ref.path.split("/")[0];
      const snap = await ref.get();
      const named = ref.id === "me" || JSON.stringify(snap.data() ?? {}).includes('"me"');
      if (snap.exists && named && !["deletedAccounts", "referralRedemptions"].includes(top)) leftovers.push(ref.path);
      for (const sub of await ref.listCollections()) await walk(await sub.listDocuments());
    }
  };
  for (const col of await db.listCollections()) await walk(await col.listDocuments());
  assert.deepEqual(leftovers, []);
});

test("a deleted org member frees the seat for the next person", async () => {
  const staff = { uid: "staff", claims: { isLingoraAdmin: true } };
  const { orgId, adminCode } = await createOrg(
    db,
    staff,
    { name: "Okul", type: "okul", seats: 1, planExpiresAt: now.getTime() + 30 * 86400000 },
    now,
  );
  await joinOrg(db, { uid: "boss" }, { code: adminCode, displayName: "Müdür" }, now);
  const { code } = await createJoinCode(db, { uid: "boss" }, { orgId, role: "member" }, now);
  await joinOrg(db, { uid: "me" }, { code, displayName: "Ben" }, now);
  assert.equal((await db.doc(`orgs/${orgId}`).get()).get("seatsUsed"), 1);
  await deleteUserData(db, "me", now);
  assert.equal((await db.doc(`orgs/${orgId}`).get()).get("seatsUsed"), 0);
  await joinOrg(db, { uid: "next" }, { code, displayName: "Sonraki" }, now);
  assert.equal((await db.doc(`orgs/${orgId}`).get()).get("seatsUsed"), 1);
});
