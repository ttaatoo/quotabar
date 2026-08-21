# QuotaBar

A menu-bar-only macOS 14+ utility (version **0.0.2**) that shows remaining **Cursor**, **ChatGPT**, and **GLM** (z.ai / BigModel coding plan) subscription quota. One dark pill in the status bar, one compact popover. No Dock icon, no other providers, no telemetry.

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

- Status item: dark rounded pill with a small bar-chart mark and a percentage (remaining quota for the selected provider’s most-constrained window, usually weekly). When ChatGPT is selected, that percentage is the selected ChatGPT account’s most-constrained remaining %. The number turns orange below 25% remaining.
- Popover (not a detached window): provider title + plan badge, relative “Updated …” time, refresh, a three-way provider switcher (Cursor / ChatGPT / GLM), an account switcher when ChatGPT has two or more accounts, two reserved meters (Session / Weekly for ChatGPT and GLM; **Cursor Models** / **Other Models** for Cursor), reset countdowns, Settings… and Quit QuotaBar.
- Settings: enable each provider, add / rename / delete ChatGPT accounts (QuotaBar also reads `~/.codex/auth.json` from `codex login`; Add account is a cookie fallback), paste Cursor / GLM credentials, GLM region, poll interval (default 120s), remaining vs used, launch at login (`SMAppService`), and an off-by-default **Preview fixtures** toggle for screenshots.

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
  MARKETING_VERSION=0.0.2 CURRENT_PROJECT_VERSION=0.0.2 \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO build
```

Ad-hoc signed app + zip (also used by the Homebrew formula and the `v*` release workflow):

```bash
chmod +x scripts/package.sh
./scripts/package.sh
```

That writes `dist/QuotaBar.app` and `dist/QuotaBar.zip` at version 0.0.2, then runs `codesign --force --deep --sign -`.

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
3. Live fetch: `GET https://cursor.com/api/usage-summary`. The two dashboard pools map to the two reserved meters: **Cursor Models** (Auto + Composer) from `individualUsage.plan.autoPercentUsed`, **Other Models** (named / API) from `apiPercentUsed`. Both reset at `billingCycleEnd`. If `apiPercentUsed` is missing, Other Models stays the disabled “—” row — `totalPercentUsed` is not substituted. Team fallback: `autoModelSelectedDisplayMessage` → Cursor Models, `namedModelSelectedDisplayMessage` → Other Models. On-demand spend stays a footer (`On-demand $x.xx`), never a third percent bar.

### ChatGPT (Plus / Pro)

ChatGPT is the only provider with **multi-account** support. Cursor and GLM stay single-account. There is no separate Codex provider and **no custom ChatGPT OAuth app**.

QuotaBar uses the same live usage path CodexBar uses:

