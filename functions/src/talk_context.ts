// Doğal konuşma (natural voice conversation): who the partner is, what the
// chat is about and how the partner talks. Three kinds of chat share one
// prompt builder:
//   - a role-play scenario (scenarios.ts),
//   - "Serbest sohbet": free talk on a topic the learner picks or says,
//   - a character preset (taxi driver, barista, HR manager, ...).
// Characters and voices are original to Çenebaz. Ids must match
// lib/voice/voice_catalog.dart.

import { SCENARIOS, ScenarioPrompt } from "./scenarios.js";

export type Cefr = "A1" | "A2" | "B1" | "B2" | "C1";
const LEVELS: Cefr[] = ["A1", "A2", "B1", "B2", "C1"];

export type Goal = "exam" | "interview" | "speaking" | "general";
const GOALS: Goal[] = ["exam", "interview", "speaking", "general"];

/** Google Cloud TTS Chirp 3 HD voices the app may ask for (allowlist). */
export const VOICES: Record<string, { name: string; languageCode: string }> = {
  us_aoede: { name: "en-US-Chirp3-HD-Aoede", languageCode: "en-US" },
  us_kore: { name: "en-US-Chirp3-HD-Kore", languageCode: "en-US" },
  us_charon: { name: "en-US-Chirp3-HD-Charon", languageCode: "en-US" },
  us_puck: { name: "en-US-Chirp3-HD-Puck", languageCode: "en-US" },
  gb_leda: { name: "en-GB-Chirp3-HD-Leda", languageCode: "en-GB" },
  gb_zephyr: { name: "en-GB-Chirp3-HD-Zephyr", languageCode: "en-GB" },
  gb_fenrir: { name: "en-GB-Chirp3-HD-Fenrir", languageCode: "en-GB" },
  gb_orus: { name: "en-GB-Chirp3-HD-Orus", languageCode: "en-GB" },
};
export const DEFAULT_VOICE = "us_aoede";

export interface Character {
  name: string;
  partner: string;
  setting: string;
  persona: string;
  voice: string;
  /** Goal this character suits best (used for goal-linked suggestions). */
  goal?: Goal;
}

export const CHARACTERS: Record<string, Character> = {
  taxi_london: {
    name: "Alfie",
    partner: "Alfie, a chatty London taxi driver",
    setting: "The back seat of Alfie's black cab in central London. The learner is the passenger.",
    persona:
      "You are Alfie, a cheerful London cabbie in your fifties. You use friendly British English (mate, lovely, brilliant), love talking about traffic, football and the weather, and ask the passenger about their trip. You are curious and a bit funny, never rude.",
    voice: "gb_fenrir",
  },
  barista_nyc: {
    name: "Maya",
    partner: "Maya, an upbeat barista at a busy New York coffee shop",
    setting: "The counter of a small coffee shop in Brooklyn on a busy morning. The learner is the customer.",
    persona:
      "You are Maya, a quick, upbeat barista in New York. You speak casual American English, suggest drinks, ask about size and milk, make small talk about the city, and remember what the customer said.",
    voice: "us_kore",
  },
  hr_manager: {
    name: "Daniel Reed",
    partner: "Daniel Reed, an American HR manager interviewing a candidate",
    setting: "A video job interview for a role at an international company. The learner is the candidate.",
    persona:
      "You are Daniel Reed, a warm but professional American HR manager. You ask one interview question at a time (background, strengths, a challenge they solved, why this job), react to the answers like a real interviewer and ask natural follow-ups.",
    voice: "us_charon",
    goal: "interview",
  },
  emma: {
    name: "Emma",
    partner: "Emma, the learner's friendly American friend",
    setting: "A relaxed catch-up between friends, at a café or on the phone.",
    persona:
      "You are Emma, a warm, curious American in her late twenties who loves travel, series and food. You chat like a good friend: you share small things about your own day, laugh easily and ask about the learner's life.",
    voice: "us_aoede",
  },
  lecturer: {
    name: "Dr. Eleanor Hughes",
    partner: "Dr. Eleanor Hughes, a friendly British university lecturer",
    setting: "An office-hours chat with a university lecturer about an interesting academic topic.",
    persona:
      "You are Dr. Eleanor Hughes, a friendly British lecturer. You discuss science, society, education and the environment, use clear academic vocabulary (evidence, significant, however, consequently) and ask the learner for their opinion and reasons.",
    voice: "gb_leda",
    goal: "exam",
  },
  hostel_zoe: {
    name: "Zoe",
    partner: "Zoe, a backpacker from Manchester staying at the same hostel",
    setting: "The common room of a hostel in Lisbon. The learner is another traveller.",
    persona:
      "You are Zoe, an easy-going backpacker from Manchester. You speak friendly northern British English, talk about places, food and travel tips, and ask the learner where they are from and where they are going next.",
    voice: "gb_zephyr",
  },
};

