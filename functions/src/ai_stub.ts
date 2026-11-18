// Test-only fake Claude client for the Local Emulator Suite (QA without the
// Anthropic secret). It can never be active in production: [stubClaudeEnabled]
// requires FUNCTIONS_EMULATOR=true, which only the Firebase emulator sets, AND
// an explicit LINGORA_AI_STUB=1 opt-in.
//
// The fake answers every structured-output call with a JSON object built from
// the request's own json_schema, so it works for converse, conversationReport,
// assessWriting and any later endpoint without per-endpoint code.
//
// Failure modes (to check the app's error UI), picked per call by:
//   - a marker in the last user message: #busy #apierr #crash #refuse #slow
//   - or the first word of the file named by LINGORA_AI_STUB_FILE.
import Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "node:fs";

import type { ClaudeClient } from "./converse.js";

export type StubMode = "ok" | "busy" | "apierr" | "crash" | "refuse" | "slow";
const MODES: StubMode[] = ["ok", "busy", "apierr", "crash", "refuse", "slow"];

/** True only inside the emulator with an explicit opt-in. */
export function stubClaudeEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.FUNCTIONS_EMULATOR === "true" && env.LINGORA_AI_STUB === "1";
}

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type Schema = Record<string, unknown>;

/** A small valid instance of [schema] (objects, arrays, enums, strings, numbers). */
export function sampleFromSchema(schema: Schema | undefined, key = ""): Json {
  if (!schema) return null;
  if (Array.isArray(schema.enum) && schema.enum.length) return schema.enum[0] as Json;
  if ("const" in schema) return schema.const as Json;
  const anyOf = (schema.anyOf ?? schema.oneOf) as Schema[] | undefined;
  if (Array.isArray(anyOf) && anyOf.length) return sampleFromSchema(anyOf[0], key);
  let type = schema.type;
  if (Array.isArray(type)) type = type.find((t) => t !== "null") ?? type[0];
  switch (type) {
    case "object": {
      const props = (schema.properties ?? {}) as Record<string, Schema>;
      const out: { [k: string]: Json } = {};
      for (const [k, s] of Object.entries(props)) out[k] = sampleFromSchema(s, k);
      return out;
    }
    case "array": {
      const min = typeof schema.minItems === "number" ? schema.minItems : 1;
      const n = Math.max(1, Math.min(min, 3));
      return Array.from({ length: n }, () => sampleFromSchema(schema.items as Schema, key));
    }
    case "boolean":
      return false;
    case "integer":
    case "number": {
      const lo = typeof schema.minimum === "number" ? schema.minimum : 0;
      const hi = typeof schema.maximum === "number" ? schema.maximum : lo + 10;
      return Math.round((lo + hi) / 2);
    }
    case "string":
      return stubText(key);
    default:
      return null;
  }
}

function stubText(key: string): string {
  const k = key.toLowerCase();
  if (k.endsWith("_tr") || k.includes("tr")) return `[stub] ${key}: Türkçe örnek açıklama.`;
  if (k === "reply") return "[stub] That sounds great! What would you like to do next?";
  if (k === "correction") return "";
  return `[stub] ${key || "text"}`;
}

function lastUserText(params: Record<string, unknown>): string {
  const msgs = (params.messages ?? []) as { role: string; content: unknown }[];
  for (let i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role !== "user") continue;
    const c = msgs[i].content;
    if (typeof c === "string") return c;
    if (Array.isArray(c)) return c.map((b) => (b as { text?: string }).text ?? "").join(" ");
  }
  return "";
}

/** Mode for this call: a #marker in the learner's text wins, then the mode file. */
export function pickMode(text: string, file: string | undefined): StubMode {
  for (const m of MODES) if (m !== "ok" && text.includes(`#${m}`)) return m;
  if (file) {
    try {
      const word = readFileSync(file, "utf8").trim().split(/\s+/)[0] as StubMode;
      if (MODES.includes(word)) return word;
    } catch {
      // no file: normal answers
    }
  }
  return "ok";
}

/** The fake client. [sleep] is injectable so tests do not wait. */
export function stubClaude(
  env: NodeJS.ProcessEnv = process.env,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
): ClaudeClient {
  const create = async (params: Record<string, unknown>) => {
    const mode = pickMode(lastUserText(params), env.LINGORA_AI_STUB_FILE);
    switch (mode) {
      case "busy":
        throw new Anthropic.RateLimitError(429, undefined, "stub: rate limited", new Headers());
      case "apierr":
        throw new Anthropic.APIError(529, undefined, "stub: overloaded", undefined);
      case "crash":
        throw new Error("stub: unexpected failure");
      case "slow":
        await sleep(20_000);
        break;
    }
    const format = (params.output_config as { format?: { schema?: Schema } } | undefined)?.format;
    const body = sampleFromSchema(format?.schema ?? { type: "object", properties: { reply: { type: "string" } } });
    return {
      id: "msg_stub",
      type: "message",
      role: "assistant",
      model: String(params.model ?? "stub"),
      stop_reason: mode === "refuse" ? "refusal" : "end_turn",
      content: mode === "refuse" ? [] : [{ type: "text", text: JSON.stringify(body) }],
      usage: { input_tokens: 0, output_tokens: 0 },
    };
  };
  return { beta: { messages: { create } } } as unknown as ClaudeClient;
}
