# QuotaBar

A menu-bar-only macOS 14+ utility (version **0.0.1**) that shows remaining **Cursor**, **ChatGPT**, and **GLM** (z.ai / BigModel coding plan) subscription quota. One dark pill in the status bar, one compact popover. No Dock icon, no other providers, no telemetry.

QuotaBar is an independent implementation. It talks to the same unofficial usage endpoints those products’ own dashboards already call. Those endpoints can change or break without notice.

## Install

Ad-hoc signed (no Apple Developer ID). On your Mac:

```bash
brew tap ttaatoo/quotabar https://github.com/ttaatoo/quotabar
brew install --formula --HEAD ttaatoo/quotabar/quotabar
# after the v0.0.1 zip is published:
brew install --cask --no-quarantine ttaatoo/quotabar/quotabar
```

`--HEAD` builds from `main` and works immediately after this repo is merged. `--no-quarantine` is required for the ad-hoc signed cask.

Then:

```bash
# formula prefix; skip if you used the cask
xattr -dr com.apple.quarantine "$(brew --prefix quotabar)/QuotaBar.app"
```

If Gatekeeper still blocks it: **System Settings → Privacy & Security → Open Anyway**.

Optional: `ln -sf "$(brew --prefix quotabar)/QuotaBar.app" /Applications/QuotaBar.app`

## What you get

- Status item: dark rounded pill with a small bar-chart mark and a percentage (remaining quota for the selected provider’s most-constrained window, usually weekly). The number turns orange below 25% remaining.
- Popover (not a detached window): provider title + plan badge, relative “Updated …” time, refresh, a three-way provider switcher, Session and Weekly meters, reset countdowns, Settings… and Quit QuotaBar.
- Settings: enable each provider, paste credentials, GLM region, poll interval (default 120s), remaining vs used, launch at login (`SMAppService`), and an off-by-default **Preview fixtures** toggle for screenshots.

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
  MARKETING_VERSION=0.0.1 CURRENT_PROJECT_VERSION=0.0.1 \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO build
```

Ad-hoc signed app + zip (also used by the Homebrew formula and the `v*` release workflow):

```bash
chmod +x scripts/package.sh
./scripts/package.sh
```

That writes `dist/QuotaBar.app` and `dist/QuotaBar.zip` at version 0.0.1, then runs `codesign --force --deep --sign -`.

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
3. Live fetch: `GET https://cursor.com/api/usage-summary`. Included / Auto percent maps to **Session**; billing-cycle / total percent maps to **Weekly**. Reset times come from `billingCycleEnd`.

### ChatGPT (consumer Plus / Pro — not Codex CLI)

ChatGPT does not publish a stable official remaining-quota API. QuotaBar does **not** call Codex `/backend-api/wham/usage`.

1. In Settings, paste a chatgpt.com session cookie (`__Secure-next-auth.session-token=…` or the full Cookie header).
2. QuotaBar exchanges it at `GET https://chatgpt.com/api/auth/session` for a bearer token, then tries  
   `GET https://chatgpt.com/backend-api/conversation_limit` and  
   `GET https://chatgpt.com/public-api/conversation_limit`.
3. It only draws meters when that JSON actually contains remaining/used percentages. If the endpoint 404s or has no numbers, you get an honest error — not dummy 80%.
4. Workaround: in chatgpt.com DevTools → Network, copy the `conversation_limit` response and paste it into the ChatGPT JSON field in Settings.

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
