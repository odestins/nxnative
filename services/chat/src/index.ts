// Discord's privileged bot token stays in a Worker secret. The iPhone presents
// a random 256-bit installation credential; its digest is the guest's identity.
// No client-supplied Discord/external user ID is ever accepted.
const DISCORD_TOKEN_URL = "https://discord.com/api/v10/partner-sdk/token/bot";
type Bindings = Cloudflare.Env & { DISCORD_BOT_TOKEN?: string };
type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

function json(value: unknown, status = 200, retry?: string): Response {
  const headers = new Headers({"Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"});
  if (retry) headers.set("Retry-After", retry);
  return new Response(JSON.stringify(value), {status, headers});
}

async function boundedJSON(message: Request | Response, limit: number): Promise<Record<string, unknown>> {
  if (!message.body) throw new Error("empty_body");
  const reader = message.body.getReader(), chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error("body_too_large"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const parsed: unknown = JSON.parse(new TextDecoder().decode(bytes));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid_body");
  return parsed as Record<string, unknown>;
}

async function digest(value: string): Promise<string> {
  const data = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(data), byte => byte.toString(16).padStart(2, "0")).join("");
}

export async function handle(request: Request, env: Bindings, fetcher: Fetcher = fetch): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (request.method === "GET" && path === "/health") {
    return json({service: "switch-guest-chat", configured: !!env.DISCORD_BOT_TOKEN}, env.DISCORD_BOT_TOKEN ? 200 : 503);
  }
  if (path !== "/v1/guest-token") return json({error: "not_found"}, 404);
  if (request.method !== "POST") return json({error: "method_not_allowed"}, 405);
  // This endpoint is for the native app, with no cookies or browser CORS access.
  if (request.headers.has("Origin")) return json({error: "native_client_required"}, 403);
  if (!env.DISCORD_BOT_TOKEN) return json({error: "guest_unavailable"}, 503, "60");
  if (request.headers.get("Content-Type")?.split(";")[0] !== "application/json") return json({error: "invalid_request"}, 415);
  const credential = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!credential) return json({error: "invalid_identity"}, 401);
  const identity = "switch:" + await digest(`switch-guest-v1:${env.DISCORD_APPLICATION_ID}:${credential}`);
  const ip = request.headers.get("CF-Connecting-IP");
  if (!ip) return json({error: "missing_client_address"}, 400);
  // Rate-limit keys contain hashes, never the bearer credential or a raw IP.
  const checks = await Promise.all([
    env.IP_LIMIT.limit({key: await digest(ip)}),
    env.IDENTITY_LIMIT.limit({key: identity}),
    env.EDGE_LIMIT.limit({key: "guest-token"})
  ]);
  if (checks.some(result => !result.success)) return json({error: "try_later"}, 429, "60");
  let name: string;
  try {
    const body = await boundedJSON(request, 1024);
    if (Object.keys(body).some(key => key !== "displayName")) return json({error: "invalid_request"}, 400);
    if (typeof body.displayName !== "string") return json({error: "invalid_name"}, 400);
    name = body.displayName.trim().normalize("NFC");
    if (!name || [...name].length > 32 || /[\p{Cc}\p{Cf}]/u.test(name)) return json({error: "invalid_name"}, 400);
  } catch { return json({error: "invalid_request"}, 400); }
  let upstreamStatus: number | undefined;
  try {
    const upstream = await fetcher(DISCORD_TOKEN_URL, {
      // Workers implements manual/follow, not Fetch's error redirect mode.
      // Never forward the bot credential to a redirect destination.
      method: "POST", redirect: "manual", signal: AbortSignal.timeout(12_000),
      headers: {"Content-Type": "application/json", Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`,
        "User-Agent": "DiscordBot (https://github.com/odestins/nxnative, 1.0)"},
      body: JSON.stringify({external_user_id: identity, preferred_global_name: name})
    });
    upstreamStatus = upstream.status;
    if (upstream.status >= 300 && upstream.status < 400) { await upstream.body?.cancel(); return json({error: "guest_unavailable"}, 502); }
    if (upstream.status === 429) { await upstream.body?.cancel(); return json({error: "try_later"}, 429, "60"); }
    const body = await boundedJSON(upstream, 32_768);
    if (!upstream.ok) {
      // Return only our known error categories. Discord bodies may contain
      // sensitive diagnostics; neither log nor forward them to the client.
      if (body.code === 530010) return json({error: "discord_linked"}, 409);
      console.warn(JSON.stringify({event: "guest_token_failed", status: upstream.status, setup: body.code === 530000}));
      return json({error: "guest_unavailable"}, 503, "60");
    }
    if (body.token_type !== "Bearer" || typeof body.access_token !== "string" || !body.access_token || body.access_token.length > 16_384 ||
        typeof body.expires_in !== "number" || !Number.isFinite(body.expires_in) || body.expires_in < 60 || body.expires_in > 604_800) {
      return json({error: "guest_unavailable"}, 502);
    }
    return json({applicationID: env.DISCORD_APPLICATION_ID, accessToken: body.access_token, expiresIn: body.expires_in});
  } catch {
    console.warn(JSON.stringify({event: "guest_token_unavailable", status: upstreamStatus}));
    return json({error: "guest_unavailable"}, 503, "60");
  }
}

export default {
  async fetch(request: Request, env: Bindings): Promise<Response> {
    try { return await handle(request, env); }
    catch { return json({error: "guest_unavailable"}, 503, "60"); }
  }
} satisfies ExportedHandler<Bindings>;
