// Security rules for Mülakat Provası history (rehearsals/{uid}/items).
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { after, before, beforeEach, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, setLogLevel, updateDoc } from "firebase/firestore";

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
    await setDoc(doc(f, "rehearsals/alice/items/r_first_1"), { kind: "first", items: [], analysis: {} });
    await setDoc(doc(f, "usageRehearsal/alice"), { freeUsed: 1 });
  });
});

const db = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

test("the owner reads, lists and deletes their rehearsal history", async () => {
  const f = db("alice");
  await assertSucceeds(getDoc(doc(f, "rehearsals/alice/items/r_first_1")));
  await assertSucceeds(getDocs(collection(f, "rehearsals/alice/items")));
  await assertSucceeds(deleteDoc(doc(f, "rehearsals/alice/items/r_first_1")));
});

test("nobody else reads it and nobody writes it from the app", async () => {
  await assertFails(getDoc(doc(db("bob"), "rehearsals/alice/items/r_first_1")));
  await assertFails(getDocs(collection(db("bob"), "rehearsals/alice/items")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "rehearsals/alice/items/r_first_1")));
  const f = db("alice");
  await assertFails(setDoc(doc(f, "rehearsals/alice/items/r_new_22"), { kind: "first" }));
  await assertFails(updateDoc(doc(f, "rehearsals/alice/items/r_first_1"), { kind: "retell" }));
});

test("the free-try counter is server-only", async () => {
  await assertFails(getDoc(doc(db("alice"), "usageRehearsal/alice")));
  await assertFails(setDoc(doc(db("alice"), "usageRehearsal/alice"), { freeUsed: 0 }));
});
