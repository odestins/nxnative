import test from "node:test";
import assert from "node:assert/strict";
import {handle} from "../src/index.ts";

const pass = {limit: async (_input: {key: string}) => ({success: true})};
const env = {DISCORD_APPLICATION_ID: "1560449870496792729", DISCORD_BOT_TOKEN: "fixture-server-secret", IP_LIMIT: pass, IDENTITY_LIMIT: pass, EDGE_LIMIT: pass} as const;
const credential = "a".repeat(43);
function request(body: unknown = {displayName: "Player"}, token = credential): Request {
  return new Request("https://chat.example/v1/guest-token", {
    method: "POST", headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.1"}, body: JSON.stringify(body)
  });
}
const tokenReply = () => Response.json({access_token: "fixture-user-access", id_token: "not-for-client", token_type: "Bearer", expires_in: 604800, scope: "sdk.social_layer"});

test("only a per-user access token reaches the client; identity comes from the credential", async () => {
  let external = "";
  const response = await handle(request(), env, async (url, init) => {
    assert.equal(url, "https://discord.com/api/v10/partner-sdk/token/bot");
    assert.equal(new Headers(init.headers).get("Authorization"), "Bot fixture-server-secret");
    assert.match(new Headers(init.headers).get("User-Agent") ?? "", /^DiscordBot \(https:\/\//);
    assert.equal(init.redirect, "manual");
    const payload = JSON.parse(init.body as string);
    external = payload.external_user_id;
    assert.match(external, /^switch:[a-f0-9]{64}$/);
    assert.equal(payload.preferred_global_name, "Player");
    assert.ok(!JSON.stringify(payload).includes(credential));
    return tokenReply();
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.deepEqual(await response.json(), {applicationID: env.DISCORD_APPLICATION_ID, accessToken: "fixture-user-access", expiresIn: 604800});
  await handle(request({displayName: "New name"}), env, async (_url, init) => {
    assert.equal(JSON.parse(init.body as string).external_user_id, external); return tokenReply();
  });
  await handle(request({displayName: "Player"}, "b".repeat(43)), env, async (_url, init) => {
    assert.notEqual(JSON.parse(init.body as string).external_user_id, external); return tokenReply();
  });
});

test("invalid and oversized identities or names never reach Discord", async () => {
  const never = async () => { throw new Error("must not call Discord"); };
  for (const token of ["", "short", "a".repeat(44), "!".repeat(43)]) assert.equal((await handle(request(undefined, token), env, never)).status, 401);
  for (const body of [{}, {displayName: ""}, {displayName: "a".repeat(33)}, {displayName: "bad\u0000name"}, {displayName: "a\u202eb"}, {displayName: "x", external_user_id: "victim"}, {displayName: "x".repeat(4096)}]) {
    assert.equal((await handle(request(body), env, never)).status, 400);
  }
});

test("both identity and IP quotas fail closed before upstream requests", async () => {
  for (const binding of ["IP_LIMIT", "IDENTITY_LIMIT", "EDGE_LIMIT"]) {
    let called = false;
    const response = await handle(request(), {...env, [binding]: {limit: async () => ({success: false})}}, async () => {called = true; return tokenReply();});
    assert.equal(response.status, 429); assert.equal(response.headers.get("Retry-After"), "60"); assert.equal(called, false);
  }
});

test("setup, upstream failures, and linked identities produce bounded safe errors", async () => {
  assert.equal((await handle(request(), {...env, DISCORD_BOT_TOKEN: undefined})).status, 503);
  for (const [status, code, expected, error] of [[400, 530000, 503, "guest_unavailable"], [400, 530010, 409, "discord_linked"], [429, 0, 429, "try_later"], [500, 0, 503, "guest_unavailable"]] as const) {
    const response = await handle(request(), env, async () => Response.json({code, secret: "must-never-escape"}, {status}));
    assert.equal(response.status, expected); assert.deepEqual(await response.json(), {error});
  }
  const failed = await handle(request(), env, async () => {throw new Error("secret transport details");});
  assert.equal(failed.status, 503); assert.deepEqual(await failed.json(), {error: "guest_unavailable"});
});

test("malformed or huge Discord responses and invalid lifetimes are not passed through", async () => {
  for (const body of [{}, {access_token: "x", token_type: "Basic", expires_in: 60}, {access_token: "x", token_type: "Bearer", expires_in: 604801}, {access_token: "x", token_type: "Bearer", expires_in: 0}, {access_token: "x".repeat(40000), token_type: "Bearer", expires_in: 3600}]) {
    const response = await handle(request(), env, async () => Response.json(body));
    assert.ok(response.status >= 500); assert.deepEqual(await response.json(), {error: "guest_unavailable"});
  }
});

test("redirect responses never forward the privileged credential and non-JSON throttling is respected", async () => {
  let requests = 0;
  const redirected = await handle(request(), env, async (_url, init) => {
    requests++; assert.equal(init.redirect, "manual");
    return new Response(null, {status: 302, headers: {Location: "https://other.example/"}});
  });
  assert.equal(redirected.status, 502); assert.equal(requests, 1);
  const throttled = await handle(request(), env, async () => new Response("busy", {status: 429}));
  assert.equal(throttled.status, 429); assert.equal(throttled.headers.get("Retry-After"), "60");
});

test("native-only methods, content type and health configuration", async () => {
  const req = request(); req.headers.set("Origin", "https://hostile.example");
  assert.equal((await handle(req, env)).status, 403);
  const wrong = request(); wrong.headers.set("Content-Type", "text/plain");
  assert.equal((await handle(wrong, env)).status, 415);
  assert.equal((await handle(new Request("https://chat.example/v1/guest-token"), env)).status, 405);
  const health = await handle(new Request("https://chat.example/health"), {...env, DISCORD_BOT_TOKEN: undefined});
  assert.equal(health.status, 503); assert.deepEqual(await health.json(), {service: "switch-guest-chat", configured: false});
});
