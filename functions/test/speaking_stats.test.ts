// Teacher speaking report: speakingStats/{uid}, class copies and orgReport.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { deleteUserData } from "../src/account.js";
import { Caller, createJoinCode, createOrg, joinOrg, orgReport } from "../src/orgs.js";
import { estimateMinutes, recordSpeaking, teacherView } from "../src/speaking_stats.js";
import { adminDb, clearFirestore } from "./helpers.js";

const db = adminDb();
const now = new Date("2026-11-19T09:00:00Z");
const staff: Caller = { uid: "staff", claims: { isLingoraAdmin: true } };

beforeEach(clearFirestore);

const words = (n: number) => Array(n).fill("word").join(" ");
/** [turns] exchanges of [perLine] words on each side. */
const request = (turns = 15, perLine = 10) => ({
  scenarioId: "cafe",
  messages: Array.from({ length: turns }, () => [
    { role: "assistant", content: words(perLine) },
    { role: "user", content: words(perLine) },
  ]).flat(),
});
const karne = (summary = "Güzel gitti. Geçmiş zamanı çalış.") => ({
  mistakes: [
    { original: "I go yesterday", corrected: "I went yesterday" },
    { original: "She have a cat", corrected: "She has a cat" },
  ],
  summary_tr: summary,
  weak_words: [{ word: "Thought" }, { word: "three" }, { word: "<script>" }],
});

test("estimateMinutes from word count, 1..30", () => {
  assert.equal(estimateMinutes(request(15).messages), 3); // 300 words
  assert.equal(estimateMinutes(request(1).messages), 1);
  assert.equal(estimateMinutes(request(20, 80).messages), 30); // capped
  assert.equal(estimateMinutes("nonsense"), 0);
});

test("stats add up and keep only the teacher's view", async () => {
  await recordSpeaking(db, "elif", request(), karne(), now);
  const v = await recordSpeaking(
    db,
    "elif",
    request(),
    {
      mistakes: [{ original: "He don't", corrected: "He doesn't" }],
      summary_tr: "Bu sohbet için karne hazırlanamadı.",
      weak_words: [{ word: "thought" }],
    },
    new Date(now.getTime() + 60e3),
  );
  assert.equal(v.conversations, 2);
  assert.equal(v.minutes, 6);
  // A declined karne keeps the previous summary.
  assert.equal(v.lastSummary, "Güzel gitti. Geçmiş zamanı çalış.");
  assert.deepEqual(v.recentMistakes[0], { original: "He don't", corrected: "He doesn't" });
  assert.equal(v.recentMistakes.length, 3);
  assert.deepEqual(v.weakWords, ["thought", "three"]);
  const raw = JSON.stringify((await db.doc("speakingStats/elif").get()).data());
  assert.equal(raw.includes("explanation"), false);
  assert.equal(raw.includes("word word"), false); // no transcript
});

test("class copy only where the student is still a member", async () => {
  await db.doc("classLinks/elif").set({ codes: ["SNFX8ABC", "SNFX8XYZ", "../bad"] });
  await db.doc("classes/SNFX8ABC").set({ ownerUid: "ayse" });
  await db.doc("classes/SNFX8ABC/members/elif").set({ name: "Elif" });
  await db.doc("classes/SNFX8XYZ").set({ ownerUid: "veli" }); // left this one
  await recordSpeaking(db, "elif", request(), karne(), now);
  const copy = (await db.doc("classes/SNFX8ABC/speaking/elif").get()).data()!;
  assert.equal(copy.conversations, 1);
  assert.equal((copy.lastAt as Timestamp).toMillis(), now.getTime());
  assert.equal((await db.doc("classes/SNFX8XYZ/speaking/elif").get()).exists, false);
});

test("orgReport shows speaking stats of org members only", async () => {
  const { orgId, adminCode } = await createOrg(
    db,
    staff,
    { name: "Başarı", type: "okul", seats: 5, planExpiresAt: now.getTime() + 90 * 864e5 },
    now,
  );
  await joinOrg(db, { uid: "boss" }, { code: adminCode, displayName: "Müdür" }, now);
  const { code } = await createJoinCode(db, { uid: "boss" }, { orgId, role: "member" }, now);
  await joinOrg(db, { uid: "elif" }, { code, displayName: "Elif" }, now);
  await recordSpeaking(db, "elif", request(), karne(), now);
  await recordSpeaking(db, "outsider", request(), karne(), now);
  const r = await orgReport(db, { uid: "boss" }, { orgId }, now);
  assert.equal(r.members.find((m) => m.uid === "elif")!.speaking?.conversations, 1);
  assert.equal(r.members.find((m) => m.uid === "boss")!.speaking, null);
  assert.equal(
    r.members.some((m) => m.uid === "outsider"),
    false,
  );
});

test("teacherView tolerates junk", () => {
  const v = teacherView({
    conversations: -3,
    minutes: "x",
    recentMistakes: [null, { original: "a" }],
    weakWords: { a: 2, b: "z" },
  });
  assert.deepEqual(v, {
    conversations: 0,
    minutes: 0,
    lastAt: 0,
    lastSummary: "",
    recentMistakes: [],
    weakWords: ["a"],
  });
});

test("account deletion removes stats and class copies", async () => {
  await db.doc("classLinks/elif").set({ codes: ["SNFX8ABC"] });
  await db.doc("classes/SNFX8ABC").set({ ownerUid: "ayse" });
  await db.doc("classes/SNFX8ABC/members/elif").set({ name: "Elif" });
  await recordSpeaking(db, "elif", request(), karne(), now);
  await deleteUserData(db, "elif");
  assert.equal((await db.doc("speakingStats/elif").get()).exists, false);
  assert.equal((await db.doc("classes/SNFX8ABC/speaking/elif").get()).exists, false);
  assert.equal((await db.doc("classes/SNFX8ABC/members/elif").get()).exists, false);
});
