// Security rules for Dilbaz Kurumsal: org data never reaches clients directly.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, setDoc, setLogLevel } from "firebase/firestore";

import { emulatorHost, PROJECT_ID } from "./helpers.js";

let env: RulesTestEnvironment;

before(async () => {
  setLogLevel("silent");
  const [host, port] = emulatorHost().split(":");
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host,
      port: Number(port),
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "orgs/o1"), { name: "Otel", seats: 5 });
    await setDoc(doc(f, "orgs/o1/members/boss"), { role: "admin" });
    await setDoc(doc(f, "orgs/o1/members/ali"), { role: "member" });
    await setDoc(doc(f, "orgs/o1/classes/c1"), { name: "Resepsiyon", teacherUid: "boss" });
    await setDoc(doc(f, "orgCodes/ABCDEFGH"), { orgId: "o1", role: "admin", active: true });
    await setDoc(doc(f, "memberships/ali"), { orgId: "o1", role: "member" });
    await setDoc(doc(f, "users/ali"), { progress: { diary: { "2026-11-10": "gizli" } } });
  });
});

const db = (uid?: string) => (uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());

test("memberships: owner read-only", async () => {
  await assertSucceeds(getDoc(doc(db("ali"), "memberships/ali")));
  await assertFails(getDoc(doc(db("boss"), "memberships/ali")));
  await assertFails(setDoc(doc(db("ali"), "memberships/ali"), { orgId: "o2", role: "admin" }));
  await assertFails(setDoc(doc(db("eve"), "memberships/eve"), { orgId: "o1", role: "admin" }));
});

test("orgs and codes are closed even to their own admins", async () => {
  for (const uid of ["boss", "ali", "eve"]) {
    await assertFails(getDoc(doc(db(uid), "orgs/o1")));
    await assertFails(getDocs(collection(db(uid), "orgs/o1/members")));
    await assertFails(getDoc(doc(db(uid), "orgs/o1/classes/c1")));
    await assertFails(getDoc(doc(db(uid), "orgCodes/ABCDEFGH")));
    await assertFails(setDoc(doc(db(uid), `orgs/o1/members/${uid}`), { role: "admin" }));
    await assertFails(setDoc(doc(db(uid), "orgCodes/ZZZZZZZZ"), { orgId: "o1", role: "admin", active: true }));
  }
  await assertFails(getDoc(doc(db(), "orgs/o1")));
});

test("an org admin cannot read a member's private progress", async () => {
  await assertFails(getDoc(doc(db("boss"), "users/ali")));
  await assertSucceeds(getDoc(doc(db("ali"), "users/ali")));
});