1. Prefer `GET https://chatgpt.com/backend-api/wham/usage` (then `https://chat.openai.com/backend-api/wham/usage` if needed) with `Authorization: Bearer <token>`, the chatgpt.com session cookie when we have one, and `ChatGPT-Account-Id` when known. Each `rate_limit` window is classified by **duration** (`limit_window_seconds` / `window_seconds` / `windowDurationMins`), not by primary/secondary slot: ≤ ~12h → **Session**, ~3–14d (incl. 10080 min / 7d) → **Weekly**, ~30d (43200 min) → **Monthly**. Plus / Codex often return only a 7-day `primary` and no 5-hour session — that window is Weekly, and Session stays the disabled “—” row. A lone window whose reset is days away is Weekly, not Session. Countdown uses the real title (`Weekly reset in 5d 13h`). `credits.balance` / unlimited stay footer-only — percentages are never invented from credits.
2. Tokens come from a chatgpt.com session cookie (Add account / paste) exchanged at `GET /api/auth/session`, **or** a read-only `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) written by `codex login` — the same file CodexBar reads. QuotaBar does not refresh or rewrite that file and does not start a Codex OAuth dance.
3. If `auth.json` exists and you have not added a ChatGPT account yet, Refresh uses that file as an implicit source. QuotaBar will not create a new account on every launch.
4. In Settings → ChatGPT, **Add account** still opens an isolated `WKWebView` on `https://chatgpt.com` as a cookie fallback. After a real session exists, the cookie is stored in the Keychain and the **label is the session email**. If ChatGPT returns no email, the label falls back to **ChatGPT** / **ChatGPT 2**. Repeat **Add account** for each extra login — each window uses a fresh `WKWebsiteDataStore`.
5. **Rename** (the email label is editable) or **Delete** from the same list. There is no single global ChatGPT cookie field.
6. Cookie paste is not the default add path. Each account has a collapsed **Advanced — cookie / JSON fallback** for a session cookie (`__Secure-next-auth.session-token=…` or a full Cookie header) and optional pasted `wham/usage` or `conversation_limit` JSON. The login window also has “Paste a session cookie instead” if the live page will not complete. Account metadata (`id`, `label`, `enabled`, and that optional email) lives in `~/.config/quotabar/config.json`. The selected account id is stored there as `selectedChatGPTAccountId`. Cookies and optional pasted JSON stay in the Keychain as `chatgpt.cookie.<account-id>` and `chatgpt.json.<account-id>`.
7. Only if `wham/usage` has no usable windows does QuotaBar fall back to  
   `GET https://chatgpt.com/backend-api/conversation_limit` and  
   `GET https://chatgpt.com/public-api/conversation_limit`, then optional pasted JSON.
8. Meters are drawn only when the JSON actually contains remaining/used percentages. Auth failures stay signed out. JSON without percentages is an honest error that mentions `wham/usage` / `codex login` — not dummy 80%. A 401 on one account does not wipe the others.
9. In the popover, pick **ChatGPT**. If you have two or more accounts, a compact account switcher appears under the provider switcher. The two reserved meters (Session / Weekly, or Monthly when that is the only longer window), the plan badge, and “Updated …” follow the selected account. The menu-bar percentage is that account’s most-constrained remaining % among the **classified** windows (orange below 25%).
10. **Refresh** updates the selected ChatGPT account (or the implicit `auth.json` source when there are no accounts). Background polling refreshes every ChatGPT account so switching stays instant. A successful Add account also refreshes that account so meters can fill in.
11. Existing single-cookie / single-JSON installs are migrated to one account labeled **ChatGPT**; credentials are not dropped. If you have no accounts and no readable `auth.json`, the popover shows the usual “Sign in / add key” empty state with a button that opens Settings.

### GLM (z.ai / BigModel coding plan)

1. Paste an API token in Settings, **or** set `Z_AI_API_KEY` / `GLM_API_KEY` / `BIGMODEL_API_KEY`, **or** put a legacy `glmApiKey` in `~/.config/quotabar/config.json` (it is migrated into Keychain and stripped from the file).
2. Pick a region: **Global** `https://api.z.ai` or **China** `https://open.bigmodel.cn`.
3. Live fetch: `GET {host}/api/monitor/usage/quota/limit` with `Authorization: Bearer <token>`.
4. Shortest `TOKENS_LIMIT` (~5h) → Session; longer `TOKENS_LIMIT` (~weekly) → Weekly. `nextResetTime` drives the countdown. `planName` / `level` is the badge.

## Preview fixtures

Settings → **Preview fixtures** loads bundled sample JSON so you can screenshot the UI without accounts. Off by default, labeled “Preview” in the popover.

## Why it is not sandboxed

Reading Cursor’s local `state.vscdb` and accepting pasted browser cookies requires ordinary user-file and network access. A sandboxed menu extra would need a grab-bag of temporary-exception entitlements (or would simply fail). QuotaBar ships as a **non-sandboxed** `LSUIElement` utility — the usual model for this class of app. It does not request iCloud, push, or any other Apple capability.

## Disclaimer

Unofficial usage endpoints, cookies, and local token files belong to their vendors and can change without notice. QuotaBar is not affiliated with Cursor, OpenAI, z.ai, or BigModel. Use your own credentials; rotate them if you ever paste a session into a chat or screenshot.

## License

[MIT](LICENSE)
