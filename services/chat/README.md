# Switch guest Chat broker

This Worker uses Discord application `1560449870496792729`, shared with ArcStation. It issues official provisional Social SDK tokens. ArcStation uses OAuth user tokens; its source, configuration and existing authorization are unchanged.

Production endpoint: `https://switch-guest-chat.stanleyodestin.workers.dev/v1/guest-token`.

The iPhone creates a cryptographically random 256-bit installation credential, stores it in a device-only Keychain item and sends it in the Authorization header over HTTPS. The server derives an application-scoped external user ID from that credential. Requests cannot choose another user's external ID. Only a bounded display name is accepted in the JSON body. The bot token is a Worker secret, never an app resource or source file.

Guest access tokens remain in app memory and are renewed by this endpoint. The server stores no tokens, messages or voice. Its logs contain only error categories and HTTP status. Requests and responses are bounded, redirects are refused, and upstream requests have a 12-second timeout. Cloudflare rate-limit bindings enforce 3 requests per identity, 10 per IP and 100 per location per minute. These are per-location limits, not a globally exact quota or device-attestation system.

## Development and deployment

Use the pinned dependencies in the lockfile:

```sh
npm ci
npm test
npm run check
npm run build
npm run deploy
```

`DISCORD_BOT_TOKEN` is already configured in the deployed Worker. For an intentional future rotation, use `npx wrangler secret put DISCORD_BOT_TOKEN` with secure interactive input or protected stdin. Never place it in `wrangler.jsonc`, the app's `discord.json`, command arguments, logs or Git. Do not reset a bot token used by another backend without coordinating its update.

`GET /health` reports whether the secret is configured, not whether Discord is reachable. API errors expose only safe categories: `discord_linked` (409), `try_later` (429), and `guest_unavailable` (5xx). Discord error 530000 requires application setup; 530010 means the guest has been merged and should use Discord OAuth.

Workers supports `redirect: "manual"`; it does not support Fetch's `error` mode. The broker rejects 3xx responses explicitly and supplies Discord's required User-Agent. Node fixtures alone do not establish Workers runtime compatibility; deployed endpoint and iOS SDK acceptance are recorded in `../../docs/upstream-2026-10-25.md`.

References: [bot token endpoint](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/bot-token-endpoint), [account merging](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/merging-accounts), [Workers Request](https://developers.cloudflare.com/workers/runtime-apis/request/).
