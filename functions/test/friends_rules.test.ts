// Friends rules (friendCodes, friendships, cheers) against the Firestore emulator.
// The feature has no Cloud Functions: these rules are the whole server side.
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
  query,
  serverTimestamp,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
} from "firebase/firestore";

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
});

const db = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "google.com" } }).firestore();
type Db = ReturnType<typeof db>;
const guestDb = (uid: string) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

/** Turkish day number, as trDay() in firestore.rules and friendDay() in the app. */
const today = () => Math.floor((Date.now() + 3 * 3600e3) / 86400e3);

// "ali" < "zeynep", so the pair id is ali_zeynep.
const PAIR = "ali_zeynep";
const ZCODE = "ZEYN2345";

const codeDoc = (uid: string, name: string) => ({ uid, name, avatar: "🦊", createdAt: serverTimestamp() });

/** Zeynep's code, written as the app does. */
async function zeynepCode() {
  await assertSucceeds(setDoc(doc(db("zeynep"), `friendCodes/${ZCODE}`), codeDoc("zeynep", "Zeynep")));
}

const newFriendship = (over: Record<string, unknown> = {}) => ({
  members: ["ali", "zeynep"],
  code: ZCODE,
  names: { ali: "Ali", zeynep: "Zeynep" },
  avatars: { ali: "⭐", zeynep: "🦊" },
  done: {},
  streak: 0,
  best: 0,
  streakDay: 0,
  createdAt: serverTimestamp(),
  ...over,
});

/** Seeds the friendship directly (rules off), e.g. mid-streak. */
async function seed(over: Record<string, unknown> = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `friendships/${PAIR}`), {
      ...newFriendship(),
      createdAt: new Date(),
      ...over,
    });
  });
}

const pairRef = (f: Db) => doc(f, `friendships/${PAIR}`);

test("friendCodes: an account creates its own well-formed code", async () => {
  await zeynepCode();
  // Guests, bad formats, someone else's uid and extra fields are refused.
  await assertFails(setDoc(doc(guestDb("g"), "friendCodes/GUES2345"), codeDoc("g", "Misafir")));
  await assertFails(setDoc(doc(db("ali"), "friendCodes/abc"), codeDoc("ali", "Ali")));
  await assertFails(setDoc(doc(db("ali"), "friendCodes/ALI0O1I2"), codeDoc("ali", "Ali"))); // 0, O, 1, I
  await assertFails(setDoc(doc(db("ali"), "friendCodes/ALKX2345"), codeDoc("zeynep", "Ali")));
  await assertFails(setDoc(doc(db("ali"), "friendCodes/ALKX2345"), { ...codeDoc("ali", "Ali"), xp: 1 }));
  await assertFails(setDoc(doc(db("ali"), "friendCodes/ALKX2345"), codeDoc("ali", "")));
  // Taking over an existing code is an update by a non-owner.
  await assertFails(setDoc(doc(db("ali"), `friendCodes/${ZCODE}`), codeDoc("ali", "Ali")));
});

test("friendCodes: anyone with an account may look a code up, but not list others", async () => {
  await zeynepCode();
  await assertSucceeds(getDoc(doc(db("ali"), `friendCodes/${ZCODE}`)));
  await assertFails(getDoc(doc(guestDb("g"), `friendCodes/${ZCODE}`)));
  await assertFails(getDocs(collection(db("ali"), "friendCodes")));
  await assertFails(getDocs(query(collection(db("ali"), "friendCodes"), where("uid", "==", "zeynep"))));
  await assertSucceeds(getDocs(query(collection(db("zeynep"), "friendCodes"), where("uid", "==", "zeynep"))));
});

test("friendCodes: only the owner renames or deletes", async () => {
  await zeynepCode();
  await assertSucceeds(setDoc(doc(db("zeynep"), `friendCodes/${ZCODE}`), codeDoc("zeynep", "Zey")));
  await assertFails(deleteDoc(doc(db("ali"), `friendCodes/${ZCODE}`)));
  await assertSucceeds(deleteDoc(doc(db("zeynep"), `friendCodes/${ZCODE}`)));
});

test("friendships: adding a friend with their code", async () => {
  await zeynepCode();
  await assertSucceeds(setDoc(pairRef(db("ali")), newFriendship()));
  // Both members read it, also through the array-contains query.
  await assertSucceeds(getDoc(pairRef(db("zeynep"))));
  await assertSucceeds(
    getDocs(query(collection(db("ali"), "friendships"), where("members", "array-contains", "ali"))),
  );
  await assertFails(getDoc(pairRef(db("mallory"))));
  await assertFails(
    getDocs(query(collection(db("mallory"), "friendships"), where("members", "array-contains", "ali"))),
  );
});

test("friendships: no code, wrong code, forged data or guests are refused", async () => {
  // No code yet.
  await assertFails(setDoc(pairRef(db("ali")), newFriendship()));
  await zeynepCode();
  await assertFails(setDoc(pairRef(guestDb("ali")), newFriendship()));
  // A code that belongs to someone else.
  await assertSucceeds(setDoc(doc(db("mert"), "friendCodes/MERT2345"), codeDoc("mert", "Mert")));
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ code: "MERT2345" })));
  // Forged name or avatar for the friend, a head start, wrong order or id.
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ names: { ali: "Ali", zeynep: "Zz" } })));
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ avatars: { ali: "⭐", zeynep: "🐼" } })));
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ streak: 5 })));
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ done: { ali: today() } })));
  await assertFails(setDoc(pairRef(db("ali")), newFriendship({ members: ["zeynep", "ali"] })));
  await assertFails(setDoc(doc(db("ali"), "friendships/zeynep_ali"), newFriendship()));
  // A third person cannot pair two others.
  await assertFails(setDoc(pairRef(db("mallory")), newFriendship()));
});

