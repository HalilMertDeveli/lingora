// Doğal konuşma: streaming talk, neural voice, caps. Claude and Google TTS
// are always fakes here: tests never call the real APIs.
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";
import { Timestamp } from "firebase-admin/firestore";

import { stubClaude, stubTts } from "../src/ai_stub.js";
import { cleanCorrections, conversationReport } from "../src/conversation_report.js";
import { ClaudeClient, FREE_DAILY_MESSAGE_LIMIT, MODEL } from "../src/converse.js";
import {
  estimateTurnSeconds,
  relevantCorrection,
  FAIR_USE_SECONDS,
  ReplyExtractor,
  SentenceSplitter,
  talk,
  TALK_MAX_TOKENS,
  TALK_MODEL,
  TalkSentence,
  warmTalk,
} from "../src/talk.js";
import {
  CHARACTERS,
  cleanTopic,
  levelStyle,
  resolveContext,
  talkSystemPrompt,
  VOICES,
} from "../src/talk_context.js";
import { cacheKey, DAILY_TTS_CHARS, rateForLevel, speak, TtsClient, TtsRequest } from "../src/tts.js";
import { adminDb, clearFirestore, rejectsWith } from "./helpers.js";

const db = adminDb();
const NOW = new Date("2026-11-19T09:00:00Z");
const DAY = 24 * 60 * 60 * 1000;

type Call = Record<string, unknown>;

/** A fake Claude that streams [json] in small pieces. */
function streamingClient(json: string | (() => never), stop = "end_turn"): { client: ClaudeClient; calls: Call[] } {
  const calls: Call[] = [];
  const create = async (params: Call) => {
    calls.push(params);
    if (typeof json === "function") json();
    const text = json as string;
    return (async function* () {
      yield { type: "message_start", message: {} };
      for (let i = 0; i < text.length; i += 7) {
        yield { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: text.slice(i, i + 7) } };
      }
      yield { type: "message_delta", delta: { stop_reason: stop } };
      yield { type: "message_stop" };
    })();
  };
  return { client: { beta: { messages: { create } } } as unknown as ClaudeClient, calls };
}

function fakeTts(fail = false): { tts: TtsClient; calls: TtsRequest[] } {
  const calls: TtsRequest[] = [];
  return {
    calls,
    tts: {
      async synthesize(req) {
        calls.push(req);
        if (fail) throw new Error("tts down");
        return Buffer.from(`mp3:${req.text}`);
      },
    },
  };
}

