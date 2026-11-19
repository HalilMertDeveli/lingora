// Security rules for config/app (forced update) and stats/ (owner dashboard).
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
    const db = ctx.firestore();
    await setDoc(doc(db, "config/app"), {
      minVersionCode: 5,
      recommendedVersionCode: 7,
      message: "Lütfen güncelle",
    });
    await setDoc(doc(db, "config/lingoraAdmins"), { uids: ["owner"] });
    await setDoc(doc(db, "stats/daily/days/2026-11-10"), { first_open: 3 });
  });
});

test("config/app: anyone may read it, even signed out", async () => {
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "config/app")));
  await assertSucceeds(getDoc(doc(env.authenticatedContext("u1").firestore(), "config/app")));
});

test("config/app: no client may write it", async () => {
  const anon = env.unauthenticatedContext().firestore();
  const user = env.authenticatedContext("u1").firestore();
  const owner = env.authenticatedContext("owner", { isLingoraAdmin: true }).firestore();
  for (const db of [anon, user, owner]) {
    await assertFails(setDoc(doc(db, "config/app"), { minVersionCode: 0 }));
    await assertFails(updateDoc(doc(db, "config/app"), { minVersionCode: 999 }));
    await assertFails(deleteDoc(doc(db, "config/app")));
  }
  await assertFails(setDoc(doc(user, "config/other"), { x: 1 }));
});

test("config: other documents and listing stay private", async () => {
  const user = env.authenticatedContext("u1").firestore();
  await assertFails(getDoc(doc(user, "config/lingoraAdmins")));
  await assertFails(getDocs(collection(user, "config")));
});

test("stats: clients can neither read nor write", async () => {
  const anon = env.unauthenticatedContext().firestore();
  const user = env.authenticatedContext("u1").firestore();
  const owner = env.authenticatedContext("owner", { isLingoraAdmin: true }).firestore();
  for (const db of [anon, user, owner]) {
    await assertFails(getDoc(doc(db, "stats/daily/days/2026-11-10")));
    await assertFails(getDocs(collection(db, "stats/daily/days")));
    await assertFails(setDoc(doc(db, "stats/daily/days/2026-11-10"), { first_open: 1000 }));
    await assertFails(updateDoc(doc(db, "stats/daily/days/2026-11-10"), { first_open: 1000 }));
    await assertFails(setDoc(doc(db, "stats/daily"), { x: 1 }));
  }
});
