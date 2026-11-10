// Lingora conversation proxy (Supabase Edge Function, Deno).
//
// The app sends { scenarioId, messages: [{ role, content }] } and gets back
// { reply, correction, tip_tr, done }. The Anthropic API key lives only here,
// in the ANTHROPIC_API_KEY secret.
import Anthropic from "npm:@anthropic-ai/sdk";
import { SCENARIOS, systemPrompt } from "./scenarios.ts";

const client = new Anthropic(); // reads ANTHROPIC_API_KEY

const MAX_MESSAGES = 20;
const MAX_CHARS = 400;

// The model must answer in exactly this shape.
const REPLY_SCHEMA = {
  type: "object",
  properties: {
    reply: { type: "string" },
    correction: { type: "string" },
    tip_tr: { type: "string" },
    done: { type: "boolean" },
  },
  required: ["reply", "correction", "tip_tr", "done"],
  additionalProperties: false,
};

type Role = "user" | "assistant";
interface IncomingMessage {
  role: Role;
  content: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Validates the app's history: alternating turns, ending with the learner. */
function parseMessages(raw: unknown): IncomingMessage[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const msgs = raw.slice(-MAX_MESSAGES);
  const out: IncomingMessage[] = [];
  for (const m of msgs) {
    if (typeof m !== "object" || m === null) return null;
    const { role, content } = m as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") return null;
    const text = content.trim().slice(0, MAX_CHARS);
    if (!text) return null;
    out.push({ role, content: text });
  }
  // The scene opens with the partner's line; the API wants a user turn first,
  // so the opening is folded into a short user preamble.
  if (out[0].role === "assistant") {
    out.unshift({ role: "user", content: "(The scene starts.)" });
  }
  for (let i = 1; i < out.length; i++) {
    if (out[i].role === out[i - 1].role) return null;
  }
  if (out[out.length - 1].role !== "user") return null;
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // TODO before launch: check that the signed-in user has an active Premium
  // subscription and enforce a daily message quota (return 429 when exceeded).

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const scenario = SCENARIOS[String(body.scenarioId)];
  const messages = parseMessages(body.messages);
  if (!scenario || !messages) return json({ error: "invalid_request" }, 400);

  try {
    const response = await client.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 2000,
      // Server-side fallback if a request is declined by a safety classifier.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      cache_control: { type: "ephemeral" },
      system: systemPrompt(scenario),
      messages,
      output_config: {
        effort: "low", // short chat replies; raise only if quality needs it
        format: { type: "json_schema", schema: REPLY_SCHEMA },
      },
    });

    if (response.stop_reason === "refusal") {
      return json({
        reply: "Let's get back to our scene. What would you like to say?",
        correction: "",
        tip_tr: "",
        done: false,
      });
    }
    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") return json({ error: "empty_response" }, 502);
    const parsed = JSON.parse(text.text);
    return json({
      reply: String(parsed.reply ?? ""),
      correction: String(parsed.correction ?? ""),
      tip_tr: String(parsed.tip_tr ?? ""),
      done: Boolean(parsed.done),
    });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "rate_limited" }, 429);
    if (error instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${error.status}: ${error.message}`);
      return json({ error: "upstream_error" }, 502);
    }
    console.error("converse failed", error);
    return json({ error: "internal_error" }, 500);
  }
});