const reply = (r: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({ reply: r, correction: "", tip_tr: "", done: false, ...extra });

const freeTalk = {
  mode: "free",
  topic: "football",
  level: "A2",
  messages: [
    { role: "assistant", content: "Hi! What do you want to talk about?" },
    { role: "user", content: "I like football very much" },
  ],
};

async function grantPremium(uid: string) {
  await db.doc(`entitlements/${uid}`).set({
    active: true,
    expiresAt: Timestamp.fromMillis(NOW.getTime() + 30 * DAY),
  });
}

beforeEach(clearFirestore);

test("ReplyExtractor decodes the reply while the JSON streams in", () => {
  const x = new ReplyExtractor();
  const json = JSON.stringify({ reply: 'Oh, "nice"!\nWhat\'s next? Café é \\ ok', correction: "x" });
  let out = "";
  for (let i = 0; i < json.length; i += 3) out += x.push(json.slice(i, i + 3));
  assert.equal(out, 'Oh, "nice"! What\'s next? Café é \\ ok');
  assert.equal(x.done, true);
  const y = new ReplyExtractor();
  assert.equal(y.push('{"repl'), "");
  assert.equal(y.push('y": "Hi \\u00'), "Hi ");
  assert.equal(y.push('e9!"'), "é!");
});

test("SentenceSplitter: the first piece goes at the first clause, later ones at sentence ends", () => {
  const s = new SentenceSplitter();
  // "Oh!" alone is too short; the first clause after a few words goes at once.
  assert.deepEqual(s.push("Oh! Nice to meet you, Mr. Brown. How "), ["Oh! Nice to meet you,", "Mr. Brown."]);
  // Later pieces: whole sentences, a short clause does not cut them.
  assert.deepEqual(s.push("are you, by the way? I'm "), ["How are you, by the way?"]);
  assert.deepEqual(s.push("fine"), []);
  assert.deepEqual(s.flush(), ["I'm fine"]);
  assert.deepEqual(s.flush(), []);
});

test("SentenceSplitter: a long first sentence without punctuation goes after 8 words", () => {
  const s = new SentenceSplitter();
  assert.deepEqual(s.push("So you went to the stadium with your friends and "), [
    "So you went to the stadium with your",
  ]);
  assert.deepEqual(s.push("watched the derby? Wow."), ["friends and watched the derby?"]);
  assert.deepEqual(s.flush(), ["Wow."]);
  // A short reaction is not cut at its comma.
  assert.deepEqual(new SentenceSplitter().push("Oh, nice! Which team?"), ["Oh, nice!"]);
});

test("talk streams sentences with neural audio for Premium, in order", async () => {
  await grantPremium("u");
  const { client, calls } = streamingClient(
    reply("Oh, you like football? Which team do you support? I love Fenerbahçe.", {
      correction: "I like football a lot.",
      tip_tr: "Nokta",
    }),
  );
  const { tts, calls: ttsCalls } = fakeTts();
  const chunks: TalkSentence[] = [];
  const r = await talk(db, client, tts, "u", freeTalk, NOW, (c) => chunks.push(c));
  assert.deepEqual(
    chunks.map((c) => c.text),
    ["Oh, you like football?", "Which team do you support?", "I love Fenerbahçe."],
  );
  assert.deepEqual(chunks.map((c) => c.i), [0, 1, 2]);
  assert.equal(Buffer.from(chunks[0].audio!, "base64").toString(), "mp3:Oh, you like football?");
  assert.equal(r.reply, "Oh, you like football? Which team do you support? I love Fenerbahçe.");
  assert.equal(r.correction, "I like football a lot.");
  assert.equal(r.voice, "neural");
  assert.equal(r.free, false);
  assert.equal(r.sentences, undefined);
  assert.ok(r.talkSecondsLeft! < FAIR_USE_SECONDS);
  // A2: a slower voice; the default voice for free talk.
  assert.equal(ttsCalls[0].rate, rateForLevel("A2"));
  assert.equal(ttsCalls[0].voiceName, VOICES.us_aoede.name);
  const p = calls[0];
  // Live turns: the fast model, no thinking; the karne keeps Sonnet (MODEL).
  assert.equal(p.model, TALK_MODEL);
  assert.equal(TALK_MODEL, "claude-haiku-5-5");
  assert.notEqual(MODEL, TALK_MODEL);
  assert.equal(p.max_tokens, TALK_MAX_TOKENS);
  assert.equal(p.stream, true);
  assert.deepEqual(p.thinking, { type: "disabled" });
  assert.equal((p.output_config as { effort: string }).effort, "low");
  assert.equal(p.fallbacks, undefined, "Haiku 5.5 has no server-side refusal fallback");
  assert.match(String(p.system), /football/);
  assert.match(String(p.system), /A2/);
});

test("free users keep the 3-message taste and get no neural audio", async () => {
  const { client } = streamingClient(reply("Great! Who is your favourite player?"));
  const { tts, calls } = fakeTts();
  for (let i = 0; i < FREE_DAILY_MESSAGE_LIMIT; i++) {
    const chunks: TalkSentence[] = [];
    const r = await talk(db, client, tts, "f", freeTalk, NOW, (c) => chunks.push(c));
    assert.equal(r.free, true);
    assert.equal(r.voice, "device");
    assert.equal(r.talkSecondsLeft, null);
    assert.equal(chunks[0].audio, null);
  }
  await rejectsWith(talk(db, client, tts, "f", freeTalk, NOW, null), "resource-exhausted", "free_quota");
  assert.equal(calls.length, 0);
});

test("a character uses its own voice unless the app picks another", async () => {
  await grantPremium("u");
  const { client, calls } = streamingClient(reply("Evening! Where to, mate?"));
  const { tts, calls: ttsCalls } = fakeTts();
  const body = { characterId: "taxi_london", messages: [{ role: "user", content: "Hello" }] };
  await talk(db, client, tts, "u", body, NOW, null);
  assert.equal(ttsCalls[0].voiceName, VOICES[CHARACTERS.taxi_london.voice].name);
  assert.match(String(calls[0].system), /Alfie/);
  await talk(db, client, tts, "u", { ...body, voice: "us_puck", messages: [{ role: "user", content: "Hi again" }] }, NOW, null);
  assert.equal(ttsCalls.at(-1)!.voiceName, VOICES.us_puck.name);
});

test("non-streaming clients get all sentences in the result", async () => {
  await grantPremium("u");
  const { client } = streamingClient(reply("Sure thing. Anything else?"));
  const r = await talk(db, client, fakeTts().tts, "u", freeTalk, NOW, null);
  assert.deepEqual(r.sentences?.map((s) => s.text), ["Sure thing.", "Anything else?"]);
});

test("identical phrases come from the cache; TTS failure falls back to the phone voice", async () => {
  await grantPremium("u");
  const { client } = streamingClient(reply("See you soon!"));
  const ok = fakeTts();
  await talk(db, client, ok.tts, "u", freeTalk, NOW, null);
  await talk(db, client, ok.tts, "u", freeTalk, NOW, null);
  assert.equal(ok.calls.length, 1);
  const key = cacheKey({ text: "See you soon!", voiceName: VOICES.us_aoede.name, languageCode: "en-US", rate: 0.92 });
  assert.ok((await db.doc(`ttsCache/${key}`).get()).exists);

  const { client: c2 } = streamingClient(reply("Something brand new here."));
  const r = await talk(db, c2, fakeTts(true).tts, "u", freeTalk, NOW, null);
  assert.equal(r.voice, "device");
  assert.equal(r.reply, "Something brand new here.");
  // Failed synthesis does not use up the character budget.
  assert.equal((await db.doc("voiceUsage/u").get()).get("ttsChars"), "See you soon!".length);
});

test("the daily character budget switches to the phone voice, not an error", async () => {
  await grantPremium("u");
  await db.doc("voiceUsage/u").set({ day: "2026-11-19", ttsChars: DAILY_TTS_CHARS - 3, talkSeconds: 0 });
  const { client } = streamingClient(reply("A long new sentence."));
  const { tts, calls } = fakeTts();
  const r = await talk(db, client, tts, "u", freeTalk, NOW, null);
  assert.equal(r.voice, "device");
  assert.equal(calls.length, 0);
});

test("Premium fair use: 45 minutes a day, then a friendly stop until tomorrow", async () => {
  await grantPremium("u");
  await db.doc("voiceUsage/u").set({ day: "2026-11-19", ttsChars: 0, talkSeconds: FAIR_USE_SECONDS });
  const { client, calls } = streamingClient(reply("Hi!"));
  await rejectsWith(talk(db, client, fakeTts().tts, "u", freeTalk, NOW, null), "resource-exhausted", "fair_use");
  assert.equal(calls.length, 0);
  const r = await talk(db, client, fakeTts().tts, "u", freeTalk, new Date(NOW.getTime() + DAY), null);
  assert.ok(r.talkSecondsLeft! > FAIR_USE_SECONDS - 60);
});

test("failed turns are refunded; refusals answer in scene", async () => {
  await grantPremium("u");
  const failing = streamingClient(() => {
    throw new Anthropic.APIError(529, undefined, "overloaded", undefined);
  });
  await rejectsWith(talk(db, failing.client, fakeTts().tts, "u", freeTalk, NOW, null), "unavailable", "upstream_error");
  assert.equal((await db.doc("usage/u").get()).get("count"), 0);

  const refusing = streamingClient("", "refusal");
  const chunks: TalkSentence[] = [];
  const r = await talk(db, refusing.client, fakeTts().tts, "u", freeTalk, NOW, (c) => chunks.push(c));
  assert.match(r.reply, /something else/);
  assert.equal(chunks.length, 1);
});

test("rejects unknown contexts and bad history before calling Claude", async () => {
  const { client, calls } = streamingClient(reply("x"));
  const tts = fakeTts().tts;
  await rejectsWith(talk(db, client, tts, "u", { characterId: "nobody", messages: freeTalk.messages }, NOW, null), "invalid-argument");
  await rejectsWith(talk(db, client, tts, "u", { scenarioId: "nope", messages: freeTalk.messages }, NOW, null), "invalid-argument");
  await rejectsWith(talk(db, client, tts, "u", { mode: "free", messages: [] }, NOW, null), "invalid-argument");
  assert.equal(calls.length, 0);
});

test("prompts: human style, recasts, level and goal", () => {
  const free = resolveContext({ mode: "free", topic: 'dizi "Friends" <b>', level: "A1", goal: "exam" })!;
  assert.equal(free.topic, "dizi  Friends  b".replace(/\s+/g, " "));
  const p = talkSystemPrompt(free);
  assert.match(p, /1 to 3 short sentences/);
  assert.match(p, /one short, open follow-up question/);
  assert.match(p, /you went to Izmir yesterday/);
  assert.match(p, /Never point out mistakes in "reply"/);
  assert.match(p, /beginner \(A1\)/);
  assert.match(p, /YDS\/YÖKDİL/);
  const hr = talkSystemPrompt(resolveContext({ characterId: "hr_manager", goal: "interview" })!);
  assert.match(hr, /Daniel Reed/);
  assert.match(hr, /job interviews/);
  const scene = talkSystemPrompt(resolveContext({ scenarioId: "cafe" })!);
  assert.match(scene, /Learner's goal/);
  assert.match(scene, /\(A1\)/);
  assert.equal(cleanTopic("x".repeat(100)).length, 60);
  assert.match(levelStyle("C1"), /native/);
  assert.equal(resolveContext({ mode: "free", level: "Z9" })!.level, "B1");
  for (const c of Object.values(CHARACTERS)) assert.ok(VOICES[c.voice], c.name);
});

test("estimateTurnSeconds counts both speakers", () => {
  assert.equal(estimateTurnSeconds("I like football very much", "x".repeat(140), 1), Math.round(5 / 1.6 + 10 + 3));
});

test("speak: Premium only, validates, caches", async () => {
  const { tts, calls } = fakeTts();
  await rejectsWith(speak(db, tts, "u", { text: "Hello there" }, NOW), "permission-denied", "premium_required");
  await grantPremium("u");
  await rejectsWith(speak(db, tts, "u", { text: "" }, NOW), "invalid-argument");
  await rejectsWith(speak(db, tts, "u", { text: "x".repeat(401) }, NOW), "invalid-argument");
  const a = await speak(db, tts, "u", { text: "Hello there", voice: "gb_orus", rate: 0.9 }, NOW);
  assert.equal(Buffer.from(a.audio!, "base64").toString(), "mp3:Hello there");
  assert.equal(a.cached, false);
  assert.equal(calls[0].voiceName, "en-GB-Chirp3-HD-Orus");
  assert.equal(calls[0].languageCode, "en-GB");
  assert.equal((await speak(db, tts, "u", { text: "Hello there", voice: "gb_orus", rate: 0.9 }, NOW)).cached, true);
  // An unknown voice id falls back to the default voice.
  await speak(db, tts, "u", { text: "Bye", voice: "elevenlabs_x" }, NOW);
  assert.equal(calls.at(-1)!.voiceName, VOICES.us_aoede.name);
});

test("the emulator stubs stream JSON and make silent MP3s", async () => {
  const env = { FUNCTIONS_EMULATOR: "true", LINGORA_AI_STUB: "1" };
  const client = stubClaude(env, async () => undefined);
  await grantPremium("u");
  const chunks: TalkSentence[] = [];
  const r = await talk(db, client, stubTts(env, async () => undefined), "u", freeTalk, NOW, (c) => chunks.push(c));
  assert.ok(chunks.length >= 2);
  assert.match(r.reply, /stub/);
  const mp3 = Buffer.from(chunks[0].audio!, "base64");
  assert.equal(mp3[0], 0xff);
  assert.equal(mp3.length % 417, 0);
});

test("karne: in-flow corrections and free-talk/character contexts", async () => {
  const lines = [
    { role: "assistant" as const, content: "Hi!" },
    { role: "user" as const, content: "Yesterday I go to Izmir" },
  ];
  assert.deepEqual(
    cleanCorrections(
      [
        { original: "Yesterday I go to Izmir", corrected: "Yesterday I went to Izmir.", tip_tr: "Geçmiş zaman" },
        { original: "never said", corrected: "x", tip_tr: "" },
        { original: "Yesterday I go to Izmir", corrected: "Yesterday I go to Izmir", tip_tr: "" },
      ],
      lines,
    ),
    [{ original: "Yesterday I go to Izmir", corrected: "Yesterday I went to Izmir.", explanation_tr: "Geçmiş zaman" }],
  );

  const calls: Call[] = [];
  const client = {
    beta: {
      messages: {
        create: async (p: Call) => {
          calls.push(p);
          return {
            stop_reason: "end_turn",
            content: [{ type: "text", text: JSON.stringify({ mistakes: [], summary_tr: "İyi gitti." }) }],
          };
        },
      },
    },
  } as unknown as ClaudeClient;
  const r = await conversationReport(
    db,
    client,
    "u",
    {
      characterId: "emma",
      topic: "travel",
      level: "A2",
      messages: lines,
      corrections: [{ original: "Yesterday I go to Izmir", corrected: "Yesterday I went to Izmir.", tip_tr: "Geçmiş zaman" }],
    },
    NOW,
  );
  assert.equal(r.mistakes.length, 1);
  assert.equal(r.mistakes[0].corrected, "Yesterday I went to Izmir.");
  assert.match(String(calls[0].system), /Emma/);
  assert.match(String(calls[0].system), /travel/);
  await rejectsWith(conversationReport(db, client, "u", { characterId: "x", messages: lines }, NOW), "invalid-argument");
});

test("warmTalk opens the TTS and Claude connections and never fails", async () => {
  let ttsWarm = 0;
  let counted = 0;
  const client = {
    beta: {
      messages: {
        countTokens: async () => {
          counted++;
          throw new Error("offline");
        },
      },
    },
  } as unknown as ClaudeClient;
  const tts: TtsClient = { synthesize: async () => Buffer.alloc(0), warm: async () => void ttsWarm++ };
  assert.deepEqual(await warmTalk(client, tts), { warm: true });
  assert.equal(ttsWarm, 1);
  assert.equal(counted, 1);
  assert.deepEqual(await warmTalk({ beta: { messages: {} } } as unknown as ClaudeClient, fakeTts().tts), { warm: true });
});

test("a reply cut off after the spoken part is kept (feedback skipped)", async () => {
  await grantPremium("u");
  const cut = JSON.stringify({ reply: "Great, see you then!", correction: "" }).slice(0, -8);
  const { client } = streamingClient(cut, "max_tokens");
  const r = await talk(db, client, fakeTts().tts, "u", freeTalk, NOW, null);
  assert.equal(r.reply, "Great, see you then!");
  assert.equal(r.correction, "");
  const broken = streamingClient('{"reply": "Hel', "max_tokens");
  await rejectsWith(talk(db, broken.client, fakeTts().tts, "u", freeTalk, NOW, null), "unavailable");
});

test("relevantCorrection keeps only fixes of the last message", () => {
  const last = "My favourite team is Fenerbahce";
  assert.equal(relevantCorrection(last, "I like football very much. Yesterday I went to the stadium."), "");
  assert.equal(relevantCorrection("Thank you, have a nice day", "Thank you, have a nice day."), "");
  assert.equal(relevantCorrection("I am agree with you", "I agree with you."), "I agree with you.");
  assert.equal(
    relevantCorrection("I am working as software developer since four years", "I have been working as a software developer for four years."),
    "I have been working as a software developer for four years.",
  );
  assert.equal(relevantCorrection("anything", ""), "");
});

test("a stale correction from an earlier turn is dropped", async () => {
  await grantPremium("u");
  const { client } = streamingClient(
    reply("Oh, Fenerbahçe! Great team.", { correction: "Yesterday I went to the stadium.", tip_tr: "Geçmiş zaman" }),
  );
  const body = { ...freeTalk, messages: [...freeTalk.messages.slice(0, 1), { role: "user", content: "My team is Fenerbahce" }] };
  const r = await talk(db, client, fakeTts().tts, "u", body, NOW, null);
  assert.equal(r.correction, "");
  assert.equal(r.tip_tr, "");
});
