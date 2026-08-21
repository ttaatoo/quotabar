# QuotaBar

A menu-bar-only macOS 14+ utility (version **0.0.9**) that shows remaining **Cursor**, **ChatGPT**, **GLM** (z.ai / BigModel coding plan), and **Grok** (consumer SuperGrok) subscription quota. One dark pill in the status bar, one compact popover. No Dock icon, no telemetry.

QuotaBar is an independent implementation. It talks to the same unofficial usage endpoints those products’ own dashboards already call. Those endpoints can change or break without notice.

## Install

Ad-hoc signed (no Apple Developer ID). On your Mac:

```bash
brew tap ttaatoo/quotabar https://github.com/ttaatoo/quotabar
brew install --cask ttaatoo/quotabar/quotabar
```

Upgrade:

```bash
brew upgrade --cask ttaatoo/quotabar/quotabar
```

If Gatekeeper blocks the app:

```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
```

Then **System Settings → Privacy & Security → Open Anyway**.

To build from `main` instead of the cask: `brew install --formula --HEAD ttaatoo/quotabar/quotabar`. After a formula install, clear quarantine on the cellar prefix (`xattr -dr com.apple.quarantine "$(brew --prefix quotabar)/QuotaBar.app"`). Optional: `ln -sf "$(brew --prefix quotabar)/QuotaBar.app" /Applications/QuotaBar.app`

## What you get

- Status item: dark rounded pill with a small bar-chart mark and a percentage (remaining quota for the selected provider’s most-constrained window, usually weekly). When ChatGPT is selected, that percentage is the most-constrained remaining % among **all visible ChatGPT accounts**. The number turns orange below 25% remaining.
- Popover (not a detached window): fixed compact chrome (`312×200`) so switching providers does not rewrite `contentSize` or move the arrow. Header is the same for every tab: provider title, “Updated …”, refresh — **email is never in the subtitle**. Four provider pills fit one row. The body is always the same top-aligned `ScrollView` of hugging account cards (email or “Not signed in” / a short hint, plan badge, that account’s meters, Credits / On-demand inside the card). Cards never stretch to fill leftover body space — that leftover is the popover background. ChatGPT stacks one card per account and scrolls inside the frozen body; Cursor / GLM / Grok are one card each. Empty Session windows are omitted. Settings… and Quit QuotaBar stay in the footer.
- Settings: same dark Theme as the popover. Enable each provider (including Grok), add / rename / delete ChatGPT accounts (Add account runs `codex login` in the default browser), paste Cursor / GLM / Grok credentials in compact secret fields, GLM region, poll interval (default 120s), remaining vs used, launch at login (`SMAppService`), and an off-by-default **Preview fixtures** toggle for screenshots.

If a provider is not signed in, you see a “Sign in / add key” empty state — never fake 100% bars.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15.4+ (Swift 5.9+) to build from source / `brew install --HEAD`

## Build

```bash
git clone https://github.com/ttaatoo/quotabar.git
cd quotabar
open QuotaBar.xcodeproj
```

In Xcode: select the **QuotaBar** scheme, destination **My Mac**, then Run.

Or from the command line:

```bash
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -configuration Release \
  MARKETING_VERSION=0.0.9 CURRENT_PROJECT_VERSION=0.0.9 \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO build
```

Ad-hoc signed app + zip (also used by the Homebrew formula and the `v*` release workflow):

```bash
chmod +x scripts/package.sh
./scripts/package.sh
```

That writes `dist/QuotaBar.app` and `dist/QuotaBar.zip` at version 0.0.9, then runs `codesign --force --deep --sign -`.

Pushing a `v*` tag (or running the Release workflow) uploads `QuotaBar.zip` to a GitHub Release.

## First-run Gatekeeper

Ad-hoc builds are unsigned by Apple. After downloading or copying the app:

```bash
xattr -dr com.apple.quarantine /path/to/QuotaBar.app
```

If macOS still blocks it: **System Settings → Privacy & Security → Open Anyway**.

## Adding credentials

Secrets go in the macOS Keychain (`app.quotabar.QuotaBar`). Non-secret preferences are written to `~/.config/quotabar/config.json` with mode `0600`. That file must never contain API keys or cookies.

### Cursor

1. Sign in to the Cursor desktop app at least once. QuotaBar read-only-opens  
   `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`  
   (copies the DB plus WAL/SHM first) and reads `cursorAuth/accessToken`.
