# Lingora conversation server

The "Konuş" tab sends chat turns to a small proxy, which calls Claude and
returns the partner's reply plus a correction with a Turkish explanation.
The Anthropic API key lives only on the server. Without a deployed proxy the
app runs an offline demo with scripted replies.

Nothing here is deployed yet.

## Files

- `supabase/functions/converse/index.ts`: the endpoint (Supabase Edge Function, Deno).
- `supabase/functions/converse/scenarios.ts`: role-play prompts. Ids must match
  `lib/data/scenarios.dart`.

## Deploy (Supabase)

```bash
supabase functions deploy converse
supabase secrets set ANTHROPIC_API_KEY=...
```

Then build the app with the function URL and the project's public anon key:

```bash
flutter build apk --dart-define=LINGORA_AI_URL=https://<project>.supabase.co/functions/v1/converse --dart-define=LINGORA_AI_KEY=<anon key>
```

Pin the SDK version in the import (`npm:@anthropic-ai/sdk@<version>`) when deploying.

## Before charging for it

- **Premium check:** verify the user's subscription in `index.ts` (marked TODO).
  Subscriptions themselves need Google Play / App Store billing, which is not built yet.
- **Daily quota:** count messages per user (e.g. a Supabase table) and return 429
  when exceeded; the app already shows a friendly message for 429.
- **Cost:** the proxy uses `claude-opus-5-5` at low effort, about 2–3K input and a few
  hundred output tokens per turn. A cheaper model such as `claude-haiku-5-5` is a
  one-line change in `index.ts` if quality holds for these short role-plays; measure on
  real chats before switching.