test("friendships: you cannot befriend yourself", async () => {
  await assertSucceeds(setDoc(doc(db("ali"), "friendCodes/ALKX2345"), codeDoc("ali", "Ali")));
  await assertFails(
    setDoc(
      doc(db("ali"), "friendships/ali_ali"),
      newFriendship({ members: ["ali", "ali"], code: "ALKX2345", names: { ali: "Ali" }, avatars: { ali: "🦊" } }),
    ),
  );
});

test("friendships: marking today's goal, own entries only", async () => {
  await seed();
  const t = today();
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t - 1 })); // not today
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t + 1 }));
  await assertFails(updateDoc(pairRef(db("ali")), { "done.zeynep": t })); // someone else's
  await assertFails(updateDoc(pairRef(db("ali")), { "names.zeynep": "Z" }));
  await assertFails(updateDoc(pairRef(db("ali")), { code: "X" }));
  await assertFails(updateDoc(pairRef(guestDb("ali")), { "done.ali": t }));
  await assertFails(updateDoc(pairRef(db("mallory")), { "done.mallory": t }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "done.ali": t }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "names.ali": "Ali Can", "avatars.ali": "🐢" }));
  await assertFails(updateDoc(pairRef(db("ali")), { "names.ali": "" }));
});

test("friendships: the streak starts when both reach the goal the same day", async () => {
  const t = today();
  await seed({ done: { zeynep: t } });
  // Ali must bump the streak together with his mark; forgetting it or
  // forging a bigger number is refused.
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t }));
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 7, streakDay: t, best: 7 }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 1, streakDay: t, best: 1 }));
  // Once a day only.
  await assertFails(updateDoc(pairRef(db("zeynep")), { streak: 2, streakDay: t, best: 2 }));
});

test("friendships: a consecutive day grows the streak, a gap restarts it", async () => {
  const t = today();
  await seed({ done: { zeynep: t, ali: t - 1 }, streak: 3, best: 3, streakDay: t - 1 });
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 1, streakDay: t, best: 3 }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 4, streakDay: t, best: 4 }));

  await seed({ done: { zeynep: t, ali: t - 3 }, streak: 9, best: 9, streakDay: t - 3 });
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 10, streakDay: t, best: 10 }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 1, streakDay: t, best: 9 }));
});

test("friendships: alone, marking the goal leaves the streak alone", async () => {
  const t = today();
  await seed({ streak: 2, best: 5, streakDay: t - 1 });
  await assertFails(updateDoc(pairRef(db("ali")), { "done.ali": t, streak: 3, streakDay: t, best: 5 }));
  await assertSucceeds(updateDoc(pairRef(db("ali")), { "done.ali": t }));
});

test("friendships: either member may remove the friendship", async () => {
  await seed();
  await assertFails(deleteDoc(pairRef(db("mallory"))));
  await assertSucceeds(deleteDoc(pairRef(db("zeynep"))));
});

const cheer = (kind: string, over: Record<string, unknown> = {}) => ({
  from: "ali",
  to: "zeynep",
  kind,
  day: today(),
  createdAt: serverTimestamp(),
  ...over,
});
const cheerRef = (f: Db, kind: string, day = today(), from = "ali") =>
  doc(f, `friendships/${PAIR}/cheers/${from}_${day}_${kind}`);

test("cheers: a preset cheer once per kind and day", async () => {
  await seed();
  await assertSucceeds(setDoc(cheerRef(db("ali"), "tebrik"), cheer("tebrik")));
  await assertSucceeds(setDoc(cheerRef(db("ali"), "hadi"), cheer("hadi")));
  // Same kind again today is an update: refused.
  await assertFails(setDoc(cheerRef(db("ali"), "tebrik"), cheer("tebrik")));
  await assertSucceeds(getDoc(cheerRef(db("zeynep"), "tebrik")));
  await assertSucceeds(getDocs(collection(db("zeynep"), `friendships/${PAIR}/cheers`)));
  await assertSucceeds(deleteDoc(cheerRef(db("zeynep"), "tebrik")));
});

test("cheers: forged, free-text or outsider cheers are refused", async () => {
  await seed();
  const t = today();
  await assertFails(setDoc(cheerRef(db("ali"), "küfür"), cheer("küfür")));
  await assertFails(setDoc(cheerRef(db("ali"), "destek"), cheer("destek", { text: "merhaba" })));
  await assertFails(setDoc(cheerRef(db("ali"), "destek"), cheer("destek", { to: "mallory" })));
  await assertFails(setDoc(cheerRef(db("ali"), "destek"), cheer("destek", { from: "zeynep" })));
  await assertFails(setDoc(cheerRef(db("ali"), "destek", t - 1), cheer("destek", { day: t - 1 })));
  await assertFails(setDoc(doc(db("ali"), `friendships/${PAIR}/cheers/x`), cheer("destek")));
  await assertFails(setDoc(cheerRef(guestDb("ali"), "destek"), cheer("destek")));
  await assertFails(
    setDoc(cheerRef(db("mallory"), "destek", t, "mallory"), cheer("destek", { from: "mallory", to: "ali" })),
  );
  await assertSucceeds(setDoc(cheerRef(db("ali"), "destek"), cheer("destek")));
  await assertFails(getDoc(cheerRef(db("mallory"), "destek")));
  await assertFails(deleteDoc(cheerRef(db("mallory"), "destek")));
  // No friendship, no cheers.
  await assertFails(
    setDoc(doc(db("ali"), `friendships/ali_mert/cheers/ali_${t}_destek`), cheer("destek", { to: "mert" })),
  );
});