2. Optional fallback: paste a `WorkosCursorSessionToken` cookie (or a full Cookie header) from [cursor.com/dashboard](https://cursor.com/dashboard) in Settings.
3. Live fetch: `GET https://cursor.com/api/usage-summary`. The two dashboard pools map to **Cursor Models** (Auto + Composer) from `individualUsage.plan.autoPercentUsed` and **Other Models** (named / API) from `apiPercentUsed`. Both reset at `billingCycleEnd`. If `apiPercentUsed` is missing, Other Models is omitted — `totalPercentUsed` is not substituted. Team fallback: `autoModelSelectedDisplayMessage` → Cursor Models, `namedModelSelectedDisplayMessage` → Other Models. On-demand spend stays a footer (`On-demand $x.xx`), never a third percent bar.
4. Signed-in email is shown **on the Cursor account card** (and on the Settings card) when Cursor publishes one: `usage-summary` if it includes an email field, otherwise `GET https://cursor.com/api/auth/me` (`email`), otherwise the session JWT `email` claim. If none of those have an address, the card says “Email unknown” rather than inventing one. On-demand spend stays inside the card (`On-demand $x.xx`), never a third percent bar.

### ChatGPT (Plus / Pro)

ChatGPT is the only provider with **multi-account** support. Cursor and GLM stay single-account. There is no separate Codex provider and **no custom ChatGPT OAuth app**.

QuotaBar uses the same live usage path CodexBar uses:

1. Prefer `GET https://chatgpt.com/backend-api/wham/usage` (then `https://chat.openai.com/backend-api/wham/usage` if needed) with `Authorization: Bearer <token>`, the chatgpt.com session cookie when we have one, and `ChatGPT-Account-Id` when known. Each `rate_limit` window is classified by **duration** (`limit_window_seconds` / `window_seconds` / `windowDurationMins`), not by primary/secondary slot: ≤ ~12h → **Session**, ~3–14d (incl. 10080 min / 7d) → **Weekly**, ~30d (43200 min) → **Monthly**. Plus / Codex often return only a 7-day `primary` and no 5-hour session — that window is Weekly, and the empty Session row is omitted. A lone window whose reset is days away is Weekly, not Session. Countdown uses the real title (`Weekly reset in 5d 13h`). `credits.balance` / unlimited stay footer-only — percentages are never invented from credits.
2. Tokens come from a chatgpt.com session cookie (Advanced paste) exchanged at `GET /api/auth/session`, **or** a read-only `auth.json` written by `codex login` — the same file CodexBar reads (`~/.codex/auth.json`, `$CODEX_HOME/auth.json`, or a private Application Support home). QuotaBar does not refresh or rewrite that file and does not start a ChatGPT OAuth app.
3. If `~/.codex/auth.json` exists and you have not added a ChatGPT account yet, Refresh uses that file as an implicit source. QuotaBar will not create a new account on every launch.
4. In Settings → ChatGPT, **Add account** locates the `codex` binary (PATH, Homebrew/npm, ChatGPT.app / Codex.app) and runs `codex login` (or `codex auth login` if that is what the CLI accepts). The CLI opens the **system default browser**. A small status window says “Finish sign-in in your browser…” with Cancel — there is no in-app `WKWebView`. If `~/.codex/auth.json` already exists, the first Add account **imports** it (email from the JWT) without launching login. Extra accounts run login against a private `CODEX_HOME` under `~/Library/Application Support/QuotaBar/managed-codex-homes/` so a second login does not overwrite `~/.codex/auth.json`. After the CLI exits 0, QuotaBar only **reads** that home’s `auth.json`.
5. If `codex` is missing, Settings tells you to install Codex CLI and/or run `codex login` in Terminal. **Advanced — cookie / JSON** remains the fallback. Cookie-only Keychain accounts keep working.
6. **Rename** or **Delete** from the same list. Deleting a managed account removes its private Codex home; `~/.codex/auth.json` is never deleted. There is no single global ChatGPT cookie field.
7. Account metadata (`id`, `label`, `enabled`, optional email, optional `codexHomePath`) lives in `~/.config/quotabar/config.json`. Cookies and optional pasted JSON stay in the Keychain as `chatgpt.cookie.<account-id>` and `chatgpt.json.<account-id>`.
8. Only if `wham/usage` has no usable windows does QuotaBar fall back to  
   `GET https://chatgpt.com/backend-api/conversation_limit` and  
   `GET https://chatgpt.com/public-api/conversation_limit`, then optional pasted JSON.
9. Meters are drawn only when the JSON actually contains remaining/used percentages. Auth failures stay signed out. JSON without percentages is an honest error — not dummy 80%. A 401 on one account does not wipe the others.
10. In the popover, pick **ChatGPT**. Every account is listed together as the same compact card used by Cursor / GLM / Grok (email, plan badge, that account’s Weekly / Session meters, Credits footer inside the card). There is no account pill/tab strip and the email is not in the header. Extra accounts scroll inside the body. The menu-bar percentage is the most-constrained remaining % among **visible** ChatGPT accounts (orange below 25%).
11. **Refresh** loads every ChatGPT account (cookie and/or that account’s Codex home), not only a selected one. Background polling does the same. A successful Add account also refreshes that account so meters can fill in.
12. Existing single-cookie / single-JSON installs are migrated to one account labeled **ChatGPT**; credentials are not dropped. If you have no accounts and no readable `auth.json`, the popover shows the usual “Sign in / add key” empty state with a button that opens Settings.

### GLM (z.ai / BigModel coding plan)

1. Paste an API token in Settings, **or** set `Z_AI_API_KEY` / `GLM_API_KEY` / `BIGMODEL_API_KEY`, **or** put a legacy `glmApiKey` in `~/.config/quotabar/config.json` (it is migrated into Keychain and stripped from the file).
2. Pick a region: **Global** `https://api.z.ai` or **China** `https://open.bigmodel.cn`.
3. Live fetch: `GET {host}/api/monitor/usage/quota/limit` with `Authorization: Bearer <token>`.
4. Shortest `TOKENS_LIMIT` (~5h) → Session; longer `TOKENS_LIMIT` (~weekly) → Weekly. `nextResetTime` drives the countdown. `planName` / `level` is the badge. MCP extras stay inside the card footer.

### Grok (consumer SuperGrok)

This is **consumer Grok / SuperGrok**, not the xAI Management API prepaid team balance. QuotaBar does not accept `xai-` console keys.

1. Prefer identity + bearer from `~/.grok/auth.json` (or `$GROK_HOME/auth.json`) written by `grok login`. Top-level keys are OIDC scope URLs; QuotaBar prefers `https://auth.x.ai::` (SuperGrok), then `https://accounts.x.ai/sign-in`. Fields used: `key` (bearer), `email`, `expires_at`, `auth_mode`, `team_id`. QuotaBar does **not** refresh or rewrite that file.
2. Optional Settings paste: SuperGrok bearer (`GROK_OAUTH_TOKEN` is also accepted). `xai-` management keys and cookie-shaped values are rejected on the OAuth field.
3. Live fetch: `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with `Authorization: Bearer <key>`, `x-xai-token-auth: xai-grok-cli`, and `Accept: application/json`.
4. Used % = `config.creditUsagePercent`, else `onDemandUsed.val / onDemandCap.val * 100`. A parseable current period without those values is **0% used**. Never invent a bar from credits-alone with no period.
5. Reset = `config.currentPeriod.end`, then `config.billingPeriodEnd`. Window title is Weekly or Monthly from that reset cycle (same classification as ChatGPT), else “Credits”. One real window is enough; empty Session is omitted.
6. Plan: `GET https://cli-chat-proxy.grok.com/v1/settings` → `subscription_tier_display` (SuperGrok / SuperGrok Heavy), 2s timeout. If that fails, fall back to OIDC SuperGrok / `auth_mode`. Settings never blocks usage.
7. Email from `auth.json` is shown on the Grok card. If the file is missing or expired: not signed in, with a `grok login` hint.

## Preview fixtures

Settings → **Preview fixtures** loads bundled sample JSON (`cursor.json`, `chatgpt.json`, `glm.json`, `grok.json`) so you can screenshot the UI without accounts. Off by default, labeled “Preview” in the popover.

## Why it is not sandboxed

Reading Cursor’s local `state.vscdb` and accepting pasted browser cookies requires ordinary user-file and network access. A sandboxed menu extra would need a grab-bag of temporary-exception entitlements (or would simply fail). QuotaBar ships as a **non-sandboxed** `LSUIElement` utility — the usual model for this class of app. It does not request iCloud, push, or any other Apple capability.

## Disclaimer

Unofficial usage endpoints, cookies, and local token files belong to their vendors and can change without notice. QuotaBar is not affiliated with Cursor, OpenAI, z.ai, BigModel, or xAI. Use your own credentials; rotate them if you ever paste a session into a chat or screenshot.

## License

[MIT](LICENSE)