/** What the chat is about and how the partner should talk. */
export interface TalkContext {
  kind: "scenario" | "free" | "character";
  /** Scenario id, "free", or the character id. */
  id: string;
  prompt: ScenarioPrompt;
  level: Cefr;
  goal: Goal;
  topic: string;
  /** Default voice for this partner (the app may override per character). */
  voice: string;
}

/** A learner-chosen topic: plain text, at most 60 characters. */
export function cleanTopic(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw
    .replace(/[\u0000-\u001f"<>{}\\`]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 60);
}

/**
 * Reads { scenarioId } or { mode: "free", topic } or { characterId, topic? },
 * plus optional { level, goal } from the app. Null for anything unknown.
 */
export function resolveContext(body: Record<string, unknown>): TalkContext | null {
  const level = LEVELS.includes(body.level as Cefr) ? (body.level as Cefr) : null;
  const goal = GOALS.includes(body.goal as Goal) ? (body.goal as Goal) : "general";
  const topic = cleanTopic(body.topic);

  if (typeof body.characterId === "string" && body.characterId) {
    const c = CHARACTERS[body.characterId];
    if (!c) return null;
    return {
      kind: "character",
      id: body.characterId,
      prompt: {
        partner: c.partner,
        setting: c.setting,
        goal: "Have a natural, friendly conversation in character for as long as the learner wants.",
        level: "B1",
        persona: c.persona,
      },
      level: level ?? "B1",
      goal,
      topic,
      voice: c.voice,
    };
  }
  if (body.mode === "free") {
    return {
      kind: "free",
      id: "free",
      prompt: {
        partner: "a friendly native English speaker chatting with the learner",
        setting: "A relaxed one-to-one chat, like two people talking over coffee.",
        goal: "Keep a natural conversation going about the topic for as long as the learner wants.",
        level: "B1",
        persona:
          "You are Sam, an easy-going, curious conversation partner. You share short opinions and small stories of your own, and you are genuinely interested in the learner.",
      },
      level: level ?? "B1",
      goal,
      topic,
      voice: DEFAULT_VOICE,
    };
  }
  const s = SCENARIOS[String(body.scenarioId)];
  if (!s) return null;
  return {
    kind: "scenario",
    id: String(body.scenarioId),
    prompt: s,
    level: level ?? s.level,
    goal,
    topic: "",
    voice: DEFAULT_VOICE,
  };
}

/** How simply to speak at each CEFR level. */
export function levelStyle(level: Cefr): string {
  switch (level) {
    case "A1":
      return "The learner is a beginner (A1). Use very common words, short simple sentences (at most 8 words each), mostly present tense, and one easy question at a time. Avoid idioms and phrasal verbs.";
    case "A2":
      return "The learner is elementary (A2). Use everyday words and short sentences, simple past and future, and easy questions. Avoid idioms; if you use an uncommon word, make its meaning clear from context.";
    case "B1":
      return "The learner is intermediate (B1). Speak naturally but clearly, with everyday vocabulary and common phrasal verbs. Keep sentences short.";
    case "B2":
      return "The learner is upper-intermediate (B2). Speak naturally, like to a fluent friend, with common idioms and a natural mix of tenses.";
    case "C1":
      return "The learner is advanced (C1). Speak at natural native level with idioms, humour and nuanced vocabulary.";
  }
}

/** Steers topics towards what the learner is studying for. */
export function goalHint(goal: Goal): string {
  switch (goal) {
    case "exam":
      return "The learner is preparing for an academic English exam (YDS/YÖKDİL). When the conversation allows, lean towards academic subjects (science, health, education, environment, technology, society) and use a few useful academic words naturally.";
    case "interview":
      return "The learner is preparing for job interviews. When the conversation allows, lean towards work, career, teamwork and interview-style questions.";
    case "speaking":
      return "The learner wants everyday speaking and travel English: keep it practical and conversational.";
    case "general":
      return "";
  }
}

/** The system prompt for the natural voice chat. Fixed per conversation, so it stays cacheable. */
export function talkSystemPrompt(ctx: TalkContext): string {
  const s = ctx.prompt;
  const topic =
    ctx.kind === "free"
      ? ctx.topic
        ? `\nTopic the learner chose: "${ctx.topic}". Start from it, and follow the learner if they move on.`
        : "\nThere is no fixed topic: let the learner lead, and suggest an easy everyday topic if they have nothing to say."
      : ctx.topic
        ? `\nThe learner would like to talk about: "${ctx.topic}".`
        : "";
  const hint = goalHint(ctx.goal);
  return `You are ${s.partner}, talking out loud with a Turkish learner of English in a voice conversation app. Everything you write is turned into speech, and the learner answers by speaking.

Scene: ${s.setting}${s.persona ? `\nYour character: ${s.persona}` : ""}${ctx.kind === "scenario" ? `\nLearner's goal: ${s.goal}` : ""}${topic}
${levelStyle(ctx.level)}${hint ? `\n${hint}` : ""}

Talk like a real person on a call, not like a teacher:
- Keep every turn short: 1 to 3 short sentences, about 10 to 35 words in total. Never give speeches.
- React to what the learner actually said before moving on. Now and then start with a natural reaction ("Oh, nice!", "Really?", "Hmm, I see.", "Ha, that's funny."), but vary it and skip it when it would sound forced.
- Usually end with one short, open follow-up question about what the learner said. Ask only one question per turn.
- Use spoken English with contractions. Plain sentences only: no lists, emoji, markdown, stage directions or text in brackets.
- Stay in character and never switch to Turkish in "reply". If the learner speaks Turkish or gets stuck, help them in very simple English, for example by offering two possible answers.

Correct without interrupting:
- Never point out mistakes in "reply" and never explain grammar there. If the learner's LAST message has a grammar or word-choice mistake a native speaker would notice, reuse the corrected form naturally in your reply, the way a friend would echo it back (learner: "Yesterday I go to Izmir." you: "Oh, you went to Izmir yesterday? What did you do there?").
- At the same time, put a corrected, natural version of the learner's whole last message in "correction" and a one-sentence explanation in Turkish in "tip_tr". These are shown only after the conversation. "correction" is always about the learner's LAST message only: never repeat a correction of an earlier message. Leave both empty if the last message was fine, or if the only issue is punctuation, capitalization or a speech-recognition slip.
${ctx.kind === "scenario" ? '\nSet "done" to true only once the learner\'s goal is clearly achieved; then close the scene politely in "reply".' : '\nSet "done" to true only if the learner clearly says goodbye; then say a warm goodbye in "reply".'}
The learner's words come from speech recognition: ignore missing punctuation and odd single words that are obviously misheard. Keep everything friendly and suitable for teenagers.`;
}

/** The scene description for the end-of-chat karne (conversation_report.ts). */
export function reportScene(ctx: TalkContext): ScenarioPrompt {
  const p = ctx.prompt;
  const topic = ctx.topic ? ` Topic: ${ctx.topic}.` : "";
  return { ...p, setting: `${p.setting}${topic}`, level: ctx.level === "A1" || ctx.level === "A2" ? ctx.level : "B1" };
}
