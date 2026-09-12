# Product

## Register

product

## Users

Power users who already pay for Cursor, ChatGPT, GLM, Grok, and/or OpenCode Go. They glance at remaining quota from a macOS menu-bar popover, usually at a desk at night, then open Settings only to sign in, paste a credential, add an account, or flip a toggle. They are not exploring a settings product; they want the pane to disappear into the task.

## Product Purpose

QuotaBar is a menu-bar-only macOS 14+ utility that shows remaining subscription quota. Settings is the credential and preference surface behind that popover: enable providers, store secrets in the Keychain, manage ChatGPT, Grok, and OpenCode Go accounts, and choose how the menu bar reads. Success is a calm preference window that matches the dark popover, never a second app.

## Brand Personality

Dense, calm, native. Quiet confidence; no marketing voice. Copy is short, literal, and English unless a file already mixes languages.

## Anti-references

- Bright macOS System Settings clones (large white grouped lists, toolbar icons, colorful sidebar glyphs)
- Stacked “SaaS settings” card walls with identical icon-title-hint blocks
- Rainbow provider chrome and full-width accent buttons on every section
- Glassmorphism, gradient type, neon-on-black “AI tool” skins
- Flashy motion or onboarding theater in a utility pane

## Design Principles

- **The popover is the product.** Settings is chrome for credentials and toggles, not a dashboard.
- **One glance, then a drill-in.** Overview first (which providers are on); secrets live one section deep.
- **Progressive disclosure.** Advanced cookie/JSON stays collapsed. Empty states teach the next action.
- **Same language as the menu extra.** Cards, rows, secret fields, and bundled brand marks must feel like the popover, not a different app.
- **Persistence is invisible.** Keychain and `~/.config/quotabar/config.json` paths do not change for a visual redesign.

## Accessibility & Inclusion

Target WCAG AA contrast on settings text. Keyboard: sidebar arrows, tab through fields, visible focus on secrets. Icon-only actions have help labels. Respect Reduce Motion (no decorative animation). Do not rely on color alone for on/off; toggles and “Off” badges carry state.
