// Security rules tests against the Firestore emulator.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  setLogLevel,
  Timestamp,
} from "firebase/firestore";

import { emulatorHost, PROJECT_ID } from "./helpers.js";

let env: RulesTestEnvironment;

before(async () => {
  setLogLevel("silent"); // the expected PERMISSION_DENIED errors are noise
  const [host, port] = emulatorHost().split(":");
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host,
      port: Number(port),
      // Compiled tests run from functions/lib/test.
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const db = (uid?: string) => (uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());

// Same fields as lib/services/firebase/progress_sync.dart writes.
const progressDoc = () => ({
  schema: 1,
  progress: { totalXp: 10, streak: 2 },
  totalXp: 10,
  displayName: null,
  clientUpdatedAt: Date.now(),
  updatedAt: serverTimestamp(),
});

test("users: owner can write a valid snapshot and read it back", async () => {
  await assertSucceeds(setDoc(doc(db("alice"), "users/alice"), progressDoc()));
  await assertSucceeds(getDoc(doc(db("alice"), "users/alice")));
  await assertSucceeds(
    setDoc(doc(db("alice"), "users/alice"), { ...progressDoc(), displayName: "Alice" }),
  );
});

test("users: others and guests are locked out", async () => {
  await assertFails(setDoc(doc(db("bob"), "users/alice"), progressDoc()));
  await assertFails(setDoc(doc(db(), "users/alice"), progressDoc()));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), { progress: {}, updatedAt: Timestamp.now() });
  });
  await assertFails(getDoc(doc(db("bob"), "users/alice")));
  await assertFails(getDoc(doc(db(), "users/alice")));
  await assertFails(deleteDoc(doc(db("alice"), "users/alice")));
});

test("users: shape and size are validated", async () => {
  const ref = doc(db("alice"), "users/alice");
  await assertFails(setDoc(ref, { ...progressDoc(), isAdmin: true }));
  await assertFails(setDoc(ref, { progress: { a: 1 } })); // no updatedAt
  await assertFails(setDoc(ref, { progress: "x", updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref, { progress: {}, updatedAt: Timestamp.fromMillis(0) })); // client clock
  await assertFails(setDoc(ref, { ...progressDoc(), displayName: "x".repeat(41) }));
  await assertFails(setDoc(ref, { ...progressDoc(), schema: "1" }));
  await assertFails(setDoc(ref, { ...progressDoc(), totalXp: -5 }));
  await assertFails(setDoc(ref, { ...progressDoc(), clientUpdatedAt: "now" }));
  const big: Record<string, number> = {};
  for (let i = 0; i < 61; i++) big[`k${i}`] = i;
  await assertFails(setDoc(ref, { progress: big, updatedAt: serverTimestamp() }));
});

test("entitlements and leagueState: owner read-only", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "entitlements/alice"), { active: true });
    await setDoc(doc(f, "leagueState/alice"), { tier: 1 });
  });
  for (const path of ["entitlements/alice", "leagueState/alice"]) {
    await assertSucceeds(getDoc(doc(db("alice"), path)));
    await assertFails(getDoc(doc(db("bob"), path)));
    await assertFails(setDoc(doc(db("alice"), path), { active: true, tier: 4 }));
  }
});

test("leagues: only group members can read, nobody writes", async () => {
  const g = "2026-11-09_0_0";
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, `leagues/${g}`), { weekKey: "2026-11-09", tier: 0 });
    await setDoc(doc(f, `leagues/${g}/members/alice`), { name: "Alice", xp: 10 });
    await setDoc(doc(f, `leagues/${g}/members/bob`), { name: "Bob", xp: 5 });
  });
  await assertSucceeds(getDocs(collection(db("alice"), `leagues/${g}/members`)));
  await assertSucceeds(getDoc(doc(db("bob"), `leagues/${g}`)));
  await assertFails(getDocs(collection(db("carol"), `leagues/${g}/members`)));
  await assertFails(getDoc(doc(db(), `leagues/${g}/members/alice`)));
  await assertFails(setDoc(doc(db("alice"), `leagues/${g}/members/alice`), { name: "Alice", xp: 9999 }));
  await assertFails(setDoc(doc(db("carol"), `leagues/${g}/members/carol`), { name: "Carol", xp: 0 }));
});

test("server-only collections are closed", async () => {
  for (const path of ["usage/alice", "purchases/abc", "leagueWeeks/2026-11-09_0"]) {
    await assertFails(getDoc(doc(db("alice"), path)));
    await assertFails(setDoc(doc(db("alice"), path), { x: 1 }));
  }
});
